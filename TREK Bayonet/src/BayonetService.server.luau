--!strict
--[[
	The authoritative half of the bayonet.

	Everything that decides the OUTCOME -- who is in front of you, team, health,
	forcefields, how hard it hits -- is decided here, from instances the server
	owns. The client sends nothing: the hitbox is the bayonet part itself, welded
	to the character, so the server sweeps the real blade through space as the
	thrust plays and asks what it overlapped.

	That is also why this does not reuse TREK_Remotes.Damage. ServerRays is false
	in GlobalConfigs, so TREK's own Security() distance check never runs, and
	handleDamage takes its OriginPos straight from the client. Firing that remote
	for a melee attack would mean a reach enforced only on the attacker's
	machine.

	Nothing in here modifies TREK. The damage, the gibs and the kill credit all
	go through TREK's own modules, called from outside.
]]

repeat
	task.wait()
until game:GetService("ReplicatedStorage"):WaitForChild("TREK_INSTALLED").Value

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local package = game:GetService("ReplicatedStorage"):WaitForChild("TREKBayonet")
local Config = require(package:WaitForChild("BayonetConfig"))

-- The hit maths, kept in its own module so it can be tested without Studio:
--     lune run tools/geometrytest.luau
local Geometry = require(package:WaitForChild("BayonetGeometry"))

-- TREK's own damage module: setDamage applies falloff, the headshot multiplier
-- and armour resistance; DamagePlayer does the TakeDamage and -- the part that
-- matters -- lbmodule.tagPlr, which is the WeaponTag the kill feed reads.
local damagemodule = require(ServerStorage:WaitForChild("TREKDamageModule"))

--[[
	TREK's own effects, for the hitmarker.

	Drawing a GUI effect from the server looks wrong until you notice TREK
	already does it: TREKExplosionModule -- a ServerStorage module -- ends its
	damage path with

		effects.Hitmark.DrawEffect(player, 'plr')

	for exactly the same reason we need to. Explosion damage, like a bayonet
	thrust, is decided on the server, so the client that should see the marker
	never ran the code that decided there was a hit. The Gun handler's own
	hitmarker() is a local inside Gun.client and cannot be reached from here.
]]
local effects = require((shared :: any).S.TREK_Modules.EffectsModule)

-- Our own remote, in our own folder. Not added to TREK_Remotes: that folder is
-- TREK's, and a stray RemoteEvent in it is exactly the kind of thing that makes
-- a later TREK update ambiguous to debug.
local stabRemote = Instance.new("RemoteEvent")
stabRemote.Name = "BayonetStab"
stabRemote.Parent = package

--[[
	Outcome of an ACCEPTED thrust, as (attacker: Player, contact: boolean).

	A BindableEvent, not a RemoteEvent: this is for other server code, and there
	is nothing here a client needs or should be told. Firing it costs nothing when
	nobody is listening.

	It exists because the outcome is knowable only in here. BayonetStab is a
	request -- it arrives before the rate limit, the equipment checks and the
	sweep have run, so a listener on it cannot tell a hit from a miss, or either
	from a thrust that was refused outright. TREK Voicelines uses this to pick
	between its hit and miss barks.

	Fired only for thrusts that got as far as the sweep. A refused thrust reports
	nothing: no swing happened, so there is no outcome to report.
]]
local outcomeEvent = Instance.new("BindableEvent")
outcomeEvent.Name = "BayonetOutcome"
outcomeEvent.Parent = package

-- Last accepted thrust per player, cleared on PlayerRemoving.
local lastStab: { [Player]: number } = {}

-- How far past the hitbox to look when gathering candidates. Nothing here can
-- cause a hit -- it only widens what a MISS is able to tell you about, so the
-- report can say "they were 0.8 studs outside" instead of "nothing found".
local REPORT_MARGIN = 6

local function debugPrint(message: string)
	if Config.Debug then
		warn("[TREKBayonet] " .. message)
	end
end

--[[
	May this attacker damage this victim?

	Reimplemented rather than called: TREK's CheckIfDamageAllowed is a local
	inside TREKServerDamage and is not exported. Same rules, with two
	differences that are corrections rather than drift -- TREK's version returns
	true when player == target (self damage), which cannot be what a bayonet
	wants, and a victim with no Player at all is an NPC, which is always fair
	game.
]]
local function damageAllowed(attacker: Player, victim: Player?, teamKill: boolean?): boolean
	if teamKill then
		return true
	end
	if not victim then
		return true
	end
	if victim == attacker then
		return false
	end
	if not victim.Team or not attacker.Team then
		return true
	end

	return victim.Team ~= attacker.Team
end

--[[
	Every character whose parts are in the box, plus every player.

	Discovery is by spatial query and then walking UP to the owning character.
	An earlier version of this function tried to be clever and enumerate
	characters directly -- workspace's children, one level into Folders -- on the
	theory that a short deterministic list beats a query. It found nothing at
	all: the NPC being stabbed was nested deeper than the scan looked, and the
	report said "no living character within 20 studs" while the blade was inside
	its chest.

	The lesson is that HIERARCHY DEPTH IS A MODELLING CHOICE. An NPC may sit
	directly in workspace, in a Folder, or inside a Model grouping a whole squad,
	and none of that should decide whether it can be stabbed. Only a query knows
	where the parts really are.

	What the query does not decide is whether a hit landed -- that is still an
	explicit box test on each candidate's parts, so crowding can cost discovery
	but never accuracy, and MaxParts is set high to make even that unlikely.

	Returns the characters found, and one part that is in the box but belongs to
	no Humanoid, which the miss report uses to say "you stabbed a prop".

	NPCs count deliberately. This is also why none of this goes through
	shared.S.trekFuncs.findPlrAndChar, which bails the moment the owning model
	has no Player:

		plr2 = game.Players:GetPlayerFromCharacter(current)
		if not plr2 then return end

	That would make the bayonet useless against dummies and admin-spawned
	clones, which is most of what anyone tests against.
]]
local function nearbyCharacters(
	attackerChar: Model,
	queryCF: CFrame,
	querySize: Vector3,
	params: OverlapParams,
	found: { { model: Model, humanoid: Humanoid } },
	seen: { [Model]: boolean }
): BasePart?
	-- The caller owns these two tables and reuses them across every sample of a
	-- stab. Clearing beats reallocating eleven times, and the OverlapParams is
	-- built once per stab for the same reason -- its filter never changes.
	table.clear(found)
	table.clear(seen)
	seen[attackerChar] = true

	local function consider(model: Instance?)
		if not model or not model:IsA("Model") or seen[model] then
			return
		end

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		seen[model] = true
		table.insert(found, { model = model, humanoid = humanoid })
	end

	-- Players first, because Players is exact and costs nothing.
	for _, player in ipairs(Players:GetPlayers()) do
		consider(player.Character)
	end

	local orphan: BasePart? = nil

	for _, part in ipairs(workspace:GetPartBoundsInBox(queryCF, querySize, params)) do
		-- Walk up to the owning character. Depth is a modelling choice: an NPC
		-- may sit directly in workspace, inside a Folder, or inside a Model
		-- grouping a whole squad, and none of that should decide whether it can
		-- be stabbed.
		local current: Instance? = part
		local owner: Model? = nil

		while current and current ~= workspace do
			if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
				owner = current
				break
			end
			current = current.Parent
		end

		if owner then
			consider(owner)
		elseif not orphan then
			-- Something solid is in the box but belongs to no Humanoid. Kept for
			-- the miss report: if this is the thing you were aiming at, the
			-- target is not a character and that is why nothing happened.
			orphan = part
		end
	end

	return orphan
end

--[[
	Sweep the blade and return the first thing it goes into.

	This is the whole hit detection. There is no projected box and no
	reconstruction of where the attacker was -- the bayonet is welded to the
	character, so the server already knows where it is, and asking what overlaps
	it is both simpler and unspoofable.

	Sampled repeatedly across HitWindow rather than once, for two reasons:

	  * the thrust animation takes time to drive the blade out, so a single test
	    at keypress would check a blade that has not extended yet;

	  * a single test can be stepped over. A blade moving at speed passes through
	    a torso between two physics frames, which is precisely why Touched is
	    unreliable for melee and why this does not use it.

	Both attacker and target are read from the server's own view at the same
	instant, so their relative geometry is correct even though that view trails
	the attacker's screen. That is what removed the need for lag compensation.
]]
local function sweepForTarget(
	attacker: Player,
	attackerChar: Model,
	root: BasePart,
	blade: Instance,
	cfg: any
): (Model?, Humanoid?, BasePart?, Vector3?)
	local pad = Vector3.new(Config.HitPadSide, Config.HitPadVertical, Config.HitPadForward)
	local deadline = os.clock() + Config.HitWindow
	local samples = 0

	--[[
		Collected ONCE, here, rather than on each of the eleven samples.

		Walking descendants is the most expensive thing this does, and the
		blade's pieces do not change during the third of a second a thrust
		lasts. The same applies to each character's limbs, cached below as they
		are first encountered. A limb destroyed mid-sweep by handleGibs drops
		out on its own -- deepestFromParts skips parts that have been unparented.
	]]
	local bladeParts = Geometry.collectParts(blade)

	if #bladeParts == 0 then
		debugPrint(string.format(
			"%s: ABORTED -- %s (a %s) contains no BasePart, so there is nothing to sweep",
			attacker.Name, blade:GetFullName(), blade.ClassName
		))
		return nil, nil, nil
	end

	local limbCache: { [Model]: { parts: { BasePart }, radii: { number } } } = {}

	--[[
		Built once and reused, like the two tables below it.

		IgnoreList is where TREK parks bullets, casings and gibs. The attacker's
		own character goes too, or the blade instantly finds the hand holding it.

		MaxParts is set explicitly: near a wall or a prop pile a box can contain
		more than the default allowance, and a limb dropping off the end of a
		truncated list is an intermittent miss with nothing to chase.
	]]
	local ignore: { Instance } = { attackerChar }
	local ignoreList = workspace:FindFirstChild("IgnoreList")
	if ignoreList then
		table.insert(ignore, ignoreList)
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.MaxParts = 500

	local candidates: { { model: Model, humanoid: Humanoid } } = {}
	local seen: { [Model]: boolean } = {}

	--[[
		How far past the hitbox to look for candidates.

		Only with Debug on. The margin exists so a MISS can name who was
		standing there and how far outside they were -- and it costs a great
		deal: six studs on every axis turns a box of roughly 4.5 x 5.5 x 5.6
		into 16.5 x 17.5 x 17.6, which is about thirty-six times the volume for
		the engine to search, eleven times a stab.

		With Debug off nobody reads that report, so the query is the hitbox
		itself and not a stud more.
	]]
	local margin = Config.Debug
		and Vector3.new(REPORT_MARGIN, REPORT_MARGIN, REPORT_MARGIN)
		or Vector3.zero

	-- Tracked purely so a miss can explain itself. Everything below is recorded
	-- across the whole sweep and reported once at the end, rather than printed
	-- per sample, so a miss is one line in the log and not eleven.
	local nearestName, nearestGap = nil :: string?, math.huge
	local firstCentre: Vector3?, lastCentre: Vector3? = nil, nil
	local sawAnyone = false
	local nearestOrphan: BasePart? = nil
	local lastQueryCF: CFrame?, lastQuerySize: Vector3? = nil, nil

	repeat
		samples += 1

		--[[
			ONE measurement of the blade per sample, not two.

			The frame is anchored at the attacker's root rather than at the
			blade, which is what makes that possible: the blade's position is no
			longer needed to build the frame it is measured in, so the world
			centre falls out of the result instead of costing a second pass.
			Only the frame's ROTATION matters to the hit test, and the root
			supplies that.

			Written out longhand, and not for style. This was

				local centre, half = frame and Geometry.bladeBox(blade, frame)

			which is silently wrong: `x and f()` is adjusted to ONE value, so
			`half` was always nil, the guard below it never passed, and no box
			was ever built. Every stab reported an empty box because there was
			no box -- not because nothing was in it.

			Proven, not guessed: `local c, d = true and two()` gives d = nil.
		]]
		local frame = Geometry.attackerFrame(root, root.Position)
		local centre, half = Geometry.boxFromParts(bladeParts, frame)

		if centre and half then
			local worldCentre = frame * centre
			firstCentre = firstCentre or worldCentre
			lastCentre = worldCentre

			local box = half + pad

			if samples == 1 then
				debugPrint(string.format(
					"%s: blade %.2fx%.2fx%.2f, hitbox %.1f wide x %.1f tall x %.1f deep, "
						.. "reaching %.1f studs ahead of you",
					attacker.Name,
					half.X * 2, half.Y * 2, half.Z * 2,
					box.X * 2, box.Y * 2, box.Z * 2,
					box.Z - centre.Z
				))
			end

			lastQueryCF, lastQuerySize = frame * CFrame.new(centre), (box + margin) * 2

			-- Called unconditionally, THEN folded into nearestOrphan. Writing it
			-- as `nearestOrphan = nearestOrphan or nearbyCharacters(...)` skips
			-- the call outright once an orphan has been seen -- which would stop
			-- gathering candidates for the rest of the sweep.
			local orphan = nearbyCharacters(attackerChar, lastQueryCF, lastQuerySize, params, candidates, seen)
			nearestOrphan = nearestOrphan or orphan

			for _, candidate in ipairs(candidates) do
				local character = candidate.model
				sawAnyone = true

				if character:FindFirstChildOfClass("ForceField") then
					continue
				end

				local victim = Players:GetPlayerFromCharacter(character)
				if not damageAllowed(attacker, victim, cfg.TeamKill) then
					continue
				end

				-- This character's limbs, walked once for the whole stab.
				local limbs = limbCache[character]
				if not limbs then
					local parts, radii = Geometry.collectParts(character, true)
					limbs = { parts = parts, radii = radii }
					limbCache[character] = limbs
				end

				-- Both values, and both are used. See the note at the top of the
				-- sweep for what happens when one of them is quietly dropped.
				local bestPart, bestGap =
					Geometry.deepestFromParts(limbs.parts, limbs.radii, frame, centre, box)

				if bestPart and bestGap <= 0 then
					debugPrint(string.format(
						"%s: hit %s in the %s on sample %d",
						attacker.Name, character.Name, bestPart.Name, samples
					))
					-- The blade's position AT THE MOMENT OF CONTACT, handed back
					-- so the damage origin is where the blade actually was
					-- rather than wherever it has swung on to since.
					return character, candidate.humanoid, bestPart, worldCentre
				end

				if bestGap < nearestGap then
					nearestGap, nearestName = bestGap, character.Name
				end
			end
		end

		-- Only the character that is still alive and in the world keeps swinging.
		if not attackerChar:IsDescendantOf(workspace) then
			return nil, nil, nil
		end

		task.wait(Config.HitSampleInterval)
	until os.clock() > deadline

	--[[
		The miss report.

		"How far outside the box was the nearest person" is the number that
		turns tuning from guesswork into arithmetic, and it is the one thing
		the previous version could not tell you.

		Blade travel is reported alongside it because it distinguishes two
		completely different faults that look identical in game. If the blade
		moved a stud or more, the server watched a real thrust and the box was
		genuinely short. If it moved almost nothing, the server never saw the
		thrust animate at all -- and no amount of padding is the fix for that.
	]]
	if not Config.Debug then
		return nil, nil, nil
	end

	local travel = (firstCentre and lastCentre) and (lastCentre - firstCentre).Magnitude or 0

	if nearestName then
		debugPrint(string.format(
			"%s: MISS over %d samples. Nearest was %s, %.1f studs outside the box -- "
				.. "add that to HitPadVertical/Side/Forward to have caught it. "
				.. "Blade travelled %.2f studs during the sweep%s",
			attacker.Name, samples, nearestName, nearestGap, travel,
			travel < 0.25 and " (barely moved -- the server may not be seeing the thrust animation)" or ""
		))
	elseif sawAnyone then
		debugPrint(string.format(
			"%s: MISS over %d samples -- everyone found was a teammate or shielded",
			attacker.Name, samples
		))
	elseif nearestOrphan then
		-- The blade is going through something, but that something is not a
		-- character. Worth naming in full: it says the target has no Humanoid,
		-- which is a modelling answer, not a tuning one.
		debugPrint(string.format(
			"%s: MISS over %d samples -- the box contained %s, which belongs to no Humanoid. "
				.. "Only models with a Humanoid can be stabbed",
			attacker.Name, samples, nearestOrphan:GetFullName()
		))
	else
		--[[
			The box was empty, which when the blade is visibly inside someone
			means the query could not see them. One re-query, filtering out only
			the attacker, separates the two reasons that can happen: they are
			inside TREK's IgnoreList (which the real query excludes, because
			that is where bullets and gibs live), or the server genuinely has
			them somewhere else.

			Run once, in the report, never in the hot loop.
		]]
		local hidden: string? = nil

		if lastQueryCF and lastQuerySize then
			local bare = OverlapParams.new()
			bare.FilterType = Enum.RaycastFilterType.Exclude
			bare.FilterDescendantsInstances = { attackerChar }
			bare.MaxParts = 500

			for _, part in ipairs(workspace:GetPartBoundsInBox(lastQueryCF, lastQuerySize, bare)) do
				local current: Instance? = part
				while current and current ~= workspace do
					if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
						hidden = current:GetFullName()
						break
					end
					current = current.Parent
				end
				if hidden then
					break
				end
			end
		end

		if hidden then
			debugPrint(string.format(
				"%s: MISS over %d samples -- %s IS in the box but was filtered out. "
					.. "It is inside workspace.IgnoreList, which this excludes because that is "
					.. "where TREK parks bullets, casings and gibs",
				attacker.Name, samples, hidden
			))
		else
			debugPrint(string.format(
				"%s: MISS over %d samples -- the box was empty. Blade travelled %.2f studs; "
					.. "if it is visibly inside someone, the server has them somewhere else",
				attacker.Name, samples, travel
			))
		end
	end

	return nil, nil, nil
end

--[[
	Every reason a thrust can be refused before detection ever runs.

	All of these used to return silently, which is why "it rarely hits" was
	impossible to act on: a stab refused here and a stab that swept and found
	nothing produced exactly the same thing in game -- an animation and no
	damage -- and exactly the same thing in the log, which was nothing.

	They are worth telling apart. A refusal means the weapon or the character
	was not in the state this expects; a miss means the geometry was short. The
	fixes have nothing in common.
]]
local function onStab(attacker: Player)
	local now = os.clock()

	--[[
		The rate limit is NOT first any more, and that is deliberate.

		It is derived from the weapon's own RoundsPerMinute -- the same number
		the gun handler paces swings with -- so there is one figure to tune and
		no second one here to drift from it. That number lives in the [2] block,
		which means the tool and its config have to be resolved before the limit
		can be known.

		Everything between here and there is a FindFirstChild or a table read.
		The expensive part of a swing is the sweep, and that still happens only
		after the limit has been applied.
	]]
	local character = attacker.Character
	if not character or not character:IsDescendantOf(workspace) then
		debugPrint(attacker.Name .. ": REFUSED -- no character in the workspace")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		debugPrint(attacker.Name .. ": REFUSED -- dead or no Humanoid")
		return
	end

	-- No stabbing out of a vehicle seat.
	if humanoid.SeatPart then
		debugPrint(attacker.Name .. ": REFUSED -- seated in " .. humanoid.SeatPart.Name)
		return
	end

	-- Needed for the attacker's facing, which is what the hitbox is measured
	-- against. Nothing else reads it.
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		debugPrint(attacker.Name .. ": REFUSED -- no HumanoidRootPart")
		return
	end

	local tool = (shared :: any).S.trekServerFuncs.returnTool(attacker, character)
	if not tool then
		-- Worth watching. TREK's own weapon setup is known to fail occasionally
		-- on respawn, and when it does this is where the bayonet notices.
		debugPrint(attacker.Name .. ": REFUSED -- TREK returnTool gave no equipped tool")
		return
	end

	-- The bayonet is a part on the weapon, not a flag in a table. A rifle
	-- without one cannot stab no matter what the client claims.
	--
	-- Searched recursively: whether the bayonet is a loose Part sitting directly
	-- under the Tool or a Model nested a few levels down is a modelling choice,
	-- and it should not decide whether the weapon works.
	local blade = tool:FindFirstChild(Config.BayonetPartName, true)
	if not blade then
		debugPrint(string.format(
			"%s: REFUSED -- nothing named %q anywhere inside %s",
			attacker.Name, Config.BayonetPartName, tool.Name
		))
		return
	end

	local reqmod = (shared :: any).S.trekServerFuncs.checkForModule(tool)
	if not reqmod then
		debugPrint(attacker.Name .. ": REFUSED -- no weapon config module on " .. tool.Name)
		return
	end

	local cfg = reqmod[Config.ConfigIndex]
	if not cfg then
		debugPrint(string.format(
			"%s: REFUSED -- %s has no [%d] block in its weapon module",
			attacker.Name, tool.Name, Config.ConfigIndex
		))
		return
	end

	--[[
		Now the rate limit, from the weapon's own cadence.

		handleFireRate in the gun handler waits 60/RoundsPerMinute after every
		swing, so that is the interval the client is pacing to and the one the
		server measures against. ServerCooldownTolerance is the slack: both
		sides time it from their own clock, and without a little give, jitter
		alone would reject swings the player made in good time.
	]]
	local rpm = tonumber(cfg.RoundsPerMinute) or 0
	if rpm <= 0 then
		-- A melee mode with no usable RoundsPerMinute would otherwise divide by
		-- zero or allow a swing every frame. Refuse rather than guess a number
		-- that the client is not pacing to.
		debugPrint(string.format(
			"%s: REFUSED -- %s [%d] has no usable RoundsPerMinute (%s)",
			attacker.Name, tool.Name, Config.ConfigIndex, tostring(cfg.RoundsPerMinute)
		))
		return
	end

	local interval = (60 / rpm) * Config.ServerCooldownTolerance
	local last = lastStab[attacker]

	if last and now - last < interval then
		debugPrint(string.format(
			"%s: REFUSED -- %.2fs since the last swing, needs %.2fs",
			attacker.Name, now - last, interval
		))
		return
	end

	-- Accepted. Stamp the clock here rather than after a successful hit, so a
	-- miss still costs the attacker their cooldown.
	lastStab[attacker] = now

	--[[
		Report the outcome exactly once per thrust.

		A hit is knowable the instant the blade connects, and is reported then. A
		miss is only PROVABLE once the whole sweep has run -- but waiting that long
		to say so puts the miss well after the swing it belongs to, so an
		unresolved thrust is called a miss at MissAnnounceAfter instead.

		Once, and only once. If a contact turns up after that early call, the
		announcement stands: saying "miss" and then "hit" for one thrust is worse
		than being wrong quietly. Damage is entirely unaffected either way -- this
		governs what listeners are told, never what the sweep does.
	]]
	local announced = false

	local function announce(contact: boolean)
		if announced then
			return
		end
		announced = true
		outcomeEvent:Fire(attacker, contact)
	end

	-- No-op when MissAnnounceAfter is at or above HitWindow: the sweep will have
	-- announced already by the time this runs.
	task.delay(Config.MissAnnounceAfter, function()
		if not announced then
			debugPrint(string.format(
				"%s: no contact after %.2fs -- calling it a miss now, sweep still running",
				attacker.Name, Config.MissAnnounceAfter
			))
		end
		announce(false)
	end)

	local targetChar, _targetHum, targetPart, hitCentre = sweepForTarget(attacker, character, root, blade, cfg)

	-- Contact is "the sweep found a humanoid". Deliberately reported before
	-- setDamage: a hit that armour reduces to zero still made contact, and the
	-- swing still looked like a hit to both players.
	local contact = targetChar ~= nil and targetPart ~= nil

	if contact and announced then
		-- The one case worth seeing in a log. It means MissAnnounceAfter is set
		-- too low for this animation: the stab landed, and was called a miss.
		debugPrint(string.format(
			"%s: LATE HIT -- contact arrived after MissAnnounceAfter (%.2fs), so it was "
				.. "announced as a miss. Raise Config.MissAnnounceAfter.",
			attacker.Name, Config.MissAnnounceAfter
		))
	end

	announce(contact)

	if not targetChar or not targetPart then
		return
	end

	-- The blade's position, not the attacker's. It is what actually made contact,
	-- and it keeps TREK's distance falloff a no-op: the blade is by definition
	-- touching the part it hit, so setDamage always returns full damage. Range
	-- is enforced by the geometry now, not by a falloff curve.
	local origin = hitCentre or targetPart.Position

	local dmg = damagemodule.setDamage(cfg, targetPart, origin, false)
	if not dmg or dmg <= 0 then
		debugPrint(string.format("%s hit %s for no damage", attacker.Name, targetChar.Name))
		return
	end

	debugPrint(string.format("%s stabbed %s for %d", attacker.Name, targetChar.Name, dmg))

	-- Damage before gibs, in that order: handleGibs destroys the part it is
	-- given, and setDamage needs it to read the hit location and armour values.
	--
	-- trekGibs is hoisted into a local rather than called as
	-- `(shared :: any).S.trekGibs...` on the line after a call. Lua would read
	-- the leading parenthesis as a continuation of the previous statement and
	-- parse the two lines as DamagePlayer(...)(shared).S.trekGibs..., which
	-- compiles cleanly and fails at runtime.
	local trekGibs = (shared :: any).S.trekGibs

	damagemodule.DamagePlayer(attacker, targetChar, dmg)
	trekGibs.handleGibs(targetPart, cfg, targetChar, origin)

	--[[
		The hitmarker, drawn on the attacker's HUD.

		Spawned and wrapped, which the explosion module does not bother with,
		because DrawEffect opens with an unbounded

			plr.PlayerGui:WaitForChild('GunHud')

		A player who somehow has no GunHud would otherwise hang this handler
		forever, and it would take the next stab's rate-limit slot with it. A
		cosmetic effect must never be able to stall the thing that does the
		damage -- so the damage is already applied by the time we get here.

		'plr' is the red marker. 'armr' is the blue one, for THealth props and
		vehicles, which the bayonet deliberately cannot damage.
	]]
	task.spawn(function()
		local ok, err = pcall(effects.Hitmark.DrawEffect, attacker, "plr")
		if not ok then
			debugPrint("hitmarker failed for " .. attacker.Name .. ": " .. tostring(err))
		end
	end)
end

stabRemote.OnServerEvent:Connect(onStab)

Players.PlayerRemoving:Connect(function(player)
	lastStab[player] = nil
end)

--[[
	Below one sample interval, the announcement can only ever beat the blade.

	Not quite as total as it sounds, and the reason is worth stating because it is
	what makes very low values usable at all: the sweep's FIRST sample runs
	synchronously, before the loop's first task.wait, so a contact found on sample
	one is reported as a hit no matter how small this is. task.delay cannot fire
	until the thread yields, and by then sample one has already returned.

	So the real effect is: point-blank stabs -- the ones already overlapping before
	the blade moves -- still say hit. Anything the blade has to TRAVEL to reach is
	resolved on a later sample and will say miss. Damage is unaffected either way.

	That is a legitimate setting if your stabs are point-blank by nature. It is
	worth saying out loud once, because "stabs at reach sound like misses" is
	otherwise indistinguishable from a broken hitbox.
]]
if Config.MissAnnounceAfter < Config.HitSampleInterval then
	warn(string.format(
		"[TREKBayonet] MissAnnounceAfter is %.3fs, below one sample interval (%.3fs). "
			.. "Only contacts found on the first sample -- point-blank stabs -- will be "
			.. "announced as hits; anything the blade travels to reach will announce as a "
			.. "miss. Damage is unaffected; the voice line is not.",
		Config.MissAnnounceAfter, Config.HitSampleInterval
	))
end

-- Announced unconditionally, not under Config.Debug. If this line is absent from
-- the log then this script did not finish, and that is the first thing worth
-- knowing when the bayonet does nothing.
print(string.format(
	"[TREKBayonet] service ready -- fire mode [%d], blade hitbox padded "
		.. "%.2f side / %.2f up / %.2f forward, swept over %.2fs, "
		.. "cadence from the weapon's RoundsPerMinute%s",
	Config.ConfigIndex,
	Config.HitPadSide, Config.HitPadVertical, Config.HitPadForward,
	Config.HitWindow,
	Config.Debug and " -- DEBUG ON, every swing will report itself" or ""
))

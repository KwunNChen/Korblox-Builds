--!strict
-- Adapters from TREK (and plain Roblox) events onto VoicelineService.request.
--
-- Nothing in here modifies TREK. Reload is a second listener on a RemoteEvent
-- TREK already owns, and everything else reads state TREK writes anyway.

local Players = game:GetService("Players")

local ServerScriptService = game:GetService("ServerScriptService")
local Service = require(ServerScriptService:WaitForChild("TREKVoicelines")
	:WaitForChild("VoicelineService"))

local Config = require(game:GetService("ReplicatedStorage")
	:WaitForChild("TREKVoicelines"):WaitForChild("VoicelineConfig"))

local Hooks = {}

-- Magazine counters already watched. Keyed by the counter itself, so equipping
-- the same weapon twenty times connects once rather than twenty times.
--
-- Without this, every equip re-parents the tool into the character and fires
-- ChildAdded again, stacking another listener on the same counter. The bark
-- cooldown hides the duplicates, so it shows up only as CPU and as a growing
-- pile of closures.
local watchedCounters: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Watch one weapon's magazines.

	TREK stores ammo as a DoubleConstrainedValue, NOT a NumberValue -- see
	TREKServerGeneral's createAmmoStore, which does
	Instance.new('DoubleConstrainedValue') and then sets MaxValue = MagCapacity.
	The two are sibling subclasses of ValueBase, so an IsA("NumberValue") test is
	false for every weapon in the game and silently disables this whole event.

	That MaxValue is the magazine size, which is why no config lookup is needed
	to know capacity.
]]
local function watchTool(tool: Instance)
	-- TREK creates TAmmo lazily, on the same ChildAdded signal that got us here,
	-- and yields before doing it. Checking without waiting loses the race on a
	-- weapon's first equip and abandons that tool for good.
	local ammo = tool:FindFirstChild("TAmmo") or tool:WaitForChild("TAmmo", 10)
	if not ammo then
		return
	end

	for _, modeFolder in ipairs(ammo:GetChildren()) do
		local counter = modeFolder:FindFirstChild("Ammo")
		if not counter or not counter:IsA("ValueBase") or watchedCounters[counter] then
			continue
		end
		watchedCounters[counter] = true

		local value = counter :: any
		local last = value.Value

		--[[
			This fires on every round leaving every weapon, which makes it the
			highest-frequency hook in the system -- so it decides whether there is
			anything to say using nothing but arithmetic, and only then goes
			looking for the character.

			The ancestor walk used to run first, on every single shot, including
			the overwhelming majority that are nowhere near the low-ammo threshold
			and produce no bark at all.
		]]
		counter:GetPropertyChangedSignal("Value"):Connect(function()
			local current = value.Value
			local previous = last
			last = current

			if current >= previous then
				return
			end

			-- MaxValue is MagCapacity straight from the weapon config. Falls back
			-- to the largest value seen if some other system made this counter --
			-- which is why it needs the value from BEFORE this shot: comparing
			-- against the post-shot value made the fallback max(current, current,
			-- 1), so it could never exceed the current reading and the ratio below
			-- was always 1.
			local capacity = tonumber(value.MaxValue) or 0
			if capacity <= 0 then
				capacity = math.max(previous, current, 1)
			end

			-- Zero is not special-cased. It used to branch off to OutOfAmmo for a
			-- dry-click line of its own; with that event gone, an empty magazine
			-- is simply the bottom of the low-ammo threshold and speaks the same
			-- line the rest of it does. Going silent at exactly zero would be the
			-- odd result -- one round left speaks, none left says nothing.
			if current / capacity > Config.LowAmmoFraction then
				return
			end

			-- Resolved per shot rather than captured. Capturing the character
			-- would pin every corpse in memory: the tool outlives the character
			-- in the Backpack, so a captured reference never becomes collectable.
			local character = tool:FindFirstAncestorOfClass("Model")
			if character then
				Service.request(character, "LowAmmo")
			end
		end)
	end
end

-- Humanoids already bound, so the player path and the workspace scan can both
-- reach the same character without connecting twice.
local bound: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Bind one humanoid. `player` is nil for anything that is not a player's
	character -- an NPC, a dummy, an admin-spawned clone.

	Non-players get Hurt/Death of their own and, more to the point, can credit a
	Kill: whatever damaged them is read off the same WeaponTag TREK writes, so
	attribution does not depend on the victim being a player.
]]
local function onCharacter(player: Player?, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or bound[humanoid] then
		return
	end
	bound[humanoid] = true

	-- Clear the channel when this character goes away, not when it arrives.
	-- Resetting on arrival was a no-op: channels are created lazily by
	-- Service.request, so a character bound moments ago has never had one. The
	-- outgoing character is the one holding a half-played line and a stale
	-- priority, and nothing was ever clearing it.
	character.Destroying:Connect(function()
		Service.reset(character)
	end)

	local lastHealth = humanoid.Health

	-- Death and Kill are announced by whichever of HealthChanged and Died gets
	-- here first, and in practice that is never Died.
	--
	-- Died is not raised by the damage that kills you. It is raised when the
	-- humanoid's state machine transitions to Dead, which is a separate step
	-- from the health write and, for a player's character, one the server does
	-- not own. HealthChanged fires from the write itself, inside TakeDamage --
	-- the earliest instant at which a kill exists at all. That gap is what made
	-- the kill bark land noticeably behind the shot.
	--
	-- Both stay connected, because they are not redundant. Health can be driven
	-- to zero without HealthChanged firing (set to a value it already held), and
	-- a humanoid can be killed by state change rather than by damage. Whichever
	-- loses the race finds `spoke` already true and does nothing.
	local spoke = false

	-- Credit the kill. Returns whether a TAG WAS THERE TO READ -- not whether
	-- anything barked. A suicide reads a tag and deliberately says nothing, and
	-- must not look like a failed read.
	--
	-- The distinction earns its keep because of the order inside TREK's own
	-- DamagePlayer (TREKDamageModule):
	--
	--     target.Humanoid:TakeDamage(damage)
	--     lbmodule.tagPlr(target.Humanoid, player)
	--
	-- The tag is written AFTER the damage. Under Roblox's default deferred
	-- signal behaviour our handler is resumed after both lines have run, so the
	-- first read finds it; on a place configured for immediate signals the
	-- handler runs inside TakeDamage, before the tag exists. Hence the retry.
	local function creditKill(retry: boolean?): boolean
		local tag = humanoid:FindFirstChild("WeaponTag")
		local killer = (tag and tag:IsA("ObjectValue")) and tag.Value or nil

		if Config.Debug then
			warn(string.format(
				"[TREKVoicelines] death%s: %s (player=%s) weaponTag=%s",
				if retry then " (tag retry)" else "",
				character.Name,
				tostring(player and player.Name or "no"),
				tostring(killer and (killer :: any).Name or "none")
			))
		end

		if not killer then
			return false
		end

		if not killer:IsA("Player") or killer == player then
			return true
		end

		local killerCharacter = killer.Character
		if killerCharacter then
			Service.request(killerCharacter, "Kill")
		end

		return true
	end

	local function speakDeath()
		if spoke then
			return
		end
		spoke = true

		Service.request(character, "Death")

		-- task.defer rather than a wait: it resumes at the end of the current
		-- resumption cycle, which is after whatever damaged us has returned and
		-- therefore after tagPlr, while still being this frame. Unreached on a
		-- place running the default deferred signals.
		if not creditKill() then
			task.defer(creditKill, true)
		end
	end

	humanoid.HealthChanged:Connect(function(health: number)
		local delta = lastHealth - health
		lastHealth = health

		-- Tested before the delta check rather than after it. A killing blow is
		-- worth announcing even when it arrives as a repeat of a health value we
		-- have already seen, which reads as a delta of zero. Death also has its
		-- own line, so a dying hit must not additionally say "ow".
		if health <= 0 then
			speakDeath()
			return
		end

		-- HealthChanged also fires on heals and on the respawn reset.
		if delta <= 0 then
			return
		end

		if delta < Config.HurtDamageThreshold then
			return
		end

		Service.request(character, "Hurt")
	end)

	humanoid.Died:Connect(speakDeath)

	-- Only players reload, so the ammo watcher is theirs alone.
	if not player then
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			task.spawn(watchTool, child)
		end
	end

	-- task.spawn because watchTool now waits for TAmmo; blocking here would
	-- stall the rest of this character's binding behind a weapon that never
	-- gets one.
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.spawn(watchTool, child)
		end
	end)
end

-- Anything with a Humanoid that turns up in Workspace: NPCs, dummies, clones.
-- Workspace.ChildAdded rather than DescendantAdded on purpose -- characters are
-- parented to Workspace directly, and DescendantAdded fires for every bullet,
-- shell and effect part in a firefight.
local function tryBindModel(instance: Instance)
	if not Config.IncludeNPCs or not instance:IsA("Model") then
		return
	end

	-- Fast path, hoisted out of the coroutine below. A model that already has its
	-- Humanoid -- a clone, a prefab NPC, a character whose parts arrived before it
	-- was parented -- binds immediately. Spawning a thread for it meant every such
	-- model paid for a coroutine that was going to resolve on its first line.
	local humanoid = instance:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- A player's own character arrives here too; resolve the owner so it is
		-- treated as a player, not an NPC.
		onCharacter(Players:GetPlayerFromCharacter(instance), instance)
		return
	end

	task.spawn(function()
		local waited = instance:WaitForChild("Humanoid", 5)
		if not waited or not waited:IsA("Humanoid") then
			return
		end

		onCharacter(Players:GetPlayerFromCharacter(instance), instance)
	end)
end

local function onPlayer(player: Player)
	if player.Character then
		onCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)

	-- Fires before the old character is destroyed, so a death line still playing
	-- at respawn is stopped rather than left ringing over the next life. This is
	-- also the path that matters on an admin LoadCharacter of everyone at once.
	player.CharacterRemoving:Connect(function(character)
		Service.reset(character)
	end)
end

--[[
	Characters within `radius` of a world point, optionally filtered to one team.
	`team` nil means anyone.

	Used by area events that have a world position but no particular speaker -- an
	explosion, a captured point.

	This used to build an intermediate array of every bound humanoid on the server
	and then filter it, so a single grenade allocated a table sized to the entire
	player and NPC count before rejecting almost all of it. It now filters while
	walking `bound` directly, and compares squared distances rather than taking a
	square root per candidate.
]]
local function charactersNear(position: Vector3, radius: number, team: string?): { Model }
	local out = {}
	local radiusSq = radius * radius

	for humanoid in pairs(bound) do
		-- Cheapest first: both are plain property reads, and between them they
		-- reject every corpse and every humanoid whose model has been destroyed.
		if humanoid.Health <= 0 or not humanoid.Parent then
			continue
		end

		local character = humanoid.Parent
		if not character:IsA("Model") then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local delta = root.Position - position
		if delta:Dot(delta) > radiusSq then
			continue
		end

		-- Last, because it is the only lookup here that leaves the instance and
		-- it only matters for the few candidates that are actually in range.
		if team then
			local player = Players:GetPlayerFromCharacter(character)
			if not player or not player.Team or player.Team.Name ~= team then
				continue
			end
		end

		table.insert(out, character)
	end

	return out
end

--[[
	Bark when a capture point changes hands.

	Watches the same `Owner` StringValue the objective system's own MainHandler
	watches, so nothing in that system is edited. Entirely optional: if the place
	has no TObjectiveSystem this binds nothing and costs nothing.
]]
local function watchObjectivePoints()
	if not Config.ObjectiveBarks then
		return
	end

	local system = workspace:FindFirstChild("TObjectiveSystem")
	local points = system and system:FindFirstChild("Points")
	if not points then
		return
	end

	for _, point in ipairs(points:GetChildren()) do
		local owner = point:FindFirstChild("Owner")
		local marker = point:FindFirstChild("Point")
		if not owner or not owner:IsA("StringValue") then
			continue
		end
		if not marker or not marker:IsA("BasePart") then
			continue
		end

		owner:GetPropertyChangedSignal("Value"):Connect(function()
			local value = owner.Value
			-- 'None' is a point going neutral mid-capture, which happens
			-- constantly while it is contested. Only a completed capture speaks.
			if value ~= "Raiders" and value ~= "Defenders" then
				return
			end

			local team = Config.ObjectiveTeamNames[value]
			for _, character in ipairs(charactersNear(marker.Position, Config.ObjectiveRadius, team)) do
				Service.request(character, "PointTaken")
			end
		end)
	end
end

--[[
	Bayonet thrusts, from the TREK Bayonet package.

	Hooked on BayonetOutcome, a BindableEvent that package fires with
	(attacker, contact) once a thrust has been accepted and swept.

	NOT on BayonetStab, which is the obvious choice and the wrong one. That remote
	is the thrust REQUEST: it arrives before the rate limit, the equipment checks
	and the sweep have run, so a listener on it cannot tell a hit from a miss, or
	either from a thrust refused outright -- and it would bark for a swing that
	never happened, including one a client invented. The outcome signal is the
	only place the answer exists, which is why the bayonet package emits it.

	Two things make this unlike the TREK hooks. The signal is created at RUNTIME
	by BayonetService -- it is not in the shipped model -- so it can appear well
	after this runs; and in a place without the bayonet installed it never appears
	at all. Hence the wait, and hence doing it on its own thread: a package that
	may not exist must not hold up the hooks behind it.
]]
local BAYONET_WAIT = 20

local function watchBayonet()
	if not Config.BayonetBarks then
		return
	end

	task.spawn(function()
		local package = game:GetService("ReplicatedStorage"):WaitForChild("TREKBayonet", BAYONET_WAIT)
		if not package then
			return
		end

		local outcome = package:WaitForChild("BayonetOutcome", BAYONET_WAIT)
		if not outcome or not outcome:IsA("BindableEvent") then
			-- The package is installed but too old to report outcomes. Say so
			-- once: the alternative is two configured events that silently never
			-- fire, which is a much worse thing to debug.
			warn("[TREKVoicelines] TREKBayonet is installed but has no BayonetOutcome signal -- "
				.. "bayonet barks need a bayonet build that reports hit/miss. Skipping them.")
			return
		end

		outcome.Event:Connect(function(player: Player, contact: boolean)
			local character = player and player.Character
			if not character then
				return
			end

			Service.request(character, if contact then "BayonetHit" else "BayonetMiss")
		end)
	end)
end

-- Characters whose reload was announced at the start, so the matching end-of-
-- reload signal can be ignored. Weak keys: a character that goes away takes its
-- entry with it.
local reloadAnnounced: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Longer than any sane ReloadSpeed. Only guards against a stamp left behind by a
-- reload that was interrupted (death mid-reload), so it never suppresses a real one.
local RELOAD_STAMP_TTL = 30

function Hooks.start()
	-- TREK's own handlers are on these same RemoteEvents; a RemoteEvent takes any
	-- number of listeners, so these add to them rather than replacing them. No
	-- TREK script is touched.
	local remotes = (shared :: any).S.TREK_Remotes

	-- Reload START. Gun fires GFX('Reload') at the top of reloadTypeOne, before
	-- the ReloadSpeed wait -- so this is the moment the player is actually
	-- vulnerable and "reloading!" is worth shouting. The Reload remote below is
	-- the wrong moment: Gun only fires it after the wait has finished, which on
	-- the KT-60 is six seconds late.
	remotes:WaitForChild("GFX").OnServerEvent:Connect(function(player: Player, kind: any)
		if kind ~= "Reload" then
			return
		end

		local character = player.Character
		if not character then
			return
		end

		reloadAnnounced[character] = os.clock()
		Service.request(character, "Reload")
	end)

	-- Reload END. TREK sends this after the ReloadSpeed wait.
	--
	-- This no longer speaks for a normal reload -- there is no end-of-reload line
	-- any more. The stamp bookkeeping stays because it is what separates the two
	-- reload types: a ReloadType 1 weapon already spoke at the START, via GFX
	-- above, and must not speak again here.
	remotes:WaitForChild("Reload").OnServerEvent:Connect(function(player: Player)
		local character = player.Character
		if not character then
			return
		end

		local announced = reloadAnnounced[character]
		reloadAnnounced[character] = nil

		if announced and os.clock() - announced < RELOAD_STAMP_TTL then
			-- Already announced at the start of this reload. Nothing to add.
			return
		end

		-- No start signal ever came, which means a ReloadType 2 recharge weapon.
		-- Those trickle rounds in and never send GFX('Reload'), so finishing is
		-- the only moment there is to announce at all.
		Service.request(character, "Reload")
	end)

	-- Explosive impact. Gun and Turret both fire this with the blast position.
	-- The bark goes to characters NEAR the blast rather than to whoever fired --
	-- a reaction to incoming fire is worth hearing; one bark per explosive round
	-- from the shooter is just noise.
	remotes:WaitForChild("Explosion").OnServerEvent:Connect(function(_player: Player, position: any)
		if typeof(position) ~= "Vector3" then
			return
		end

		for _, character in ipairs(charactersNear(position, Config.IncomingRadius, nil)) do
			Service.request(character, "Incoming")
		end
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end

	watchObjectivePoints()
	watchBayonet()

	-- NPCs, dummies and admin-spawned clones. Guarded by `bound`, so a player
	-- character picked up here is not connected a second time.
	if Config.IncludeNPCs then
		workspace.ChildAdded:Connect(tryBindModel)
		for _, child in ipairs(workspace:GetChildren()) do
			tryBindModel(child)
		end
	end
end

return Hooks

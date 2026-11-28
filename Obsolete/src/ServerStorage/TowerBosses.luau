--[[
	TowerBosses
	Mini-boss floors for ServerScriptService.TowerRun. TowerDifficulties lists each difficulty's bossFloors and
	bossPool; on a boss floor TowerRun calls Bosses[id](ctx) and gates the floor clear on what it returns.

	ctx = {
	  spawn = function(cf, setup?): Model   -- TowerRun's spawnSoldier (tags, team, kill credit); setup(soldier) runs before he's parented
	  spots = { CFrame }            -- the floor's EnemySpawns, farthest from the stairs first
	  live  = function(): boolean   -- false once the run or floor is over; boss loops stop
	  entry = BasePart?             -- the floor's EntryPoint
	}
	returns { name = "HUD NAME", tagline = "intro card line", models = { Model } }
	ctx.reinforce(cf) spawns an alerted soldier who counts toward the clear (TowerRun).

	Every boss gets an intro card (StarterPlayerScripts.BossFX, from TowerStatus BossName / BossTagline) and a
	second phase at half health (phaseAt below: TowerStatus.BossPhase = 2 and a warning line).

	Ids:
	  CBRN  Bloxian CBRN Squad: an officer and 3 troopers in Bloxia kit and the MCU-2 mask (presets CBRN / CBRNOfficer: red lenses, yellow armband), immune to gas (attribute GasMask), who lob
	        sarin at the squad. Gas is the TREK Gas Grenade's GasCloud with a longer dose threshold, so leaving
	        the cloud fast enough saves you. Below half health the officer gasses his own position.
	        Counters: a crate of gas masks at the EntryPoint (worn at once, 30 s of filter per floor), and every
	        throw is telegraphed: "GAS!" and a 0.6 s windup (kill him in it and he drops it at his own feet),
	        then the canister hisses for 1 s before the cloud opens.
  Signals   Signals Officer at his desk radio with two of his men: once the floor is alerted, 15 s on the set warns
	        the next 2 floors (ctx.warnAhead), and 20 s after the alert he radios the squad's positions every 5 s.
	        His floor is also in lockdown: shutters seal every breach door; sabotage the junction box or kill him to lift them.
	  Jammer    Spectrum Denial Team: Jammer Operator with a manpack jammer, a Jammer Assistant and a rifleman (+2 escorts). Near him the HUD, kill feed and name tags
	        drop out under static (player attribute Jam).
  Juggernaut  A slow heavy in an EOD bomb suit (UniformPreset Juggernaut) with a belt-fed LMG on full auto at any range
	        (WeaponProfiles JuggernautLMG). Armor attribute: hits from the front and sides do a quarter (SPH_Server),
	        his back is open. Once alerted he walks at the nearest player. Two riflemen with him.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bosses = {}

-- Phase 2: once hum drops to frac of its max health, TowerStatus.BossPhase goes to 2 (BossFX stings, the boss
-- strip turns), text flashes as a BossWarning, and fn() runs. Ends quietly if the floor or the boss is over first.
local function phaseAt(ctx, hum, frac, text, fn)
	task.spawn(function()
		while ctx.live() and hum.Parent and hum.Health > 0 and hum.Health > hum.MaxHealth * frac do task.wait(0.25) end
		if not ctx.live() or not hum.Parent or hum.Health <= 0 then return end
		if ctx.status then
			ctx.status:SetAttribute("BossPhase", 2)
			ctx.status:SetAttribute("BossWarning", nil) -- same text twice still re-flashes
			ctx.status:SetAttribute("BossWarning", text)
		end
		fn()
	end)
end

-- Sarin -----------------------------------------------------------------------------------------------

local CBRN_DOSE = 1.2 -- seconds inside a cloud before the dose lands (the grenade's own is one tick)
local THROW_RANGE = 55
local THROW_EVERY = NumberRange.new(16, 24) -- per thrower
local THROW_GAP = 6 -- at least this long between any two squad throws
local FLIGHT = 0.9
local AIM_SPREAD = 4 -- studs off the target, so moving players can beat it
local MAX_CLOUDS = 2
local WINDUP = 0.6 -- "GAS!" to release; killing the thrower in this window drops the canister at his feet
local FUSE = 1 -- canister hisses on the floor this long before the cloud opens
local MASK_FILTER = 30 -- seconds of mask wear per player per CBRN floor
local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local gas -- { cloud = GasCloud module, config = boss config } once found, false if the package is missing

local function deepCopy(t)
	local c = {}
	for k, v in t do c[k] = if type(v) == "table" then deepCopy(v) else v end
	return c
end

local function findModule(name)
	for _, root in { ServerScriptService, ServerStorage, ReplicatedStorage } do
		local m = root:FindFirstChild(name, true)
		if m and m:IsA("ModuleScript") then return m end
	end
	return nil
end

local function loadGas()
	if gas ~= nil then return gas end
	local cloudModule, configModule = findModule("GasCloud"), findModule("GasConfig")
	if not cloudModule or not configModule then
		warn("TowerBosses: TREK Gas Grenade (GasCloud/GasConfig) is not in the place; the CBRN squad throws nothing")
		gas = false
		return gas
	end
	local ok, cloud = pcall(require, cloudModule)
	local ok2, config = pcall(require, configModule)
	if not ok or not ok2 then
		warn("TowerBosses: gas package failed to load: " .. tostring(if ok then config else cloud))
		gas = false
		return gas
	end
	config = deepCopy(config)
	if config.Nerve then config.Nerve.DoseThreshold = CBRN_DOSE end
	gas = { cloud = cloud, config = config }
	return gas
end

local clouds = 0

local function sarin(at)
	local g = loadGas()
	if not g then return end
	clouds += 1
	g.cloud.spawn(at, nil, g.config)
	task.delay((g.config.CloudDuration or 14) + 1, function() clouds -= 1 end)
end

local function sight(from, to, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(from, to - from, params) == nil
end

-- the nearest standing player this thrower can see within range
local function target(model)
	local head = model:FindFirstChild("Head")
	if not head then return nil end
	local best, bestD = nil, THROW_RANGE
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and p:GetAttribute("InTowerRun") then
			local d = (root.Position - head.Position).Magnitude
			if d < bestD and sight(head.Position, root.Position, { model, char }) then best, bestD = root, d end
		end
	end
	return best
end

local function ground(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	return if hit then hit.Position + Vector3.new(0, 0.3, 0) else pos
end

local function down(model, hum)
	return not model.Parent or not hum or hum.Health <= 0 or model:GetAttribute("Downed") or hum:GetAttribute("Downed")
end

local function shout(model)
	local head = model:FindFirstChild("Head")
	if not head then return end
	local bb = Instance.new("BillboardGui")
	bb.Name, bb.Adornee, bb.AlwaysOnTop, bb.LightInfluence = "GasShout", head, true, 0
	bb.Size, bb.StudsOffset, bb.MaxDistance = UDim2.fromOffset(100, 32), Vector3.new(0, 2.6, 0), 90
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	t.FontFace, t.Text, t.TextSize = FONT, "GAS!", 26
	t.TextColor3, t.TextStrokeTransparency = Color3.fromRGB(240, 200, 40), 0.3
	t.Parent = bb
	bb.Parent = head
	Debris:AddItem(bb, WINDUP + 1)
end

-- "GAS!", a windup, then an anchored canister on a parabola to near the target; it hisses, then the cloud opens.
local function lob(model, root)
	local hand = model:FindFirstChild("Right Arm") or model:FindFirstChild("Head")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hand or not hum then return end
	shout(model)
	local feet = model:GetPivot().Position
	local t = os.clock()
	while os.clock() - t < WINDUP do
		if down(model, hum) then -- killed mid-windup: the pin's out, it drops where he stood
			sarin(ground(if model.Parent then model:GetPivot().Position else feet, { model }))
			return
		end
		feet = model:GetPivot().Position
		task.wait()
	end
	if down(model, hum) then sarin(ground(feet, { model })) return end
	if not root.Parent then return end -- target gone during the windup: he holds it
	local anim = model:FindFirstChild("ThrowAnimation")
	local animator = hum:FindFirstChildOfClass("Animator")
	if anim and animator then pcall(function() animator:LoadAnimation(anim):Play() end) end
	local from = hand.Position + Vector3.new(0, 1, 0)
	local off = Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1) * AIM_SPREAD
	local aim = root.Position + root.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * 0.3 + off
	-- land on the floor under the aim point
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, root.Parent }
	local down = workspace:Raycast(aim + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	local land = if down then down.Position + Vector3.new(0, 0.3, 0) else aim
	local can = Instance.new("Part")
	can.Name = "SarinCanister"
	can.Shape = Enum.PartType.Cylinder
	can.Size = Vector3.new(0.9, 0.5, 0.5)
	can.Color = Color3.fromRGB(70, 78, 52)
	can.Material = Enum.Material.Metal
	can.Anchored, can.CanCollide, can.CanQuery, can.CanTouch = true, false, false, false
	can.Parent = workspace
	local hiss = Instance.new("Sound")
	hiss.SoundId = "rbxassetid://71965695347680"
	hiss.Volume = 0.5
	hiss.Parent = can
	local apex = math.min(6, (land - from).Magnitude * 0.15) -- indoors: keep under the ceiling
	local t0 = os.clock()
	while os.clock() - t0 < FLIGHT do
		local a = (os.clock() - t0) / FLIGHT
		can.CFrame = CFrame.new(from:Lerp(land, a) + Vector3.new(0, 4 * apex * a * (1 - a), 0)) * CFrame.Angles(a * 12, 0, a * 5)
		task.wait()
	end
	can.CFrame = CFrame.new(land) * CFrame.Angles(0, 0, math.rad(90))
	hiss:Play()
	Debris:AddItem(can, 15)
	task.wait(FUSE)
	sarin(land)
end

-- Player gas masks ------------------------------------------------------------------------------------
-- The highlighted mask on the desk by the EntryPoint gives each player one mask per CBRN floor (Player attributes HasMask, MaskFilter).
-- Taking one puts it straight on (and back on after a respawn) until the filter runs out; there's no storing it.
-- While it's on, the character carries GasMask, which GasCloud already treats as protected, and the filter drains.
-- Everything is taken back when the floor ends.

local MASK_MORPH = ServerStorage.BloxiaMorphs.GasMask -- MCU-2 mask, same one the CBRN squad wears

local function maskOff(char)
	if not char then return end
	char:SetAttribute("GasMask", nil)
	for _, p in char:GetChildren() do
		if p:GetAttribute("PlayerMask") then p:Destroy() end
	end
end

local function maskOn(char)
	local head = char:FindFirstChild("Head")
	if not head then return end
	char:SetAttribute("GasMask", true)
	for _, src in MASK_MORPH.Gear:GetChildren() do
		local p = src:Clone()
		p.Name = "PlayerGasMask"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
		p.CFrame = head.CFrame * MASK_MORPH.Head.CFrame:ToObjectSpace(src.CFrame)
		p:SetAttribute("PlayerMask", true)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = head, p
		w.Parent = p
		p.Parent = char
	end
end

-- wear it whenever this player has filter left and isn't already wearing it (pickup, respawn)
local function wearIfOwed(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and not char:GetAttribute("GasMask")
		and p:GetAttribute("HasMask") and (p:GetAttribute("MaskFilter") or 0) > 0 then
		maskOn(char)
	end
end

local function issueMasks(ctx)
	local crate
	local entry = ctx.entry
	if entry then
		local toward = if #ctx.spots > 0 then (ctx.spots[#ctx.spots].Position - entry.Position) * Vector3.new(1, 0, 1) else Vector3.zero
		local at = entry.Position + (if toward.Magnitude > 0.1 then toward.Unit * 5 else Vector3.zero)
		local floorAt = ground(at, {})
		-- the real MCU-2 mask (Body + Lens; no balaclava) standing on the desk nearest the stairs, facing them
		local desk, deskDist
		for _, d in (ctx.floor or entry.Parent):GetDescendants() do
			local n, pn = d.Name:lower(), d.Parent.Name:lower()
			if d:IsA("Model") and (n:find("desk") or n:find("table")) and not (pn:find("desk") or pn:find("table")) then
				local dist = (d:GetPivot().Position - entry.Position).Magnitude
				if dist < 30 and (not deskDist or dist < deskDist) then desk, deskDist = d, dist end
			end
		end
		if desk then
			local cf, sz = desk:GetBoundingBox()
			local params = RaycastParams.new() -- sees phones/lamps on the desk too
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {}
			-- try a few spots along the desk's long side; the lowest hit is bare desktop, not a phone or lamp
			local along = if sz.X >= sz.Z then cf.RightVector * sz.X else cf.LookVector * sz.Z
			local best
			for _, k in { 0.2, -0.2, 0 } do -- the ends first: clutter tends to sit mid-desk
				local hit = workspace:Raycast(cf.Position + along * k + Vector3.new(0, sz.Y / 2 + 1, 0), Vector3.new(0, -sz.Y - 2, 0), params)
				if hit and (not best or hit.Position.Y < best.Position.Y - 0.05) then best = hit end
			end
			if best then floorAt = best.Position end
		end
		crate = Instance.new("Model")
		crate.Name = "GasMaskPickup"
		local face = (entry.Position - floorAt) * Vector3.new(1, 0, 1) -- the face is head -Z: point it at the stairs, snapped to 90°
		local yaw = if face.Magnitude < 0.1 then 0 else math.round(math.atan2(-face.X, -face.Z) / (math.pi / 2)) * (math.pi / 2)
		local faceUp = CFrame.Angles(0, yaw, 0)
		local body
		for _, src in MASK_MORPH.Gear:GetChildren() do
			if src.Name ~= "Balaclava" then
				local p = src:Clone()
				p.Anchored, p.CanCollide, p.CanTouch = true, false, false
				p.CFrame = faceUp * MASK_MORPH.Head.CFrame:ToObjectSpace(src.CFrame)
				p.Parent = crate
				if src.Name == "Gas Mask Body" then body = p end
			end
		end
		local bcf, bsz = crate:GetBoundingBox()
		crate:PivotTo(CFrame.new(floorAt + Vector3.new(0, bsz.Y / 2, 0) - bcf.Position) * crate:GetPivot())
		local glow = Instance.new("Highlight")
		glow.FillColor, glow.OutlineColor = Color3.fromRGB(240, 200, 40), Color3.fromRGB(255, 220, 60)
		glow.FillTransparency, glow.OutlineTransparency = 0.7, 0
		glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- findable from the stairwell door
		glow.Parent = crate
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name, prompt.Style = "MaskPrompt", Enum.ProximityPromptStyle.Custom -- DoorPromptClient draws the house tag
		prompt.ActionText, prompt.ObjectText = "Take mask", "CBRN KIT"
		prompt.HoldDuration, prompt.RequiresLineOfSight, prompt.MaxActivationDistance = 0.3, false, 9
		prompt.Triggered:Connect(function(p)
			if p:GetAttribute("InTowerRun") and not p:GetAttribute("HasMask") then
				p:SetAttribute("MaskFilter", MASK_FILTER)
				p:SetAttribute("HasMask", true)
				wearIfOwed(p)
			end
		end)
		prompt.Parent = body or crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
		crate.Parent = workspace
	end
	task.spawn(function()
		while ctx.live() do
			local dt = task.wait(0.25)
			for _, p in Players:GetPlayers() do
				wearIfOwed(p)
				local char = p.Character
				if char and char:GetAttribute("GasMask") then
					local left = math.max(0, (p:GetAttribute("MaskFilter") or 0) - dt)
					p:SetAttribute("MaskFilter", left)
					if left <= 0 then maskOff(char) end
				end
			end
		end
		if crate then crate:Destroy() end
		for _, p in Players:GetPlayers() do
			maskOff(p.Character)
			p:SetAttribute("HasMask", nil)
			p:SetAttribute("MaskFilter", nil)
		end
	end)
end

function Bosses.CBRN(ctx)
	local models = {}
	local nextThrow = 0
	issueMasks(ctx)
	for i = 1, 4 do
		local spot = ctx.spots[(i - 1) % #ctx.spots + 1]
		local m = ctx.spawn(spot)
		local officer = i == 1
		m.Name = if officer then "CBRN Squad Lead" else "CBRN Trooper"
		m:SetAttribute("FeedName", m.Name) -- otherwise the kill feed calls them "Bloxian Rifleman"
		m:SetAttribute("GasMask", true) -- GasCloud's isProtected skips anyone with this
		m:SetAttribute("Boss", "CBRN")
		m:SetAttribute("UniformPreset", if officer then "CBRNOfficer" else "CBRN") -- UniformModule: Bloxia kit + MCU-2 mask
		local hum = m:FindFirstChildOfClass("Humanoid")
		if officer and hum then
			hum.MaxHealth *= 2.5
			hum.Health = hum.MaxHealth
		end
		table.insert(models, m)

		local enraged = false
		if officer and hum then
			-- hurt: gas where he stands, fight from inside it, and throw twice as often
			phaseAt(ctx, hum, 0.5, "AGENT RELEASED ON ENEMY CP", function()
				enraged = true
				sarin(m:GetPivot().Position)
			end)
		end
		task.spawn(function()
			local due = os.clock() + math.random(4, 10)
			while ctx.live() and m.Parent and hum and hum.Health > 0 do
				if os.clock() >= due and os.clock() >= nextThrow and clouds < MAX_CLOUDS then
					local root = target(m)
					if root then
						nextThrow = os.clock() + THROW_GAP
						due = os.clock() + math.random(THROW_EVERY.Min, THROW_EVERY.Max) * (if enraged then 0.5 else 1)
						task.spawn(lob, m, root)
					end
				end
				task.wait(0.5)
			end
		end)
	end
	return { name = "BLOXIAN CBRN SQUAD", tagline = "CHEM HAZARD  ·  DON MASKS AT INSERTION POINT", models = models }
end

-- Shared by the comms bosses ----------------------------------------------------------------------------
-- ctx.status is TowerStatus: BossWarning flashes a red line under the boss strip, BossObjective holds one there
-- (StarterPlayerScripts.BossFX draws both, plus the jammer static and the "spotted" flash).

local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Interior = ServerStorage:WaitForChild("CityKit"):WaitForChild("Interior")

local function flash(ctx, text)
	if ctx.status then
		ctx.status:SetAttribute("BossWarning", nil) -- same text twice still re-flashes
		ctx.status:SetAttribute("BossWarning", text)
	end
end

-- the KORBLOX COMMAND radio popup (AdminConsole LocalScript shows TowerStatus.Radio)
local function radio(ctx, text)
	if ctx.status then
		ctx.status:SetAttribute("Radio", nil) -- same text twice still re-sends
		ctx.status:SetAttribute("Radio", text)
	end
end

local function objective(ctx, text)
	if ctx.status then ctx.status:SetAttribute("BossObjective", text) end
end

local function bossMan(ctx, cf, name, id, hpMul, setup)
	local m = ctx.spawn(cf, setup)
	m.Name = name
	m:SetAttribute("FeedName", name)
	m:SetAttribute("Boss", id)
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum and hpMul then
		hum.MaxHealth *= hpMul
		hum.Health = hum.MaxHealth
	end
	return m, hum
end

-- alerted: the floor's first death clears Unalerted (TowerRun), or he got shot himself
local function waitForAlert(ctx, m, hum)
	while ctx.live() and not down(m, hum) and m:GetAttribute("Unalerted") ~= false and hum.Health >= hum.MaxHealth do
		task.wait(0.25)
	end
	return ctx.live() and not down(m, hum)
end

local function runners()
	local list = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if char and p:GetAttribute("InTowerRun") and char:FindFirstChild("HumanoidRootPart") then table.insert(list, p) end
	end
	return list
end

-- on the nearest wall to `pos`, at chest height, facing out of it; free-standing if no wall is close
local function wallMount(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local from = ground(pos, ignore) + Vector3.new(0, 4, 0)
	-- doors (and the lockdown shutters over them) are not wall: keep the mount clear of each doorway
	local doors = {}
	for _, d in CollectionService:GetTagged("BreachDoor") do
		if d:IsDescendantOf(workspace) and d:IsA("Model") then
			local cf, sz = d:GetBoundingBox()
			table.insert(doors, { cf, sz })
		end
	end
	local function nearDoor(p)
		for _, d in doors do
			local lp = d[1]:PointToObjectSpace(p)
			if math.abs(lp.X) < d[2].X / 2 + 2 and math.abs(lp.Z) < d[2].Z / 2 + 2 and math.abs(lp.Y) < d[2].Y / 2 + 2 then return true end
		end
		return false
	end
	local best
	for _, dir in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local hit = workspace:Raycast(from, dir * 14, params)
		if hit and math.abs(hit.Normal.Y) < 0.2 and not nearDoor(hit.Position) and (not best or hit.Distance < best.Distance) then best = hit end
	end
	if best then return best.Position + best.Normal * 0.46, best.Normal end
	return from, Vector3.zAxis
end

-- Swap a man's helmet for the radioman's patrol cap (plus any `extras`: { morph, sourcePart, name }).
-- UniformModule welds morph parts ("Morph<n>") a moment after spawn, so wait for them.
local RADIOMAN = ServerStorage.BloxiaMorphs.Radioman
local function wearPiece(m, morph, src, name)
	local body = morph:FindFirstChild(src:GetAttribute("Body") or "Torso")
	local mine = body and m:FindFirstChild(body.Name)
	if not mine then return end
	local p = src:Clone()
	for _, j in p:GetDescendants() do if j:IsA("JointInstance") or j:IsA("WeldConstraint") then j:Destroy() end end
	p.Name, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = name, false, false, false, false, true, false
	p.CFrame = mine.CFrame * body.CFrame:ToObjectSpace(src.CFrame)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = mine, p
	w.Parent = p
	p.Parent = m
end
local function patrolCap(m, extras)
	task.spawn(function()
		local head, t = m:FindFirstChild("Head"), 0
		local function headGear()
			local list = {}
			for _, p in m:GetChildren() do
				local w = p:IsA("BasePart") and p.Name:match("^Morph") and p:FindFirstChildOfClass("WeldConstraint")
				if w and w.Part0 == head then table.insert(list, p) end
			end
			return list
		end
		while head and #headGear() == 0 and t < 6 and m.Parent do t += task.wait(0.1) end
		if not (head and m.Parent) then return end
		for _, p in headGear() do p:Destroy() end
		wearPiece(m, RADIOMAN, RADIOMAN["Accessory (pcr)"].Handle, "PatrolCap")
		for _, e in extras or {} do wearPiece(m, e[1], e[2], e[3]) end
	end)
end

-- Signals Officer -----------------------------------------------------------------------------------------
-- He keeps his post: a duty desk against the wall of the farthest room with his ANGR-5 set on it, two of his
-- men with him. Patrol cap, headset and officer's armband. Once the floor is alerted he gets on the set (GoTo, Soldier AI).
--   10 s alive at the set: he warns the floors above (ctx.warnAhead: the next 2 start alerted, half as many again).
--   20 s after the alert, wherever he is: he radios the squad's positions every SPOT_EVERY s (character attribute
--   Spotted, a call counter: CoreModule counts each new call as a sighting through walls), until he's dead.

local lockdown -- (ctx, officer, hum): the Lockdown section below; the Signals Officer's floor is sealed
local SIG_TRANSMIT = 15 -- he starts at his set, so no chase: the squad gets 15 s once he's on it
local SIG_SPOT_DELAY = 20
local SIG_SPOT_EVERY = 5
local SIG_AT_RADIO = 5
local SIG_DESK, SIG_SET = Interior.DutyDesk, Interior.RadioANGR5 -- both pivot at bottom centre
local OFFICER_KIT = {
	{ RADIOMAN, RADIOMAN["Accessory (CommercialPilotHeadset(Black))"].Handle, "Headset" },
	{ ServerStorage.BloxiaMorphs.GasMaskOfficer, ServerStorage.BloxiaMorphs.GasMaskOfficer.Gear.Armband, "OfficerArmband" },
}

function Bosses.Signals(ctx)
	-- his post: the desk against the nearest wall of the farthest room, its back to the wall
	local hq = ctx.spots[1]
	local wallAt, normal = wallMount(hq.Position, {})
	local floorY = ground(hq.Position, {}).Y
	local _, deskSize = SIG_DESK:GetBoundingBox()
	local wall = Vector3.new(wallAt.X, floorY, wallAt.Z) - normal * 0.46
	local deskAt = wall + normal * (deskSize.Z / 2 + 0.15)
	local face = CFrame.lookAt(deskAt, deskAt + normal)
	local post = Instance.new("Model")
	post.Name = "SignalsPost"
	local desk = SIG_DESK:Clone()
	desk:PivotTo(face)
	desk.Parent = post
	post.Parent = workspace
	local onDesk = RaycastParams.new()
	onDesk.FilterType, onDesk.FilterDescendantsInstances = Enum.RaycastFilterType.Include, { desk }
	local top = workspace:Raycast(deskAt + Vector3.new(0, 8, 0), Vector3.new(0, -10, 0), onDesk)
	local radio = SIG_SET:Clone()
	radio.Name = "SignalsRadio"
	radio:PivotTo(CFrame.new(if top then top.Position else deskAt + Vector3.new(0, deskSize.Y, 0)) * face.Rotation)
	radio.Parent = post
	for _, d in post:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	local lamp = Instance.new("PointLight")
	lamp.Color, lamp.Range, lamp.Brightness = Color3.fromRGB(255, 60, 40), 8, 0
	lamp.Parent = radio.PrimaryPart or radio:FindFirstChildWhichIsA("BasePart", true)

	-- he stands at the desk working the set, his two men at his shoulders facing the door side
	local radioPos = deskAt + normal * (deskSize.Z / 2 + 2)
	local stand = radioPos + Vector3.new(0, 3.5, 0)
	local officerCf = CFrame.lookAt(stand, stand - normal)
	local m, hum = bossMan(ctx, officerCf, "Signals Officer", "Signals", 2)
	patrolCap(m, OFFICER_KIT)
	local models = { m }
	lockdown(ctx, m, hum)
	phaseAt(ctx, hum, 0.5, "ENEMY QRF INBOUND", function()
		if not ctx.reinforce then return end
		for i = 2, 3 do ctx.reinforce(ctx.spots[i] or ctx.spots[1]) end
	end)
	for _, side in { -1, 1 } do
		table.insert(models, ctx.spawn(officerCf * CFrame.new(side * 3, 0, 2.5) * CFrame.Angles(0, math.pi, 0)))
	end
	task.spawn(function()
		local calls, spotting, sent = 0, false, false
		if waitForAlert(ctx, m, hum) then
			m:SetAttribute("Unalerted", false)
			local alertAt, onRadio, nextCall = os.clock(), 0, 0
			flash(ctx, "ENEMY NET ACTIVE")
			while ctx.live() and not down(m, hum) do
				local dt = task.wait(0.25)
				local near = (m:GetPivot().Position - radioPos).Magnitude < SIG_AT_RADIO
				m:SetAttribute("GoTo", if sent or near then nil else radioPos)
				lamp.Brightness = if near and not sent and os.clock() % 0.6 < 0.3 then 3 else 0
				if not sent and near then
					onRadio += dt
					objective(ctx, string.format("ENEMY TX  ·  %ds", math.ceil(SIG_TRANSMIT - onRadio)))
					if onRadio >= SIG_TRANSMIT then
						sent = true
						ctx.warnAhead(2)
						flash(ctx, "UPPER FLOORS ALERTED")
						objective(ctx, nil)
					end
				end
				if not spotting and os.clock() - alertAt >= SIG_SPOT_DELAY then
					spotting = true
					flash(ctx, "POSITION COMPROMISED")
				end
				if spotting and os.clock() >= nextCall then
					calls += 1
					nextCall = os.clock() + SIG_SPOT_EVERY
					for _, p in runners() do p.Character:SetAttribute("Spotted", calls) end
					-- the call goes out over the floor's net: anyone still unalerted (CoreModule ignores calls then) wakes up
					for _, e in workspace:GetChildren() do
						if e:GetAttribute("Unalerted") then e:SetAttribute("Unalerted", false) end
					end
				end
			end
		end
		m:SetAttribute("GoTo", nil)
		for _, p in Players:GetPlayers() do
			if p.Character then p.Character:SetAttribute("Spotted", nil) end
		end
		if ctx.live() then
			flash(ctx, "RTO NEUTRALIZED")
			objective(ctx, nil)
		end
		while ctx.live() do task.wait(0.5) end
		post:Destroy()
	end)
	return { name = "SIGNALS OFFICER", tagline = "PRIORITY TARGET: ENEMY RTO  ·  DENY COMMS UP-TOWER", models = models }
end

-- Spectrum Denial Team ---------------------------------------------------------------------------------------
-- An operator with a jammer pack, and two escorts. While he's up every player gets a Jam attribute (0..1), full
-- within JAM_FULL studs of him and fading out at JAM_REACH: BossFX hides the HUD, kill feed and name tags and
-- lays static over the screen, heavier as Jam rises.

local JAM_FULL, JAM_REACH = 15, 90

-- Manpack jammer: the Creator Store "Signal Jammer" mesh (BloxiaMorphs.SignalJammer) strapped to a ruck frame,
-- grille out, antennas poking up behind his patrol cap. Falls back to a block if the mesh is missing.
local JAMMER_MESH = ServerStorage.BloxiaMorphs:FindFirstChild("SignalJammer")
local function jammerPack(m)
	local torso = m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso")
	if not torso then return end
	local function weld(p)
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.Anchored = false, false, false, true, false
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, p
		w.Parent = p
	end
	local function bit(size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = "JammerPack"
		p.Size, p.Color, p.Material = size, color, material or Enum.Material.Fabric
		p.CFrame = torso.CFrame * offset
		weld(p)
		p.Parent = m
		return p
	end
	local OLIVE, STRAP = Color3.fromRGB(62, 66, 48), Color3.fromRGB(28, 28, 26)
	bit(Vector3.new(1.8, 2, 0.3), CFrame.new(0, 0, 0.66), OLIVE) -- ruck frame on the back
	for _, x in { -0.55, 0.55 } do -- shoulder straps over the top and down the chest
		bit(Vector3.new(0.3, 0.08, 1.2), CFrame.new(x, 1.04, 0.1), STRAP)
		bit(Vector3.new(0.3, 1.3, 0.08), CFrame.new(x, 0.4, -0.54), STRAP)
	end
	local top -- where the LED sits
	if JAMMER_MESH then
		local j = JAMMER_MESH:Clone()
		j.Name = "JammerPack"
		j:ScaleTo(2.2)
		j:PivotTo(torso.CFrame * CFrame.new(0, -0.05, 0.81 + j.PrimaryPart.Size.Z / 2))
		for _, p in j:GetDescendants() do if p:IsA("BasePart") then weld(p) end end
		j.Parent = m
		local b = j.PrimaryPart
		bit(Vector3.new(b.Size.X + 0.1, 0.22, b.Size.Z + 0.08), torso.CFrame:ToObjectSpace(b.CFrame * CFrame.new(0, -0.35, 0)), STRAP) -- tie-down band
		top = b.CFrame * CFrame.new(b.Size.X * 0.32, b.Size.Y / 2 + 0.06, 0)
	else
		local box = bit(Vector3.new(1.5, 1.9, 0.75), CFrame.new(0, 0, 1.2), OLIVE, Enum.Material.Metal)
		for _, x in { -0.5, 0, 0.5 } do bit(Vector3.new(0.08, 3, 0.08), CFrame.new(x, 2.4, 1.2), STRAP, Enum.Material.Metal) end
		top = box.CFrame * CFrame.new(0.5, 1.01, 0)
	end
	local led = bit(Vector3.new(0.22, 0.12, 0.22), torso.CFrame:ToObjectSpace(top), Color3.fromRGB(255, 40, 30), Enum.Material.Neon)
	led.Name = "JammerLED"
	return led
end


function Bosses.Jammer(ctx)
	local op, hum = bossMan(ctx, ctx.spots[1], "Jammer Operator", "Jammer", 1.5)
	local led = jammerPack(op)
	patrolCap(op)
	local models = { op }
	-- the Assistant spawns at the Operator's side (spot 2 if a wall is there) and keeps to it
	local side = ctx.spots[1] * CFrame.new(3, 0, 0)
	local ray = RaycastParams.new()
	ray.FilterDescendantsInstances = { op }
	local blocked = workspace:Raycast(ctx.spots[1].Position, side.Position - ctx.spots[1].Position, ray)
	local asst, asstHum = bossMan(ctx, if blocked and ctx.spots[2] then ctx.spots[2] else side, "Jammer Assistant", "Jammer")
	table.insert(models, asst)
	patrolCap(asst)
	task.spawn(function()
		local aRoot = asst:FindFirstChild("HumanoidRootPart")
		while ctx.live() and aRoot and not down(asst, asstHum) and not down(op, hum) do
			local at = op:GetPivot()
			-- re-issued often: his own AI keeps giving him cover/angle moves, this wins most ticks
			if (aRoot.Position - at.Position).Magnitude > 8 then asstHum:MoveTo((at * CFrame.new(3, 0, 1)).Position) end
			task.wait(0.15)
		end
	end)
	if ctx.spots[3] then table.insert(models, ctx.spawn(ctx.spots[3])) end -- plain Bloxian rifleman
	flash(ctx, "COMMS JAMMED")
	local boost = 1 -- phase 2 pushes the jam out this much farther
	phaseAt(ctx, hum, 0.5, "J██MER O█T██T INC███SED", function() boost = 1.6 end)
	task.spawn(function()
		while ctx.live() and not down(op, hum) do
			local at = op:GetPivot().Position
			for _, p in Players:GetPlayers() do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				local jam = 0
				if root and p:GetAttribute("InTowerRun") then
					local d = (root.Position - at).Magnitude
					jam = math.clamp((JAM_REACH * boost - d) / ((JAM_REACH - JAM_FULL) * boost), 0, 1)
				end
				jam = math.round(jam * 20) / 20
				if p:GetAttribute("Jam") ~= jam then p:SetAttribute("Jam", if jam > 0 then jam else nil) end
			end
			local blink = 0.5 / boost
			if led then led.Transparency = if os.clock() % blink < blink / 2 then 0 else 0.8 end
			task.wait(0.2)
		end
		for _, p in Players:GetPlayers() do p:SetAttribute("Jam", nil) end
		if ctx.live() then
			flash(ctx, "COMMS RESTORED")
			objective(ctx, nil)
		end
	end)
	return { name = "SPECTRUM DENIAL TEAM", tagline = "EW T█REAT  ·  COM█S DEGRA█ED IN PRO█IMITY", models = models }
end

-- Lockdown -----------------------------------------------------------------------------------------------------
-- The Signals Officer's floor is sealed: a hazard-striped steel shutter slams over every BreachDoor (door attribute
-- Lockdown: DoorService ignores it, NPCs too). A junction box is mounted where the squad can still reach (checked
-- with pathfinding from the EntryPoint; if nothing's reachable the shutters nearest the stairs stay up).
-- Sabotage the box (hold E) or kill the officer and every shutter rolls up.

local BOX_HOLD = 6
local HAZARD_Y, HAZARD_K = Color3.fromRGB(235, 190, 30), Color3.fromRGB(20, 20, 20)

local function shutterFace(part, face)
	local sg = Instance.new("SurfaceGui")
	sg.Face, sg.LightInfluence, sg.PixelsPerStud = face, 1, 40
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud -- PixelsPerStud is ignored under the default FixedSize
	sg.Parent = part
	local band = Instance.new("Frame") -- hazard band along the bottom
	band.Size, band.Position = UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.86)
	band.BackgroundColor3, band.BorderSizePixel, band.ClipsDescendants = HAZARD_Y, 0, true
	band.Parent = sg
	for i = -2, 16 do
		local st = Instance.new("Frame")
		st.AnchorPoint = Vector2.new(0.5, 0.5)
		st.Size, st.Position, st.Rotation = UDim2.new(1 / 28, 0, 3, 0), UDim2.new(i / 14, 0, 0.5, 0), 35
		st.BackgroundColor3, st.BorderSizePixel = HAZARD_K, 0
		st.Parent = band
	end
	local top = band:Clone() -- and the top
	top.Position, top.Size = UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.07)
	top.Parent = sg
	local t = Instance.new("TextLabel")
	t.Size, t.Position, t.BackgroundTransparency = UDim2.fromScale(0.9, 0.12), UDim2.fromScale(0.05, 0.36), 1
	t.FontFace, t.TextScaled, t.Text = FONT, true, "LOCKDOWN"
	t.TextColor3 = Color3.fromRGB(215, 45, 35)
	t.Parent = sg
	local t2 = t:Clone()
	t2.Position, t2.Size, t2.Text = UDim2.fromScale(0.1, 0.5), UDim2.fromScale(0.8, 0.06), "SECURITY SEAL · NO ENTRY"
	t2.TextColor3 = Color3.fromRGB(220, 220, 220)
	t2.Parent = sg
end

-- Roller shutter: a housing over the frame and guide rails down the sides hold it; the slab unrolls out of the
-- housing (Size + CFrame tween, top edge fixed) and rolls back up into it.
local ROLLED_H = 0.1
local function roll(slab, down, t)
	local h, rest = slab:GetAttribute("FullHeight"), slab:GetAttribute("Rest")
	local size = Vector3.new(slab.Size.X, if down then h else ROLLED_H, slab.Size.Z)
	local cf = if down then rest else rest * CFrame.new(0, h / 2 + 0.3, 0) -- rolled: tucked inside the housing
	if t == 0 then slab.Size, slab.CFrame = size, cf return end
	TweenService:Create(slab, TweenInfo.new(t, Enum.EasingStyle.Quad, if down then Enum.EasingDirection.In else Enum.EasingDirection.InOut), { Size = size, CFrame = cf }):Play()
end

local function makeShutter(door)
	local pivot = door:GetPivot()
	local w, h = (door:GetAttribute("Width") or 6) + 0.8, (door:GetAttribute("Height") or 8.5) + 0.3
	local model = Instance.new("Model")
	model.Name = "LockdownShutter"
	local first
	for _, side in { 1, -1 } do -- a sheet on each face of the door, just off the leaves
		local slab = Instance.new("Part")
		slab.Name = "Slab"
		slab.Size = Vector3.new(w, h, 0.35)
		slab.Color, slab.Material = Color3.fromRGB(78, 82, 88), Enum.Material.DiamondPlate
		slab.Anchored, slab.CanCollide = true, true
		slab.CFrame = pivot * CFrame.new(0, h / 2, 0.62 * side) * CFrame.Angles(0, if side < 0 then math.pi else 0, 0)
		first = first or slab
		slab:SetAttribute("FullHeight", h)
		slab:SetAttribute("Rest", slab.CFrame)
		shutterFace(slab, Enum.NormalId.Front)
		shutterFace(slab, Enum.NormalId.Back)
		slab.Parent = model
		local function fixed(name, size, cf)
			local p = Instance.new("Part")
			p.Name, p.Size, p.CFrame = name, size, cf
			p.Color, p.Material = Color3.fromRGB(52, 55, 60), Enum.Material.Metal
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			p.Parent = model
			return p
		end
		local housing = fixed("Housing", Vector3.new(w + 0.5, 0.9, 0.9), slab.CFrame * CFrame.new(0, h / 2 + 0.45, 0))
		for _, side in { -1, 1 } do fixed("Rail", Vector3.new(0.22, h, 0.55), slab.CFrame * CFrame.new(side * (w / 2 + 0.11), 0, 0)) end
		local beacon = Instance.new("Part")
		beacon.Name = "Beacon"
		beacon.Shape = Enum.PartType.Cylinder
		beacon.Size = Vector3.new(0.5, 0.6, 0.6)
		beacon.Color, beacon.Material = Color3.fromRGB(255, 50, 35), Enum.Material.Neon
		beacon.Anchored, beacon.CanCollide, beacon.CanQuery = true, false, false
		beacon.CFrame = housing.CFrame * CFrame.new(0, 0.45 + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90))
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 50, 35), 12, 2
		light.Parent = beacon
		beacon.Parent = model
	end
	model.PrimaryPart = first
	return model, first.CFrame
end

-- fuse box mesh (ServerStorage.JunctionBoxMesh): cabinet opens toward its -Z, door hanging open, back is its +Z face
local BOX_MESH = ServerStorage:FindFirstChild("JunctionBoxMesh")

local function makeJunctionBox(at, facing)
	local box = Instance.new("Model")
	box.Name = "JunctionBox"
	local mount = CFrame.lookAt(at, at + facing) -- `at` is 0.46 off the wall; the wall is at mount's +Z
	local body
	if BOX_MESH then
		body = BOX_MESH:Clone()
		body.CFrame = mount * CFrame.new(0, 0, 0.46 - body.Size.Z / 2) -- back flush on the wall
	else
		body = Instance.new("Part")
		body.Size = Vector3.new(2.6, 3.2, 0.9)
		body.Color, body.Material = Color3.fromRGB(110, 116, 104), Enum.Material.Metal
		body.CFrame = mount
	end
	body.Name, body.Anchored = "Body", true
	body.Parent = box
	local sign = Instance.new("Part") -- warning sign on the wall above it
	sign.Name = "Sign"
	sign.Size = Vector3.new(1.4, 0.75, 0.05)
	sign.Color, sign.Anchored, sign.CanCollide, sign.CanQuery = HAZARD_Y, true, false, false
	sign.CFrame = mount * CFrame.new(0, 2.1, 0.43)
	sign.Parent = box
	local sg = Instance.new("SurfaceGui")
	sg.Face, sg.PixelsPerStud, sg.LightInfluence = Enum.NormalId.Front, 80, 1
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Parent = sign
	local warnPlate = Instance.new("Frame")
	warnPlate.Size, warnPlate.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	warnPlate.Parent = sg
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency, t.FontFace, t.TextScaled = UDim2.fromScale(1, 1), 1, FONT, true
	t.Text, t.TextColor3 = "DANGER\nHIGH VOLTAGE", HAZARD_K -- no glyph: HighwayGothic has no ⚡, it pushed DANGER off-centre
	t.Parent = warnPlate
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.08, 0), UDim.new(0.08, 0)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.1, 0), UDim.new(0.1, 0)
	pad.Parent = t
	local glow = Instance.new("Highlight")
	glow.FillColor, glow.OutlineColor = HAZARD_Y, Color3.fromRGB(255, 220, 60)
	glow.FillTransparency, glow.OutlineTransparency = 0.75, 0
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.Parent = box
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.Style = "SabotagePrompt", Enum.ProximityPromptStyle.Custom -- DoorPromptClient draws it like Revive
	prompt.ActionText, prompt.ObjectText = "Sabotage", "JUNCTION BOX"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = BOX_HOLD, 8, false
	prompt.Parent = body
	box.PrimaryPart = body
	box.Parent = workspace
	return box, prompt
end


local function reachable(from, to)
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = true })
	local ok = pcall(function() path:ComputeAsync(from, to) end)
	return ok and path.Status == Enum.PathStatus.Success
end

function lockdown(ctx, m, hum)
	local root = ctx.floor or workspace
	local seals = {} -- { door, model, restCf, prompts = { [prompt] = wasEnabled } }
	for _, door in CollectionService:GetTagged("BreachDoor") do
		if door:IsDescendantOf(root) then
			local model, rest = makeShutter(door)
			local seal = { door = door, model = model, rest = rest, prompts = {} }
			door:SetAttribute("Lockdown", true)
			for _, pr in door:GetDescendants() do
				if pr:IsA("ProximityPrompt") then
					seal.prompts[pr] = pr.Enabled
					pr.Enabled = false
				end
			end
			model:PivotTo(rest)
			model.Parent = workspace
			table.insert(seals, seal)
		end
	end
	local entryPos = if ctx.entry then ctx.entry.Position + Vector3.new(0, 2, 0) else nil

	local function lift(seal, quick)
		if seal.lifted then return end
		seal.lifted = true
		seal.door:SetAttribute("Lockdown", nil)
		for pr, was in seal.prompts do if pr.Parent then pr.Enabled = was end end
		-- the housing and rails stay; the beacon goes dark
		for _, p in seal.model:GetChildren() do
			if p.Name == "Beacon" then
				p.Material, p.Color = Enum.Material.SmoothPlastic, Color3.fromRGB(90, 30, 25)
				local light = p:FindFirstChildOfClass("PointLight")
				if light then light.Enabled = false end
			elseif p.Name == "Slab" then
				if quick then p:Destroy() continue end
				p.CanCollide = false
				roll(p, false, 1.4)
				Debris:AddItem(p, 1.5)
			end
		end
	end

	-- where the box goes: the farthest spawn the squad can walk to with the shutters down
	local boxSpot
	if entryPos then
		task.wait(0.2) -- let the new shutters into the navmesh
		local order = table.clone(seals)
		table.sort(order, function(a, b) return (a.rest.Position - entryPos).Magnitude < (b.rest.Position - entryPos).Magnitude end)
		for tries = 0, #order do
			for i = 2, #ctx.spots do -- spot 1 is the officer's
				local p = ctx.spots[i].Position
				if (p - entryPos).Magnitude > 20 and reachable(entryPos, p) then boxSpot = p break end
			end
			if boxSpot or tries == #order then break end
			lift(order[tries + 1], true) -- nothing reachable yet: leave the shutter nearest the stairs open
			task.wait(0.2)
		end
	end
	boxSpot = boxSpot or (if entryPos then entryPos + Vector3.new(0, 0, -8) else ctx.spots[1].Position)
	local at, facing = wallMount(boxSpot, { m })
	local box, prompt = makeJunctionBox(at, facing)

	-- slam: each shutter unrolls out of its housing with the door's kick sound
	for _, seal in seals do
		if not seal.lifted then
			for _, slab in seal.model:GetChildren() do
				if slab.Name == "Slab" then
					roll(slab, false, 0)
					roll(slab, true, 0.35)
				end
			end
			local kick = seal.door:FindFirstChild("Kick", true)
			if kick then
				local s = kick:Clone()
				s.Parent = seal.model.PrimaryPart
				task.delay(0.35, function() if s.Parent then s:Play() end end)
			end
		end
	end
	flash(ctx, "BREACH POINTS SEALED")

	local sabotaged = false
	prompt.Triggered:Connect(function(p)
		if p:GetAttribute("InTowerRun") then sabotaged = true end
	end)
	task.spawn(function()
		while ctx.live() and not sabotaged and not down(m, hum) do task.wait(0.25) end
		prompt.Enabled = false
		if sabotaged then
			local sparks = Instance.new("Sparkles")
			sparks.SparkleColor = HAZARD_Y
			sparks.Parent = box.PrimaryPart
			Debris:AddItem(sparks, 3)
		end
		local hl = box:FindFirstChildOfClass("Highlight") -- no longer the objective either way
		if hl then hl.Enabled = false end
		if ctx.live() then
			flash(ctx, "BREACH POINTS OPEN")
			objective(ctx, nil)
		end
		for _, seal in seals do lift(seal, not ctx.live()) end
		while ctx.live() do task.wait(0.5) end
		box:Destroy()
		for _, seal in seals do seal.model:Destroy() end
	end)
end

-- Juggernaut -----------------------------------------------------------------------------------------------------
-- Holds the farthest room until the floor is alerted, then walks at the nearest player, never taking cover,
-- firing 40-round strings (no tap fire at range). His plates cover the front and sides, not the back.

local JUGG_ARMOR = 0.25 -- share of damage a hit from the front or sides does
local JUGG_HP = 4 -- x the soldier's health
local JUGG_SPEED = 8
local JUGG_CLOSE = 18 -- he stops walking this close and just shoots
local JUGG_FACEPLATE = 3750 -- raw head damage that breaks his faceplate (~25 rifle headshots); SPH_Server reads FaceplateHP

-- RPG-7s lying around his floor, on the stairs' side (ctx.spots runs farthest first, so the back of the list).
-- Each is one pickup (hold E); the launchers handed out are taken back when the floor ends.
local RPG_PICKUPS = 3
local RPG_TOOL = ServerStorage:FindFirstChild("RPG-7")
local RPG_MODEL = ReplicatedStorage.SPH_Assets.WeaponModels:FindFirstChild("RPG-7")

-- at: explicit pickup CFrames (the Apache roof); otherwise picked from ctx.spots
local function rpgPickups(ctx, at)
	if not RPG_TOOL or not RPG_MODEL then return end
	local spots, used = at or {}, {}
	local n = if at then 0 else #ctx.spots
	for _, i in { n, math.ceil(n * 0.75), math.ceil(n * 0.5), n - 1 } do
		if i >= 4 and not used[i] and #spots < RPG_PICKUPS then -- spots 1-3 are the Juggernaut and his riflemen
			used[i] = true
			table.insert(spots, ctx.spots[i])
		end
	end
	if #spots == 0 and ctx.entry then spots = { CFrame.new(ctx.entry.Position) } end
	local pickups, given = {}, {}
	for _, cf in spots do
		local m = RPG_MODEL:Clone()
		m.Name = "RPGPickup"
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanTouch = true, false, false
			elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then d:Destroy() end
		end
		local at = ground((cf * CFrame.new(3, 0, 0)).Position, { m })
		-- lay it flat: turn the bounding box's longest axis to world X, then yaw by a random 90°
		local box, size = m:GetBoundingBox()
		local lie = if size.X >= size.Y and size.X >= size.Z then CFrame.identity
			elseif size.Y >= size.Z then CFrame.Angles(0, 0, math.pi / 2) else CFrame.Angles(0, math.pi / 2, 0)
		local flat = lie:VectorToWorldSpace(size)
		local want = CFrame.new(at + Vector3.new(0, math.abs(flat.Y) / 2, 0)) * CFrame.Angles(0, math.random(0, 3) * math.pi / 2, 0) * lie
		m:PivotTo(want * box:ToObjectSpace(m:GetPivot()))
		local glow = Instance.new("Highlight")
		glow.FillColor, glow.OutlineColor = Color3.fromRGB(240, 200, 40), Color3.fromRGB(255, 220, 60)
		glow.FillTransparency, glow.OutlineTransparency = 0.7, 0
		glow.Parent = m
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name, prompt.Style = "RPGPrompt", Enum.ProximityPromptStyle.Custom -- DoorPromptClient draws the house tag
		prompt.ActionText, prompt.ObjectText = "Take RPG", "ANTI-ARMOR"
		prompt.HoldDuration, prompt.RequiresLineOfSight, prompt.MaxActivationDistance = 0.5, false, 9
		prompt.Triggered:Connect(function(p)
			local backpack = p:FindFirstChild("Backpack")
			if not backpack or not p:GetAttribute("InTowerRun") or not m.Parent then return end
			if backpack:FindFirstChild(RPG_TOOL.Name) or (p.Character and p.Character:FindFirstChild(RPG_TOOL.Name)) then return end -- one each
			local tool = RPG_TOOL:Clone()
			tool.Parent = backpack
			table.insert(given, tool)
			m:Destroy()
		end)
		prompt.Parent = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
		m.Parent = workspace
		table.insert(pickups, m)
	end
	task.spawn(function()
		while ctx.live() do task.wait(0.5) end
		for _, m in pickups do m:Destroy() end
		for _, tool in given do
			local hum = tool.Parent and tool.Parent:FindFirstChildOfClass("Humanoid")
			if hum then hum:UnequipTools() task.wait(0.4) end -- SPH needs it holstered before it goes
			tool:Destroy()
		end
	end)
end

function Bosses.Juggernaut(ctx)
	rpgPickups(ctx)
	local m, hum = bossMan(ctx, ctx.spots[1], "Juggernaut", "Juggernaut", JUGG_HP, function(s)
		s:SetAttribute("UniformPreset", "Juggernaut")
		s:SetAttribute("NoKnife", true)
		s:SetAttribute("NoGrenades", true)
		s:SetAttribute("Armor", JUGG_ARMOR)
		s:SetAttribute("FaceplateHP", JUGG_FACEPLATE)
		local settings = s:FindFirstChild("Settings")
		for name, value in { Weapon = "JuggernautLMG", RandomAppearance = false, UseCover = false, DetectionRange = 150, AwarenessRange = 150 } do
			local v = settings and settings:FindFirstChild(name)
			if v then v.Value = value end
		end
		local h = s:FindFirstChildOfClass("Humanoid")
		if h then h.WalkSpeed = JUGG_SPEED end -- SpeedModule reads it as his base
	end)
	local models = { m }
	for i = 2, 3 do
		if ctx.spots[i] then table.insert(models, ctx.spawn(ctx.spots[i])) end
	end
	local close = JUGG_CLOSE
	-- plates cracking: he takes twice the damage, but charges you at double speed
	phaseAt(ctx, hum, 0.5, "PHASE 2", function()
		close = 6
		m:SetAttribute("Armor", JUGG_ARMOR * 2)
		-- SpeedService owns WalkSpeed (his SpeedModule goes through it), so a modifier, not a write
		local ss = ServerScriptService:FindFirstChild("Common") and ServerScriptService.Common:FindFirstChild("SpeedService")
		if ss then require(ss).setModifier(hum, "JuggernautEnraged", { mul = 2 }) else hum.WalkSpeed = JUGG_SPEED * 2 end
	end)
	task.spawn(function()
		if waitForAlert(ctx, m, hum) then
			m:SetAttribute("Unalerted", false)
			while ctx.live() and not down(m, hum) do
				local at, best, bestD = m:GetPivot().Position, nil, math.huge
				for _, p in runners() do
					local d = (p.Character.HumanoidRootPart.Position - at).Magnitude
					if d < bestD then best, bestD = p.Character.HumanoidRootPart.Position, d end
				end
				m:SetAttribute("GoTo", if best and bestD > close then best else nil)
				task.wait(1)
			end
		end
		if m.Parent then m:SetAttribute("GoTo", nil) end
		if ctx.live() then
			flash(ctx, "JUGGERNAUT DOWN")
			objective(ctx, nil)
		end
	end)
	return { name = "JUGGERNAUT", tagline = "HEAVY ARMOR  ·  ENGAGE FROM REAR OR DEFEAT FACEPLATE", models = models }
end

-- Apache (the roof, before extraction) ---------------------------------------------------------------------------
-- TowerRun's extraction calls it with ctx = { live, status, center = roof deck centre (Vector3), rpgSpots = { CFrame } }.
-- An AH-64 (ServerStorage.Apache, anchored, moved by script) flies a fixed clockwise loop of four checkpoints just
-- outside the parapet corners. At each it hovers facing the squad: a red laser marks its target for GUN_WINDUP
-- seconds, then the chin gun fires a burst. Every round is a raycast from the gun, so the roof cover stops it.
-- RPG-7s lie around the roof; ExplosionFX takes one off the Hits attribute for each blast that reaches a model
-- tagged ApacheBoss. At half hits it also fires two Hydra rockets at the target before each burst (red ring first); each is a rocket
-- from the pods that flies at the ring and explodes on the first thing it hits. Roof fences (SPH_NoCollide) are see-through to it.
-- Either objective ends it: shoot it down, or survive APACHE_SURVIVE seconds and it breaks off and flies away.
-- Returns like a floor boss; the model gets attribute Down once it's gone either way (TowerRun waits on that).

local APACHE_HITS = 5
local APACHE_SURVIVE = 120 -- matches the radio call: "hold it off for two minutes"
local APACHE_ALT = 30 -- hover height above the deck
local APACHE_RING = 150 -- checkpoint distance from the roof centre, on the diagonals (the 200x200 roof's corners are ~141 out)
local APACHE_LEG = { 7, 5 } -- seconds between checkpoints, phase 1 / 2
local APACHE_HOVER = { 5, 3.5 } -- seconds at a checkpoint, phase 1 / 2
local GUN_WINDUP = { 0.9, 0.6 } -- laser time before a burst, phase 1 / 2
local GUN_BURST = 2.2
local GUN_RATE = 14 -- rounds per second
local GUN_DAMAGE = 11 -- caught in the open a full burst kills; cover stops every round
local GUN_SPREAD = 3 -- studs of scatter around the target, so running still beats some of it
local STRAFE_EVERY = { 3.5, 2 } -- seconds between bursts fired on the move, phase 1 / 2
local GUN_SOUND = "rbxassetid://146320268"
local HYDRA_FLIGHT = 1.4
local HYDRA_RADIUS = 10
local HYDRA_SPREAD = 6
local RED = Color3.fromRGB(255, 40, 30)

local function beam(from, to, width, color, life)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color = Enum.Material.Neon, color
	p.Size = Vector3.new(width, width, (to - from).Magnitude)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = workspace
	if life then Debris:AddItem(p, life) end
	return p
end

local function runnerRoots()
	local roots = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and p:GetAttribute("InTowerRun") and not hum:GetAttribute("Downed") and not char:GetAttribute("Downed") then
			table.insert(roots, root)
		end
	end
	return roots
end

function Bosses.Apache(ctx)
	local template = ServerStorage:FindFirstChild("Apache")
	if not template then error("ServerStorage.Apache is missing") end
	local explode = require(ReplicatedStorage.SPH_Assets.Modules.ExplosionFX)
	local heli = template:Clone()
	heli.Name = "ApacheBoss"
	heli:SetAttribute("Hits", APACHE_HITS)
	CollectionService:AddTag(heli, "ApacheBoss")
	local gun, mainRotor, tailRotor = heli.M230, heli.MainRotor, heli.TailRotor
	local ignore = RaycastParams.new()
	ignore.FilterType = Enum.RaycastFilterType.Exclude
	-- SPH_NoCollide parts (the roof's chain-link fences) don't stop bullets, so they don't stop the Apache's either
	local skip = CollectionService:GetTagged("SPH_NoCollide")
	table.insert(skip, heli)
	ignore.FilterDescendantsInstances = skip
	ignore.RespectCanCollide = true

	local c = ctx.center
	local checkpoints = {}
	for i = 0, 3 do -- clockwise from the NE corner, seen from above
		local a = math.rad(45 - i * 90)
		table.insert(checkpoints, c + Vector3.new(math.cos(a), 0, -math.sin(a)) * APACHE_RING + Vector3.new(0, APACHE_ALT, 0))
	end

	local cf = CFrame.lookAt(checkpoints[1] + Vector3.new(300, 80, -300), checkpoints[1])
	heli:PivotTo(cf)
	heli.Parent = workspace
	local rotor = heli.Body:FindFirstChild("Rotor")
	if rotor then rotor:Play() end

	-- every frame: the body goes to cf, its nose eased round (toward yawTo if set, else cf's own facing); rotors spin
	local yawTo = nil
	local snap = false -- the crash spin: no easing
	local pose = cf
	local conn = RunService.Heartbeat:Connect(function(dt)
		local want = cf
		if yawTo then
			local look = (yawTo - cf.Position) * Vector3.new(1, 0, 1)
			if look.Magnitude > 0.1 then want = CFrame.lookAt(cf.Position, cf.Position + look) end
		end
		pose = if snap then cf else CFrame.new(cf.Position) * pose.Rotation:Lerp(want.Rotation, math.min(1, dt * 2.5))
		heli:PivotTo(pose)
		-- SpinAxis: each rotor's axis in its own space (ServerStorage.Apache sets it; the tail rotor's isn't Y)
		mainRotor.CFrame *= CFrame.fromAxisAngle(mainRotor:GetAttribute("SpinAxis") or Vector3.yAxis, dt * 28)
		tailRotor.CFrame *= CFrame.fromAxisAngle(tailRotor:GetAttribute("SpinAxis") or Vector3.yAxis, dt * 45)
	end)

	local phase = 1 -- 2 from half hits: faster legs and laser, Hydra rockets, more strafing

	local function fly(to, seconds, stopAt)
		local from = cf.Position
		yawTo = nil
		cf = CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z))
		local t = 0
		while t < seconds and heli:GetAttribute("Hits") > 0 and ctx.live() and os.clock() < (stopAt or math.huge) do
			t += task.wait()
			local a = math.clamp(t / seconds, 0, 1)
			a = a * a * (3 - 2 * a)
			cf = CFrame.lookAt(from:Lerp(to, a), to + (to - from).Unit) * CFrame.Angles(math.rad(-8) * math.sin(a * math.pi), 0, 0) -- nose down mid-leg
		end
	end

	local function pickTarget()
		local muzzle = gun.Position
		local seen, all = {}, runnerRoots()
		for _, root in all do
			local hit = workspace:Raycast(muzzle, root.Position - muzzle, ignore)
			if hit and hit.Instance:IsDescendantOf(root.Parent) then table.insert(seen, root) end
		end
		local list = if #seen > 0 then seen else all
		return list[math.random(math.max(#list, 1))]
	end

	local rocketSpare = heli.Functionality.PilotWeapons["Hydra70-1"].Rockets:FindFirstChildWhichIsA("Model"):Clone()
	local function hydra(root)
		for i = 1, 2 do
			if not root.Parent then return end
			local aim = root.Position + Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1) * HYDRA_SPREAD
			local floor = workspace:Raycast(aim + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), ignore)
			local land = if floor then floor.Position else aim - Vector3.new(0, 3, 0)
			-- red ring where it lands, for the whole flight
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
			ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, RED, 0.55
			ring.Size = Vector3.new(0.1, HYDRA_RADIUS * 1.2, HYDRA_RADIUS * 1.2)
			ring.CFrame = CFrame.new(land + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Parent = workspace
			local pod = heli:FindFirstChild("HydraCannon" .. i) or gun
			local from = pod.Position
			-- the pod's own rocket leaves the pod (a spare clone once it's empty); its pivot looks down the nose
			local rack = heli.Functionality.PilotWeapons["Hydra70-" .. i].Rockets
			local rocket = rack:FindFirstChildWhichIsA("Model") or rocketSpare:Clone()
			for _, part in rocket:GetDescendants() do
				if part:IsA("BasePart") then part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false end
			end
			rocket.Parent = workspace
			local dir = (land - from).Unit
			rocket:PivotTo(CFrame.lookAt(from, from + dir))
			local exhaust = Instance.new("Attachment")
			exhaust.Parent = rocket:FindFirstChildWhichIsA("BasePart")
			exhaust.WorldPosition = from - dir * 3
			local fire = Instance.new("Fire")
			fire.Size, fire.Heat = 2, 0
			fire.Parent = exhaust
			local smoke = Instance.new("Smoke")
			smoke.Size, smoke.Opacity, smoke.RiseVelocity, smoke.Color = 1.5, 0.35, 0, Color3.fromRGB(200, 200, 200)
			smoke.Parent = exhaust
			task.spawn(function()
				-- flies straight at the ring and blows up on the first thing it touches (the ring's floor, at the latest)
				local speed = (land - from).Magnitude / HYDRA_FLIGHT
				local p, t, at = from, 0, nil
				while not at and t < HYDRA_FLIGHT * 2 do
					local dt = task.wait()
					t += dt
					local step = dir * speed * dt
					local hit = workspace:Raycast(p, step, ignore)
					if hit then at = hit.Position else p += step end
					rocket:PivotTo(CFrame.lookAt(p, p + dir))
				end
				rocket:Destroy()
				ring:Destroy()
				explode(at or p, HYDRA_RADIUS, "Default", nil)
			end)
			task.wait(0.35)
		end
	end

	local function burst(root)
		-- windup: a red laser from the gun onto the target
		local t = 0
		local laser = nil
		while t < GUN_WINDUP[phase] and root.Parent and heli:GetAttribute("Hits") > 0 do
			if laser then laser:Destroy() end
			laser = beam(gun.Position, root.Position, 0.15, RED)
			t += task.wait()
		end
		if laser then laser:Destroy() end
		local shots = math.floor(GUN_BURST * GUN_RATE)
		for _ = 1, shots do
			if not root.Parent or heli:GetAttribute("Hits") <= 0 or not ctx.live() then return end
			local muzzle = gun.Position
			local aim = root.Position + Vector3.new(math.random() * 2 - 1, math.random() - 0.5, math.random() * 2 - 1) * GUN_SPREAD
			local dir = (aim - muzzle).Unit * ((aim - muzzle).Magnitude + 30)
			local hit = workspace:Raycast(muzzle, dir, ignore)
			local stop = if hit then hit.Position else muzzle + dir
			beam(muzzle, stop, 0.2, Color3.fromRGB(255, 210, 120), 0.05)
			local s = Instance.new("Sound")
			s.SoundId, s.Volume, s.RollOffMaxDistance = GUN_SOUND, 1.2, 500
			s.Parent = gun
			s.PlayOnRemove = true
			s:Destroy()
			local hum = hit and hit.Instance.Parent and hit.Instance.Parent:FindFirstChildOfClass("Humanoid")
			if hum and Players:GetPlayerFromCharacter(hum.Parent) then hum:TakeDamage(GUN_DAMAGE) end
			task.wait(1 / GUN_RATE)
		end
	end

	-- hits from ExplosionFX: HUD pips, phase 2 at half
	ctx.status:SetAttribute("BossLeft", APACHE_HITS)
	-- invisible solid hull box: SPH rockets stop on it (SPH_Collide beats the Transparency=1 pierce rule), so a rocket
	-- can't slip between the mesh's collision hulls or behind the client's slightly late copy of the moving heli
	do
		local body = heli.Body
		local box = Instance.new("Part")
		box.Name, box.Transparency, box.Anchored, box.CanCollide, box.CanQuery, box.CanTouch, box.Massless = "Hitbox", 1, true, true, true, false, true
		local bcf, bsize = heli:GetBoundingBox()
		-- hull only: the rotor disc is most of the box's width, so use the fuselage's width and height, full length
		-- measured against the hull meshes: fuselage + stub wings ~16 wide, ~14 tall, 60 long, centred 3 studs aft
		box.Size = Vector3.new(16, 14, 60)
		box.CFrame = CFrame.new(bcf.Position.X, body.Position.Y, bcf.Position.Z) * heli:GetPivot().Rotation * CFrame.new(0, 0, 3)
		CollectionService:AddTag(box, "SPH_Collide")

		box.Parent = heli
	end
	heli:GetAttributeChangedSignal("Hits"):Connect(function()
		local hits = math.max(heli:GetAttribute("Hits"), 0)
		ctx.status:SetAttribute("BossLeft", hits)
		if phase == 1 and hits > 0 and hits <= APACHE_HITS / 2 then
			phase = 2
			ctx.status:SetAttribute("BossPhase", 2)
			flash(ctx, "PHASE 2")
		end
	end)

	rpgPickups(ctx, ctx.rpgSpots)
	-- after TowerRun sets BossName (once this returns), so BossFX types them into the boss card
	task.delay(2, function()
		if ctx.live() then radio(ctx, "Hostile Apache inbound, how'd it get through?!!!") end
	end)
	task.delay(6, function()
		if ctx.live() then radio(ctx, "Hold it off for two minutes! We'll scramble air assets in your AO.") end
	end)
	local deadline = os.clock() + (ctx.survive or APACHE_SURVIVE) -- ctx.survive: shorter, for Studio tests
	local over = false
	task.spawn(function() -- the countdown on the objective line
		while not over do
			local left = math.max(0, math.ceil(deadline - os.clock()))
			objective(ctx, string.format("SURVIVE %d:%02d OR SHOOT IT DOWN", left // 60, left % 60))
			task.wait(1)
		end
	end)

	task.spawn(function()
		fly(checkpoints[1], 7) -- inbound
		local i = 1
		while ctx.live() and heli:GetAttribute("Hits") > 0 and os.clock() < deadline do
			-- hover: face the squad, rockets (phase 2), then a burst
			local hoverEnd = os.clock() + APACHE_HOVER[phase]
			cf = CFrame.new(cf.Position)
			yawTo = c
			task.wait(0.8)
			-- keep firing until it's time to move: rockets (phase 2) then a burst, again and again
			repeat
				local root = pickTarget()
				if root then
					yawTo = root.Position
					if phase == 2 then hydra(root) end
					burst(root)
				end
				task.wait(0.3)
			until os.clock() >= math.min(hoverEnd, deadline) or not ctx.live() or heli:GetAttribute("Hits") <= 0
			i = i % #checkpoints + 1
			-- strafe: bursts on the move along the leg
			local moving = true
			task.spawn(function()
				task.wait(1)
				while moving and ctx.live() and heli:GetAttribute("Hits") > 0 do
					local root = pickTarget()
					if root then burst(root) end
					task.wait(STRAFE_EVERY[phase])
				end
			end)
			fly(checkpoints[i], APACHE_LEG[phase], deadline)
			moving = false
		end
		over = true
		objective(ctx, nil)
		if not ctx.live() then
			conn:Disconnect()
			heli:Destroy()
			return
		end
		if heli:GetAttribute("Hits") > 0 then
			-- the squad held out: it breaks off, climbing away from the roof
			CollectionService:RemoveTag(heli, "ApacheBoss")
			flash(ctx, "APACHE BREAKING OFF")
			local from = cf.Position
			local away = ((from - c) * Vector3.new(1, 0, 1)).Unit
			fly(from + away * 500 + Vector3.new(0, 120, 0), 9)
			conn:Disconnect()
			heli:SetAttribute("Down", true)
			heli:Destroy()
			return
		end
		-- shot down: blast, then it spins away from the roof trailing fire and goes off the edge
		CollectionService:RemoveTag(heli, "ApacheBoss")
		radio(ctx, "Splash one! That Apache is going down, good work!")
		explode(heli.Body.Position, 0, "Default", nil)
		local fire = Instance.new("Fire")
		fire.Size, fire.Heat = 18, 12
		fire.Parent = heli.Body
		local smoke = Instance.new("Smoke")
		smoke.Size, smoke.Opacity, smoke.RiseVelocity, smoke.Color = 12, 0.6, 6, Color3.fromRGB(40, 40, 40)
		smoke.Parent = heli.Body
		local from = cf.Position
		local away = ((from - c) * Vector3.new(1, 0, 1)).Unit
		yawTo, snap = nil, true
		local t, yaw = 0, 0
		while t < 5 do
			local dt = task.wait()
			t += dt
			yaw += dt * math.rad(300)
			cf = CFrame.new(from + away * t * 14 - Vector3.new(0, t * t * 5, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-15), 0, math.rad(10))
		end
		explode(heli.Body.Position, 0, "Default", nil)
		conn:Disconnect()
		heli:SetAttribute("Down", true)
		heli:Destroy()
	end)
	return { name = "AH-64 APACHE", tagline = "GUNSHIP ON STATION", models = { heli } }
end

return Bosses

--[[
	BarrageService
	Decides when a barrage happens and where every shell in it lands.

	Structure follows Variable Snowstorm's ThunderService, which already solves
	the same shape of problem: a windowed event with a warning lead, scheduled
	work that has to be cancellable, and a generation counter so a barrage that
	was stopped cannot detonate shells it queued before it ended.

	This service never creates a shell part. It publishes four numbers per shell
	and lets each client draw its own -- see ShellRender.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Shared = require(ArtilleryFolder:WaitForChild("ArtilleryShared"))
local ImpactService = require(script.Parent:WaitForChild("ImpactService"))
local CharacterCache = require(game:GetService("ServerScriptService"):WaitForChild("Common"):WaitForChild("CharacterCache"))

local Attr = Shared.Attr

local BarrageService = {}

local stateHolder: Instance
local shellEvent: RemoteEvent?

local running = false
local barrageActive = false
local generation = 0

-- Reused for the ground snap. The character filter is rebuilt per barrage, not
-- per shell.
local snapParams = RaycastParams.new()
snapParams.FilterType = Enum.RaycastFilterType.Exclude
snapParams.IgnoreWater = false
snapParams.RespectCanCollide = true

-- Same character filter as the ground snap, but water is ignored: a swimmer has
-- open sky above them, and counting the surface as a roof would make anyone in
-- the water untargetable.
local shelterParams = RaycastParams.new()
shelterParams.FilterType = Enum.RaycastFilterType.Exclude
shelterParams.IgnoreWater = true
shelterParams.RespectCanCollide = true

local debugMarkers: { BasePart } = {}

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Artillery] " .. message, ...))
	end
end

local function refreshSnapFilter()
	local ignore = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	snapParams.FilterDescendantsInstances = ignore
	shelterParams.FilterDescendantsInstances = ignore
end

-- ============================================================
-- PLACEMENT
-- ============================================================

-- Y is ignored on purpose, so a single flat plate tagged over a spawn protects
-- the whole column above it rather than only the slab's own thickness.
local function inSafeZone(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged(Config.SafeZoneTag) do
		if zone:IsA("BasePart") then
			local offset = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size * 0.5
			if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- Offsets for the shelter samples, scaled by ShelterSampleRadius: one ray
-- straight up plus four around it.
local SHELTER_SAMPLES = {
	Vector2.new(0, 0),
	Vector2.new(1, 0),
	Vector2.new(-1, 0),
	Vector2.new(0, 1),
	Vector2.new(0, -1),
}

--[[
	True if there is enough over this position to call it a roof.

	Casts UP rather than testing anything for being a ceiling: whatever stops the
	ray is the roof. A bunker, a bridge, a rock overhang and a tree canopy all
	work with nothing tagged and nothing authored.

	Sampled across five rays rather than one, for the same reason the damage
	cover check is sampled: one ray straight up is a coin flip on the edge of any
	cover, so standing in a doorway would flicker between safe and targetable
	from one barrage to the next.

	This only stops the guns AIMING at you. It is not a shield -- a shell aimed
	at the squad outside your door still lands outside your door, and the blast
	does not care what you are standing under.
]]
local function isSheltered(position: Vector3): boolean
	if not Config.SkipShelteredPlayers then
		return false
	end

	local up = Vector3.new(0, Config.ShelterCheckHeight, 0)
	local origin = position + Vector3.new(0, 2, 0)

	local blocked = 0
	for _, offset in SHELTER_SAMPLES do
		local from = origin + Vector3.new(offset.X, 0, offset.Y) * Config.ShelterSampleRadius
		if workspace:Raycast(from, up, shelterParams) then
			blocked += 1
		end
	end

	return blocked / #SHELTER_SAMPLES >= Config.ShelterBlockedThreshold
end

-- Drops the impact onto whatever surface is under it. Without this, shells
-- detonate at the height of whoever they were aimed from, which over a hill or
-- a trench means airbursts nobody can see.
local function snapToGround(position: Vector3): Vector3?
	local from = Vector3.new(position.X, position.Y + Config.GroundSnapHeight, position.Z)
	local length = Config.GroundSnapHeight + Config.GroundSnapDepth

	local result = workspace:Raycast(from, Vector3.new(0, -length, 0), snapParams)
	if result then
		return result.Position
	end
	return nil
end

--[[
	Picks the barrage's centre, weighted toward whoever has company. This is the
	Centaura behaviour: the guns fire at random, but the random is biased to
	where people actually are.

	Players under a roof are dropped from the candidate list entirely -- they
	cannot be seen from a battery kilometres away, so shelling them is the guns
	knowing something they have no way to know. They also stop counting toward
	anyone else's cluster weight, which falls out of the same list and is right:
	a squad that made it indoors should not still be pulling fire onto the door
	they came through.
]]
local function pickEpicenter(): Vector3?
	local positions: { Vector3 } = {}
	local sheltered = 0

	for _, player in Players:GetPlayers() do
		local entry = CharacterCache.getAlive(player)
		if entry then
			if isSheltered(entry.root.Position) then
				sheltered += 1
			else
				table.insert(positions, entry.root.Position)
			end
		end
	end

	if #positions == 0 then
		if sheltered > 0 then
			log("barrage skipped -- all %d players are under cover", sheltered)
		end
		return nil
	end

	local weights = table.create(#positions)
	local total = 0

	for index, position in positions do
		-- One point for existing, one more for every neighbour. A lone player is
		-- never immune, just less likely than a squad.
		local weight = 1
		for other, otherPosition in positions do
			if other ~= index and (otherPosition - position).Magnitude <= Config.ClusterRadius then
				weight += 1
			end
		end
		weights[index] = weight
		total += weight
	end

	local roll = math.random() * total
	local chosen = positions[#positions]

	for index, weight in weights do
		roll -= weight
		if roll <= 0 then
			chosen = positions[index]
			break
		end
	end

	local angle = math.random() * math.pi * 2
	local radius = math.sqrt(math.random()) * Config.EpicenterJitter

	return chosen + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- scatter: how wide around the epicenter (studs); ShellScatterRadius for the battery.
local function rollImpact(epicenter: Vector3, scatter: number): Vector3?
	for _ = 1, Config.SafeZoneRetries do
		local angle = math.random() * math.pi * 2
		local radius = math.random() ^ Config.ScatterCenterBias * scatter

		local candidate = epicenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if not inSafeZone(candidate) then
			local grounded = snapToGround(candidate)
			if grounded then
				return grounded
			end
		end
	end
	return nil
end

-- ============================================================
-- FIRING
-- ============================================================

local function clearMarkers()
	for _, marker in debugMarkers do
		marker:Destroy()
	end
	table.clear(debugMarkers)
end

local function addMarker(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "ArtilleryImpactMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.4, Config.KillRadius * 2, Config.KillRadius * 2)
	marker.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 0.6
	marker.Color = Color3.fromRGB(255, 70, 40)
	marker.Material = Enum.Material.Neon
	marker.Parent = workspace

	table.insert(debugMarkers, marker)
end

-- gunship: a model with a Muzzle attachment (the AC-130). Its shells leave from
-- there, and its Shots attribute counts up so it can flash and fire its sound.
local function fireShell(impact: Vector3, heading: number, isLive: () -> boolean, gunship: Model?)
	local event = shellEvent
	if not event then
		return
	end

	local flightTime: number
	local launch: Vector3
	local muzzle = gunship and gunship.Parent and gunship:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		flightTime = Shared.rollRange(Config.GunshipShellFlightTime)
		launch = muzzle.WorldPosition
		gunship:SetAttribute("Shots", (gunship:GetAttribute("Shots") or 0) + 1)
	else
		flightTime = Shared.rollRange(Config.ShellFlightTime)
		local spread = (math.random() - 0.5) * 2 * Config.BatteryHeadingSpread
		launch = Shared.launchPoint(
			impact,
			heading + spread,
			Shared.rollRange(Config.ShellLaunchDistance),
			Shared.rollRange(Config.ShellLaunchHeight)
		)
	end

	-- GetServerTimeNow is shared between the server and every client, so an
	-- absolute impact stamp is all the clients need to land their explosion on
	-- the same frame the damage happens -- whatever their ping is. Sending a
	-- duration instead would drift by exactly one trip's latency per shell.
	local impactTime = workspace:GetServerTimeNow() + flightTime

	-- Sent to everyone rather than distance-gated: trails are meant to be
	-- visible from across the map, and dead players watching the barrage land
	-- have no character to measure a distance from. The payload is four values,
	-- and the client culls what it cannot see.
	event:FireAllClients(launch, impact, flightTime, impactTime)

	task.delay(flightTime, function()
		if not isLive() then
			return
		end
		ImpactService.detonate(impact)
	end)
end

-- A gunship's own barrage on epicenter: no warning, straight into its shells,
-- and apart from the battery, so both can fire at once. Stops if the gunship is
-- shot down or gone.
local function runGunshipBarrage(epicenter: Vector3, gunship: Model, count: number)
	refreshSnapFilter()

	local impacts: { Vector3 } = {}
	for _ = 1, count do
		local impact = rollImpact(epicenter, Config.GunshipScatterRadius)
		if impact then
			table.insert(impacts, impact)
		end
	end
	log("gunship barrage -- %d shells, no warning", #impacts)

	local function live(): boolean
		return running
	end
	for _, impact in impacts do
		if not running or not gunship.Parent or gunship:GetAttribute("ShotDown") == true then
			log("gunship barrage stopped -- its gunship is down")
			return
		end
		fireShell(impact, 0, live, gunship)
		task.wait(Shared.rollRange(Config.GunshipShellSpacing))
	end
	task.wait(Config.GunshipShellFlightTime.Max)
end

-- epicenterOverride: a fire mission's aim point. Without one the guns pick
-- their own, biased toward where players are. mission.caller: whoever called it
-- (the barrage stops the moment he is dead). mission.gunship: what it is fired
-- from, if not the battery (the barrage stops if it is shot down or gone).
local function runBarrage(epicenterOverride: Vector3?, mission: { caller: Model?, gunship: Model? }?)
	generation += 1
	local thisGeneration = generation
	barrageActive = true

	local caller = mission and mission.caller
	local gunship = mission and mission.gunship
	local function callerDown(): boolean
		local gunshipLost = gunship ~= nil and (not gunship.Parent or gunship:GetAttribute("ShotDown") == true)
		if not caller and not gunshipLost then
			return false
		end
		local human = caller and caller.Parent and caller:FindFirstChildOfClass("Humanoid")
		if not gunshipLost and (not caller or (human and human.Health > 0)) then
			return false
		end
		barrageActive = false
		stateHolder:SetAttribute(Attr.WarningActive, false)
		stateHolder:SetAttribute(Attr.BarrageActive, false)
		stateHolder:SetAttribute(Attr.ShellsLeft, 0)
		stateHolder:SetAttribute(Attr.SecondsToFirstImpact, 0)
		clearMarkers()
		log("barrage called off -- %s", if gunshipLost then "its gunship is down" else "whoever called it is dead")
		return true
	end

	refreshSnapFilter()

	local epicenter = epicenterOverride or pickEpicenter()
	if not epicenter then
		barrageActive = false
		log("barrage skipped -- nobody alive to shell")
		return
	end

	local heading = if Config.RandomBatteryHeading then math.random() * 360 else Config.BatteryHeading

	local count = math.round(Shared.rollRange(Config.ShellsPerBarrage))
	local impacts: { Vector3 } = {}

	--A gunship puts its shells right where the radioman called; the battery spreads them.
	local scatter = if gunship then Config.GunshipScatterRadius else Config.ShellScatterRadius
	for _ = 1, count do
		local impact = rollImpact(epicenter, scatter)
		if impact then
			table.insert(impacts, impact)
		end
	end

	if #impacts == 0 then
		barrageActive = false
		log("barrage skipped -- every impact landed in a safe zone or off the map")
		return
	end

	if Config.DebugDrawImpacts then
		clearMarkers()
		for _, impact in impacts do
			addMarker(impact)
		end
	end

	log(
		"BARRAGE INCOMING -- %d shells, heading %.0f, first impact in %.0fs",
		#impacts,
		heading,
		Config.BarrageWarningLead
	)

	-- The warning. Clients watch this attribute and play the battery report off
	-- it, the same way the snowstorm's clients pick up ThunderActive.
	stateHolder:SetAttribute(Attr.WarningActive, true)
	stateHolder:SetAttribute(Attr.ShellsLeft, #impacts)

	local warningEndsAt = os.clock() + Config.BarrageWarningLead
	while os.clock() < warningEndsAt do
		if thisGeneration ~= generation or callerDown() then
			return
		end
		stateHolder:SetAttribute(Attr.SecondsToFirstImpact, math.max(math.round(warningEndsAt - os.clock()), 0))
		task.wait(0.25)
	end

	if thisGeneration ~= generation then
		return
	end

	stateHolder:SetAttribute(Attr.WarningActive, false)
	stateHolder:SetAttribute(Attr.SecondsToFirstImpact, 0)
	stateHolder:SetAttribute(Attr.BarrageActive, true)

	local left = #impacts
	for _, impact in impacts do
		if thisGeneration ~= generation or callerDown() then
			return
		end

		fireShell(impact, heading, function()
			return thisGeneration == generation
		end, gunship)
		left -= 1
		stateHolder:SetAttribute(Attr.ShellsLeft, left)

		task.wait(Shared.rollRange(if gunship then Config.GunshipShellSpacing else Config.ShellSpacing))
	end

	-- Hold the window open until the last shell has actually landed, or a UI
	-- reading BarrageActive calls the all-clear while rounds are still in the
	-- air.
	task.wait(Config.ShellFlightTime.Max)

	if thisGeneration == generation then
		barrageActive = false
		stateHolder:SetAttribute(Attr.BarrageActive, false)
		clearMarkers()
		log("barrage over")
	end
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

function BarrageService.triggerNow()
	if not running or barrageActive then
		return false
	end
	task.spawn(runBarrage)
	return true
end

function BarrageService.isActive(): boolean
	return barrageActive
end

--[[
	A fire mission called in from inside the game (a Bloxian radioman, say): the
	same barrage, centred on position instead of on wherever players cluster.

	Gives back true and what a caller needs to get clear -- seconds of warning,
	the radius shells can land and still kill in, and how long until the last
	shell is down -- or false and why it could not fire.

	With mission.gunship (the AC-130 firing on its own) it is the gunship's
	barrage instead: no warning, and it fires whether or not the battery is.
]]
function BarrageService.fireMission(position: Vector3, mission: { caller: Model?, gunship: Model? }?): (boolean, any)
	if not running then
		return false, "artillery is not running"
	end
	local gunship = mission and mission.gunship
	if gunship then
		local count = math.round(Shared.rollRange(Config.ShellsPerBarrage))
		task.spawn(function()
			runGunshipBarrage(position, gunship, count)
			if gunship.Parent then
				gunship:SetAttribute("MissionOver", true)
			end
		end)
		return true, {
			gunship = true,
			warning = 0,
			radius = Config.GunshipScatterRadius + Config.KillRadius,
			duration = count * Config.GunshipShellSpacing.Max + Config.GunshipShellFlightTime.Max,
		}
	end
	if barrageActive then
		return false, "the guns are already firing"
	end

	task.spawn(function()
		runBarrage(position, mission)
		local gunship = mission and mission.gunship
		if gunship and gunship.Parent then
			gunship:SetAttribute("MissionOver", true)
		end
	end)
	return true, {
		gunship = mission ~= nil and mission.gunship ~= nil,
		warning = Config.BarrageWarningLead,
		firstImpact = Config.BarrageWarningLead + Config.ShellFlightTime.Min,
		radius = (if mission and mission.gunship then Config.GunshipScatterRadius else Config.ShellScatterRadius)
			+ Config.KillRadius,
		duration = Config.BarrageWarningLead
			+ Config.ShellsPerBarrage.Max * Config.ShellSpacing.Max
			+ Config.ShellFlightTime.Max,
	}
end

function BarrageService.start()
	if not Config.Enabled then
		return
	end

	if running then
		warn("[BarrageService] start() called twice; ignoring.")
		return
	end
	running = true

	stateHolder = Shared.getStateHolder()
	shellEvent = Shared.getShellEvent()

	stateHolder:SetAttribute(Attr.BarrageActive, false)
	stateHolder:SetAttribute(Attr.WarningActive, false)
	stateHolder:SetAttribute(Attr.ShellsLeft, 0)
	stateHolder:SetAttribute(Attr.SecondsToFirstImpact, 0)

	if not shellEvent then
		running = false
		warn(
			"[BarrageService] ReplicatedStorage.ArtilleryShell is missing -- artillery disabled. "
				.. "Move it into ReplicatedStorage alongside Artillery and ArtilleryState (install step 2)."
		)
		return
	end

	log(
		"ready -- barrages every %.0f-%.0fs, %.0f-%.0f shells each",
		Config.BarrageInterval.Min,
		Config.BarrageInterval.Max,
		Config.ShellsPerBarrage.Min,
		Config.ShellsPerBarrage.Max
	)

	if not Config.NaturalBarrages then
		log("natural barrages off -- only fire missions fire")
		return
	end

	task.spawn(function()
		local firstWait = if Config.DebugFirstBarrageDelay >= 0
			then Config.DebugFirstBarrageDelay
			else Shared.rollRange(Config.BarrageInterval)

		task.wait(firstWait)

		while running do
			local online = #Players:GetPlayers()
			if online >= Config.MinPlayersForBarrage then
				local ok, err = pcall(runBarrage)
				if not ok then
					warn("[BarrageService] barrage failed", err)
					barrageActive = false
					stateHolder:SetAttribute(Attr.BarrageActive, false)
					stateHolder:SetAttribute(Attr.WarningActive, false)
				end
			else
				-- Silent here used to look identical to broken: the loop would
				-- skip forever with nothing in Output, and DebugBarrageNow (which
				-- has no player-count check at all) would still fire -- so the
				-- system LOOKED like it only ever worked from the debug command.
				-- This is the whole reason for that.
				log(
					"natural barrage skipped -- %d online, MinPlayersForBarrage is %d. "
						.. "DebugBarrageNow ignores this and always fires.",
					online,
					Config.MinPlayersForBarrage
				)
			end

			task.wait(Shared.rollRange(Config.BarrageInterval))
		end
	end)
end

function BarrageService.stop()
	running = false
	generation += 1
	barrageActive = false

	if stateHolder then
		stateHolder:SetAttribute(Attr.BarrageActive, false)
		stateHolder:SetAttribute(Attr.WarningActive, false)
	end

	clearMarkers()
end

return BarrageService

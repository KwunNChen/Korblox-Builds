-- Thunderstorm window inside the Peak phase. Owns strike placement and kills.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))
local CharacterCache = require(ServerScriptService:WaitForChild("Common"):WaitForChild("CharacterCache"))

local Attr = Shared.Attr

local ThunderService = {}

-- Raise to schedule less often, lower for tighter strike timing.
local SCHEDULE_INTERVAL = 0.25

-- Candidate positions tried before giving up on this player's turn. Raise if
-- strikes feel sparse where players gather.
local MAX_PLACEMENT_ATTEMPTS = 4

local THUNDER_PHASE = "Peak"

local stateHolder: Instance
local strikeEvent: RemoteEvent?

local running = false
local windowActive = false
local windowGeneration = 0

type Strike = { position: Vector3 }

local nextStrikeAt = setmetatable({}, { __mode = "k" }) :: { [Player]: number }
local spawnedAt = setmetatable({}, { __mode = "k" }) :: { [Player]: number }
local anchors: { Player } = {}

local pending: { Strike } = {}

local strikeParams = RaycastParams.new()
strikeParams.FilterType = Enum.RaycastFilterType.Exclude
strikeParams.IgnoreWater = true

local function refreshCharacterFilter()
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	strikeParams.FilterDescendantsInstances = characters
end

local function rollInterval(sheltered: boolean): number
	local range = Config.ThunderStrikeInterval
	local seconds = range.Min + math.random() * (range.Max - range.Min)

	if sheltered then
		seconds /= math.max(Config.ThunderShelteredRateScale, 0.01)
	end
	return seconds
end

-- Must check every player, not just the anchor, or standing still stops being
-- survivable once two people are near each other.
local function isClearOfPlayers(position: Vector3): boolean
	local limit = Config.ThunderSafeRadius * Config.ThunderSafeRadius

	for _, player in Players:GetPlayers() do
		local entry = CharacterCache.get(player)
		if entry then
			local offset = entry.root.Position - position
			if offset:Dot(offset) < limit then
				return false
			end
		end
	end
	return true
end

local function isFarFromPending(position: Vector3): boolean
	local limit = Config.ThunderMinSeparation * Config.ThunderMinSeparation

	for _, strike in pending do
		local offset = strike.position - position
		if offset:Dot(offset) < limit then
			return false
		end
	end
	return true
end

local function broadcast(position: Vector3)
	local event = strikeEvent
	if not event then
		return
	end

	local limit = Config.ThunderAudibleDistance * Config.ThunderAudibleDistance

	for _, player in Players:GetPlayers() do
		local entry = CharacterCache.get(player)
		if entry then
			local offset = entry.root.Position - position
			if offset:Dot(offset) <= limit then
				event:FireClient(player, position)
			end
		end
	end
end

local function resolveStrike(strike: Strike, generation: number)
	local index = table.find(pending, strike)
	if index then
		table.remove(pending, index)
	end

	if generation ~= windowGeneration then
		return
	end

	local now = os.clock()
	local position = strike.position
	local killLimit = Config.ThunderKillRadius * Config.ThunderKillRadius
	local grace = Config.ThunderSpawnGrace

	for _, player in Players:GetPlayers() do
		local entry = CharacterCache.getAlive(player)
		if entry then
			local spawned = spawnedAt[player]
			local graced = spawned ~= nil and (now - spawned) < grace
			local offset = entry.root.Position - position

			if not graced and offset:Dot(offset) <= killLimit then
				if not WeatherService.isPlayerSheltered(player) then
					entry.humanoid.Health = 0
				end
			end
		end
	end
end

local function spawnStrike(player: Player, generation: number)
	local entry = CharacterCache.get(player)
	if not entry then
		return
	end

	local origin = entry.root.Position
	local spread = math.max(Config.ThunderSpawnRadius - Config.ThunderSafeRadius, 0)
	local fall = Config.ThunderCloudHeight * 2

	for _ = 1, MAX_PLACEMENT_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local radius = Config.ThunderSafeRadius + math.random() * spread
		local candidate = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

		local from = candidate + Vector3.new(0, Config.ThunderCloudHeight, 0)
		local result = workspace:Raycast(from, Vector3.new(0, -fall, 0), strikeParams)

		if result and isClearOfPlayers(result.Position) and isFarFromPending(result.Position) then
			local strike: Strike = { position = result.Position }
			table.insert(pending, strike)
			broadcast(result.Position)
			task.delay(Config.ThunderTelegraph, resolveStrike, strike, generation)
			return
		end
	end
end

-- The storm hunts a fixed number of players rather than everyone, so a full
-- server is not proportionally more dangerous than an empty one.
local function rotateAnchors(now: number)
	table.clear(anchors)

	local candidates = {}
	for _, player in Players:GetPlayers() do
		if CharacterCache.get(player) then
			table.insert(candidates, player)
		end
	end

	local count = math.min(Config.ThunderAnchorCount, #candidates)
	for index = 1, count do
		local pick = math.random(#candidates)
		local player = candidates[pick]
		candidates[pick] = candidates[#candidates]
		candidates[#candidates] = nil

		table.insert(anchors, player)

		-- Staggered so a fresh target set does not fire all at once.
		local range = Config.ThunderStrikeInterval
		nextStrikeAt[player] = now + (index / count) * range.Min
	end
end

local function scheduleLoop(generation: number)
	local nextRotateAt = 0

	while running and windowActive and generation == windowGeneration do
		task.wait(SCHEDULE_INTERVAL)

		if generation ~= windowGeneration then
			break
		end

		local now = os.clock()

		if now >= nextRotateAt then
			nextRotateAt = now + Config.ThunderAnchorRotate
			rotateAnchors(now)
		end

		for _, player in anchors do
			local due = nextStrikeAt[player]
			if due and now >= due then
				local ok, sheltered = pcall(WeatherService.isPlayerSheltered, player)
				nextStrikeAt[player] = now + rollInterval(ok and sheltered or false)

				local spawnOk, err = pcall(spawnStrike, player, generation)
				if not spawnOk then
					warn("[ThunderService] strike failed for", player.Name, err)
				end
			end
		end
	end
end

local function endWindow()
	if not windowActive then
		return
	end
	windowActive = false
	windowGeneration += 1
	table.clear(pending)
	table.clear(anchors)
	stateHolder:SetAttribute(Attr.ThunderActive, false)
end

local function runWindow()
	windowGeneration += 1
	local generation = windowGeneration

	windowActive = true
	table.clear(nextStrikeAt)
	stateHolder:SetAttribute(Attr.ThunderActive, true)

	task.wait(Config.ThunderWarningLead)
	if generation ~= windowGeneration then
		return
	end

	task.spawn(scheduleLoop, generation)

	task.wait(Config.ThunderDuration)
	if generation == windowGeneration then
		endWindow()
	end
end

function ThunderService.triggerNow()
	if not running or windowActive then
		return
	end
	task.spawn(runWindow)
end

function ThunderService.isActive(): boolean
	return windowActive
end

local function trackPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		spawnedAt[player] = os.clock()
		refreshCharacterFilter()
	end)
end

function ThunderService.start()
	if not Config.EnableThunderstorm then
		return
	end

	if running then
		warn("[ThunderService] start() called twice; ignoring.")
		return
	end
	running = true

	stateHolder = Shared.getStateHolder()
	strikeEvent = Shared.getStrikeEvent()
	stateHolder:SetAttribute(Attr.ThunderActive, false)

	if not strikeEvent then
		running = false
		warn(
			"[ThunderService] ReplicatedStorage.ThunderStrike is missing -- lightning disabled. "
				.. "Move it into ReplicatedStorage alongside Weather and WeatherState (install step 2)."
		)
		return
	end

	for _, player in Players:GetPlayers() do
		if player.Character then
			spawnedAt[player] = os.clock()
		end
		trackPlayer(player)
	end
	refreshCharacterFilter()

	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(refreshCharacterFilter)

	WeatherService.PhaseChanged:Connect(function(phaseName)
		if phaseName ~= THUNDER_PHASE then
			endWindow()
			return
		end

		local generation = windowGeneration
		local needed = Config.ThunderWarningLead + Config.ThunderDuration
		local latestStart = math.max(WeatherService.getPhaseTimeRemaining() - needed, 0)

		task.delay(math.random() * latestStart, function()
			if running and not windowActive and generation == windowGeneration then
				if WeatherService.getPhase() == THUNDER_PHASE then
					runWindow()
				end
			end
		end)
	end)
end

function ThunderService.stop()
	running = false
	endWindow()
end

return ThunderService

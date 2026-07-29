--[[
	Thunderstorm window inside the Peak phase.

	Lightning here is purely environmental: it does no damage, ignores shelter,
	and never targets anyone. Players are picked only to decide WHERE in the
	world a strike happens, so that it lands somewhere a person can see or hear
	it rather than in an empty corner of the map.
]]

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
local SCHEDULE_INTERVAL = 0.5

-- Candidate positions tried before giving up on this player's turn.
local MAX_PLACEMENT_ATTEMPTS = 3

local THUNDER_PHASE = "Peak"

local stateHolder: Instance
local strikeEvent: RemoteEvent?

local running = false
local windowActive = false
local windowGeneration = 0

local nextStrikeAt = setmetatable({}, { __mode = "k" }) :: { [Player]: number }
local anchors: { Player } = {}

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

local function rollInterval(): number
	local range = Config.ThunderStrikeInterval
	return range.Min + math.random() * (range.Max - range.Min)
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

local function spawnStrike(player: Player)
	local entry = CharacterCache.get(player)
	if not entry then
		return
	end

	local origin = entry.root.Position
	local spread = math.max(Config.ThunderMaxDistance - Config.ThunderMinDistance, 0)
	local fall = Config.ThunderCloudHeight * 2

	for _ = 1, MAX_PLACEMENT_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local radius = Config.ThunderMinDistance + math.random() * spread
		local candidate = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

		local from = candidate + Vector3.new(0, Config.ThunderCloudHeight, 0)
		local result = workspace:Raycast(from, Vector3.new(0, -fall, 0), strikeParams)

		if result then
			broadcast(result.Position)
			return
		end
	end
end

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

		-- Staggered so a fresh set does not all fire at once.
		nextStrikeAt[player] = now + (index / count) * Config.ThunderStrikeInterval.Min
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
				nextStrikeAt[player] = now + rollInterval()

				local ok, err = pcall(spawnStrike, player)
				if not ok then
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

	refreshCharacterFilter()
	Players.PlayerAdded:Connect(refreshCharacterFilter)
	Players.PlayerRemoving:Connect(refreshCharacterFilter)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(refreshCharacterFilter)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(refreshCharacterFilter)
	end)

	WeatherService.PhaseChanged:Connect(function(phaseName)
		if phaseName ~= THUNDER_PHASE then
			endWindow()
			return
		end

		if math.random() > Config.ThunderChance then
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

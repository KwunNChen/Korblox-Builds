-- Thunderstorm window inside the Peak phase. Environmental only, no damage.

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

-- Seconds of heads-up the debug log gives before a thunderstorm opens.
local WARNING_LEAD = 15

local THUNDER_PHASE = "Peak"

local stateHolder: Instance
local strikeEvent: RemoteEvent?

local running = false
local windowActive = false
local windowGeneration = 0

local nextStrikeAt = setmetatable({}, { __mode = "k" }) :: { [Player]: number }
local anchors: { Player } = {}

local function log(...)
	if Config.ThunderDebugLog then
		print("[Thunder/server]", ...)
	end
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

	local spread = math.max(Config.ThunderMaxDistance - Config.ThunderMinDistance, 0)
	local angle = math.random() * math.pi * 2
	local radius = Config.ThunderMinDistance + math.random() * spread

	broadcast(entry.root.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	log(string.format("strike %.0f studs from %s", radius, player.Name))
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
	log("thunderstorm over")
end

local function runWindow()
	windowGeneration += 1
	local generation = windowGeneration

	windowActive = true
	table.clear(nextStrikeAt)
	stateHolder:SetAttribute(Attr.ThunderActive, true)

	log(
		string.format(
			"THUNDERSTORM STARTING -- rumble now, first strike in %.0fs, runs %.0fs",
			Config.ThunderWarningLead,
			Config.ThunderDuration
		)
	)

	task.wait(Config.ThunderWarningLead)
	if generation ~= windowGeneration then
		return
	end

	log("strikes beginning")
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

	log(
		string.format(
			"ready -- %.0f%% chance per Peak, %.0fs long. Set DebugThunder on ReplicatedStorage.Weather to force one.",
			Config.ThunderChance * 100,
			Config.ThunderDuration
		)
	)

	WeatherService.PhaseChanged:Connect(function(phaseName)
		if phaseName ~= THUNDER_PHASE then
			endWindow()
			return
		end

		if math.random() > Config.ThunderChance then
			log("Peak started -- no thunderstorm this phase (ThunderChance roll failed)")
			return
		end

		local generation = windowGeneration
		local needed = Config.ThunderWarningLead + Config.ThunderDuration
		local latestStart = math.max(WeatherService.getPhaseTimeRemaining() - needed, 0)
		local startsIn = math.random() * latestStart

		log(string.format("Peak started -- thunderstorm scheduled in %.0fs", startsIn))

		if startsIn > WARNING_LEAD then
			task.delay(startsIn - WARNING_LEAD, function()
				if running and not windowActive and generation == windowGeneration then
					log(string.format("thunderstorm in %.0f seconds", WARNING_LEAD))
				end
			end)
		end

		task.delay(startsIn, function()
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

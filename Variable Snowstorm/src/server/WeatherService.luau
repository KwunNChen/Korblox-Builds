-- Server authority for storm state. Publishes to ReplicatedStorage.WeatherState.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))

local Attr = Shared.Attr

local WeatherService = {}

local PHASE_ORDER = { "Clear", "Building", "Peak", "Fading" }

-- Intensity travels from `from` to `to` across each phase.
local PHASE_CURVE = {
	Clear = { from = 0, to = 0 },
	Building = { from = 0, to = 1 },
	Peak = { from = 1, to = 1 },
	Fading = { from = 1, to = 0 },
}

local CENTER_ONLY = { Vector2.new(0, 0) }

local state = {
	phaseIndex = 1,
	elapsed = 0,
	duration = 0,
	clock = 0,
	intensity = 0,
	wind = Vector3.zero,
	phaseName = "Clear",
	secondsLeft = -1,
	override = nil :: number?,
	instantNonce = 0,
}

local stateHolder: Instance
local running = false

local phaseChanged = Instance.new("BindableEvent")
local intensityChanged = Instance.new("BindableEvent")

WeatherService.PhaseChanged = phaseChanged.Event
WeatherService.IntensityChanged = intensityChanged.Event

local supportsGlobalWind = pcall(function()
	return workspace.GlobalWind
end)

local serverShelterParams = Shared.newShelterParams({})

local function rollDuration(phaseName: string): number
	local range = Config.PhaseDurations[phaseName]
	return math.max(range.Min + math.random() * (range.Max - range.Min), 0.1)
end

local function publishSecondsLeft()
	local secondsLeft = math.max(math.floor(state.duration - state.elapsed), 0)
	if secondsLeft ~= state.secondsLeft then
		state.secondsLeft = secondsLeft
		stateHolder:SetAttribute(Attr.PhaseSecondsLeft, secondsLeft)
	end
end

local function advancePhase(dt: number)
	state.elapsed += dt

	while state.elapsed >= state.duration do
		state.elapsed -= state.duration
		state.phaseIndex = (state.phaseIndex % #PHASE_ORDER) + 1
		state.phaseName = PHASE_ORDER[state.phaseIndex]
		state.duration = rollDuration(state.phaseName)
		stateHolder:SetAttribute(Attr.Phase, state.phaseName)
		publishSecondsLeft()
		phaseChanged:Fire(state.phaseName)
	end
end

local function computeIntensity(): number
	if state.override then
		return state.override
	end

	local curve = PHASE_CURVE[state.phaseName]
	local alpha = math.clamp(state.elapsed / state.duration, 0, 1)
	local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local base = Shared.lerp(curve.from, curve.to, eased)

	if base > 0.05 then
		base *= 1 + math.noise(state.clock * Config.PeakWobbleSpeed, 50) * Config.PeakWobbleAmount
	end

	return math.clamp(base, 0, 1)
end

local function computeWind(intensity: number): Vector3
	local heading = math.noise(state.clock * Config.WindDirectionDrift, 0) * math.pi * 2
	local gust = 1 + math.noise(state.clock * Config.WindGustSpeed, 100) * Config.WindGustAmount
	local speed = Shared.lerp(Config.WindCalmSpeed, Config.WindStormSpeed, intensity) * gust

	return Vector3.new(math.cos(heading) * speed, 0, math.sin(heading) * speed)
end

local function publish(intensity: number, wind: Vector3, force: boolean?)
	if intensity < Config.IntensityEpsilon then
		intensity = 0
	end

	local movedEnough = math.abs(intensity - state.intensity) > Config.IntensityEpsilon
	local crossedZero = (intensity == 0) ~= (state.intensity == 0)
	if force or movedEnough or crossedZero then
		state.intensity = intensity
		stateHolder:SetAttribute(Attr.Intensity, intensity)
		intensityChanged:Fire(intensity)
	end

	if (wind - state.wind).Magnitude > 0.25 then
		state.wind = wind
		stateHolder:SetAttribute(Attr.WindX, wind.X)
		stateHolder:SetAttribute(Attr.WindZ, wind.Z)

		if supportsGlobalWind and Config.DriveGlobalWind then
			workspace.GlobalWind = wind
		end
	end
end

function WeatherService.getIntensity(): number
	return state.intensity
end

function WeatherService.getPhase(): string
	return state.phaseName
end

function WeatherService.getWind(): Vector3
	return state.wind
end

function WeatherService.getPhaseTimeRemaining(): number
	return math.max(state.duration - state.elapsed, 0)
end

-- Use this for gameplay, never a value a client reports.
function WeatherService.isPlayerSheltered(player: Player): (boolean, number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, 0
	end

	serverShelterParams.FilterDescendantsInstances = { character }
	local coverage = Shared.sampleShelter((root :: BasePart).Position, serverShelterParams, CENTER_ONLY)

	return coverage > 0.5, coverage
end

-- Pins intensity, ignoring the cycle. nil resumes. `instant` skips the client ramp-up.
function WeatherService.setOverride(intensity: number?, instant: boolean?)
	state.override = if intensity then math.clamp(intensity, 0, 1) else nil

	if instant then
		if not stateHolder then
			warn("[WeatherService] setOverride instant flag ignored -- start() has not run yet.")
			return
		end

		local i = computeIntensity()
		publish(i, computeWind(i), true)

		state.instantNonce += 1
		stateHolder:SetAttribute(Attr.InstantCue, state.instantNonce)
	end
end

local function jumpToPhase(phaseName: string)
	state.phaseIndex = table.find(PHASE_ORDER, phaseName) :: number
	state.phaseName = phaseName
	state.elapsed = 0
	state.duration = rollDuration(phaseName)
	stateHolder:SetAttribute(Attr.Phase, phaseName)
	publishSecondsLeft()
	phaseChanged:Fire(phaseName)
end

function WeatherService.forceStorm()
	jumpToPhase("Building")
end

function WeatherService.forceClear()
	jumpToPhase("Fading")
end

function WeatherService.start()
	if running then
		warn("[WeatherService] start() called twice; ignoring.")
		return
	end
	running = true

	stateHolder = Shared.getStateHolder()
	state.phaseName = PHASE_ORDER[state.phaseIndex]
	state.duration = rollDuration(state.phaseName)
	stateHolder:SetAttribute(Attr.Phase, state.phaseName)
	publishSecondsLeft()

	task.spawn(function()
		while running do
			local dt = task.wait(Config.ServerTickRate)
			state.clock += dt

			advancePhase(dt)
			publishSecondsLeft()

			local intensity = computeIntensity()
			publish(intensity, computeWind(intensity))
		end
	end)
end

function WeatherService.stop()
	running = false
end

return WeatherService

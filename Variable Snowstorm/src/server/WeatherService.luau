--[[
	WeatherService  (server authority)

	Owns the *state* of the storm -- nothing visual. It publishes four numbers
	to ReplicatedStorage.WeatherState as attributes and lets every client render
	from those locally.

	Why attributes instead of RemoteEvents:
	  * They replicate automatically, including to players who join mid-blizzard,
	    so there is no "request current weather on join" handshake to write.
	  * Only changed values go over the wire.
	  * Total network cost of the entire system is 4 numbers a few times a second,
	    regardless of how many players are online.

	Why the server does NOT render particles or check roofs for visuals:
	  A server-created ParticleEmitter replicates to *every* client, and there is
	  no way to hide a server-owned instance from one player and not another. So
	  per-player shelter is physically impossible to do server-side. The server
	  keeps authority over what the weather IS; each client decides what it looks
	  like from where they are standing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))

local Attr = Shared.Attr

local WeatherService = {}

-- ============================================================
-- Storm cycle definition
-- ============================================================

local PHASE_ORDER = { "Clear", "Building", "Peak", "Fading" }

-- Where intensity starts and ends within each phase. Building ramps 0 -> 1,
-- Fading walks it back down, and the two flat phases hold.
local PHASE_CURVE = {
	Clear = { from = 0, to = 0 },
	Building = { from = 0, to = 1 },
	Peak = { from = 1, to = 1 },
	Fading = { from = 1, to = 0 },
}

-- Server-side shelter checks are for gameplay hooks only, so a single straight-up
-- ray is enough. The client uses the full pattern for its visuals.
local CENTER_ONLY = { Vector2.new(0, 0) }

-- ============================================================
-- Internal state
-- ============================================================

local state = {
	phaseIndex = 1,
	elapsed = 0,
	duration = 0,
	clock = 0,
	intensity = 0,
	wind = Vector3.zero,
	override = nil :: number?,
}

local stateHolder: Instance
local running = false

local phaseChanged = Instance.new("BindableEvent")
local intensityChanged = Instance.new("BindableEvent")

--[[
	Hooks for gameplay code. Nothing is bound to these yet -- they exist so cold
	damage, WalkSpeed penalties, or SFX can be added later without touching the
	state machine.

		local Weather = require(ServerScriptService.Weather.WeatherService)
		Weather.PhaseChanged:Connect(function(phase) ... end)
]]
WeatherService.PhaseChanged = phaseChanged.Event
WeatherService.IntensityChanged = intensityChanged.Event

-- workspace.GlobalWind is a relatively recent property. Probe once at load
-- rather than wrapping every assignment in a pcall.
local supportsGlobalWind = pcall(function()
	return workspace.GlobalWind
end)

local serverShelterParams = Shared.newShelterParams({})

-- ============================================================
-- Cycle logic
-- ============================================================

local function rollDuration(phaseName: string): number
	local range = Config.PhaseDurations[phaseName]
	local value = range.Min + math.random() * (range.Max - range.Min)
	-- Never allow 0, or the advance loop below would spin forever.
	return math.max(value, 0.1)
end

local function advancePhase(dt: number)
	state.elapsed += dt

	while state.elapsed >= state.duration do
		state.elapsed -= state.duration
		state.phaseIndex = (state.phaseIndex % #PHASE_ORDER) + 1

		local phaseName = PHASE_ORDER[state.phaseIndex]
		state.duration = rollDuration(phaseName)
		phaseChanged:Fire(phaseName)
	end
end

local function computeIntensity(): number
	if state.override then
		return state.override
	end

	local phaseName = PHASE_ORDER[state.phaseIndex]
	local curve = PHASE_CURVE[phaseName]

	local alpha = math.clamp(state.elapsed / state.duration, 0, 1)
	local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local base = Shared.lerp(curve.from, curve.to, eased)

	-- Keep the peak alive instead of pinning it at a flat 1.0.
	if base > 0.05 then
		local wobble = math.noise(state.clock * Config.PeakWobbleSpeed, 50) * Config.PeakWobbleAmount
		base = base * (1 + wobble)
	end

	return math.clamp(base, 0, 1)
end

local function computeWind(intensity: number): Vector3
	-- Perlin noise gives a heading that wanders smoothly instead of snapping.
	local heading = math.noise(state.clock * Config.WindDirectionDrift, 0) * math.pi * 2
	local gust = 1 + math.noise(state.clock * Config.WindGustSpeed, 100) * Config.WindGustAmount
	local speed = Shared.lerp(Config.WindCalmSpeed, Config.WindStormSpeed, intensity) * gust

	return Vector3.new(math.cos(heading) * speed, 0, math.sin(heading) * speed)
end

local function publish(intensity: number, wind: Vector3)
	-- Only write when the value actually moved. Attribute writes replicate to
	-- every client, so silently skipping no-op writes is most of the network
	-- savings in this system.
	if math.abs(intensity - state.intensity) > Config.IntensityEpsilon then
		state.intensity = intensity
		stateHolder:SetAttribute(Attr.Intensity, intensity)
		intensityChanged:Fire(intensity)
	end

	if (wind - state.wind).Magnitude > 0.25 then
		state.wind = wind
		stateHolder:SetAttribute(Attr.WindX, wind.X)
		stateHolder:SetAttribute(Attr.WindZ, wind.Z)

		-- GlobalWind is engine-side: it drives foliage and dynamic clouds for
		-- free, and costs one replicated Vector3.
		if supportsGlobalWind and Config.DriveGlobalWind then
			workspace.GlobalWind = wind
		end
	end

	local phaseName = PHASE_ORDER[state.phaseIndex]
	if stateHolder:GetAttribute(Attr.Phase) ~= phaseName then
		stateHolder:SetAttribute(Attr.Phase, phaseName)
	end
end

-- ============================================================
-- Public API
-- ============================================================

function WeatherService.getIntensity(): number
	return state.intensity
end

function WeatherService.getPhase(): string
	return PHASE_ORDER[state.phaseIndex]
end

function WeatherService.getWind(): Vector3
	return state.wind
end

--[[
	Server-authoritative shelter check, for gameplay only.

	The client runs its own far more detailed version for visuals, but a client
	can lie, so anything that costs a player health or speed has to be decided
	here. One ray per player every couple of seconds is cheap enough to ignore.

	Returns: sheltered (boolean), coverage (0-1)
]]
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

--[[
	Pins intensity to a fixed value, ignoring the cycle. Pass nil to resume.
	Handy from the command bar while tuning:  Weather.setOverride(1)

	Pass `instant = true` to also skip the client's lighting/particle ramp-up,
	which otherwise takes several seconds to visually catch up to a fresh
	override. Testing-convenience only -- real storms never use this path.
]]
function WeatherService.setOverride(intensity: number?, instant: boolean?)
	state.override = if intensity then math.clamp(intensity, 0, 1) else nil

	if instant then
		if not stateHolder then
			warn("[WeatherService] setOverride instant flag ignored -- start() has not run yet.")
			return
		end

		-- Publish immediately so the command bar doesn't wait for the next tick.
		local i = computeIntensity()
		publish(i, computeWind(i))

		-- A monotonically-incrementing counter guarantees the attribute always
		-- changes, so the client's GetAttributeChangedSignal reliably fires even
		-- if this is called twice back to back with the same intensity.
		state.instantNonce = (state.instantNonce or 0) + 1
		stateHolder:SetAttribute(Attr.InstantCue, state.instantNonce)
	end
end

function WeatherService.forceStorm()
	state.phaseIndex = table.find(PHASE_ORDER, "Building") :: number
	state.elapsed = 0
	state.duration = rollDuration("Building")
	phaseChanged:Fire("Building")
end

function WeatherService.forceClear()
	state.phaseIndex = table.find(PHASE_ORDER, "Fading") :: number
	state.elapsed = 0
	state.duration = rollDuration("Fading")
	phaseChanged:Fire("Fading")
end

function WeatherService.start()
	if running then
		warn("[WeatherService] start() called twice; ignoring.")
		return
	end
	running = true

	stateHolder = Shared.getStateHolder()
	state.duration = rollDuration(PHASE_ORDER[state.phaseIndex])

	-- A fixed-rate loop rather than a Heartbeat connection: this does not need
	-- to run every frame, and task.wait hands back the true elapsed time so the
	-- cycle stays accurate even if the server hitches.
	task.spawn(function()
		while running do
			local dt = task.wait(Config.ServerTickRate)
			state.clock += dt

			advancePhase(dt)

			local intensity = computeIntensity()
			publish(intensity, computeWind(intensity))
		end
	end)
end

function WeatherService.stop()
	running = false
end

return WeatherService

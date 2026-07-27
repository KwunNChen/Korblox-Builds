-- Helpers shared by the server and client weather code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("WeatherConfig"))

local WeatherShared = {}

local SHELTER_RAY = Vector3.new(0, Config.ShelterRayLength, 0)

WeatherShared.Attr = table.freeze({
	Intensity = "Intensity",
	Phase = "Phase",
	WindX = "WindX",
	WindZ = "WindZ",
	InstantCue = "InstantCue",
	PhaseSecondsLeft = "PhaseSecondsLeft",
	ThunderActive = "ThunderActive",
})

function WeatherShared.getStateHolder(): Instance
	return ReplicatedStorage:WaitForChild("WeatherState")
end

-- Nil if it is missing; callers disable lightning rather than yield forever.
function WeatherShared.getStrikeEvent(): RemoteEvent?
	return ReplicatedStorage:WaitForChild("ThunderStrike", 10) :: RemoteEvent?
end

-- Whole seconds, the resolution PhaseSecondsLeft replicates at.
function WeatherShared.getPhaseTimeRemaining(stateHolder: Instance): number
	local secondsLeft = stateHolder:GetAttribute(WeatherShared.Attr.PhaseSecondsLeft)
	if typeof(secondsLeft) ~= "number" then
		return 0
	end
	return secondsLeft
end

-- Framerate-independent smoothing. `smoothing` is a time constant in seconds.
function WeatherShared.damp(current: number, target: number, smoothing: number, dt: number): number
	if smoothing <= 0 then
		return target
	end
	return target + (current - target) * math.exp(-dt / smoothing)
end

function WeatherShared.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Build once per system and reuse; do not allocate per cast.
function WeatherShared.newShelterParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = Config.ShelterRespectCanCollide
	return params
end

-- Returns 0 (open sky) to 1 (fully covered).
function WeatherShared.sampleShelter(origin: Vector3, params: RaycastParams, offsets: { Vector2 }?, spread: number?): number
	local samples = offsets or Config.ShelterSampleOffsets
	local radius = spread or Config.ShelterSampleSpread

	local blocked = 0
	for _, offset in samples do
		local from = origin + Vector3.new(offset.X * radius, 0, offset.Y * radius)
		if workspace:Raycast(from, SHELTER_RAY, params) then
			blocked += 1
		end
	end

	return blocked / #samples
end

return table.freeze(WeatherShared)

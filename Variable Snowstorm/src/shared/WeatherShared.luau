--[[
	WeatherShared
	Small helpers used by both the server and the client. Keeping the shelter
	sampler here means both sides agree on what "sheltered" means, even though
	they run it at very different resolutions and frequencies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("WeatherConfig"))

local WeatherShared = {}

-- Attribute names live in one place so a typo is a nil index, not a silent
-- "storm never starts" bug.
WeatherShared.Attr = table.freeze({
	Intensity = "Intensity",
	Phase = "Phase",
	WindX = "WindX",
	WindZ = "WindZ",
	InstantCue = "InstantCue",
})

--[[
	Returns the replicated state holder. Created by Rojo with sane defaults, so
	it always exists before either side asks for it -- including for players who
	join halfway through a blizzard.
]]
function WeatherShared.getStateHolder(): Instance
	return ReplicatedStorage:WaitForChild("WeatherState")
end

--[[
	Framerate-independent exponential smoothing.

	A plain `lerp(current, target, 0.1)` moves faster on a 240fps machine than a
	30fps one, which makes the snow fade at different speeds per player. This
	version depends only on wall-clock time.

	`smoothing` is a time constant in seconds: roughly how long to cover ~63% of
	the remaining distance.
]]
function WeatherShared.damp(current: number, target: number, smoothing: number, dt: number): number
	if smoothing <= 0 then
		return target
	end
	return target + (current - target) * math.exp(-dt / smoothing)
end

function WeatherShared.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--[[
	Builds a RaycastParams configured for roof detection. Callers should build
	this ONCE and reuse it -- allocating a fresh one per cast is the most common
	way these systems end up producing avoidable garbage.
]]
function WeatherShared.newShelterParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = Config.ShelterRespectCanCollide
	return params
end

--[[
	Fires a small pattern of upward rays and returns how sheltered the point is,
	from 0 (open sky) to 1 (fully covered).

	Sampling a pattern rather than a single ray means standing next to a doorway
	or under a thin tree gives a partial value, which the caller can smooth into
	a gentle fade instead of a hard on/off pop.
]]
function WeatherShared.sampleShelter(origin: Vector3, params: RaycastParams, offsets: { Vector2 }?, spread: number?): number
	local samples = offsets or Config.ShelterSampleOffsets
	local radius = spread or Config.ShelterSampleSpread
	local up = Vector3.new(0, Config.ShelterRayLength, 0)

	local blocked = 0
	for _, offset in samples do
		local from = origin + Vector3.new(offset.X * radius, 0, offset.Y * radius)
		if workspace:Raycast(from, up, params) then
			blocked += 1
		end
	end

	return blocked / #samples
end

return table.freeze(WeatherShared)

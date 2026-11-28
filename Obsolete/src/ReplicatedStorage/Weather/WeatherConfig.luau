--[[
	WeatherConfig -- Tower Assault copy of the repo's Variable Snowstorm config.
	Tuned for a permanent whiteout outside the tower. Lightning and the storm
	slowdown are not installed here (the slowdown would fight Spearhead over WalkSpeed).
	Players in a tower run (InTowerRun) see no storm at all -- see WeatherClient.
]]

local WeatherConfig = {}

-- STORM CYCLE (server)
WeatherConfig.PhaseDurations = {
	Clear = NumberRange.new(90, 150),
	Building = NumberRange.new(35, 55),
	Peak = NumberRange.new(150, 240),
	Fading = NumberRange.new(40, 60),
}
WeatherConfig.ServerTickRate = 0.25
WeatherConfig.IntensityEpsilon = 0.005
WeatherConfig.PeakWobbleAmount = 0.18
WeatherConfig.PeakWobbleSpeed = 0.15

-- WIND
WeatherConfig.WindCalmSpeed = 6
WeatherConfig.WindStormSpeed = 70
WeatherConfig.WindDirectionDrift = 0.02
WeatherConfig.WindGustSpeed = 0.4
WeatherConfig.WindGustAmount = 0.3
WeatherConfig.DriveGlobalWind = true

-- SHELTER / ROOF DETECTION
WeatherConfig.ShelterRayLength = 250
WeatherConfig.ShelterSampleSpread = 5
WeatherConfig.ShelterSampleOffsets = {
	Vector2.new(0, 0),
	Vector2.new(1, 1),
	Vector2.new(-1, 1),
	Vector2.new(1, -1),
	Vector2.new(-1, -1),
}
WeatherConfig.ShelterCheckInterval = 0.2
WeatherConfig.ShelterSmoothing = 0.35
WeatherConfig.ShelterRespectCanCollide = true
WeatherConfig.ServerShelterInterval = 2

-- PARTICLES (client)
WeatherConfig.ParticleBudget = 3000
WeatherConfig.FlakeLifetime = NumberRange.new(2.5, 4)
WeatherConfig.FlakeTexture = "rbxasset://textures/particles/sparkles_main.dds"
WeatherConfig.FlakeColor = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(222, 236, 255))
WeatherConfig.RigSize = Vector3.new(100, 50, 100)
WeatherConfig.RigHeightOffset = 14
WeatherConfig.SnowCeilingMargin = 2
WeatherConfig.SnowCeilingMinHeight = 4
WeatherConfig.LookaheadTime = 0.45
WeatherConfig.LookaheadMaxDistance = 45
WeatherConfig.FlakeGravity = 26
WeatherConfig.FlakeDrag = 1.6
WeatherConfig.FlakeSpeed = NumberRange.new(0.5, 2.5)
WeatherConfig.SquashAtCalm = 0
WeatherConfig.SquashAtPeak = 1.6
WeatherConfig.FlakeSizeCalm = 0.3
WeatherConfig.FlakeSizePeak = 0.9
WeatherConfig.IntensityBuckets = 20

-- LIGHTING (client, local only). Low FogEnd + heavy haze = whiteout.
WeatherConfig.EnableLightingEffects = true
WeatherConfig.StormFogEnd = 70
WeatherConfig.StormFogColor = Color3.fromRGB(198, 210, 226)
WeatherConfig.StormOutdoorAmbient = Color3.fromRGB(105, 115, 130)
WeatherConfig.StormAtmosphereDensity = 0.72
WeatherConfig.StormAtmosphereHaze = 4
-- With an Atmosphere in Lighting, Fog* is ignored: this colour is what the whiteout looks like.
WeatherConfig.StormAtmosphereColor = Color3.fromRGB(200, 208, 220)
WeatherConfig.LightingSmoothing = 1.5

-- WIND AUDIO (client)
WeatherConfig.EnableWindAudio = true
WeatherConfig.WindSoundId = "rbxassetid://71284123166666"
WeatherConfig.WindMaxVolume = 0.5
WeatherConfig.WindIndoorVolumeDrop = 0.65
WeatherConfig.WindIndoorHighGain = -25
WeatherConfig.WindIndoorMidGain = -8
WeatherConfig.WindPitchCalm = 0.85
WeatherConfig.WindPitchStorm = 1.2
WeatherConfig.WindAudioSmoothing = 1.2
WeatherConfig.WindPitchSmoothing = 0.4

-- 0-1 pins the storm at that intensity, -1 runs the cycle. Pinned to a full blizzard.
WeatherConfig.DebugStartIntensity = 1

return table.freeze(WeatherConfig)

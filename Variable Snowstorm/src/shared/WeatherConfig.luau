--[[
	WeatherConfig
	Every tunable number for the snowstorm lives here so you never have to dig
	through the server or client logic to retune the look and feel.

	Shared between server and client, so both sides always agree on thresholds.
]]

local WeatherConfig = {}

-- ============================================================
-- STORM CYCLE  (server only)
-- ============================================================

-- How long each phase lasts, in seconds. A random value inside the range is
-- rolled every time the phase is entered, so the cycle never feels metronomic.
WeatherConfig.PhaseDurations = {
	Clear = NumberRange.new(60, 120),
	Building = NumberRange.new(20, 35),
	Peak = NumberRange.new(45, 90),
	Fading = NumberRange.new(25, 40),
}

-- How often the server recomputes storm state. This is NOT a render loop --
-- the client smooths between these values locally, so 4 ticks/second is plenty.
WeatherConfig.ServerTickRate = 0.25

-- Intensity only replicates when it moves more than this. Stops us from
-- spamming attribute replication with meaningless 0.0001 changes.
WeatherConfig.IntensityEpsilon = 0.005

-- At Peak the storm breathes instead of sitting at a flat 1.0.
WeatherConfig.PeakWobbleAmount = 0.18
WeatherConfig.PeakWobbleSpeed = 0.15

-- ============================================================
-- WIND  (server computes, client consumes)
-- ============================================================

WeatherConfig.WindCalmSpeed = 6 -- studs/sec at intensity 0
WeatherConfig.WindStormSpeed = 70 -- studs/sec at intensity 1
WeatherConfig.WindDirectionDrift = 0.02 -- how fast the wind slowly changes heading
WeatherConfig.WindGustSpeed = 0.4 -- frequency of gust noise
WeatherConfig.WindGustAmount = 0.3 -- +/- fraction of speed a gust adds

-- Mirror the wind into workspace.GlobalWind so foliage and dynamic clouds
-- react too. Set false if your map already drives GlobalWind elsewhere.
WeatherConfig.DriveGlobalWind = true

-- ============================================================
-- SHELTER / ROOF DETECTION
-- ============================================================

-- How far up we look for a roof. Anything higher than this is "open sky".
WeatherConfig.ShelterRayLength = 250

-- Rays are fired in a small pattern around the player instead of a single
-- ray straight up, so a pillar or a gap in the canopy gives partial shelter
-- instead of flickering between 0% and 100%.
WeatherConfig.ShelterSampleSpread = 5 -- studs from center
WeatherConfig.ShelterSampleOffsets = {
	Vector2.new(0, 0),
	Vector2.new(1, 1),
	Vector2.new(-1, 1),
	Vector2.new(1, -1),
	Vector2.new(-1, -1),
}

-- Seconds between shelter checks on the client. The result is smoothed, so
-- this can be surprisingly slow without looking laggy.
WeatherConfig.ShelterCheckInterval = 0.2

-- Seconds for the snow to fully fade in/out when you step under cover.
-- This is an exponential smoothing time constant, not a hard duration.
WeatherConfig.ShelterSmoothing = 0.35

-- Ignore parts with CanCollide off (decorative leaves, signs, effects) when
-- deciding what counts as a roof. Turn OFF if your builders make real roofs
-- non-collidable.
WeatherConfig.ShelterRespectCanCollide = true

-- Server-side shelter check, used only by gameplay hooks. Deliberately
-- coarser and slower than the client's -- it is for damage logic, not visuals.
WeatherConfig.ServerShelterInterval = 2

-- ============================================================
-- PARTICLES  (client only)
-- ============================================================

-- Hard ceiling on live flakes at full intensity. Live count is roughly
-- Rate * average Lifetime, so MaxRate is derived from this -- tune this ONE
-- number to trade quality for framerate.
WeatherConfig.ParticleBudget = 450

WeatherConfig.FlakeLifetime = NumberRange.new(2.5, 4)

-- Built-in Studio texture, guaranteed to exist. Swap for your own snowflake
-- decal id (rbxassetid://...) whenever art gives you one.
WeatherConfig.FlakeTexture = "rbxasset://textures/particles/sparkles_main.dds"

WeatherConfig.FlakeColor = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(222, 236, 255))

-- The emission volume that rides along with the camera. Flakes spawn
-- throughout this box, so snow is already mid-air when a storm starts
-- instead of taking several seconds to fall into view.
WeatherConfig.RigSize = Vector3.new(140, 50, 140)
WeatherConfig.RigHeightOffset = 14 -- studs above the camera

-- Push the volume ahead of the camera so you cannot outrun your own snow.
WeatherConfig.LookaheadTime = 0.45
WeatherConfig.LookaheadMaxDistance = 45

WeatherConfig.FlakeGravity = 22 -- downward acceleration
WeatherConfig.FlakeDrag = 1.6 -- >0 required for wind to affect particles
WeatherConfig.FlakeSpeed = NumberRange.new(1, 4)

-- Flakes stretch into streaks as the storm peaks.
WeatherConfig.SquashAtCalm = 0
WeatherConfig.SquashAtPeak = 2.5

WeatherConfig.FlakeSizeCalm = 0.35
WeatherConfig.FlakeSizePeak = 0.6

-- NumberSequence/ColorSequence properties allocate on every assignment, so we
-- only rebuild them when intensity moves into a new bucket rather than every
-- frame. More buckets = smoother, but more garbage.
WeatherConfig.IntensityBuckets = 20

-- ============================================================
-- LIGHTING  (client only -- applied locally, never replicated)
-- ============================================================

WeatherConfig.EnableLightingEffects = true

WeatherConfig.StormFogEnd = 550 -- FogEnd at full intensity
WeatherConfig.StormFogColor = Color3.fromRGB(198, 210, 226)
WeatherConfig.StormOutdoorAmbient = Color3.fromRGB(105, 115, 130)
WeatherConfig.StormAtmosphereDensity = 0.42
WeatherConfig.StormAtmosphereHaze = 3.2

-- Seconds of smoothing on lighting changes.
WeatherConfig.LightingSmoothing = 1.5

-- ============================================================
-- WIND AUDIO  (client only)
-- ============================================================

WeatherConfig.EnableWindAudio = true
WeatherConfig.WindSoundId = "rbxassetid://4175285709"

WeatherConfig.WindMaxVolume = 0.5

-- Fraction of the volume removed at full shelter. 0.65 means indoors you hear
-- 35% of the outdoor volume -- present, but clearly outside.
WeatherConfig.WindIndoorVolumeDrop = 0.65

-- Equalizer gains (dB) applied at full shelter. Cutting the highs is what makes
-- it read as "storm heard through a wall" rather than just quieter.
WeatherConfig.WindIndoorHighGain = -25
WeatherConfig.WindIndoorMidGain = -8

-- PlaybackSpeed is driven off the replicated wind magnitude, so audio gusts line
-- up with the visual ones instead of drifting on a separate noise source.
WeatherConfig.WindPitchCalm = 0.85
WeatherConfig.WindPitchStorm = 1.2

WeatherConfig.WindAudioSmoothing = 1.2

-- Separate, shorter time constant for pitch. The server only publishes wind a
-- few times a second, so without smoothing the pitch steps audibly; smoothing it
-- as slowly as the volume would instead flatten the gusts out. Raise it if the
-- pitch still sounds jumpy, lower it if gusts feel sluggish.
WeatherConfig.WindPitchSmoothing = 0.4

-- ============================================================
-- GAMEPLAY: STORM SLOWDOWN  (server only -- must be, or clients could ignore it)
-- ============================================================

WeatherConfig.EnableStormSlowdown = true

-- Speed multiplier applied at full intensity while out in the open.
--
-- This is a multiplier rather than a flat subtraction so it stacks correctly
-- with sprinting: 0.875 costs a walking player exactly 2 studs/sec at Roblox's
-- default WalkSpeed of 16 (16 -> 14), while a sprinter at 1.5x lands on
-- 16 * 1.5 * 0.875 = 21 instead of 24. You lose proportionally more the faster
-- you are moving, which reads as fighting through the wind.
--
-- Scales with intensity, so light snow barely slows you and only a peak
-- blizzard costs the full amount.
WeatherConfig.StormSpeedMultiplier = 0.875

-- How often the server re-evaluates. Each pass costs one raycast per player, so
-- this is cheap; it is separate from ServerShelterInterval because movement
-- wants to feel more responsive than damage ticks do.
WeatherConfig.StormSlowdownInterval = 0.5

return table.freeze(WeatherConfig)

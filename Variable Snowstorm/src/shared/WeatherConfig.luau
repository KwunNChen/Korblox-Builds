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
	Clear = NumberRange.new(90, 150),
	Building = NumberRange.new(35, 55),
	Peak = NumberRange.new(85, 150),
	Fading = NumberRange.new(40, 60),
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
-- number to trade quality for framerate. Live particle count (and roughly its
-- render cost) scales linearly with this value, so raise it in small steps.
WeatherConfig.ParticleBudget = 1200

WeatherConfig.FlakeLifetime = NumberRange.new(2.5, 4)

-- Built-in Studio texture, guaranteed to exist. Swap for your own snowflake
-- decal id (rbxassetid://...) whenever art gives you one.
WeatherConfig.FlakeTexture = "rbxasset://textures/particles/sparkles_main.dds"

WeatherConfig.FlakeColor = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(222, 236, 255))

-- The emission volume that rides along with the camera. Flakes spawn
-- throughout this box, so snow is already mid-air when a storm starts
-- instead of taking several seconds to fall into view.
WeatherConfig.RigSize = Vector3.new(100, 50, 100) -- this makes snow more compact
WeatherConfig.RigHeightOffset = 14 -- studs above the camera

-- Push the volume ahead of the camera so you cannot outrun your own snow.
WeatherConfig.LookaheadTime = 0.45
WeatherConfig.LookaheadMaxDistance = 45

-- Terminal fall speed is FlakeGravity / FlakeDrag. Raising gravity spreads the
-- same flake count down a taller column, so it costs some visible density.
WeatherConfig.FlakeGravity = 26 -- downward acceleration
WeatherConfig.FlakeDrag = 1.6 -- >0 required for wind to affect particles
WeatherConfig.FlakeSpeed = NumberRange.new(0.5, 2.5)

-- Flakes stretch into streaks as the storm peaks.
WeatherConfig.SquashAtCalm = 0
WeatherConfig.SquashAtPeak = 1.6

-- Peak size is the main framerate risk here, not ParticleBudget: overdraw
-- scales with flake area, so this is the first thing to lower if Peak drops
-- below your target framerate. Kept small enough to aim through.
WeatherConfig.FlakeSizeCalm = 0.3
WeatherConfig.FlakeSizePeak = 0.55

-- NumberSequence/ColorSequence properties allocate on every assignment, so we
-- only rebuild them when intensity moves into a new bucket rather than every
-- frame. More buckets = smoother, but more garbage.
WeatherConfig.IntensityBuckets = 20

-- ============================================================
-- LIGHTING  (client only -- applied locally, never replicated)
-- ============================================================

WeatherConfig.EnableLightingEffects = true

WeatherConfig.StormFogEnd = 250 -- FogEnd at full intensity -- lower reads as thicker
WeatherConfig.StormFogColor = Color3.fromRGB(198, 210, 226)
WeatherConfig.StormOutdoorAmbient = Color3.fromRGB(105, 115, 130)
WeatherConfig.StormAtmosphereDensity = 0.65
WeatherConfig.StormAtmosphereHaze = 5.0

-- Seconds of smoothing on lighting changes.
WeatherConfig.LightingSmoothing = 1.5

-- ============================================================
-- WIND AUDIO  (client only)
-- ============================================================

WeatherConfig.EnableWindAudio = true
WeatherConfig.WindSoundId = "rbxassetid://71284123166666"

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

-- Crosswind speed multiplier at full intensity, out in the open. A multiplier
-- rather than a subtraction so it stacks with sprinting.
WeatherConfig.StormSpeedMultiplier = 0.875

-- Jump height multiplier at full intensity, out in the open.
WeatherConfig.StormJumpMultiplier = 0.85

-- How often the server re-checks shelter. One raycast per player per pass.
WeatherConfig.StormSlowdownInterval = 0.5

-- How far heading moves the multiplier at full wind. Against the 0.875 base,
-- 0.175 gives 0.70 into the wind and 1.05 with it. 0 makes the storm slow you
-- the same in every direction.
WeatherConfig.WindDirectionalSwing = 0.175

-- How often heading is re-evaluated. Costs only arithmetic; shelter raycasts
-- stay on StormSlowdownInterval.
WeatherConfig.StormDirectionInterval = 0.15

-- Blows players downwind while they are airborne.
WeatherConfig.EnableWindAirborneDrift = true

-- Sideways acceleration (studs/sec^2) at full wind. Roughly 5-6 studs of drift
-- across a default jump arc at 12.
WeatherConfig.WindAirborneAccel = 12

-- ============================================================
-- GAMEPLAY: THUNDERSTORM
-- ============================================================

WeatherConfig.EnableThunderstorm = true

-- Lightning is weather, not a threat. It never damages anyone, never targets
-- anyone, and always strikes at a distance. Nothing in this section changes
-- gameplay.

-- Chance a Peak phase contains a thunderstorm at all. Below 1 they become an
-- event you notice rather than a fixture of every storm.
WeatherConfig.ThunderChance = 0.6

-- Seconds the storm runs, and the rumble that opens it. Long and rare rather
-- than short and constant.
WeatherConfig.ThunderDuration = 150
WeatherConfig.ThunderWarningLead = 6

-- Seconds between strikes near one player.
WeatherConfig.ThunderStrikeInterval = NumberRange.new(7, 16)

-- How many players the storm plays out around at once, so the strike rate a
-- single person sees stays the same whether two or thirty are on the map.
WeatherConfig.ThunderAnchorCount = 4
WeatherConfig.ThunderAnchorRotate = 12

-- How far off strikes land. Deliberately past StormFogEnd (250): fog turns the
-- far ones into nothing but a flash on the horizon, and only the nearest show
-- an actual bolt. Raising the minimum pushes lightning further away.
WeatherConfig.ThunderMinDistance = 160
WeatherConfig.ThunderMaxDistance = 420

-- How far above the ground the bolt starts.
WeatherConfig.ThunderCloudHeight = 300

-- The patch of cloud a strike lights up. Height must stay inside StormFogEnd
-- (250) or the fog swallows it entirely, which is also why it sits well below
-- ThunderCloudHeight -- the top of the bolt is beyond fog range regardless.
WeatherConfig.ThunderCloudGlowHeight = 130
WeatherConfig.ThunderCloudGlowSize = 90
WeatherConfig.ThunderCloudGlowColor = Color3.fromRGB(190, 215, 255)

-- Studs/sec used to delay the crack by distance, the way real thunder lags.
WeatherConfig.ThunderSoundSpeed = 400

-- Your own asset id. Roblox audio is private by default, so an id from another
-- game will not play here.
WeatherConfig.ThunderCrackSoundId = "rbxassetid://137673547776909"

-- The warning rumble is the same asset slowed down, so there is only one sound
-- to source. Lower pitch is a longer, deeper roll.
WeatherConfig.ThunderWarningPitch = 0.3
WeatherConfig.ThunderWarningVolume = 0.8

-- Strikes past this are never sent to a client at all. Also sets how far the
-- flash and rumble carry, so it has to comfortably exceed ThunderMaxDistance
-- or nearby players will miss strikes entirely.
WeatherConfig.ThunderAudibleDistance = 1200

-- Hard ceilings on client cost. Past these, a strike recycles an older visual
-- rather than growing the pool. Raise if you run very high player counts.
WeatherConfig.ThunderVisualPool = 16
WeatherConfig.ThunderMaxConcurrentSounds = 4

-- Sky darkening while a window is open. It ramps in across ThunderWarningLead,
-- so the sky going dark is the warning, and flashes punch harder against it.
WeatherConfig.ThunderDarkenExposure = -1.0 -- added to Lighting.ExposureCompensation
WeatherConfig.ThunderDarkenBrightness = 0.35 -- multiplier on Lighting.Brightness
WeatherConfig.ThunderSkyColor = Color3.fromRGB(70, 78, 92)
WeatherConfig.ThunderAmbientColor = Color3.fromRGB(48, 54, 68)
WeatherConfig.ThunderDarkenSmoothing = 2.5 -- seconds

-- Blots the sun out entirely at full darkness: hides the sun and moon discs,
-- kills atmospheric glare, and shuts off god rays. Dimming Brightness alone
-- leaves a bright disc hanging in an otherwise black sky. False keeps the sun
-- visible if your map needs it.
WeatherConfig.ThunderHideSun = true

-- How far a full-intensity blizzard darkens the sky on its own, with no
-- thunderstorm running. 1 makes Peak snow as dark as a thunderstorm, so the sun
-- is fully blotted at Peak either way; 0 leaves the darkening to thunder alone.
WeatherConfig.StormDarkenAmount = 1

-- How hard a strike flashes the whole sky. The main dial for this effect:
-- raise these and lower ThunderBoltWidth to make the flash the event and the
-- bolt incidental. Exposure has to clear ThunderDarkenExposure to read at all.
WeatherConfig.ThunderFlashBrightness = 4.5
WeatherConfig.ThunderFlashExposure = 1.1

-- Bolt thickness in studs. Thin reads as a distant streak, thick reads as a
-- beam landing next to you.
WeatherConfig.ThunderBoltWidth = 0.4

-- ============================================================
-- DEBUG
-- ============================================================

-- Set 0-1 to skip the cycle and start every playtest at that intensity.
-- -1 runs the normal cycle. Needs no Command Bar -- edit, save, press Play.
WeatherConfig.DebugStartIntensity = -1

return table.freeze(WeatherConfig)

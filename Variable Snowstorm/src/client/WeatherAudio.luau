--[[
	WeatherAudio  (client only)

	Wind ambience layer. Reads nothing itself -- WeatherClient feeds it the same
	intensity/shelter/wind values it uses for the visuals, so audio and picture
	can never disagree.

	The Sound is parented to SoundService, NOT to the snow rig. A Sound parented
	to a BasePart or Attachment becomes 3D positional with distance falloff; a
	Sound anywhere else plays globally at uniform volume, which is what ambience
	wants. The rig is a BasePart, so parenting there would quietly break this.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))

local WeatherAudio = {}

local sound: Sound? = nil
local equalizer: EqualizerSoundEffect? = nil

local currentVolume = 0
local currentMuffle = 0 -- smoothed copy of shelter, 0 = open sky, 1 = covered
local currentWindSpeed = 0 -- smoothed; the raw value arrives in ~4Hz steps

--[[
	Builds the sound rig. Safe to call when no asset is configured -- it warns
	once and leaves every later call a no-op, rather than spamming errors or
	silently pretending to work.
]]
function WeatherAudio.init()
	if not Config.EnableWindAudio then
		return
	end

	if Config.WindSoundId == "" then
		warn(
			"[WeatherAudio] No WindSoundId set in WeatherConfig -- wind audio disabled. "
				.. "Grab a looping wind asset from Toolbox > Audio and paste its id into "
				.. "WeatherConfig.WindSoundId (see the README)."
		)
		return
	end

	local newSound = Instance.new("Sound")
	newSound.Name = "WindAmbience"
	newSound.SoundId = Config.WindSoundId
	newSound.Looped = true
	newSound.Volume = 0
	newSound.Parent = SoundService -- global, non-positional

	local newEqualizer = Instance.new("EqualizerSoundEffect")
	newEqualizer.Name = "ShelterMuffle"
	-- A SoundEffect applies to the Sound it is parented to.
	newEqualizer.Parent = newSound

	sound = newSound
	equalizer = newEqualizer
end

--[[
	Computes the volume the wind should sit at. Shared by update() and snap() so
	the instant test override can never drift from the normal path.
]]
local function targetVolume(intensity: number, shelter: number): number
	local exposure = 1 - shelter * Config.WindIndoorVolumeDrop
	return Config.WindMaxVolume * intensity * exposure
end

local function applyLevels()
	local activeSound = sound
	if not activeSound then
		return
	end

	activeSound.Volume = currentVolume

	-- Pitch tracks the smoothed wind, not the raw value. The server only
	-- publishes wind a few times a second, so using it directly would step the
	-- pitch in audible jumps rather than gliding between gusts.
	local windAlpha = math.clamp(currentWindSpeed / Config.WindStormSpeed, 0, 1)
	activeSound.PlaybackSpeed = Shared.lerp(Config.WindPitchCalm, Config.WindPitchStorm, windAlpha)

	if equalizer then
		equalizer.HighGain = Shared.lerp(0, Config.WindIndoorHighGain, currentMuffle)
		equalizer.MidGain = Shared.lerp(0, Config.WindIndoorMidGain, currentMuffle)
	end

	-- Don't hold a voice for a sound nobody can hear. The start and stop
	-- thresholds differ on purpose: a single cutoff would let the sound flap on
	-- and off while the volume sits right at the boundary.
	if activeSound.Playing and currentVolume < 0.001 then
		activeSound.Playing = false
	elseif not activeSound.Playing and currentVolume > 0.005 then
		activeSound.Playing = true
	end
end

--[[
	Per-frame update. `dt` drives the same framerate-independent smoothing the
	lighting and shelter fades use, so the wind ramps at the same rate on a 30fps
	laptop and a 240fps desktop.
]]
function WeatherAudio.update(intensity: number, shelter: number, windSpeed: number, dt: number)
	if not sound then
		return
	end

	currentVolume = Shared.damp(currentVolume, targetVolume(intensity, shelter), Config.WindAudioSmoothing, dt)
	currentMuffle = Shared.damp(currentMuffle, shelter, Config.WindAudioSmoothing, dt)

	-- Pitch gets its own, shorter time constant. Smoothing it as slowly as the
	-- volume fade would flatten the gusts into a monotone.
	currentWindSpeed = Shared.damp(currentWindSpeed, windSpeed, Config.WindPitchSmoothing, dt)

	applyLevels()
end

--[[
	Jumps straight to the target levels with no easing. Used only by the
	setOverride(intensity, true) test path, so a command-bar override sounds
	instant instead of fading up over a second.
]]
function WeatherAudio.snap(intensity: number, shelter: number, windSpeed: number)
	if not sound then
		return
	end

	currentVolume = targetVolume(intensity, shelter)
	currentMuffle = shelter
	currentWindSpeed = windSpeed

	applyLevels()
end

return WeatherAudio

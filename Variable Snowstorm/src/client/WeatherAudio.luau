-- Wind ambience. Fed by WeatherClient; owns no state of its own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))

local WeatherAudio = {}

-- Raise to write engine properties less often, lower for finer steps.
local VOLUME_EPSILON = 0.004
local PITCH_EPSILON = 0.004
local GAIN_EPSILON = 0.3

local sound: Sound? = nil
local equalizer: EqualizerSoundEffect? = nil

local currentVolume = 0
local currentMuffle = 0
local currentWindSpeed = 0

local lastVolume = -1
local lastPlaybackSpeed = -1
local lastHighGain = math.huge
local lastMidGain = math.huge

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
	-- SoundService keeps it global; parenting to a BasePart would make it 3D.
	newSound.Parent = SoundService

	local newEqualizer = Instance.new("EqualizerSoundEffect")
	newEqualizer.Name = "ShelterMuffle"
	newEqualizer.Parent = newSound

	sound = newSound
	equalizer = newEqualizer
end

local function targetVolume(intensity: number, shelter: number): number
	return Config.WindMaxVolume * intensity * (1 - shelter * Config.WindIndoorVolumeDrop)
end

local function applyLevels()
	local activeSound = sound
	if not activeSound then
		return
	end

	local volume = if currentVolume < VOLUME_EPSILON then 0 else currentVolume
	if math.abs(volume - lastVolume) > VOLUME_EPSILON or (volume == 0 and lastVolume ~= 0) then
		lastVolume = volume
		activeSound.Volume = volume
	end

	local windAlpha = math.clamp(currentWindSpeed / Config.WindStormSpeed, 0, 1)
	local playbackSpeed = Shared.lerp(Config.WindPitchCalm, Config.WindPitchStorm, windAlpha)
	if math.abs(playbackSpeed - lastPlaybackSpeed) > PITCH_EPSILON then
		lastPlaybackSpeed = playbackSpeed
		activeSound.PlaybackSpeed = playbackSpeed
	end

	if equalizer then
		local highGain = Shared.lerp(0, Config.WindIndoorHighGain, currentMuffle)
		if math.abs(highGain - lastHighGain) > GAIN_EPSILON then
			lastHighGain = highGain
			equalizer.HighGain = highGain
		end

		local midGain = Shared.lerp(0, Config.WindIndoorMidGain, currentMuffle)
		if math.abs(midGain - lastMidGain) > GAIN_EPSILON then
			lastMidGain = midGain
			equalizer.MidGain = midGain
		end
	end

	if activeSound.Playing and currentVolume < 0.001 then
		activeSound.Playing = false
	elseif not activeSound.Playing and currentVolume > 0.005 then
		activeSound.Playing = true
	end
end

function WeatherAudio.update(intensity: number, shelter: number, windSpeed: number, dt: number)
	if not sound then
		return
	end

	currentVolume = Shared.damp(currentVolume, targetVolume(intensity, shelter), Config.WindAudioSmoothing, dt)
	currentMuffle = Shared.damp(currentMuffle, shelter, Config.WindAudioSmoothing, dt)
	currentWindSpeed = Shared.damp(currentWindSpeed, windSpeed, Config.WindPitchSmoothing, dt)

	applyLevels()
end

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

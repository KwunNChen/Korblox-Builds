--[[
	ArtilleryAudio
	The battery report, the incoming whistle, and the impact.

	Impacts are pooled and capped. A twenty-shell barrage will happily try to
	start twenty overlapping booms, and past about six they stop being separate
	sounds and become mud.

	The whistle is not handled here beyond being built -- it gets parented to
	the shell part itself, so Roblox's own 3D audio does the panning and the
	falloff, and the rise as a shell bears down on you costs nothing.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Shared = require(ArtilleryFolder:WaitForChild("ArtilleryShared"))

local ArtilleryAudio = {}

local soundPool: { Sound } = {}
local activeSounds = 0
local reportSound: Sound?

local nearId = ""
local farId = ""
local whistleId = ""

local normalizeId = Shared.assetId

local function verifySound(sound: Sound)
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)

		if ok and sound.IsLoaded and sound.TimeLength > 0 then
			return
		end

		warn(
			string.format("[ArtilleryAudio] audio failed to load (%s) -- it will be silent.", sound.SoundId)
				.. "\n  Roblox audio is private by default: an id only plays if you uploaded it, or the"
				.. "\n  uploader marked it public. Grabbing an id off a Toolbox MODEL also fails here --"
				.. "\n  you need the audio asset's own id, not the model wrapping it."
		)
	end)
end

local function playPooled(soundId: string, volume: number, pitch: number)
	if soundId == "" or activeSounds >= Config.MaxConcurrentSounds then
		return
	end

	local sound = table.remove(soundPool)
	if not sound then
		return
	end

	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch

	activeSounds += 1

	local released = false
	local function release()
		if not released then
			released = true
			activeSounds -= 1
			table.insert(soundPool, sound)
		end
	end

	local connection
	connection = sound.Ended:Connect(function()
		connection:Disconnect()
		release()
	end)

	sound:Play()

	-- Backstop. A sound whose asset never loaded never fires Ended, and without
	-- this the pool would leak one entry per failed shell until nothing plays.
	task.delay(12, function()
		if not released then
			connection:Disconnect()
			sound:Stop()
			release()
		end
	end)
end

-- Built here, parented by the caller onto the moving shell.
function ArtilleryAudio.newWhistle(): Sound?
	if not Config.EnableAudio or whistleId == "" then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "ShellWhistle"
	sound.SoundId = whistleId
	sound.Volume = 0
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = Config.WhistleRollOffMax
	sound.PlaybackSpeed = Config.WhistlePitchStart
	return sound
end

function ArtilleryAudio.batteryReport()
	if not Config.EnableAudio or not reportSound then
		return
	end
	(reportSound :: Sound):Play()
end

--[[
	Schedules an impact boom, delayed by how far away it was.

	The flash always arrives before the sound, the way real gunfire does. Over a
	kilometre that gap runs to about three seconds, which is most of what makes
	distance readable when there is nothing else to judge it by.
]]
function ArtilleryAudio.impact(position: Vector3)
	if not Config.EnableAudio then
		return
	end

	local camera = workspace.CurrentCamera
	local viewer = if camera then camera.CFrame.Position else position
	local distance = (viewer - position).Magnitude

	if distance > Config.ImpactAudibleDistance then
		return
	end

	local near = distance <= Config.ImpactNearDistance
	local soundId = if near then nearId else farId
	if soundId == "" then
		-- Fall back to whichever one was actually filled in, so a half-configured
		-- install is quiet rather than silent.
		soundId = if nearId ~= "" then nearId else farId
	end

	local alpha = math.clamp(1 - distance / Config.ImpactAudibleDistance, 0, 1)
	local volume = alpha * alpha * Config.ImpactVolume
	local pitch = Shared.lerp(0.8, 1.1, alpha)

	task.delay(distance / math.max(Config.SoundSpeed, 1), playPooled, soundId, volume, pitch)
end

function ArtilleryAudio.init()
	if not Config.EnableAudio then
		return
	end

	nearId = normalizeId(Config.ImpactNearSoundId)
	farId = normalizeId(Config.ImpactFarSoundId)
	whistleId = normalizeId(Config.ShellWhistleSoundId)
	local reportId = normalizeId(Config.BatteryReportSoundId)

	if nearId == "" and farId == "" and whistleId == "" and reportId == "" then
		warn(
			"[ArtilleryAudio] every sound id in ArtilleryConfig is empty -- artillery runs silent. "
				.. "It needs four: BatteryReportSoundId (the warning), ShellWhistleSoundId, "
				.. "ImpactNearSoundId and ImpactFarSoundId. See the README."
		)
		return
	end

	for index = 1, Config.MaxConcurrentSounds do
		local sound = Instance.new("Sound")
		sound.Name = "ArtilleryImpact"
		sound.SoundId = if nearId ~= "" then nearId else farId
		sound.Volume = 0
		sound.Parent = SoundService
		table.insert(soundPool, sound)

		if index == 1 and sound.SoundId ~= "" then
			verifySound(sound)
		end
	end

	if reportId ~= "" then
		local report = Instance.new("Sound")
		report.Name = "ArtilleryBatteryReport"
		report.SoundId = reportId
		report.Volume = Config.BatteryReportVolume
		report.Parent = SoundService
		reportSound = report
	end
end

return ArtilleryAudio

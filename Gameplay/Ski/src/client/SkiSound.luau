local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiSound = {}
SkiSound.__index = SkiSound

local warnedMissing = false

local function warnOnce()
	if warnedMissing then
		return
	end
	warnedMissing = true
	warn("[Ski] no sound ids set -- skiing is silent. They're at the TOP of SkiConfig under \"PUT YOUR SOUND IDS HERE\". Roblox audio is private, so you need your own: View > Toolbox > Audio, right click, Copy Asset ID.")
end

local function assetId(value: unknown): string?
	if type(value) ~= "string" then
		return nil
	end

	local digits = value:match("(%d+)")
	if not digits or #digits < 6 then
		return nil
	end

	return "rbxassetid://" .. digits
end

local function newLoop(parent: BasePart, rawId: string): Sound?
	local id = assetId(rawId)
	if not id then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMaxDistance = 120
	sound.Parent = parent
	sound:Play()
	return sound
end

function SkiSound.new(character: Model)
	local self = setmetatable({}, SkiSound)

	self.root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.loops = {}

	if not Config.EnableSound or not self.root then
		return self
	end

	if not (assetId(Config.GlideSoundId) or assetId(Config.CarveSoundId) or assetId(Config.WindSoundId)) then
		warnOnce()
	end

	self.glide = newLoop(self.root, Config.GlideSoundId)
	self.carve = newLoop(self.root, Config.CarveSoundId)
	self.wind = newLoop(self.root, Config.WindSoundId)

	for _, sound in { self.glide, self.carve, self.wind } do
		if sound then
			table.insert(self.loops, sound)
		end
	end

	return self
end

local function playOneShot(root: BasePart?, rawId: string, volume: number, pitch: number?)
	local id = assetId(rawId)
	if not Config.EnableSound or not root or not id then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 150
	sound.Parent = root
	sound:Play()

	Debris:AddItem(sound, 6)
end

local function driveLoop(sound: Sound?, targetVolume: number, targetPitch: number, dt: number)
	if not sound then
		return
	end
	sound.Volume = Shared.damp(sound.Volume, targetVolume, Config.SoundSmoothing, dt)
	sound.PlaybackSpeed = Shared.damp(sound.PlaybackSpeed, targetPitch, Config.SoundSmoothing, dt)
end

function SkiSound:update(dt: number, speed: number, scrub: number, riding: boolean, onSnow: boolean)
	if #self.loops == 0 then
		return
	end

	local speedAlpha = math.clamp(speed / Config.MaxSpeed, 0, 1)
	local grounded = riding and onSnow

	driveLoop(
		self.glide,
		if grounded then speedAlpha * Config.GlideMaxVolume else 0,
		Shared.lerp(Config.GlidePitchSlow, Config.GlidePitchFast, speedAlpha),
		dt
	)

	local scrubAlpha = math.clamp(scrub / Config.SpraySaturationSpeed, 0, 1)
	driveLoop(
		self.carve,
		if grounded then scrubAlpha * Config.CarveMaxVolume else 0,
		Shared.lerp(0.9, 1.15, scrubAlpha),
		dt
	)

	driveLoop(
		self.wind,
		speedAlpha * speedAlpha * Config.WindMaxVolume,
		Shared.lerp(Config.WindPitchSlow, Config.WindPitchFast, speedAlpha),
		dt
	)
end

function SkiSound:jump()
	playOneShot(self.root, Config.JumpSoundId, Config.OneShotVolume)
end

function SkiSound:land(impactSpeed: number)
	local strength = math.clamp(impactSpeed / Config.LandingPuffSpeed, 0, 1)
	if strength < 0.15 then
		return
	end

	playOneShot(
		self.root,
		Config.LandSoundId,
		Config.OneShotVolume * (0.4 + strength * 0.6),
		1.15 - strength * 0.3
	)
end

function SkiSound:mute()
	for _, sound in self.loops do
		sound.Volume = 0
	end
end

function SkiSound:destroy()
	for _, sound in self.loops do
		sound:Destroy()
	end
	self.loops = {}
	self.glide, self.carve, self.wind = nil, nil, nil
end

return SkiSound

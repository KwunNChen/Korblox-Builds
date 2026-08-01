--[[
	SkiSound
	Three loops that follow what you're doing, and three one-shots.

	    Glide  skis over snow, follows speed
	    Carve  the edges biting, follows SIDEWAYS speed -- so it arrives when you
	           turn instead of droning the whole way down the hill
	    Wind   follows speed, and keeps going in the air

	EVERY ID IS EMPTY BY DEFAULT and has to be filled in. Roblox audio is private
	to the place that owns it, so an id from anywhere else is silent with no
	error at all. An empty slot is skipped rather than creating a Sound that can
	never play.

	LOCAL TO YOU, like the poses and the spray. These are made on the client, so
	nobody else hears them. Sharing would mean the server creating and driving
	them from replicated speed.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiSound = {}
SkiSound.__index = SkiSound

-- Warned about once per session rather than once per spawn, or strapping in
-- repeatedly with no audio set fills Output with the same line.
local warnedMissing = false

local function warnOnce()
	if warnedMissing then
		return
	end
	warnedMissing = true
	warn("[Ski] no sound ids set -- skiing is silent. They're at the TOP of SkiConfig under \"PUT YOUR SOUND IDS HERE\". Roblox audio is private, so you need your own: View > Toolbox > Audio, right click, Copy Asset ID.")
end

--[[
	Pulls a usable asset id out of whatever is in config, or nil if there isn't
	one.

	Two jobs. It lets the "PUT GLIDE SOUND ID HERE" placeholders read as unset
	rather than as broken ids -- so an unfilled slot is skipped silently instead
	of creating a Sound that can never play. And it accepts whatever form you
	paste: a bare number, an rbxassetid:// url, or a full web address all work,
	because Copy Asset ID gives you a different one depending on where you copy
	it from.
]]
local function assetId(value: unknown): string?
	if type(value) ~= "string" then
		return nil
	end

	local digits = value:match("(%d+)")
	-- Roblox ids are long. A short run of digits is something else entirely --
	-- a stray number in a placeholder, most likely.
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

--[[
	One-shots are detached from this object on purpose: they're parented to the
	root and cleaned up by Debris, not by us.

	The crash sound is why. A wipeout destroys this object in the same breath as
	playing it, and a Sound owned by us would be cut off mid-hit.
]]
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

	-- Glide and carve need snow under you. Ski onto rock and both cut, which is
	-- the same rule the spray follows.
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

	-- Wind doesn't care what's under you, or whether there's anything under you
	-- at all -- it's the only one that keeps going through a jump.
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

-- Pitched down and louder the harder you come in, so a heavy landing sounds
-- like one rather than being the same clip every time.
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

-- No crash sound here. It's played by SkiRagdoll on the server, so everyone
-- watching hears the wipeout rather than only the person it happened to.

function SkiSound:destroy()
	for _, sound in self.loops do
		sound:Destroy()
	end
	self.loops = {}
	self.glide, self.carve, self.wind = nil, nil, nil
end

return SkiSound

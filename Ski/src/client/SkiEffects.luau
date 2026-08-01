--[[
	SkiEffects
	Snow off the edges, a burst on landing, and the camera stretching with speed.

	Reads only. Nothing in here can change how the skis ride, and every piece
	switches off independently in config -- the system rides identically with all
	of it disabled.

	LOCAL TO YOU, like the poses. Particles and camera changes made on the client
	don't replicate, so you see your own spray and not other people's. Sharing it
	would mean replicating each player's sideways speed continuously, which is a
	lot of traffic for something cosmetic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiEffects = {}
SkiEffects.__index = SkiEffects

local function newEmitter(): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Config.SprayTexture
	emitter.Color = ColorSequence.new(Config.SprayColor)
	emitter.LightEmission = 0.35
	emitter.LightInfluence = 0.8

	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 2.4),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})

	emitter.Lifetime = NumberRange.new(0.3, 0.75)
	emitter.Speed = NumberRange.new(4, 11)
	emitter.SpreadAngle = Vector2.new(26, 26)
	emitter.Drag = 5
	emitter.Rate = 0
	emitter.Enabled = false

	-- Snow thrown off a ski keeps most of the ski's own motion, so it trails
	-- behind you instead of hanging in the air where you left it.
	emitter.VelocityInheritance = 0.4

	return emitter
end

--[[
	`isLocal` gates the camera work, and it is not optional.

	Spray belongs to whoever's skiing, but there is only one camera and it is
	yours. An instance built for somebody else's character that still wrote
	FieldOfView would be stretching YOUR view to match THEIR speed -- and with
	several people on the hill they'd fight over it every frame.
]]
function SkiEffects.new(character: Model, isLocal: boolean)
	local self = setmetatable({}, SkiEffects)

	self.emitters = {} :: { ParticleEmitter }
	self.isLocal = isLocal
	self.fovBoost = 0
	self.camera = if isLocal then workspace.CurrentCamera else nil
	self.baseFov = if self.camera then self.camera.FieldOfView else 70

	if Config.EnableSpray then
		local gear = character:FindFirstChild("SkiGear")
		for _, name in { "LeftSki", "RightSki" } do
			local ski = gear and gear:FindFirstChild(name)
			if ski and ski:IsA("BasePart") then
				-- At the tail, so spray comes off behind you rather than out of
				-- the middle of your boot.
				local attachment = Instance.new("Attachment")
				attachment.Name = "SkiSprayPoint"
				attachment.CFrame = CFrame.new(0, 0, ski.Size.Z * 0.45)
				attachment.Parent = ski

				local emitter = newEmitter()
				emitter.Parent = attachment
				table.insert(self.emitters, emitter)
			end
		end
	end

	return self
end

--[[
	`scrub` is sideways speed across the skis -- see the note in SkiConfig for
	why that and not total speed.

	`onSnow` gates it by material, so skiing across rock throws nothing. That is
	most of what makes the snow read as snow rather than as a white floor.
]]
function SkiEffects:update(dt: number, speed: number, scrub: number, onSnow: boolean, riding: boolean)
	if #self.emitters > 0 then
		local intensity = if riding and onSnow
			then math.clamp(scrub / Config.SpraySaturationSpeed, 0, 1)
			else 0

		local rate = intensity * Config.SprayMaxRate

		for _, emitter in self.emitters do
			emitter.Rate = rate
			emitter.Enabled = rate > 1
		end
	end

	if Config.EnableSpeedFov and self.camera then
		local target = if riding then (speed / Config.MaxSpeed) * Config.MaxFovBoost else 0
		self.fovBoost = Shared.damp(self.fovBoost, target, Config.FovSmoothing, dt)
		self.camera.FieldOfView = self.baseFov + self.fovBoost
	end
end

-- One-shot burst on touchdown, sized by how hard you came down.
function SkiEffects:landingPuff(impactSpeed: number, onSnow: boolean)
	if not Config.EnableLandingPuff or not onSnow then
		return
	end

	local strength = math.clamp(impactSpeed / Config.LandingPuffSpeed, 0, 1)
	if strength < 0.15 then
		return
	end

	local count = math.floor(Config.LandingPuffCount * strength)
	for _, emitter in self.emitters do
		emitter:Emit(count)
	end
end

function SkiEffects:destroy()
	for _, emitter in self.emitters do
		local attachment = emitter.Parent
		emitter:Destroy()
		if attachment and attachment:IsA("Attachment") then
			attachment:Destroy()
		end
	end
	self.emitters = {}

	-- Put the camera back. Left stretched, it follows the player around for the
	-- rest of the session.
	if self.camera and Config.EnableSpeedFov then
		self.camera.FieldOfView = self.baseFov
	end
end

return SkiEffects

local Players = game:GetService("Players")
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
	emitter.VelocityInheritance = 0.4

	return emitter
end

local function newTrail(): Trail
	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new(Config.TrailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.TrailTransparency),
		NumberSequenceKeypoint.new(0.7, Config.TrailTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = Config.TrailLifetime
	trail.LightInfluence = 1
	trail.FaceCamera = false
	trail.MinLength = 0.15
	trail.Enabled = false
	return trail
end

function SkiEffects.new(character: Model, isLocal: boolean)
	local self = setmetatable({}, SkiEffects)

	self.emitters = {} :: { ParticleEmitter }
	self.isLocal = isLocal
	self.fovBoost = 0
	self.camera = if isLocal then workspace.CurrentCamera else nil
	self.baseFov = if self.camera then self.camera.FieldOfView else 70

	self.trails = {} :: { Trail }
	self.attachments = {} :: { Attachment }

	local gear = character:FindFirstChild("SkiGear")
	for _, name in { "LeftSki", "RightSki" } do
		local ski = gear and gear:FindFirstChild(name)
		if not (ski and ski:IsA("BasePart")) then
			continue
		end

		if Config.EnableSpray then
			local attachment = Instance.new("Attachment")
			attachment.Name = "SkiSprayPoint"
			attachment.CFrame = CFrame.new(0, 0, ski.Size.Z * 0.45)
			attachment.Parent = ski
			table.insert(self.attachments, attachment)

			local emitter = newEmitter()
			emitter.Parent = attachment
			table.insert(self.emitters, emitter)
		end

		if Config.EnableTrails then
			local left = Instance.new("Attachment")
			left.Name = "SkiTrailLeft"
			left.CFrame = CFrame.new(-Config.TrailWidth * 0.5, -ski.Size.Y * 0.5, 0)
			left.Parent = ski

			local right = Instance.new("Attachment")
			right.Name = "SkiTrailRight"
			right.CFrame = CFrame.new(Config.TrailWidth * 0.5, -ski.Size.Y * 0.5, 0)
			right.Parent = ski

			local trail = newTrail()
			trail.Attachment0 = left
			trail.Attachment1 = right
			trail.Parent = ski

			table.insert(self.attachments, left)
			table.insert(self.attachments, right)
			table.insert(self.trails, trail)
		end
	end

	if isLocal then
		self:_buildWindRush()
		self:_buildHud()
	end

	return self
end

function SkiEffects:_buildWindRush()
	if not Config.EnableWindRush or not self.camera then
		return
	end

	local rig = Instance.new("Part")
	rig.Name = "SkiWindRush"
	rig.Size = Vector3.new(26, 18, 26)
	rig.Transparency = 1
	rig.Anchored = true
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.Parent = self.camera

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Config.WindRushTexture
	emitter.Color = ColorSequence.new(Config.WindRushColor)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(0.35)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(0)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.LockedToPart = false
	emitter.Squash = NumberSequence.new(3)
	emitter.Parent = rig

	self.windRig = rig
	self.windEmitter = emitter
end

function SkiEffects:_buildHud()
	if not Config.EnableSpeedHud then
		return
	end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SkiSpeed"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -24, 1, -24)
	holder.Size = UDim2.fromOffset(96, 38)
	holder.BackgroundTransparency = 1
	holder.Parent = gui

	local speed = Instance.new("TextLabel")
	speed.Name = "Value"
	speed.Size = UDim2.fromScale(1, 0.7)
	speed.BackgroundTransparency = 1
	speed.Font = Enum.Font.GothamBold
	speed.TextScaled = true
	speed.TextXAlignment = Enum.TextXAlignment.Right
	speed.TextColor3 = Color3.fromRGB(255, 255, 255)
	speed.TextStrokeTransparency = 0.55
	speed.Text = "0"
	speed.Parent = holder

	local unit = Instance.new("TextLabel")
	unit.Position = UDim2.fromScale(0, 0.7)
	unit.Size = UDim2.fromScale(1, 0.3)
	unit.BackgroundTransparency = 1
	unit.Font = Enum.Font.GothamMedium
	unit.TextSize = 10
	unit.TextXAlignment = Enum.TextXAlignment.Right
	unit.TextColor3 = Color3.fromRGB(176, 206, 236)
	unit.TextStrokeTransparency = 0.75
	unit.Text = "STUDS/S"
	unit.Parent = holder

	gui.Parent = playerGui

	self.hud = gui
	self.hudValue = speed
end

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

	for _, trail in self.trails do
		trail.Enabled = riding and onSnow and speed > 4
	end

	if not self.isLocal then
		return
	end

	if Config.EnableSpeedFov and self.camera then
		local target = if riding then (speed / Config.MaxSpeed) * Config.MaxFovBoost else 0
		self.fovBoost = Shared.damp(self.fovBoost, target, Config.FovSmoothing, dt)
		self.camera.FieldOfView = self.baseFov + self.fovBoost
	end

	if self.windEmitter and self.camera then
		self.windRig.CFrame = self.camera.CFrame

		local over = (speed - Config.WindRushSpeed) / math.max(Config.MaxSpeed - Config.WindRushSpeed, 1)
		local intensity = math.clamp(over, 0, 1)

		self.windEmitter.Rate = intensity * Config.WindRushMaxRate
		self.windEmitter.Enabled = intensity > 0.01
	end

	if self.hud then
		self.hud.Enabled = riding
		if riding then
			self.hudValue.Text = string.format("%d", math.floor(speed + 0.5))
		end
	end
end

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

function SkiEffects:setActive(active: boolean)
	for _, emitter in self.emitters do
		emitter.Enabled = false
		emitter.Rate = 0
	end

	for _, trail in self.trails do
		trail.Enabled = false
	end

	if not active and self.windEmitter then
		self.windEmitter.Enabled = false
	end
end

function SkiEffects:destroy()
	for _, emitter in self.emitters do
		emitter:Destroy()
	end
	for _, trail in self.trails do
		trail:Destroy()
	end
	for _, attachment in self.attachments do
		attachment:Destroy()
	end

	self.emitters = {}
	self.trails = {}
	self.attachments = {}

	if self.windRig then
		self.windRig:Destroy()
		self.windRig = nil
		self.windEmitter = nil
	end

	if self.hud then
		self.hud:Destroy()
		self.hud = nil
	end

	if self.camera and Config.EnableSpeedFov then
		self.camera.FieldOfView = self.baseFov
	end
end

return SkiEffects

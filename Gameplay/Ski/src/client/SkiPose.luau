local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiPose = {}
SkiPose.__index = SkiPose

local JOINTS = { "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

local POSES = {
	Stance = {
		RootJoint = Vector3.new(0.68, 0, 0),
		Neck = Vector3.new(-0.58, 0, 0),
		["Right Shoulder"] = Vector3.new(-0.12, 0, 1.42),
		["Left Shoulder"] = Vector3.new(-0.12, 0, -1.42),
		["Right Hip"] = Vector3.zero,
		["Left Hip"] = Vector3.zero,
	},

	Carve = {
		RootJoint = Vector3.new(0.68, 0, 0),
		Neck = Vector3.new(-0.58, 0, 0),
		["Right Shoulder"] = Vector3.new(0.34, 0, 1.2),
		["Left Shoulder"] = Vector3.new(0.34, 0, -1.2),
		["Right Hip"] = Vector3.zero,
		["Left Hip"] = Vector3.zero,
	},

	Tuck = {
		RootJoint = Vector3.new(1.05, 0, 0),
		Neck = Vector3.new(-0.85, 0, 0),
		["Right Shoulder"] = Vector3.new(-0.2, 0, 1.55),
		["Left Shoulder"] = Vector3.new(-0.2, 0, -1.55),
		["Right Hip"] = Vector3.zero,
		["Left Hip"] = Vector3.zero,
	},

	Brake = {
		RootJoint = Vector3.new(0.55, 0, 0),
		Neck = Vector3.new(-0.42, 0, 0),
		["Right Shoulder"] = Vector3.new(0.42, 0, 0.7),
		["Left Shoulder"] = Vector3.new(0.42, 0, -0.7),
		["Right Hip"] = Vector3.new(0, -0.28, 0.26),
		["Left Hip"] = Vector3.new(0, 0.28, -0.26),
	},

	Air = {
		RootJoint = Vector3.new(0.3, 0, 0),
		Neck = Vector3.new(-0.22, 0, 0),
		["Right Shoulder"] = Vector3.new(0.46, 0, 1.2),
		["Left Shoulder"] = Vector3.new(0.46, 0, -1.2),
		["Right Hip"] = Vector3.new(0, 0, 0.12),
		["Left Hip"] = Vector3.new(0, 0, -0.12),
	},
}

local NEUTRAL = {}
for _, name in JOINTS do
	NEUTRAL[name] = Vector3.zero
end

function SkiPose.new(character: Model)
	local self = setmetatable({}, SkiPose)

	self.joints = {} :: { [string]: Motor6D }
	self.defaults = {} :: { [string]: CFrame }
	self.current = {} :: { [string]: Vector3 }
	self.target = NEUTRAL
	self.lean = 0

	self.plantSide = 0
	self.plantLeft = 0
	self.plantReadyAt = 0
	self.lastPlantSide = 0

	self.poleTrail = Config.PoleTrailAngle
	self.tracks = {} :: { [string]: AnimationTrack }
	self.activeTrack = nil :: AnimationTrack?
	self.poseName = ""

	self.released = true

	local torso = character:FindFirstChild("Torso")
	local root = character:FindFirstChild("HumanoidRootPart")
	self.root = root :: BasePart?

	for _, name in JOINTS do
		local holder = if name == "RootJoint" then root else torso
		local joint = holder and holder:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			self.joints[name] = joint
			self.defaults[name] = joint.C0
			self.current[name] = Vector3.zero
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	self.animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	self.skiJoints = {} :: { [number]: Motor6D }
	self.poleJoints = {} :: { [number]: Motor6D }
	self.skiLimbs = {} :: { [number]: BasePart }
	self.poleLimbs = {} :: { [number]: BasePart }

	local function limb(r6: string, r15: string): BasePart?
		return (character:FindFirstChild(r6) or character:FindFirstChild(r15)) :: BasePart?
	end

	self.skiLimbs[-1] = limb("Left Leg", "LeftFoot")
	self.skiLimbs[1] = limb("Right Leg", "RightFoot")
	self.poleLimbs[-1] = limb("Left Arm", "LeftHand")
	self.poleLimbs[1] = limb("Right Arm", "RightHand")

	local gear = character:FindFirstChild("SkiGear")
	if gear then
		local function collect(into, prefix: string)
			for _, entry in { { "Left" .. prefix, -1 }, { "Right" .. prefix, 1 } } do
				local part = gear:FindFirstChild(entry[1])
				local attach = part and part:FindFirstChild(entry[1] .. "Attach")
				if attach and attach:IsA("Motor6D") then
					into[entry[2] :: number] = attach
				end
			end
		end

		collect(self.skiJoints, "Ski")
		collect(self.poleJoints, "Pole")
	end

	return self
end

local function isDeployed(joint: Motor6D, limb: BasePart?): boolean
	return limb ~= nil and joint.Part0 == limb
end

local function footBase(sign: number): CFrame
	return CFrame.new(
		sign * Config.SkiFootOffset.X,
		Config.SkiFootOffset.Y,
		Config.SkiFootOffset.Z
	)
end

local ROOT_TO_SOLE = 3
local ROOT_TO_LEG_CENTRE = 2
local POLE_UPRIGHT = -math.pi / 2

function SkiPose:_alignSkis()
	local root = self.root
	if not root then
		return
	end

	local drop = ROOT_TO_SOLE - ROOT_TO_LEG_CENTRE - Config.SkiThickness * 0.5 - Config.SkiCamber
	local roll = self.lean * Config.CarveDirection * Config.MaxEdgeAngle
	local facing = (root.CFrame * CFrame.Angles(0, 0, roll)).Rotation

	for sign, joint in self.skiJoints do
		local leg = self.skiLimbs[sign]

		if leg and joint.Parent and isDeployed(joint, leg) then
			local boot = leg.CFrame
				* CFrame.new(sign * Config.SkiFootOffset.X, -drop, Config.SkiFootOffset.Z)

			joint.C0 = leg.CFrame:Inverse() * (CFrame.new(boot.Position) * facing)
		end
	end
end

function SkiPose:_restSkis()
	for sign, joint in self.skiJoints do
		if joint.Parent and isDeployed(joint, self.skiLimbs[sign]) then
			joint.C0 = footBase(sign)
		end
	end
end

function SkiPose:_restPoles()
	for sign, joint in self.poleJoints do
		if joint.Parent and isDeployed(joint, self.poleLimbs[sign]) then
			joint.C0 = CFrame.new(
				sign * Config.PoleHandOffset.X,
				Config.PoleHandOffset.Y,
				Config.PoleHandOffset.Z
			) * CFrame.Angles(0, 0, POLE_UPRIGHT + sign * Config.PoleHandTilt)
		end
	end
end

function SkiPose:_applyPoleCounterRotation(armAngle: number)
	for sign, joint in self.poleJoints do
		if joint.Parent and isDeployed(joint, self.poleLimbs[sign]) then
			local rest = CFrame.Angles(-self.poleTrail, 0, 0)
				* CFrame.Angles(0, 0, POLE_UPRIGHT + sign * Config.PoleHandTilt)

			joint.C0 = CFrame.new(
				sign * Config.PoleHandOffset.X,
				Config.PoleHandOffset.Y,
				Config.PoleHandOffset.Z
			) * CFrame.Angles(-armAngle, 0, 0) * rest
		end
	end
end

local function rootLean(self): number
	local root = self.current.RootJoint
	return if root then root.X else 0
end

function SkiPose:_uprightCompensation(name: string): number
	if name == "Right Hip" then
		return rootLean(self)
	elseif name == "Left Hip" then
		return -rootLean(self)
	end
	return 0
end

function SkiPose:armAngle(): number
	local shoulder = self.current["Right Shoulder"]
	return (if shoulder then shoulder.Z else 0) - rootLean(self)
end

function SkiPose:_trackFor(poseName: string): AnimationTrack?
	local id = Config.Animations[poseName]
	if not id or id == "" or not self.animator then
		return nil
	end

	local existing = self.tracks[poseName]
	if existing then
		return existing
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = id

	local ok, track = pcall(function()
		return self.animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(string.format("[Ski] could not load animation for pose %q (%s)", poseName, id))
		return nil
	end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	self.tracks[poseName] = track
	return track
end

function SkiPose:setPose(poseName: string)
	if self.poseName == poseName and not self.released then
		return
	end
	self.poseName = poseName
	self.released = false

	if self.activeTrack then
		self.activeTrack:Stop(0.15)
		self.activeTrack = nil
	end

	local track = self:_trackFor(poseName)
	if track then
		track:Play(0.15)
		self.activeTrack = track
		self.target = NEUTRAL
		return
	end

	self.target = POSES[poseName] or NEUTRAL
end

function SkiPose:setLean(lean: number)
	self.lean = lean

	if not Config.EnablePolePlants then
		return
	end

	local side = if lean > Config.PolePlantLean then 1 elseif lean < -Config.PolePlantLean then -1 else 0
	local now = os.clock()

	if side ~= 0 and side ~= self.lastPlantSide and now >= self.plantReadyAt then
		self.lastPlantSide = side
		self.plantSide = side
		self.plantLeft = Config.PolePlantDuration
		self.plantReadyAt = now + Config.PolePlantCooldown
	end
end

function SkiPose:_plantReach(sign: number): number
	if self.plantSide ~= sign or self.plantLeft <= 0 then
		return 0
	end

	local progress = 1 - (self.plantLeft / Config.PolePlantDuration)

	local envelope
	if progress < 0.18 then
		envelope = progress / 0.18
	elseif progress < 0.68 then
		envelope = 1
	else
		envelope = 1 - (progress - 0.68) / 0.32
	end

	return envelope * Config.PolePlantReach
end

function SkiPose:_carveOverlay(name: string): Vector3
	local lean = self.lean * Config.CarveDirection

	if name == "RootJoint" then
		return Vector3.new(0, -lean * Config.MaxLeanAngle, lean * Config.MaxCounterTwist)
	elseif name == "Neck" then
		return Vector3.new(0, lean * Config.MaxLeanAngle * Config.NeckCounterRoll, 0)
	elseif name == "Right Hip" then
		return Vector3.new(-lean * Config.MaxLegTip, 0, 0)
	elseif name == "Left Hip" then
		return Vector3.new(lean * Config.MaxLegTip, 0, 0)
	elseif name == "Right Shoulder" then
		return Vector3.new(0, 0, -self:_plantReach(1))
	elseif name == "Left Shoulder" then
		return Vector3.new(0, 0, self:_plantReach(-1))
	end

	return Vector3.zero
end

function SkiPose:update(dt: number)
	if self.released then
		return
	end

	if self.activeTrack then
		self:_restSkis()
		self:_restPoles()
		return
	end

	if self.plantLeft > 0 then
		self.plantLeft -= dt
	end

	local trailTarget = if self.poseName == "Air" then Config.PoleAirAngle else Config.PoleTrailAngle
	self.poleTrail = Shared.damp(self.poleTrail, trailTarget, Config.PoseSmoothing, dt)

	for name, joint in self.joints do
		local goal = self.target[name] or Vector3.zero
		local current = self.current[name]

		current = Vector3.new(
			Shared.damp(current.X, goal.X, Config.PoseSmoothing, dt),
			Shared.damp(current.Y, goal.Y, Config.PoseSmoothing, dt),
			Shared.damp(current.Z, goal.Z, Config.PoseSmoothing, dt)
		)
		self.current[name] = current

		local carve = self:_carveOverlay(name)
		local upright = self:_uprightCompensation(name)

		joint.C0 = self.defaults[name]
			* CFrame.Angles(current.X + carve.X, current.Y + carve.Y, current.Z + carve.Z + upright)

		joint.Transform = CFrame.identity
	end

	self:_alignSkis()
	self:_applyPoleCounterRotation(self:armAngle())
end

function SkiPose:release()
	if self.released then
		return
	end
	self.released = true

	if self.activeTrack then
		self.activeTrack:Stop(0.15)
		self.activeTrack = nil
	end

	for name, joint in self.joints do
		joint.C0 = self.defaults[name]
		self.current[name] = Vector3.zero
	end

	self:_restSkis()
	self:_applyPoleCounterRotation(0)

	self.poseName = ""
	self.target = NEUTRAL
end

function SkiPose:destroy()
	self:release()
	for _, track in self.tracks do
		track:Destroy()
	end
	self.tracks = {}
	self.joints = {}
end

return SkiPose

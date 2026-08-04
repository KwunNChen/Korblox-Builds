local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))
local SkiPhysics = require(script.Parent:WaitForChild("SkiPhysics"))
local SkiPose = require(script.Parent:WaitForChild("SkiPose"))
local SkiEffects = require(script.Parent:WaitForChild("SkiEffects"))
local SkiSound = require(script.Parent:WaitForChild("SkiSound"))
local SkiRemoteView = require(script.Parent:WaitForChild("SkiRemoteView"))

local UP = Vector3.yAxis
local LIMBS = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local WALKING, RIDING, AIRBORNE = "Walking", "Riding", "Airborne"

local MIN_GROUND_DOT = math.cos(math.rad(Config.MaxGroundAngle))
local MAX_CLOSING_SPEED = 60
local GROUND_CONTACT_TOLERANCE = 0.4
local STORM_FORCE_NAME = "StormWindForce"

local player = Players.LocalPlayer

local remotes = Shared.getRemotes()
if not remotes then
	warn("[Ski] ReplicatedStorage.SkiRemotes missing -- ski client disabled.")
	return
end

local equipEvent = Shared.getRemote(remotes, "SkiEquip")
if not equipEvent then
	warn("[Ski] no SkiEquip remote -- ski client disabled.")
	return
end

local crashEvent = Shared.getRemote(remotes, "SkiCrash")
local stateEvent = Shared.getRemote(remotes, "SkiState")

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

local jumpQueued = false

UserInputService.JumpRequest:Connect(function()
	jumpQueued = true
end)

local function isDown(key: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(key)
end

local function isButtonDown(button: Enum.KeyCode): boolean
	if not UserInputService.GamepadEnabled then
		return false
	end
	local ok, down = pcall(UserInputService.IsGamepadButtonDown, UserInputService, Enum.UserInputType.Gamepad1, button)
	return ok and down
end

local function readMoveDirection(humanoid: Humanoid): Vector3
	local move = humanoid.MoveDirection
	if move.Magnitude > 0.05 then
		return move
	end

	local x = (isDown(Enum.KeyCode.D) and 1 or 0) - (isDown(Enum.KeyCode.A) and 1 or 0)
	local z = (isDown(Enum.KeyCode.S) and 1 or 0) - (isDown(Enum.KeyCode.W) and 1 or 0)
	if x == 0 and z == 0 then
		return Vector3.zero
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end

	local cf = camera.CFrame
	local flatLook = Shared.safeUnit(Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z), -Vector3.zAxis)
	local flatRight = Shared.safeUnit(Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z), Vector3.xAxis)

	return Shared.safeUnit(flatRight * x - flatLook * z, Vector3.zero)
end

local function readInput(humanoid: Humanoid, heading: Vector3, grounded: boolean)
	local move = readMoveDirection(humanoid)
	local right = Shared.safeUnit(heading:Cross(UP), Vector3.xAxis)
	local flatHeading = Shared.safeUnit(Vector3.new(heading.X, 0, heading.Z), heading)

	local along = move:Dot(flatHeading)

	return {
		steer = math.clamp(move:Dot(right), -1, 1),
		braking = grounded and (isDown(Config.BrakeKey) or isButtonDown(Config.BrakeButton) or along < -0.5),
		tucking = isDown(Config.TuckKey) or isButtonDown(Config.TuckButton),
	}
end

local skier: any = nil

local function clearGravityCancel(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	for _, child in root:GetChildren() do
		if child.Name == "SkiGravityCancel" or child.Name == "SkiForcePoint" then
			child:Destroy()
		end
	end
end

local function setLimbCollision(self, enabled: boolean)
	for part, original in self.limbCollision do
		if part.Parent then
			part.CanCollide = if enabled then original else false
		end
	end
end

local function stopSkiing(leaveLimp: boolean?)
	if not skier then
		return
	end

	local self = skier
	skier = nil

	if not leaveLimp and self.humanoid and self.humanoid.Parent then
		self.humanoid.PlatformStand = false
	end

	setLimbCollision(self, true)

	if self.force then
		self.force.Enabled = false
		self.force:Destroy()
	end
	if self.forceAttachment then
		self.forceAttachment:Destroy()
	end
	if self.pose then
		self.pose:destroy()
	end
	if self.effects then
		self.effects:destroy()
	end
	if self.sound then
		self.sound:destroy()
	end

	if self.character then
		clearGravityCancel(self.character)
		Shared.setWalkAnimation(self.character, nil)
	end

	log("stopped")
end

local function startSkiing(character: Model)
	stopSkiing()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end

	clearGravityCancel(character)

	local forceAttachment = Instance.new("Attachment")
	forceAttachment.Name = "SkiForcePoint"
	forceAttachment.Parent = root

	local force = Instance.new("VectorForce")
	force.Name = "SkiGravityCancel"
	force.Attachment0 = forceAttachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Enabled = false
	force.Parent = root

	local limbCollision = {}
	for _, name in LIMBS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			limbCollision[part] = part.CanCollide
		end
	end

	skier = {
		character = character,
		humanoid = humanoid,
		root = root,

		force = force,
		forceAttachment = forceAttachment,
		limbCollision = limbCollision,
		pose = SkiPose.new(character),
		effects = SkiEffects.new(character, true),
		sound = SkiSound.new(character),

		state = WALKING,
		velocity = Vector3.zero,
		heading = root.CFrame.LookVector,
		up = UP,
		lean = 0,

		groundParams = Shared.newGroundParams({ character }),
		lastGroundTime = os.clock(),
		lastGroundDistance = nil :: number?,

		landedAt = -math.huge,

		jumpReadyAt = os.clock() + Config.EquipGrace,
		graceUntil = os.clock() + Config.EquipGrace,

		reportAt = 0,
		sentState = "",
		sentSpeed = 0,
		sentScrub = 0,
		sentLean = 0,
		sentOnSnow = false,
	}

	jumpQueued = false

	Shared.setWalkAnimation(character, Config.Animations.Walking)

	log("started")
end

local function enterSim(self)
	self.humanoid.PlatformStand = true
	self.force.Enabled = true
	setLimbCollision(self, false)

	self.velocity = self.root.AssemblyLinearVelocity
	self.heading = self.root.CFrame.LookVector
	self.lastGroundDistance = nil
end

local function enterWalking(self)
	self.state = WALKING
	self.humanoid.PlatformStand = false
	self.force.Enabled = false
	setLimbCollision(self, true)
	self.velocity = Vector3.zero
	self.lastGroundDistance = nil
end

local function probeGround(self, root: BasePart): RaycastResult?
	return workspace:Raycast(
		root.Position,
		Vector3.new(0, -(Config.HoverHeight + Config.ProbeMargin), 0),
		self.groundParams
	)
end

local function report(self, now: number, speed: number, scrub: number, onSnow: boolean)
	if not stateEvent or now < self.reportAt then
		return
	end

	local moved = self.state ~= self.sentState
		or onSnow ~= self.sentOnSnow
		or math.abs(speed - self.sentSpeed) > Config.SpeedEpsilon
		or math.abs(scrub - self.sentScrub) > Config.ScrubEpsilon
		or math.abs(self.lean - self.sentLean) > Config.LeanEpsilon

	if not moved then
		return
	end

	self.reportAt = now + Config.StateBroadcastRate
	self.sentState, self.sentSpeed = self.state, speed
	self.sentScrub, self.sentLean, self.sentOnSnow = scrub, self.lean, onSnow

	stateEvent:FireServer({
		state = self.state,
		speed = speed,
		scrub = scrub,
		lean = self.lean,
		onSnow = onSnow,
	})
end

local function step(dt: number)
	local self = skier
	if not self then
		return
	end

	local character, humanoid, root = self.character, self.humanoid, self.root
	if not character.Parent or humanoid.Health <= 0 then
		stopSkiing()
		return
	end

	local now = os.clock()
	local gravity = workspace.Gravity

	local hit = probeGround(self, root)

	local grounded = hit ~= nil and hit.Normal:Dot(UP) >= MIN_GROUND_DOT
	local groundNormal = if grounded then hit.Normal else UP
	local friction = if grounded then Shared.frictionFor(hit) else Config.DefaultFriction
	local onSnow = grounded and Config.SprayMaterials[hit.Material] == true

	local input = readInput(humanoid, self.heading, grounded and self.state ~= AIRBORNE)

	local hoverHeight = Config.HoverHeight + Config.GroundClearance

	if self.state == WALKING then
		if grounded and SkiPhysics.slopePull(groundNormal, gravity).Magnitude > Config.SlideEnterAccel then
			enterSim(self)
			self.state = RIDING
			self.up = groundNormal
			log("sliding")
		else
			jumpQueued = false
			self.lean = 0
			self.pose:release()
			self.effects:update(dt, 0, 0, onSnow, false)
			self.sound:update(dt, 0, 0, false, onSnow)
			report(self, now, 0, 0, onSnow)
			return
		end
	end

	if grounded then
		self.up = Shared.safeUnit(Shared.dampVector(self.up, groundNormal, Config.NormalSmoothing, dt), groundNormal)
	end

	if self.state == AIRBORNE then
		local reach = hoverHeight + GROUND_CONTACT_TOLERANCE + math.max(0, -self.velocity.Y * dt)
		local landed = grounded and hit.Distance <= reach and self.velocity:Dot(groundNormal) <= 0

		if landed then
			local impact = -self.velocity:Dot(groundNormal)
			self.effects:landingPuff(impact, onSnow)
			self.sound:land(impact)

			local quality = SkiPhysics.landingQuality(self.heading, self.up, self.velocity, groundNormal)

			if quality.crashed and now < self.graceUntil then
				quality = { crashed = false, speedKeep = Config.LandingWorstKeep, errorDegrees = quality.errorDegrees }
				log("bad landing ignored, still settling in")
			end

			if quality.crashed then
				log("crashed (%.0f deg off)", quality.errorDegrees)

				self.force.Enabled = false

				if crashEvent then
					crashEvent:FireServer()
					stopSkiing(true)
				else
					stopSkiing()
				end
				return
			end

			self.velocity *= quality.speedKeep
			self.landedAt = now
			self.up = groundNormal
			self.heading = Shared.safeUnit(Shared.projectOnPlane(self.heading, groundNormal), self.heading)
			self.lastGroundDistance = nil
			self.state = RIDING
			self.jumpReadyAt = now + Config.JumpCooldown
			log("landed (%.0f deg off, kept %.0f%%)", quality.errorDegrees, quality.speedKeep * 100)
		else
			local result = SkiPhysics.airStep(
				{ velocity = self.velocity, heading = self.heading, up = self.up },
				input,
				gravity,
				dt
			)
			self.velocity = result.velocity
			self.heading = result.heading
			self.up = result.up
		end
	end

	if self.state == RIDING then
		if not grounded then
			if now - self.lastGroundTime > Config.CoyoteTime then
				self.state = AIRBORNE
				self.lastGroundDistance = nil
				log("airborne")
			end
		else
			self.lastGroundTime = now

			local result = SkiPhysics.groundStep(
				{ velocity = self.velocity, heading = self.heading, up = self.up },
				input,
				{ normal = self.up, friction = friction },
				gravity,
				dt
			)
			self.velocity = result.velocity
			self.heading = result.heading

			local distance = hit.Distance
			local closing = 0
			if self.lastGroundDistance then
				closing = math.clamp((distance - self.lastGroundDistance) / dt, -MAX_CLOSING_SPEED, MAX_CLOSING_SPEED)
			end
			self.lastGroundDistance = distance

			self.velocity += Vector3.new(0, SkiPhysics.hoverAccel(hoverHeight - distance, closing) * dt, 0)

			local sink = hoverHeight - distance
			if sink > 0 then
				root.CFrame += Vector3.new(0, sink, 0)
				self.lastGroundDistance = hoverHeight

				if self.velocity.Y < 0 then
					self.velocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
				end
			end

			if jumpQueued and now >= self.jumpReadyAt then
				self.velocity += groundNormal * Config.JumpImpulse
				self.state = AIRBORNE
				self.lastGroundDistance = nil
				self.sound:jump()
				log("jump")
			elseif SkiPhysics.slopePull(self.up, gravity).Magnitude < Config.SlideExitAccel
				and self.velocity.Magnitude < Config.SlideExitSpeed
			then
				enterWalking(self)
				jumpQueued = false
				self.lean = 0
				self.pose:release()
				log("walking")
				return
			end
		end
	end

	jumpQueued = false

	local right = self.heading:Cross(self.up)
	if right.Magnitude < 1e-3 then
		right = Shared.safeUnit(self.heading:Cross(UP), Vector3.xAxis)
	end
	right = right.Unit
	self.up = right:Cross(self.heading).Unit

	local stormForce = root:FindFirstChild(STORM_FORCE_NAME)
	if stormForce and stormForce:IsA("VectorForce") and stormForce.Enabled then
		stormForce.Enabled = false
	end

	self.force.Force = Vector3.new(0, root.AssemblyMass * gravity, 0)
	root.AssemblyLinearVelocity = self.velocity
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAlong(root.Position, self.heading, self.up)

	local poseName = "Stance"
	if self.state == AIRBORNE then
		poseName = "Air"
	elseif input.braking then
		poseName = "Brake"
	elseif input.tucking then
		poseName = "Tuck"
	elseif math.abs(input.steer) > 0.3 then
		poseName = "Carve"
	end

	self.lean = Shared.damp(self.lean, if self.state == AIRBORNE then 0 else input.steer, Config.LeanSmoothing, dt)
	self.pose:setPose(poseName)
	self.pose:setLean(self.lean)

	local lateral = Shared.safeUnit(self.up:Cross(self.heading), Vector3.xAxis)
	local scrub = math.abs(self.velocity:Dot(lateral))

	local speed = self.velocity.Magnitude
	self.effects:update(dt, speed, scrub, onSnow, self.state ~= AIRBORNE)
	self.sound:update(dt, speed, scrub, self.state ~= AIRBORNE, onSnow)

	report(self, now, speed, scrub, onSnow)
end

local function unequipCrashes(self): boolean
	if os.clock() < self.graceUntil then
		return false
	end

	if self.state == AIRBORNE then
		return true
	end

	if os.clock() - self.landedAt < Config.UnequipCrashWindow then
		return true
	end

	if self.state == WALKING and self.humanoid.Parent then
		local humanoidState = self.humanoid:GetState()
		return humanoidState == Enum.HumanoidStateType.Freefall
			or humanoidState == Enum.HumanoidStateType.Jumping
	end

	return false
end

equipEvent.OnClientEvent:Connect(function(isEquipped: boolean)
	if isEquipped then
		local character = player.Character
		if character then
			startSkiing(character)
		end
		return
	end

	local self = skier
	if self and crashEvent and unequipCrashes(self) then
		self.force.Enabled = false
		crashEvent:FireServer()

		stopSkiing(true)
		return
	end

	stopSkiing()
end)

player.CharacterRemoving:Connect(function()
	stopSkiing()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Config.EquipKey then
		equipEvent:FireServer()
	end
end)

SkiRemoteView.start()

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(step, dt)
	if not ok then
		warn("[Ski] sim error: " .. tostring(err))
		stopSkiing()
	end

	local viewOk, viewErr = pcall(SkiRemoteView.update, dt)
	if not viewOk then
		warn("[Ski] remote render error: " .. tostring(viewErr))
	end
end)

RunService:BindToRenderStep("SkiPose", Enum.RenderPriority.Character.Value + 1, function(dt)
	if skier then
		skier.pose:update(dt)
	end

	SkiRemoteView.updatePoses(dt)
end)

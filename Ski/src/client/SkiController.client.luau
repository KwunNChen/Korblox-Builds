--[[
	SkiController
	Walking, sliding, and being in the air. Everything that touches a character;
	all the arithmetic lives in SkiPhysics.

	Deliberately small. No poses, no particles, no landing scoring, no tricks --
	those all went in too early last time and buried the one thing that had to
	be right first, which is whether it rides properly.

	WHY THE CLIENT: Roblox hands a player network ownership of their own
	character. A force applied from the server is simulated on the owning client
	anyway, so running the loop there costs a round trip of input latency and
	buys nothing. The server keeps what matters -- who has skis on.

	Four things here are load-bearing and were all bugs the first time round:

	1. GRAVITY IS CANCELLED by a VectorForce holding up exactly the assembly's
	   weight. Without it the engine's gravity and the sim's both apply and you
	   fall at double rate.

	2. TOUCHING DOWN means arriving at ride height, not the ground probe seeing
	   something. The probe reaches ProbeMargin further than the skis ride;
	   landing on first contact hands you back to the Humanoid in mid-air.

	3. THE HOVER SPRING'S damping term reads closing speed off the probe, not
	   world Y velocity. On a slope those are wildly different -- see the note
	   on SkiPhysics.hoverAccel.

	4. LIMB COLLISIONS are off only while the sim drives. R6's Humanoid uses the
	   leg parts to find the floor, so leaving them off would break walking.
]]

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

-- A fresh probe onto different ground makes the height jump discontinuously.
-- Left unclamped that reads as an enormous closing speed and the spring
-- launches you.
local MAX_CLOSING_SPEED = 60

-- How far above ride height still counts as touching down. NOT the probe
-- length -- see note 2 at the top.
local GROUND_CONTACT_TOLERANCE = 0.4

-- Variable Snowstorm's airborne wind push. It gates on the Humanoid being in
-- Freefall or Jumping and platform standing reports neither, so it mostly
-- switches itself off -- but the server only re-checks twice a second, and this
-- closes that window.
local STORM_FORCE_NAME = "StormWindForce"

--[[
	The default Animate script is deliberately LEFT RUNNING while the sim drives.

	It used to be muzzled -- tracks stopped, jump and fall states disabled -- so
	its clips couldn't fight the ski poses. That worked, and then broke
	unequipping: Animate only picks a new animation when the Humanoid changes
	state, so with its states disabled and its tracks stopped it had nothing left
	to wake it up, and the character stood frozen afterwards.

	SkiPose zeroes each joint's Transform instead, which is where animations
	actually write. Animate carries on doing its thing, the poses win anyway, and
	there is nothing to restart when the skis come off.
]]

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

-- Optional on purpose. A missing crash remote means no ragdoll, not a script
-- that hangs on the way in and takes the whole sim down with it.
local crashEvent = Shared.getRemote(remotes, "SkiCrash")

-- Likewise: without this you simply aren't visible to anyone else.
local stateEvent = Shared.getRemote(remotes, "SkiState")

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

-- ============================================================
-- INPUT
-- ============================================================

local jumpQueued = false

UserInputService.JumpRequest:Connect(function()
	jumpQueued = true
end)

local function isDown(key: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(key)
end

-- IsKeyDown only answers for the keyboard -- hand it a ButtonL2 and it returns
-- false forever. Kept separate because the gamepad call rejects keyboard codes.
local function isButtonDown(button: Enum.KeyCode): boolean
	if not UserInputService.GamepadEnabled then
		return false
	end
	local ok, down = pcall(function()
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, button)
	end)
	return ok and down
end

-- Humanoid.MoveDirection already respects rebound keys, gamepads and mobile
-- thumbsticks. The raw fallback is here because MoveDirection can read zero
-- while platform standing on some rigs, and losing steering the moment you
-- start sliding would be a spectacular way to fail.
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
		-- Pitch is flips, and flips without landing scoring are just a way to
		-- come down backwards with no consequence. SkiPhysics.airStep already
		-- handles it -- this is the switch to turn on when tricks go in.
		pitch = 0,
		-- Pulling back brakes as well as the dedicated key, because that is what
		-- everyone tries first.
		braking = grounded and (isDown(Config.BrakeKey) or isButtonDown(Config.BrakeButton) or along < -0.5),
		tucking = isDown(Config.TuckKey) or isButtonDown(Config.TuckButton),
	}
end

-- ============================================================
-- THE SKIER
-- ============================================================

local skier: any = nil

--[[
	Destroys any gravity-cancelling force on the character, ours or orphaned.

	That force holds up exactly the assembly's weight. Left behind with nothing
	driving the character, it does not just look wrong -- you hang in the air
	with no way down and no way to ski it off. There is no recovering from it
	short of resetting, so it is worth sweeping for rather than trusting that
	every exit path cleaned up after itself.

	The force is created by the client and never replicates, so this is the only
	side that can see it. The server cannot help here.
]]
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

--[[
	`leaveLimp` is for the crash path only. Normally stopping stands the
	character back up, but on a wipeout the server is setting PlatformStand for
	the ragdoll at the same moment -- and both sides writing it in the same frame
	is a race the ragdoll can lose, leaving you upright and rigid mid-tumble.
	Handing that one property over to the server avoids the argument entirely.
]]
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

	-- Switched off before it's destroyed. Destroy alone should be enough, but
	-- this costs nothing and the failure it guards against is being stuck in
	-- mid-air permanently.
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

	-- In case a previous session died without cleaning up: two of these stacked
	-- would cancel gravity twice and launch you.
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
		jumpReadyAt = os.clock() + Config.EquipGrace,
		graceUntil = os.clock() + Config.EquipGrace,

		-- Last values published to everyone else, so the epsilon check has
		-- something to compare against.
		reportAt = 0,
		sentState = "",
		sentSpeed = 0,
		sentScrub = 0,
		sentLean = 0,
		sentOnSnow = false,
	}

	-- A press from before the skis went on is not a request to jump on them.
	-- The grace period above handles a HELD key; this handles a stale one.
	jumpQueued = false

	log("started")
end

-- Hand control from the Humanoid to the sim.
local function enterSim(self)
	self.humanoid.PlatformStand = true
	self.force.Enabled = true
	setLimbCollision(self, false)

	-- Carry the walking velocity in rather than starting from a standstill, so
	-- stepping onto a slope is continuous instead of a stutter.
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

--[[
	Three downward probes: under the boot, and out near each end of the ski.

	One probe only knows about the ground directly under you, and the ski is over
	five studs long -- so a dip or a rise puts the tip or tail through the snow
	well before the middle notices. Whichever probe is closest drives the hover
	spring, so the end that is about to dig in is the one that lifts you.

	Returns two things on purpose. The DISTANCE comes from the closest probe,
	because that is the one about to clip. The SURFACE -- the normal we align to
	and the material we take friction from -- comes from under the boot, because
	that is the ground you are actually riding. Taking the normal from whichever
	probe happened to win makes the skis flick about at every edge in the terrain.
]]
local function probeGround(self, root: BasePart, heading: Vector3): (RaycastResult?, RaycastResult?)
	local down = Vector3.new(0, -(Config.HoverHeight + Config.ProbeMargin), 0)
	local origin = root.Position

	local flat = Vector3.new(heading.X, 0, heading.Z)
	local reach = if flat.Magnitude > 1e-4
		then flat.Unit * (Config.SkiLength * Config.ProbeSpread)
		else Vector3.zero

	local centre = workspace:Raycast(origin, down, self.groundParams)
	local closest = centre

	for _, offset in { reach, -reach } do
		local hit = workspace:Raycast(origin + offset, down, self.groundParams)

		-- Near-vertical faces out at the ends are ignored. A bank in front of
		-- the tips is not ground to ride up, and letting it shorten the hover
		-- distance would fire you into the air at the foot of every steep rise.
		if hit and hit.Normal:Dot(UP) >= MIN_GROUND_DOT then
			if not closest or hit.Distance < closest.Distance then
				closest = hit
			end
		end
	end

	return closest, centre or closest
end

--[[
	Publishes what everyone else needs to render you.

	Rate limited, and skipped entirely when nothing has moved -- straight-line
	skiing barely changes any of these, and firing five attribute writes per
	player ten times a second regardless is what makes this expensive on a busy
	hill. Same idea as WeatherConfig's IntensityEpsilon in Variable Snowstorm.

	The state string is exempt from the epsilon: it's discrete, and a missed
	change to Airborne means somebody stays in a riding pose the whole way
	through your jump.
]]
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

	-- ---------- ground probe ----------
	local hit, surface = probeGround(self, root, self.heading)

	local grounded = hit ~= nil and surface ~= nil and surface.Normal:Dot(UP) >= MIN_GROUND_DOT
	local groundNormal = if grounded then surface.Normal else UP
	local friction = if grounded then Shared.frictionFor(surface) else Config.DefaultFriction
	local onSnow = grounded and Config.SprayMaterials[surface.Material] == true

	local input = readInput(humanoid, self.heading, grounded and self.state ~= AIRBORNE)

	-- Fixed. The skis are solved against the root rather than hung off the legs,
	-- so nothing the pose does moves them and ride height has nothing to track.
	local hoverHeight = Config.HoverHeight + Config.GroundClearance

	-- ---------- walking ----------
	if self.state == WALKING then
		--[[
			The Humanoid keeps the character while walking, jumps and falls
			included. Taking over the moment you left the ground meant an
			ordinary hop got seized by the sim on the way up and handed back on
			the way down, which made a flat-ground jump end as a stubby little
			freefall a couple of studs off the deck.

			Nothing is lost by waiting -- land on a slope and this picks it up on
			the very next frame.
		]]
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

	-- ---------- smoothed ground normal ----------
	if grounded then
		self.up = Shared.safeUnit(Shared.dampVector(self.up, groundNormal, Config.NormalSmoothing, dt), groundNormal)
	end

	-- ---------- airborne ----------
	if self.state == AIRBORNE then
		local reach = hoverHeight + GROUND_CONTACT_TOLERANCE + math.max(0, -self.velocity.Y * dt)
		local landed = grounded and hit.Distance <= reach and self.velocity:Dot(groundNormal) <= 0

		if landed then
			-- Measured before the landing scrubs any speed off, so the burst and
			-- the thump match the hit you actually took rather than what's left
			-- after it.
			local impact = -self.velocity:Dot(groundNormal)
			self.effects:landingPuff(impact, onSnow)
			self.sound:land(impact)

			-- Scored on whether the skis point where you're travelling AND
			-- whether they're flat to the ground you're hitting; worse wins.
			local quality = SkiPhysics.landingQuality(self.heading, self.up, self.velocity, groundNormal)

			-- Wiping out in the first moments after strapping in is never
			-- something the player did, so it doesn't count.
			if quality.crashed and now < self.graceUntil then
				quality = { crashed = false, speedKeep = Config.LandingWorstKeep, errorDegrees = quality.errorDegrees }
				log("bad landing ignored, still settling in")
			end

			if quality.crashed then
				log("crashed (%.0f deg off)", quality.errorDegrees)

				-- No crash sound from here. SkiRagdoll plays it on the server so
				-- everyone watching hears it, not just the person who ate it.
				-- The server owns the ragdoll, so everyone sees it. It also
				-- takes the skis off, which stops the sim -- so bail out here
				-- rather than carrying on driving a character that's mid-fall.
				--
				-- Stopping does NOT depend on the remote. Without it you simply
				-- come to a halt instead of tumbling; the one thing that must
				-- not happen is the sim carrying on regardless.
				-- Gravity comes back BEFORE the server is told. The ragdoll
				-- needs something to fall under, and leaving even a frame of
				-- cancelled gravity between the two is a frame of hanging in
				-- the air.
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

	-- ---------- riding ----------
	if self.state == RIDING then
		if not grounded then
			-- Coyote time: a bump that throws you a few inches shouldn't detach
			-- the whole sim.
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

			-- Hover spring. Closing speed comes from the probe, not world Y
			-- velocity -- see note 3 at the top.
			local distance = hit.Distance
			local closing = 0
			if self.lastGroundDistance then
				closing = math.clamp((distance - self.lastGroundDistance) / dt, -MAX_CLOSING_SPEED, MAX_CLOSING_SPEED)
			end
			self.lastGroundDistance = distance

			self.velocity += Vector3.new(0, SkiPhysics.hoverAccel(hoverHeight - distance, closing) * dt, 0)

			if jumpQueued and now >= self.jumpReadyAt then
				-- Along the ground normal, not straight up: launching off a lip
				-- should throw you along the slope.
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

	-- ---------- apply ----------
	-- Re-orthogonalise before building the CFrame: a heading and up that have
	-- drifted parallel make lookAlong produce garbage.
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

	-- ---------- pose ----------
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

	-- ---------- effects ----------
	-- Sideways speed across the skis. This is what actually throws snow: a
	-- straight run at full speed barely marks it, a hard carve throws a wall.
	local lateral = Shared.safeUnit(self.up:Cross(self.heading), Vector3.xAxis)
	local scrub = math.abs(self.velocity:Dot(lateral))

	local speed = self.velocity.Magnitude
	self.effects:update(dt, speed, scrub, onSnow, self.state ~= AIRBORNE)
	self.sound:update(dt, speed, scrub, self.state ~= AIRBORNE, onSnow)

	report(self, now, speed, scrub, onSnow)
end

-- ============================================================
-- WIRING
-- ============================================================

equipEvent.OnClientEvent:Connect(function(isEquipped: boolean)
	if isEquipped then
		local character = player.Character
		if character then
			startSkiing(character)
		end
	else
		stopSkiing()
	end
end)

-- Wrapped, not passed directly: CharacterRemoving hands over the character,
-- which would arrive as the leaveLimp flag.
player.CharacterRemoving:Connect(function()
	stopSkiing()
end)

-- Fired with no arguments, this asks the server to toggle. The server fires it
-- back with a boolean to report the actual state.
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Config.EquipKey then
		equipEvent:FireServer()
	end
end)

-- Wrapped because an error mid-frame would otherwise leave the character
-- platform-standing with gravity cancelled -- frozen in mid-air with no way
-- out. Failing means dropping the skis, not floating forever.
SkiRemoteView.start()

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(step, dt)
	if not ok then
		warn("[Ski] sim error: " .. tostring(err))
		stopSkiing()
	end

	-- Wrapped separately. Rendering somebody else going wrong must not take your
	-- own skiing down with it.
	local viewOk, viewErr = pcall(SkiRemoteView.update, dt)
	if not viewOk then
		warn("[Ski] remote render error: " .. tostring(viewErr))
	end
end)

--[[
	Poses run AFTER the engine's animation pass, which is the whole reason this
	is a separate binding at Character + 1 rather than part of the loop above.
	The default Animate script writes idle and walk poses into the same Motor6D
	C0 values during the Character step; anything written before it is silently
	overwritten on the same frame, and the skis go back to whatever angle the
	walk cycle left the legs at.
]]
RunService:BindToRenderStep("SkiPose", Enum.RenderPriority.Character.Value + 1, function(dt)
	if skier then
		skier.pose:update(dt)
	end

	-- Other people's poses need the same slot for the same reason.
	SkiRemoteView.updatePoses(dt)
end)

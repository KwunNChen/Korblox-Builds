--!strict
--[[
	Drives the body along a path, and puts everything back afterwards.

	Both moves share this. The vault and the mantle differ in their curve and in
	whether they own the character's rotation; everything else -- taking the
	body, zeroing velocity, the frame loop, the deadline, the teardown -- is the
	same problem twice, so it is solved once here.

	--------------------------------------------------------------------------
	WHY A KINEMATIC CFRAME WRITE AND NOT A CONSTRAINT
	--------------------------------------------------------------------------

	TREK's HeadAndArmsController writes HumanoidRootPart.CFrame every frame
	while a weapon with TurnToTarget is equipped. Anything that CONVERGES on a
	goal -- AlignPosition, a tween, a BodyMover -- loses that argument, because
	a direct assignment beats a force every time. So we assign too, and we
	assign last in the frame.

	Ski solves the same problem the same way and its comments are worth reading
	if this ever needs changing. The one thing we do NOT copy from it is the
	VectorForce gravity-cancel: Ski integrates velocity and so has to remove
	gravity from its integrator, whereas we overwrite the velocity outright
	every frame. Gravity has nowhere to accumulate, so there is no force to
	cancel and no instance to leak if a move ends badly.
]]

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local package = ReplicatedStorage:WaitForChild("TREKParkour")
local Config = require(package:WaitForChild("ParkourConfig"))
local Shared = require(package:WaitForChild("ParkourShared"))
local Pose = require(script.Parent:WaitForChild("ParkourPose"))

local ParkourMotion = {}

-- R6. Arms and legs only -- the torso and head have to keep colliding or the
-- character falls through the world.
local LIMBS = { "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

local BIND_NAME = "TREKParkourMotion"

--[[
	Runs after the default Animate script and the Humanoid have had their turn,
	so our write is the last one that frame. Ski uses the same slot for its pose
	for the same reason.
]]
local BIND_PRIORITY = Enum.RenderPriority.Character.Value + 1

--[[
	A move before its teardown is attached. The controller builds one of these,
	`launch` fills in onFinish, and only then is it a Spec.
]]
export type Draft = {
	from: Vector3,
	to: Vector3,
	duration: number,
	arcHeight: number,
	grab: Vector3?,
	facing: Vector3?,
	animation: string?,
	animationLate: string?,
	onFinish: ((reason: string) -> ())?,
}

export type Spec = {
	from: Vector3,
	to: Vector3,
	duration: number,
	arcHeight: number,
	grab: Vector3?, -- set for a two-segment mantle; nil for a single vault arc
	facing: Vector3?, -- set to own the rotation; nil leaves it alone
	animation: string?, -- config slot played from the start
	animationLate: string?, -- config slot swapped in at HangFraction
	onFinish: (reason: string) -> (),
}

type Run = {
	spec: Spec,
	humanoid: Humanoid,
	root: BasePart,
	character: Model,
	startedAt: number,
	deadline: number,
	tookPlatformStand: boolean,
	limbCollision: { [BasePart]: boolean },
	swapped: boolean,
	neck: Motor6D?,
}

local run: Run? = nil

-- R6 keeps the Neck in the Torso. R15 puts it in the Head, which is checked too
-- so this degrades rather than erroring on a rig it was not built for.
local function neckOf(character: Model): Motor6D?
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("Head")
	local neck = torso and torso:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") then
		return neck
	end
	return nil
end

local function restoreLimbs(current: Run)
	for part, original in current.limbCollision do
		if part.Parent then
			part.CanCollide = original
		end
	end
end

--[[
	Every exit goes through here, and it must be safe to call twice -- under a
	bad enough frame the deadline and the completion can land together.
]]
function ParkourMotion.stop(reason: string)
	local current = run
	if not current then
		return
	end
	run = nil

	pcall(RunService.UnbindFromRenderStep, RunService, BIND_NAME)

	-- stopAll rather than stopping the slot we started: after an abort the track
	-- playing may not be the one this move began with.
	pcall(Pose.stopAll, current.humanoid)

	restoreLimbs(current)

	--[[
		Only give PlatformStand back if we were the ones who took it.

		TREK sets PlatformStand on a player who has lost both legs and never
		clears it -- that is its paralysis marker. Writing false unconditionally
		here would cure them, which is a gameplay bug wearing a movement bug's
		clothes. blockReason refuses to start a move on such a character, so if
		we took it, it was ours to give back.
	]]
	if current.tookPlatformStand and current.humanoid.Parent then
		current.humanoid.PlatformStand = false
	end

	current.spec.onFinish(reason)
end

local function step(current: Run)
	local humanoid, root = current.humanoid, current.root

	-- The character can be destroyed between frames, not only on Died.
	if not root.Parent or not humanoid.Parent or not current.character.Parent then
		ParkourMotion.stop("character gone")
		return
	end

	if humanoid.Health <= 0 then
		ParkourMotion.stop("died")
		return
	end

	-- Someone sat you down, or you lost your legs, mid-move.
	if humanoid.SeatPart or humanoid:FindFirstChild("TParalCondition") then
		ParkourMotion.stop("interrupted")
		return
	end

	local now = os.clock()

	--[[
		The deadline is the server-hitch guard, and it is the only thing between
		a frame-budget blowout and a player left kinematic forever. It is
		checked against an absolute clock rather than accumulated dt, because an
		accumulated clock drifts across exactly the spike we are guarding for.
	]]
	if now > current.deadline then
		ParkourMotion.stop("deadline")
		return
	end

	local spec = current.spec
	local alpha = math.clamp((now - current.startedAt) / spec.duration, 0, 1)

	local position = if spec.grab
		then Shared.mantlePoint(spec.from, spec.grab, spec.to, alpha, Config.HangFraction)
		else Shared.arcPoint(spec.from, spec.to, alpha, spec.arcHeight)

	-- The catch hands over to the haul at the same point the curve changes gear,
	-- so the pose and the path agree about where the lip is.
	if spec.animationLate and not current.swapped and alpha >= Config.HangFraction then
		current.swapped = true
		if spec.animation then
			Pose.stop(humanoid, spec.animation)
		end
		Pose.play(humanoid, spec.animationLate, spec.duration * (1 - Config.HangFraction))
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	--[[
		Two rules in one line.

		A move with no facing writes POSITION ONLY, keeping whatever rotation the
		character already has. That is what lets the vault coexist with an
		equipped weapon: TREK stays free to point the root at the mouse, we never
		contest it, and you vault forward while still aiming.

		A move that DOES want the rotation only gets it once the weapon has
		actually gone. The client starts moving the instant it decides to, but
		the unequip is the server's and lands a round trip later -- until then
		TREK is still writing rotation every frame and contesting it looks like a
		fight. Testing for the Tool each frame rather than waiting on an
		acknowledgement means the climb takes over the moment it is free, and
		degrades to translation-only if the holster never happens at all.
	]]
	if spec.facing and not current.character:FindFirstChildOfClass("Tool") then
		root.CFrame = CFrame.lookAlong(position, spec.facing, Vector3.yAxis)
	else
		root.CFrame = CFrame.new(position) * root.CFrame.Rotation
	end

	--[[
		Cancel the animation's neck track, if asked to.

		Writing Transform rather than C0 is the whole trick: an animation drives
		joints through Transform, and this binding runs at Character + 1 -- after
		the animator has had its turn -- so identity here wins for the frame. C0
		is left alone, which is why the head ends up at its rest pose relative to
		the torso rather than pinned to the world.

		The same trick Ski uses to stop the default Animate script fighting its
		procedural poses.
	]]
	if Config.KeepHeadLevel and current.neck and current.neck.Parent then
		current.neck.Transform = CFrame.identity
	end

	if alpha >= 1 then
		ParkourMotion.stop("completed")
	end
end

--[[
	Returns false if the move could not be started. The caller has already run
	blockReason; this only catches the things that can change between deciding
	and starting.
]]
function ParkourMotion.start(character: Model, humanoid: Humanoid, root: BasePart, spec: Spec): boolean
	if run then
		return false
	end

	if humanoid.PlatformStand then
		return false
	end

	local limbCollision: { [BasePart]: boolean } = {}
	for _, name in LIMBS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			limbCollision[part] = part.CanCollide
			-- Without this the legs catch the lip of the ledge and the whole
			-- move stutters against geometry it is supposed to be clearing.
			part.CanCollide = false
		end
	end

	humanoid.PlatformStand = true

	local current: Run = {
		spec = spec,
		humanoid = humanoid,
		root = root,
		character = character,
		startedAt = os.clock(),
		deadline = os.clock() + spec.duration + Config.WatchdogGrace,
		tookPlatformStand = true,
		limbCollision = limbCollision,
		swapped = false,
		neck = neckOf(character),
	}

	run = current

	--[[
		A move with two tracks splits its time at HangFraction, so each gets
		exactly the slice of the move it is meant to cover. A move with one track
		gets the lot.
	]]
	if spec.animation then
		local window = if spec.animationLate then spec.duration * Config.HangFraction else spec.duration
		Pose.play(humanoid, spec.animation, window)
	end

	RunService:BindToRenderStep(BIND_NAME, BIND_PRIORITY, function()
		if not run then
			return
		end

		-- An error in the curve must end the move, not freeze the player in it.
		local ok, err = pcall(step, current)
		if not ok then
			Shared.warn("motion step errored: %s", tostring(err))
			ParkourMotion.stop("errored")
		end
	end)

	return true
end

return ParkourMotion

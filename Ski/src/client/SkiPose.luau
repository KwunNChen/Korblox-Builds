--[[
	SkiPose
	Procedural R6 posing, driven straight off the Motor6D C0 values.

	THIS IS ALSO WHAT MAKES THE SKIS SIT FLAT, and there are two separate jobs in
	that. The skis are welded to the legs, so they inherit whatever angle the
	legs are at, and on R6 the legs hang off the TORSO, which RootJoint pitches.
	Lean the body forward and the skis tip nose-up on their own, hips or no hips.

	_alignSkis handles the skis, by solving the joint against the root part
	instead of trying to work out how far they got tilted. _uprightCompensation
	handles the legs, feeding the torso lean back into the hips so they stay
	vertical and the boots stay in the bindings.

	MUST RUN AFTER THE ENGINE'S ANIMATION PASS. The default Animate script writes
	idle and walk poses into these same joints during the Character step, so
	anything written before it is silently overwritten on the same frame. The
	controller binds this at RenderPriority.Character + 1 for exactly that.

	LOCAL TO YOU. Joint changes made on the client don't replicate, so other
	players see you riding unposed. Filling in Config.Animations swaps a slot for
	a real animation, which goes through the Animator and does replicate.

	TUNING: every number is radians, applied as defaultC0 * CFrame.Angles(x,y,z).
	R6 bakes a 90-degree yaw into the shoulder and hip joints, so the axes are
	not the ones you would guess:

	    shoulders/hips   x = swing out sideways,  y = twist,  z = swing fore/aft
	    root/neck        x = lean forward,        y = roll,   z = twist

	Left-side joints carry the mirrored yaw, and the sign rule that falls out of
	it is NOT "negate everything". It differs per axis, and getting it wrong is
	silent -- the pose just looks permanently lopsided:

	    Z (fore/aft)   OPPOSITE signs to swing both limbs the same way, which is
	                   what you want for arms reaching forward together or legs
	                   angling forward together.

	    X (sideways)   MATCHING signs to mirror, which is what you want for arms
	                   splaying out or tucking in evenly. Opposite signs here
	                   throw both arms the same way and the whole upper body
	                   reads as leaning to one side, permanently.

	    Y (twist)      OPPOSITE signs to mirror -- e.g. the snowplow wedge.

	If the arms splay out when they should tuck in, flip the sign on ALL the
	shoulder X values together; they are mirrored, so they move as a pair.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiPose = {}
SkiPose.__index = SkiPose

local JOINTS = { "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

--[[
	THE SKI STANCE, AND WHY IT IS BUILT THIS WAY.

	The real posture is knees bent, shins resting on the front of the boots,
	weight forward, hands ahead. R6 has no knee. The leg is one rigid piece from
	hip to sole, and a bent knee is not available at any price.

	Angling the whole leg forward from the hip is the nearest thing available,
	and it is the "Right Hip"/"Left Hip" Z value below. It is set to zero in
	every pose, because the leg has no ankle either: swing it forward and the
	foot tilts with it, lifting the heel off the ski by about a stud times
	sin(angle). Past a very small angle the character reads as standing on tiptoe.

	So the legs stay vertical and the stance is carried entirely by the torso
	lean. The skis no longer care either way, since _alignSkis solves them
	against the root rather than inheriting anything from the leg, but the BOOTS
	still do: swing the legs and the feet leave the bindings.
]]
local POSES = {
	-- The riding stance from the reference: weight forward, hands ahead, legs
	-- angled as far as a kneeless rig can manage.
	--[[
		Weight forward, hands ahead, legs straight down.

		THE HIPS ARE AT ZERO ON PURPOSE, and it is worth knowing before you reach
		for them. R6's leg is a single block a stud deep with no ankle, so
		swinging it forward tilts the "foot" with it while the ski underneath is
		held flat. The heel lifts off the ski by roughly a stud times sin(angle),
		and the character reads as standing on tiptoe.

		So the legs stay vertical and the skis lie genuinely flat, with the whole
		stance carried by the torso lean. It is the honest trade on this rig: a
		knee bend and flat feet cannot both exist without an ankle to absorb the
		difference, and flat feet are the one people notice.

		The machinery to angle them is still here and still correct -- put a
		number back in the hip Z and the ski counter-rotation and ride height
		both follow. It's the LOOK that doesn't survive it, not the maths.
	]]
	Stance = {
		RootJoint = Vector3.new(0.68, 0, 0),
		Neck = Vector3.new(-0.58, 0, 0),
		["Right Shoulder"] = Vector3.new(-0.12, 0, 1.42),
		["Left Shoulder"] = Vector3.new(-0.12, 0, -1.42),
		["Right Hip"] = Vector3.zero,
		["Left Hip"] = Vector3.zero,
	},

	-- Same stance, arms opened for balance. Body roll is layered on top from the
	-- live lean value rather than baked in here.
	Carve = {
		RootJoint = Vector3.new(0.68, 0, 0),
		Neck = Vector3.new(-0.58, 0, 0),
		["Right Shoulder"] = Vector3.new(0.34, 0, 1.2),
		["Left Shoulder"] = Vector3.new(0.34, 0, -1.2),
		["Right Hip"] = Vector3.zero,
		["Left Hip"] = Vector3.zero,
	},

	-- Folded right down over flat skis. All of it is in the waist, for the same
	-- reason as the stance -- angling the legs is what lifts the heels.
	Tuck = {
		RootJoint = Vector3.new(1.05, 0, 0),
		Neck = Vector3.new(-0.85, 0, 0),
		["Right Shoulder"] = Vector3.new(-0.2, 0, 1.55),
		["Left Shoulder"] = Vector3.new(-0.2, 0, -1.55),
		["Right Hip"] = Vector3.zero,
		["Left Hip"] = Vector3.zero,
	},

	-- Snowplow. The hip Y values twist the tips together into the wedge; the Z
	-- keeps the forward stance underneath it.
	Brake = {
		RootJoint = Vector3.new(0.55, 0, 0),
		Neck = Vector3.new(-0.42, 0, 0),
		["Right Shoulder"] = Vector3.new(0.42, 0, 0.7),
		["Left Shoulder"] = Vector3.new(0.42, 0, -0.7),
		["Right Hip"] = Vector3.new(0, -0.28, 0.26),
		["Left Hip"] = Vector3.new(0, 0.28, -0.26),
	},

	-- Legs straighten and the body opens up. Reads as committed rather than
	-- falling, and the straighter legs raise you back to full ride height.
	Air = {
		RootJoint = Vector3.new(0.12, 0, 0),
		Neck = Vector3.new(-0.06, 0, 0),
		["Right Shoulder"] = Vector3.new(0.72, 0, 0.22),
		["Left Shoulder"] = Vector3.new(0.72, 0, -0.22),
		["Right Hip"] = Vector3.new(0, 0, 0.15),
		["Left Hip"] = Vector3.new(0, 0, -0.15),
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
	self.tracks = {} :: { [string]: AnimationTrack }
	self.activeTrack = nil :: AnimationTrack?
	self.poseName = ""

	-- Released means hands off the joints entirely, not "hold a neutral pose".
	-- While walking the Animate script owns these, and writing neutral over the
	-- top would kill the walk animation just as dead as writing a ski pose.
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

	--[[
		The joints holding the gear on. Both need correcting as the limbs move:
		welded gear inherits its limb's rotation, and neither the skis nor the
		poles want to go where the limb is going.

		The limb each one SHOULD be attached to is recorded alongside it, and
		that is not bookkeeping -- it is the guard that stops this file fighting
		SkiGear. Both write the same C0. When the server stows the gear it
		repoints these joints at the Torso and gives them a back-carry offset;
		writing a foot offset onto a joint hanging off the Torso puts the ski
		straight through the middle of the character.
	]]
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

-- True only while the joint is still hanging off the limb we expect. Stowed
-- gear hangs off the Torso instead, and belongs to SkiGear until it comes back.
local function isDeployed(joint: Motor6D, limb: BasePart?): boolean
	return limb ~= nil and joint.Part0 == limb
end

--[[
	Rebuilt from config rather than remembered from construction.

	The server rewrites these C0s every time the gear stows or deploys, so a
	value captured once goes stale the first time you take the skis off. Deriving
	it means we always agree with whatever the server last set.
]]
local function footBase(sign: number): CFrame
	return CFrame.new(
		sign * Config.SkiFootOffset.X,
		Config.SkiFootOffset.Y,
		Config.SkiFootOffset.Z
	)
end

-- R6 geometry: half the leg spacing, and root centre down to the soles.
local LEG_SPACING = 0.5
local ROOT_TO_SOLE = 3

--[[
	Puts the skis flat, by MEASURING rather than predicting.

	Every earlier attempt worked out how far the skis had been tilted and applied
	the opposite. That kept being wrong, because on R6 the tilt arrives from two
	joints at once: the hips, and the Torso via RootJoint (the legs hang off the
	Torso, so pitching it pitches them). Two signs to get right, derived on paper,
	and I got one backwards more than once.

	This asks the rig instead of predicting it. The root part is already squared
	up to the slope by the controller, so a flat ski is just "wherever the root
	is, dropped to the feet". Solving for the joint that lands it there needs no
	angles at all:

	    ski = leg.CFrame * C0     therefore     C0 = leg.CFrame:Inverse() * target

	Self-correcting by construction. Whatever the torso, the hips or the walk
	animation happen to be doing to the leg on any given frame, the skis come out
	flat against the slope.
]]
function SkiPose:_alignSkis()
	local root = self.root
	if not root then
		return
	end

	for sign, joint in self.skiJoints do
		local leg = self.skiLimbs[sign]

		-- Skipped the moment the gear is stowed: those joints belong to SkiGear
		-- until they come back to the feet.
		if leg and joint.Parent and isDeployed(joint, leg) then
			local target = root.CFrame
				* CFrame.new(
					sign * (LEG_SPACING + Config.SkiFootOffset.X),
					-(ROOT_TO_SOLE - Config.SkiThickness * 0.5),
					Config.SkiFootOffset.Z
				)

			joint.C0 = leg.CFrame:Inverse() * target
		end
	end
end

-- Hands the skis back to the legs, so they follow the feet through a normal
-- walk cycle. Used when the pose is released and the Humanoid is driving again.
function SkiPose:_restSkis()
	for sign, joint in self.skiJoints do
		if joint.Parent and isDeployed(joint, self.skiLimbs[sign]) then
			joint.C0 = footBase(sign)
		end
	end
end

-- Roblox puts a cylinder's flat faces on its X axis, so the pole is built with
-- +X running grip to tip. Matches POLE_UPRIGHT in SkiGear.
local POLE_UPRIGHT = -math.pi / 2

--[[
	Holds the poles where a skier holds them, whatever the arms are doing.

	Welded to the arm, a pole goes wherever the arm goes -- and the ski stance
	puts the hands right out in front, which swung the poles up to horizontal
	and made them read as lances rather than something you're holding.

	So the arm's swing is cancelled first, then the pole is placed in torso space
	instead: hanging down, tilted out sideways, and trailed backwards by
	PoleTrailAngle. Hands stay forward, tips stay behind you.
]]
function SkiPose:_applyPoleCounterRotation(armAngle: number)
	for sign, joint in self.poleJoints do
		-- Same guard as the skis: hands off once SkiGear has stowed them.
		if joint.Parent and isDeployed(joint, self.poleLimbs[sign]) then
			local rest = CFrame.Angles(-Config.PoleTrailAngle, 0, 0)
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

--[[
	Cancels the torso's pitch at the hips, so the legs stay vertical in world
	space however far the body folds.

	R6 hangs the legs off the TORSO, and RootJoint is what pitches the torso --
	so leaning forward swings the legs backward with it, and the skis welded to
	them tip nose-up. That happens with the hips at dead zero; it is not a hip
	angle problem, which is why zeroing them didn't fix it.

	Feeding the lean back in with the opposite sign means a pose's hip Z is the
	leg angle you ACTUALLY get, measured from vertical, rather than something
	relative to a torso that is itself tipping. Change the lean and the legs stay
	put.
]]
function SkiPose:_uprightCompensation(name: string): number
	if name == "Right Hip" then
		return rootLean(self)
	elseif name == "Left Hip" then
		return -rootLean(self)
	end
	return 0
end

-- The arms' pitch in WORLD space. The arms hang off the torso too, and unlike
-- the legs they are LEFT to swing with it -- arms following the body is natural.
-- So the torso lean has to come off here for the poles to hang right.
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

-- -1 to 1. Rolls the upper body into the turn, on top of whatever pose is up.
function SkiPose:setLean(lean: number)
	self.lean = lean
end

--[[
	The carving layer, added on top of whatever pose is active.

	Kept separate from the pose tables because it is continuous -- it follows
	steering input frame by frame rather than blending between fixed shapes. A
	pose says "this is a tuck"; this says "and you are three quarters of the way
	into a right-hand turn".

	The hip X values are the important ones. They tip both legs the same way in
	world space, and because the skis are welded to the legs, that IS the edge
	angle. The opposite signs are not a mirror -- R6's left and right hips carry
	opposite baked-in yaws, so opposite local values are what produce the SAME
	world rotation.
]]
function SkiPose:_carveOverlay(name: string): Vector3
	local lean = self.lean * Config.CarveDirection

	if name == "RootJoint" then
		-- Y rolls the body into the turn; Z twists the shoulders back toward the
		-- fall line so the legs turn underneath a quiet upper body.
		return Vector3.new(0, -lean * Config.MaxLeanAngle, lean * Config.MaxCounterTwist)
	elseif name == "Neck" then
		-- Cancels part of the body roll so the head stays level.
		return Vector3.new(0, lean * Config.MaxLeanAngle * Config.NeckCounterRoll, 0)
	elseif name == "Right Hip" then
		return Vector3.new(-lean * Config.MaxEdgeAngle, 0, 0)
	elseif name == "Left Hip" then
		return Vector3.new(lean * Config.MaxEdgeAngle, 0, 0)
	end

	return Vector3.zero
end

function SkiPose:update(dt: number)
	if self.released then
		return
	end

	for name, joint in self.joints do
		local goal = self.target[name] or Vector3.zero
		local current = self.current[name]

		current = Vector3.new(
			Shared.damp(current.X, goal.X, Config.PoseSmoothing, dt),
			Shared.damp(current.Y, goal.Y, Config.PoseSmoothing, dt),
			Shared.damp(current.Z, goal.Z, Config.PoseSmoothing, dt)
		)
		self.current[name] = current

		-- An animation owns the joints outright while it plays.
		if self.activeTrack then
			continue
		end

		local carve = self:_carveOverlay(name)
		local upright = self:_uprightCompensation(name)

		joint.C0 = self.defaults[name]
			* CFrame.Angles(current.X + carve.X, current.Y + carve.Y, current.Z + carve.Z + upright)

		--[[
			Wipes whatever the Animate script just wrote.

			This is the whole reason poses work. Animations drive Transform,
			these poses drive C0, and the engine applies BOTH -- they layer, they
			don't override. So an idle or jump clip playing underneath was being
			added on top of the ski stance, which is what made the arms sway and
			the jump read wrong.

			Zeroing it here, after the animation pass, is the clean way to win.
			The alternative -- stopping Animate's tracks and disabling the states
			it watches -- also works, but it leaves Animate with nothing to wake
			it up afterwards, so the character stands frozen after unequipping
			until something forces a state change.
		]]
		joint.Transform = CFrame.identity
	end

	-- Skis are solved against the root, so they need nothing from the pose. The
	-- poles still follow the arm blend, so they stay put through a pose change
	-- rather than only once it has settled.
	self:_alignSkis()
	self:_applyPoleCounterRotation(self:armAngle())
end

-- Hands the joints back. Safe to call every frame: it works once then costs a
-- branch.
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

	-- Gear goes back to hanging off the limbs, so the skis follow the feet
	-- through a normal walk cycle. If it's stowed the server owns these joints
	-- and will overwrite this anyway; writing the deployed value is only wrong
	-- for a frame.
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

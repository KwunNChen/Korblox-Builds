--[[
	SkiConfig
	Every tunable number for the ski system.

	Split in two. The GEAR half is live right now -- it is what builds the skis
	and poles and decides where they sit on the body. The MOVEMENT half at the
	bottom is dormant: SkiPhysics reads it, but nothing calls SkiPhysics yet.
	Ignore it until the gear looks right.
]]

local SkiConfig = {}

-- ============================================================
-- EQUIPPING
-- ============================================================

SkiConfig.ToolName = "Skis"

-- Give every player a pair on spawn. Turn off if skis should come from a shop,
-- a rack, or a round-start handout instead.
SkiConfig.GiveOnSpawn = true

-- Walk speed multiplier while the skis are on your feet. Applied through
-- SpeedService as a named modifier, so it stacks with sprinting and weather
-- rather than overwriting them. Does nothing while the gear is on your back.
SkiConfig.WalkSpeedMultiplier = 0.55

-- ============================================================
-- SKI SHAPE
-- ============================================================

-- Total length, tip to tail. An R6 character is about 5 studs tall, so this is
-- deliberately close to "as tall as you are" the way real skis are.
SkiConfig.SkiLength = 5.4

-- Sidecut: wide at the tip and tail, narrow underfoot. This is what stops them
-- reading as planks. Keep Waist smallest or the shape inverts.
SkiConfig.SkiTipWidth = 0.58
SkiConfig.SkiWaistWidth = 0.44
SkiConfig.SkiTailWidth = 0.54

SkiConfig.SkiThickness = 0.16

-- The nose sweep, built from a couple of short segments angled up. Rise is how
-- far the very tip ends up above the base, in studs.
SkiConfig.SkiTipRise = 0.5
SkiConfig.SkiTipSegments = 2

-- Camber: the middle of the ski sits this far proud of the ends. Real skis do
-- this and it is most of why they look sprung rather than flat. Subtle on
-- purpose -- 0 is a flat ski.
SkiConfig.SkiCamber = 0.05

-- White painted wood: the material carries the grain, the colour paints over it.
SkiConfig.SkiColor = Color3.fromRGB(244, 244, 240)
SkiConfig.SkiMaterial = Enum.Material.Wood

--[[
	The binding, built the way a real one is: a toe piece and a heel piece with
	the boot clamped between them, rather than one block wrapping the leg.

	They sit just fore and aft of the leg on purpose. R6's leg is a stud deep,
	so anything within half a stud of the boot centre is buried inside it and
	invisible -- BindingSpacing is what pushes these two clear of it. That is
	also why they can be genuinely small: they don't need to be oversized to be
	seen, they just need to be somewhere you can see them.
]]
SkiConfig.BindingColor = Color3.fromRGB(38, 42, 50)

SkiConfig.BindingToeSize = Vector3.new(0.52, 0.19, 0.34)
SkiConfig.BindingHeelSize = Vector3.new(0.5, 0.24, 0.3)

-- How far each piece sits from the middle of the boot. Below about 0.5 they
-- vanish into the leg.
SkiConfig.BindingSpacing = 0.56

-- ============================================================
-- POLE SHAPE
-- ============================================================

-- Shaft length BELOW the grip, not the whole pole. An R6 hand sits about 2
-- studs off the ground, so much more than this and the poles bury themselves.
SkiConfig.PoleLength = 1.85
SkiConfig.PoleThickness = 0.11
SkiConfig.PoleColor = Color3.fromRGB(52, 56, 64)
SkiConfig.PoleMaterial = Enum.Material.Metal

SkiConfig.PoleGripLength = 0.55
SkiConfig.PoleGripThickness = 0.19
SkiConfig.PoleGripColor = Color3.fromRGB(28, 30, 36)

-- The disc near the bottom that stops the pole sinking into snow.
SkiConfig.PoleBasketDiameter = 0.46
SkiConfig.PoleBasketThickness = 0.06

-- How far up from the tip the basket sits.
SkiConfig.PoleBasketHeight = 0.45

-- ============================================================
-- WHERE THE GEAR SITS
-- ============================================================
--
-- These are the numbers to nudge if something is floating, clipping, or facing
-- the wrong way. R6 legs and arms are 2 studs tall, so their far end is 1 stud
-- below centre -- that is where the 1.0s come from.

-- Skis on your feet. X spreads them apart, Y drops them to the sole, Z shifts
-- them fore and aft (positive is backwards, so more ski sits in front of the
-- boot -- which is how a real ski is mounted).
--
-- The Y puts the ski's BASE level with the ground, which means its top surface
-- sits slightly inside the leg. That is deliberate: the alternative is resting
-- the ski on the sole, which buries it. Nothing controls standing height yet,
-- so this is the honest compromise until movement goes in.
SkiConfig.SkiFootOffset = Vector3.new(0.1, -0.92, 0.35)

-- Poles in your hands.
SkiConfig.PoleHandOffset = Vector3.new(0, -0.85, -0.25)

-- How far the poles tilt out sideways from vertical, in radians. Nobody carries
-- poles perfectly upright.
SkiConfig.PoleHandTilt = 0.18

--[[
	How far the pole tips trail behind you while riding, in radians.

	The poles are welded to the arms, so without this they swing wherever the
	arms go -- and the ski stance puts the hands right out in front, which
	pointed the poles forward like lances. The pose cancels the arm's swing and
	applies this instead, so the hands stay forward while the tips stay back
	where a skier actually holds them.

	0 hangs them straight down. Around 0.5 is the usual downhill carry.
]]
SkiConfig.PoleTrailAngle = 0.55

-- How the skis ride when they're on your back:
--
--   "AFrame"    up your spine with the tips leaning together above your head
--               and the tails open below -- an upside-down V. The real carry.
--   "Diagonal"  strapped together as a pair, slung corner to corner
--   "Vertical"  dead straight and parallel
--   "Crossed"   an X. Nobody carries skis this way, but it's here.
SkiConfig.SkiCarryStyle = "AFrame"

-- Where the bundle sits. X shifts it across your back, Y up and down, Z how far
-- it stands off you -- just enough to clear the torso and the sling.
SkiConfig.SkiBackOffset = Vector3.new(0, 0.1, 0.72)

-- AFRAME: how far each ski leans in, in radians. The sideways offset needed to
-- make the tips actually meet is worked out from this, so this is the only
-- number you need -- bigger is a wider stance at the tails.
SkiConfig.SkiApexAngle = 0.26

-- AFRAME: gap left between the two tips at the top, so they lean together
-- without visibly intersecting.
SkiConfig.SkiApexGap = 0.28

-- DIAGONAL: lean away from vertical, radians. About 0.62 puts the tips over one
-- shoulder and the tails past the opposite hip.
SkiConfig.SkiCarryAngle = 0.62

-- DIAGONAL and VERTICAL: gap between the two skis.
SkiConfig.SkiCarrySpread = 0.2

-- CROSSED: how far each ski tips to open the X.
SkiConfig.SkiBackTilt = 0.36

-- Poles stowed on your back, outboard of the skis.
SkiConfig.PoleBackOffset = Vector3.new(0.85, 0.1, 0.62)
SkiConfig.PoleBackTilt = 0.12

-- ============================================================
-- CARRY STRAP
-- ============================================================
--
-- A sling over one shoulder plus a pair of bands cinched round the skis. Both
-- only appear while the skis are on your back -- you take the strap off to ski,
-- same as you would in real life.

SkiConfig.EnableStrap = true

SkiConfig.StrapColor = Color3.fromRGB(28, 31, 36)
SkiConfig.StrapMaterial = Enum.Material.Fabric

-- The sling across your body.
SkiConfig.StrapWidth = 0.22
SkiConfig.StrapThickness = 0.13
SkiConfig.StrapLength = 2.7

-- How diagonally the sling lies, in radians. 0 is straight up and down.
SkiConfig.StrapTilt = 0.62

-- Which shoulder it goes over: 1 for right, -1 for left.
SkiConfig.StrapShoulder = 1

-- The bands cinched round the skis, and how far each sits from the boot.
SkiConfig.StrapCinchWidth = 0.17
SkiConfig.StrapCinchSpacing = 0.95

-- ============================================================
-- USING YOUR OWN MESH INSTEAD
-- ============================================================
--
-- Leave empty and the skis above are built from parts. Put an uploaded MeshId
-- here and that gets used instead, with the same joints and the same offsets.
-- Nothing else has to change.
--
-- A mesh's origin and forward axis are whatever the artist left them as, so
-- expect to need the scale and rotation below. Rotation is in degrees.
SkiConfig.SkiMeshId = ""
SkiConfig.SkiMeshScale = Vector3.new(1, 1, 1)
SkiConfig.SkiMeshOffset = Vector3.new(0, 0, 0)
SkiConfig.SkiMeshRotation = Vector3.new(0, 0, 0)

SkiConfig.PoleMeshId = ""
SkiConfig.PoleMeshScale = Vector3.new(1, 1, 1)
SkiConfig.PoleMeshOffset = Vector3.new(0, 0, 0)
SkiConfig.PoleMeshRotation = Vector3.new(0, 0, 0)

-- ============================================================
-- DEBUG
-- ============================================================

-- Prints equip, stow and build events to Output.
SkiConfig.DebugLog = true

-- ============================================================
-- ============================================================
-- MOVEMENT
-- ============================================================
-- ============================================================
--
-- IF YOU ONLY TUNE ONE NUMBER, MAKE IT LateralDrag. The ratio between it and
-- ForwardDrag is the entire difference between skiing and sliding on soap.

-- ============================================================
-- GROUND TRACKING
-- ============================================================

-- How high the root part rides above the ground while sliding.
--
-- 3.0 is not arbitrary: R6's root sits exactly 3 studs above the soles, and
-- SkiFootOffset already puts the ski bases level with the soles. So this value
-- puts the skis flat on the snow. Change SkiFootOffset and this has to move
-- with it.
SkiConfig.HoverHeight = 3.0

-- How far past HoverHeight we still look for ground. This is the spring's
-- reach, NOT the point at which you count as landed -- touching down uses a
-- much tighter test, or you would "land" while still metres up.
SkiConfig.ProbeMargin = 2.5

--[[
	The ground is checked at three points -- under the boot and out near each end
	of the ski -- and this is how far the outer two sit, as a fraction of the
	ski's length.

	One probe under the boot only knows about the ground directly beneath you,
	and the ski is over five studs long. Ski into a dip or over a rise and the
	tip or tail is through the snow well before the middle has any idea. That is
	the clipping you see on the way into a slope.

	0 puts all three in the same place, which is the old single-probe behaviour.
	Much above 0.4 and the probes sit past the ends of the ski and start lifting
	you over ground you aren't on yet.
]]
SkiConfig.ProbeSpread = 0.38

-- Hover spring. A spring rather than a hard snap, because snapping reads as
-- teleporting over bumps. Critical damping is 2*sqrt(stiffness), so these are
-- very slightly springy on purpose.
SkiConfig.HoverStiffness = 170
SkiConfig.HoverDamping = 25

-- Seconds of smoothing on the ground normal. Terrain normals are noisy voxel
-- data, and without this the skis visibly shake on smooth ground. Raise it if
-- you still see jitter, lower it if the skis feel late to follow the ground.
SkiConfig.NormalSmoothing = 0.08

-- Steeper than this (degrees) counts as a wall, not ground.
SkiConfig.MaxGroundAngle = 75

-- ============================================================
-- WALKING AND SLIDING
-- ============================================================

-- Downhill pull (studs/sec^2) needed before walking turns into sliding.
-- Roughly a 4 degree slope. Raise it if you slide on ground that should be
-- walkable.
SkiConfig.SlideEnterAccel = 14

-- Sliding stops when the pull drops below this AND you are slower than
-- SlideExitSpeed. Both matter: speed alone would drop you out of the slide
-- every time you slowed for a turn, slope alone would strand you sliding across
-- a flat run-out. Keep both under SlideEnterAccel so there is a dead band --
-- without the gap you flicker between the two states on any borderline ground.
SkiConfig.SlideExitAccel = 9
SkiConfig.SlideExitSpeed = 6

-- ============================================================
-- THE RIDE
-- ============================================================

--[[
	Along-ski drag, per second, and NOT per-material -- it applies everywhere.

	Kept tiny on purpose. At 90 studs/sec this used to be 0.35, which worked out
	at 31 studs/sec^2 of braking against snow's 8 -- so the surface you were on
	barely mattered and nothing ever really glided. Dropping it to 0.05 hands
	that job to SurfaceFriction below, where it belongs: snow now runs away from
	you and mud still stops you dead.

	Raise it if EVERY surface feels too slippery. If it's only one surface that's
	wrong, that's SurfaceFriction, not this.
]]
SkiConfig.ForwardDrag = 0.05
SkiConfig.LateralDrag = 9.0
SkiConfig.CarveRecovery = 0.35
SkiConfig.SlopeAccelGain = 0.55
SkiConfig.AirDrag = 0.0022
SkiConfig.TuckDragMultiplier = 0.45
SkiConfig.MaxSpeed = 260

--[[
	Coulomb friction by material, for Terrain voxels and BaseParts alike.

	Deceleration works out as mu * gravity * cos(slope), so these bite hardest on
	the flat and ease off as it steepens -- which is the behaviour you want.

	SNOW AND ICE ARE DELIBERATELY ALMOST FRICTIONLESS. Snow at 0.005 is about
	1 stud/sec^2 of drag, so you keep basically everything you earn and a long
	flat run-out barely slows you at all.

	Consequence worth knowing: you will not coast to a stop on snow any more.
	From full speed on the flat, friction alone takes well over a minute to stop
	you. Braking is how you stop now -- that is what it's for. If you want to
	glide back to a halt on your own, snow around 0.03 does it.
]]
SkiConfig.SurfaceFriction = {
	-- Slick end. Ordered so ice is always faster than snow, which is always
	-- faster than anything you'd find under the snow.
	[Enum.Material.Ice] = 0.002,
	[Enum.Material.Glacier] = 0.003,
	[Enum.Material.Snow] = 0.005,

	-- Man-made surfaces: fast, but nothing like snow.
	[Enum.Material.SmoothPlastic] = 0.05,
	[Enum.Material.Metal] = 0.05,
	[Enum.Material.DiamondPlate] = 0.07,
	[Enum.Material.Plastic] = 0.08,
	[Enum.Material.Wood] = 0.10,
	[Enum.Material.WoodPlanks] = 0.10,

	-- Bare ground. Skiing onto any of these should feel like a mistake.
	[Enum.Material.Rock] = 0.14,
	[Enum.Material.Slate] = 0.14,
	[Enum.Material.Grass] = 0.18,
	[Enum.Material.Sand] = 0.22,
	[Enum.Material.Mud] = 0.30,
}

-- Anything not listed above. Middling on purpose -- an unlisted material is
-- usually not something you meant to ski on.
SkiConfig.DefaultFriction = 0.08
SkiConfig.FrictionAttribute = "SkiFriction"

-- Radians/sec you can swing the skis at a standstill.
SkiConfig.TurnRate = 4.6

-- How fast turning tightens up as you speed up. Effective rate is
-- TurnRate / (1 + speed * TurnSpeedFalloff).
--
-- This used to be 0.012, which at 150 studs/sec left you 1.1 rad/sec -- over
-- five seconds to turn all the way round, which is why it felt like steering a
-- ship. At 0.006 the same speed gives 2.4. Push it back up if fast runs start
-- feeling twitchy rather than committing.
SkiConfig.TurnSpeedFalloff = 0.006

SkiConfig.BrakeDecel = 95
SkiConfig.BrakeLateralDrag = 30
SkiConfig.BrakeHoldSpeed = 3

-- ============================================================
-- JUMPING AND AIR
-- ============================================================

-- Launch speed added along the GROUND NORMAL rather than straight up, so
-- jumping off a lip throws you along the slope the way it should.
SkiConfig.JumpImpulse = 62
SkiConfig.JumpCooldown = 0.25

-- Seconds after leaving the ground where a jump still counts. Small, but the
-- difference between crisp and unresponsive.
SkiConfig.CoyoteTime = 0.12

SkiConfig.AirYawRate = 3.4
SkiConfig.AirPitchRate = 2.8
SkiConfig.AirDriftAccel = 18

-- ============================================================
-- LANDING AND CRASHING
-- ============================================================
--
-- A landing is scored on two things, and whichever is worse wins: whether the
-- skis point where you're actually travelling, and whether they're parallel to
-- the ground you're hitting.

-- Land within this many degrees of straight and you keep all your speed.
SkiConfig.LandingCleanAngle = 25

-- Past this and you eat it. Between the two, speed is scrubbed in proportion --
-- a scrappy landing costs you, it doesn't end you.
SkiConfig.LandingCrashAngle = 65

-- Fraction of speed kept on the worst landing you can survive.
SkiConfig.LandingWorstKeep = 0.45

-- Coming down harder than this crashes you whatever the angle. Set very high to
-- turn height-based crashes off.
SkiConfig.CrashImpactSpeed = 165

-- Fraction of speed you keep through a wipeout.
SkiConfig.CrashSpeedKeep = 0.15

-- How long you're on the floor. The character properly ragdolls for this long
-- -- R6's joints are swapped for ball sockets and the limbs go limp.
SkiConfig.CrashDuration = 1.8

-- Spin thrown in at the moment of the wipeout, radians/sec, so you tumble
-- instead of just going limp and sliding.
SkiConfig.CrashTumble = 9

-- ============================================================
-- POSES
-- ============================================================

-- Seconds of blend between poses. A time constant, not a duration.
SkiConfig.PoseSmoothing = 0.12

--[[
	CARVING.

	A turn is not one lean. Real carving is four things happening at once, and
	each of these is one of them:

	  MaxEdgeAngle      the skis tip onto their edges. THE defining thing --
	                    everything else is decoration on top of it. On R6 this
	                    is the legs tipping sideways at the hip; the skis are
	                    welded to them, so they go on edge for free.

	  MaxLeanAngle      the body inclines into the turn.

	  NeckCounterRoll   how much of that lean the head cancels, so you keep
	                    looking level instead of tipping your head with your
	                    body. This is what separates angulation from just
	                    falling sideways.

	  MaxCounterTwist   the upper body stays facing down the hill while the
	                    legs turn underneath it. The thing that makes a skier
	                    look like a skier rather than a plank pivoting.

	If a turn looks right but MIRRORED, don't touch any of the four -- flip
	CarveDirection instead. It negates all of them together.
]]
SkiConfig.CarveDirection = 1

SkiConfig.MaxEdgeAngle = 0.5
SkiConfig.MaxLeanAngle = 0.55
SkiConfig.NeckCounterRoll = 0.6
SkiConfig.MaxCounterTwist = 0.35

SkiConfig.LeanSmoothing = 0.14

-- There is no TuckHoverDrop any more. R6 has no knee, so every crouch is the
-- legs angled forward from the hip, and how far that lowers you falls out of
-- the geometry -- see the hip values in SkiPose. Want a deeper tuck? Raise the
-- hip angle in the Tuck pose and the ride height follows on its own.

-- Leave empty to use the built-in procedural poses. Drop in an R6 animation id
-- and that slot switches over instead, no other file changes.
--
-- Worth knowing: procedural poses are LOCAL TO YOU. Joint changes made on the
-- client don't replicate, so other players see you riding unposed. Real
-- animations go through the Animator and do replicate -- which is the reason to
-- fill these in eventually.
SkiConfig.Animations = {
	Stance = "",
	Carve = "",
	Tuck = "",
	Brake = "",
	Air = "",
}

-- ============================================================
-- CONTROLS
-- ============================================================

-- Steering reads Humanoid.MoveDirection, so it already follows rebound keys,
-- gamepads and mobile thumbsticks. These are the extras.
SkiConfig.BrakeKey = Enum.KeyCode.S
SkiConfig.TuckKey = Enum.KeyCode.LeftShift
SkiConfig.EquipKey = Enum.KeyCode.G

SkiConfig.BrakeButton = Enum.KeyCode.ButtonL2
SkiConfig.TuckButton = Enum.KeyCode.ButtonR2

-- ============================================================
-- EQUIP ZONES
-- ============================================================

-- Tag any part with this (CollectionService, or the Tags section of the
-- Properties panel) and touching it straps the skis on. Give the part an
-- attribute "SkiZoneRemoves" = true to make it take them off instead -- one tag
-- at the top of the run, one at the bottom.
SkiConfig.ZoneTag = "SkiZone"
SkiConfig.ZoneRemovesAttribute = "SkiZoneRemoves"

-- Stops a zone re-firing every frame you stand on it.
SkiConfig.ZoneCooldown = 1

return table.freeze(SkiConfig)

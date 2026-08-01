--[[
	SkiConfig
	Every tunable number for the ski system.

	Split in two. The GEAR half is live right now -- it is what builds the skis
	and poles and decides where they sit on the body. The MOVEMENT half at the
	bottom is dormant: SkiPhysics reads it, but nothing calls SkiPhysics yet.
	Ignore it until the gear looks right.
]]

local SkiConfig = {}

-- ############################################################
-- #
-- #   PUT YOUR SOUND IDS HERE
-- #
-- ############################################################
--
-- Skiing is SILENT until you fill these in, and that's deliberate: Roblox audio
-- is private to whichever place owns it, so an id copied from another game
-- plays as silence with no error and nothing in Output. Shipping a real id
-- would just look broken.
--
-- To get one: View > Toolbox > Audio, search, right click, Copy Asset ID.
-- Paste it over the placeholder. Bare numbers and full rbxassetid:// URLs both
-- work. Anything still saying PUT... is treated as empty and skipped, so fill
-- in as many or as few as you like.
--
-- If you only do one, do GlideSoundId.

-- Skis running over snow. Follows your speed. The workhorse -- pick something
-- that loops without an audible seam.
SkiConfig.GlideSoundId = "rbxassetid://9125408271"

-- The edges biting. Follows SIDEWAYS speed, so it arrives when you turn rather
-- than droning all the way down. Wants to be a harsher scrape than the glide.
SkiConfig.CarveSoundId = "rbxassetid://9113597285"

-- Follows speed, and the only one that keeps going while you're in the air.
SkiConfig.WindSoundId = "rbxassetid://93035214379043"

-- One-shots.
SkiConfig.JumpSoundId = "rbxassetid://135162567109750"
SkiConfig.LandSoundId = "rbxassetid://82342043168584"
SkiConfig.CrashSoundId = "rbxassetid://91358197736651"

-- Volumes, pitch and smoothing for the above live further down under SOUND.
-- Two other things take ids you may want to fill in eventually: SkiMeshId /
-- PoleMeshId to use your own models, and Animations to replace the built-in
-- procedural poses.

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

-- How far the whole bundle tips backwards, in radians, so the tops lean away
-- from your head instead of straight up through whatever hair you're wearing.
-- Applies to every carry style. 0 stands them dead upright.
SkiConfig.SkiBackLean = 0.2

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

--[[
	A deliberate gap between the ski bases and the snow, on top of HoverHeight.

	HoverHeight puts the skis EXACTLY on the ground, which leaves no room for
	error -- and the hover spring always has some. Ride down a slope onto the
	flat and the spring is still catching up when the ground levels out, so the
	skis dip through it for a moment.

	This is the margin that absorbs that. There is a narrow band that works: too
	little and the skis catch the ground coming off a slope, too much and they
	visibly hover over it. Raise it if you clip, lower it if they float, and
	expect to be working in hundredths rather than tenths.

	It is measured from the LOWEST part of the ski, camber included, so changing
	SkiCamber does not quietly eat into it.
]]
SkiConfig.GroundClearance = 0.04

-- How far past HoverHeight we still look for ground. This is the spring's
-- reach, NOT the point at which you count as landed -- touching down uses a
-- much tighter test, or you would "land" while still metres up.
SkiConfig.ProbeMargin = 2.5

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

--[[
	Settling-in time after strapping the skis on. For this long you cannot jump
	and cannot wipe out.

	Both halves are needed. Strapping in while jump is queued -- or simply held
	-- fired you straight into the air on the first frame of the sim, and a
	launch you never asked for tends to end in a landing you can't save. Blocking
	the jump stops the common case; suspending crashes covers whatever else the
	first moments throw up, since a wipeout in the instant you strap in is never
	something the player did.
]]
SkiConfig.EquipGrace = 0.35

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

	  MaxEdgeAngle      how far the SKIS roll onto their edges. This is the big
	                    one and it carries the whole look of a carve.

	  MaxLegTip         how far the LEGS lean over. SMALL, and it has to be.

	  MaxLeanAngle      how far the TORSO inclines. Also small, and less than
	                    the legs, which is what gives the bent-at-the-hip shape
	                    a real skier has.

	WHY MaxLegTip CANNOT BE BIG, even though a real skier's legs go right over:
	R6 has no knee and no ankle. Tipping the leg pivots the whole thing about the
	hip, so the foot swings through an arc instead of staying planted. At 0.7 rad
	on a two-stud leg that is over a stud sideways, and the boot simply walks off
	the ski. A real leg absorbs all of that in the joints below the hip.

	So the skis carry the edge angle and the legs only suggest it. Raise MaxLegTip
	past about 0.25 and you will see the character step off its own skis.

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

SkiConfig.MaxEdgeAngle = 0.72
SkiConfig.MaxLegTip = 0.18
SkiConfig.MaxLeanAngle = 0.32
SkiConfig.NeckCounterRoll = 0.5
SkiConfig.MaxCounterTwist = 0.45

SkiConfig.LeanSmoothing = 0.14

--[[
	POLE PLANTS.

	A skier taps the snow with the inside pole as each turn starts. It's the
	rhythm you recognise a skier by from a distance, more than the turns
	themselves.

	Triggered off the lean crossing sides, not off a timer, so it lands with your
	actual turns rather than metronoming through them. And because lean is one of
	the values that replicates, other players plant poles too without any extra
	work.

	PolePlantLean is how committed a turn has to be before it earns a plant --
	raise it and only proper carves get one. The cooldown stops a wobble at speed
	turning into frantic tapping.
]]
SkiConfig.EnablePolePlants = true

-- Deliberately low. A plant should feel like part of how you turn, not a rare
-- flourish, so anything that reads as a real turn earns one.
SkiConfig.PolePlantLean = 0.18
SkiConfig.PolePlantCooldown = 0.3

-- How long the whole plant takes, and how far the arm reaches. The reach is
-- radians added to the shoulder, so it stacks on whatever pose is running.
--
-- Most of the duration is spent HELD at full reach rather than travelling, so
-- the tip sits in the snow while the turn comes round it. Raise the reach if
-- the pole still looks like it's waving past rather than planting.
SkiConfig.PolePlantDuration = 0.55
SkiConfig.PolePlantReach = 1.75

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
-- EFFECTS
-- ============================================================
--
-- All of this is local to you. Particles and camera changes made on the client
-- don't replicate, same as the poses -- so you see your own spray and not other
-- people's. Making it shared means replicating scrub speed per player, which is
-- a lot of traffic for something cosmetic.

SkiConfig.EnableSpray = true

--[[
	Spray is driven by SIDEWAYS speed across the skis, not by how fast you're
	going. That is the honest measure: a dead-straight schuss at full tilt throws
	almost nothing, and a hard carve throws a wall of it even at moderate speed.
	Drive it off total speed instead and it just blasts constantly.
]]
SkiConfig.SprayMaxRate = 120

-- Sideways speed, in studs/sec, at which spray reaches full rate.
SkiConfig.SpraySaturationSpeed = 28

SkiConfig.SprayTexture = "rbxasset://textures/particles/smoke_main.dds"
SkiConfig.SprayColor = Color3.fromRGB(255, 255, 255)

-- Only these throw spray. Ski across rock and nothing comes off it, which is
-- most of what makes the snow feel like snow.
SkiConfig.SprayMaterials = {
	[Enum.Material.Snow] = true,
	[Enum.Material.Glacier] = true,
	[Enum.Material.Ice] = true,
	[Enum.Material.Sand] = true,
}

-- A burst of it when you touch down.
SkiConfig.EnableLandingPuff = true

-- Impact speed that produces a full-sized burst.
SkiConfig.LandingPuffSpeed = 45
SkiConfig.LandingPuffCount = 30

-- Camera stretch with speed. The cheapest thing there is for making fast feel
-- fast -- degrees added to the field of view at MaxSpeed, scaled by how fast
-- you're actually going.
SkiConfig.EnableSpeedFov = true
SkiConfig.MaxFovBoost = 20
SkiConfig.FovSmoothing = 0.35

--[[
	TRACKS LEFT IN THE SNOW.

	A ribbon drawn behind each ski. Unlike the spray, this runs off SPEED rather
	than sideways scrub -- you leave a track wherever you go, not only where you
	turn. It cuts on rock for the same reason the spray does.

	TrailLifetime is the one to watch. It's how many seconds a track lingers, and
	it's also the cost: a long lifetime on a busy hill is a lot of ribbon on
	screen at once. Ten seconds looks great with three people and less great with
	twenty.
]]
SkiConfig.EnableTrails = true
SkiConfig.TrailLifetime = 7
SkiConfig.TrailWidth = 0.42
SkiConfig.TrailColor = Color3.fromRGB(214, 228, 244)
SkiConfig.TrailTransparency = 0.55

--[[
	WIND RUSH: streaks flying past the camera once you're properly moving.

	The particles are stationary. They don't fly past you, you fly past THEM --
	which is why the effect scales itself honestly and needs no velocity maths.

	Nothing happens below WindRushSpeed, on purpose. If it's always on it stops
	meaning anything, and the whole job of this effect is telling you when you've
	crossed from fast into too fast.
]]
SkiConfig.EnableWindRush = true
SkiConfig.WindRushSpeed = 65
SkiConfig.WindRushMaxRate = 70
SkiConfig.WindRushTexture = "rbxasset://textures/particles/sparkles_main.dds"
SkiConfig.WindRushColor = Color3.fromRGB(226, 240, 255)

-- The number on screen. Local player only, and only while you're actually
-- sliding -- it has nothing to say while you're stood still.
SkiConfig.EnableSpeedHud = true

-- ============================================================
-- SOUND
-- ============================================================
--
-- THE IDS THEMSELVES ARE AT THE VERY TOP OF THIS FILE, under "PUT YOUR SOUND
-- IDS HERE". Only the mixing lives down here.

SkiConfig.EnableSound = true

SkiConfig.GlideMaxVolume = 0.4
SkiConfig.CarveMaxVolume = 0.55
SkiConfig.WindMaxVolume = 0.45
SkiConfig.OneShotVolume = 0.7

-- Playback speed at a standstill and at MaxSpeed. Pitch climbing with speed is
-- most of what makes the loops feel connected to what you're doing rather than
-- just playing underneath it.
SkiConfig.GlidePitchSlow = 0.75
SkiConfig.GlidePitchFast = 1.4
SkiConfig.WindPitchSlow = 0.8
SkiConfig.WindPitchFast = 1.25

-- Seconds of smoothing on volume and pitch. A time constant, not a duration --
-- without it every loop steps audibly as speed changes.
SkiConfig.SoundSmoothing = 0.25

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
-- SHOWING OTHER PLAYERS
-- ============================================================
--
-- Poses, spray and sound are all built on the client, and none of that
-- replicates. So a skier is only posed, spraying and audible on their OWN
-- screen unless the numbers driving those things are sent round.
--
-- Each client publishes five values; the server writes them as character
-- attributes, which do replicate; everyone else renders from those.

-- How often those values go up, in seconds. This is not a physics rate -- the
-- pose and the sound both smooth toward whatever they last heard, so ten times
-- a second is plenty.
SkiConfig.StateBroadcastRate = 0.1

--[[
	How much a value has to move before it's worth sending at all.

	Straight-line skiing barely changes any of these, and pushing five attribute
	writes per player ten times a second regardless is what makes this expensive
	once there are more than a handful of people on a hill.
]]
SkiConfig.SpeedEpsilon = 1.5
SkiConfig.ScrubEpsilon = 1.5
SkiConfig.LeanEpsilon = 0.05

--[[
	HOW FAR AWAY ANOTHER SKIER IS STILL WORTH DRAWING.

	Rendering someone else costs the same whether they fill your screen or are a
	speck across the valley: six joint writes a frame, two emitters, two trails
	and three sound loops each. Twenty people on a hill is that twenty times
	over, including everyone behind you and everyone inside a tree.

	Two tiers, both measured from the camera.

	  RemotePoseDistance   past this, stop posing them. Poses are the per-frame
	                       cost AND the first thing to stop being legible: you
	                       cannot tell a carve from a tuck on someone a hundred
	                       studs away, but their spray and their tracks still
	                       read fine.

	  RemoteCullDistance   past this, stop everything.

	Raise them if distant skiers look dead, lower them if a busy hill drags.
]]
SkiConfig.RemotePoseDistance = 140
SkiConfig.RemoteCullDistance = 420

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

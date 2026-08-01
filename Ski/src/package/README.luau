--[[

	GIVE CREDIT TO PLAGUEBYTE!!!!! @pb6008 for any inquiries

	SKIS

	Skis and poles that weld to your character and sling across your back on a
	carry strap when you're not using them. Strap in and point downhill.

	Carving, snowplow braking, jumps that throw you along the slope, landings
	you can blow, and a proper ragdoll when you do.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder in step 5.


	========================================================
	CONTROLS
	========================================================

	    G                strap in / take them off
	    WASD / stick     steer
	    S / pull back    snowplow brake
	    Shift            tuck -- cuts air drag, raises your top speed
	    Space            jump

	Steering reads Humanoid.MoveDirection, so rebound keys, gamepads and mobile
	thumbsticks all work with no extra setup.

	You can also strap in by walking over a brick. Tag any part "SkiZone" (the
	Tags box at the bottom of the Properties panel) and touching it puts the
	skis on. Give that part an attribute "SkiZoneRemoves" = true and it takes
	them off instead -- one at the top of the run, one at the bottom.


	========================================================
	INSTALL
	========================================================

	The folders in this package are named after where they go. Drag each one
	into the matching service.

	1. This package should be sitting in ServerStorage. If it's anywhere else,
	   move it there first. Scripts don't execute in ServerStorage. Leave it in
	   ServerScriptService or Workspace and the server scripts start running
	   before the shared modules exist.

	2. Open the "ReplicatedStorage" folder. Move both children into the real
	   ReplicatedStorage service:

	       Ski
	       SkiRemotes

	   SkiRemotes is a convenience, not a requirement -- the server builds any
	   remote that's missing when it starts. Dragging it in just saves it the
	   job.

	3. Open the "ServerScriptService" folder. Move both children into the real
	   ServerScriptService service:

	       Ski
	       Common

	   IF YOUR GAME ALREADY HAS A COMMON FOLDER, MERGE -- DON'T REPLACE. Open
	   this one and drag its files into yours, keeping anything already there.

	   Common is shared ground between the Korblox packages rather than Ski's
	   own folder. Ski only uses SpeedService out of it; CharacterCache is in
	   there for Variable Snowstorm. Replace the folder wholesale and you take
	   out whatever the other package needed, and the only sign of it is an
	   infinite yield on a WaitForChild that never returns.

	4. Open the "StarterPlayerScripts" folder. Move its Ski folder into:

	       StarterPlayer > StarterPlayerScripts

	   Don't skip this one. It's the half that does the actual skiing. Miss it
	   and the gear still appears and still slows you down, but you will never
	   slide anywhere.

	5. Delete the empty KorbloxSki folder.


	WHEN YOU'RE DONE

	    ReplicatedStorage
	    |-- Ski                   SkiConfig, SkiShared
	    +-- SkiRemotes            SkiEquip, SkiCrash, SkiState

	    ServerScriptService
	    |-- Ski                   SkiService, SkiRuntime, SkiGear, SkiRagdoll
	    +-- Common                SpeedService, CharacterCache

	    StarterPlayer/StarterPlayerScripts
	    +-- Ski                   SkiController, SkiPhysics, SkiPose,
	                              SkiEffects, SkiSound, SkiRemoteView

	Press Play. You spawn with the skis on your back and a "Skis" tool in your
	hotbar. Press G, walk onto something that slopes, and you're skiing.


	========================================================
	UPDATING A COPY YOU ALREADY INSTALLED
	========================================================

	Replace the script folders. You do NOT need to redo SkiRemotes -- the server
	adds anything missing on startup, so an older folder catches up on its own.

	That is deliberate. A missing remote used to mean an infinite yield, and
	those do not fail loudly: the script simply stops at that line, and
	everything after it never runs. One forgotten folder could take the whole
	system down with nothing in Output but a warning.


	========================================================
	IF SOMETHING SITS WRONG
	========================================================

	All the placement lives in SkiConfig, in the "WHERE THE GEAR SITS" section.
	Nudge and look -- there is no substitute for watching it.

	    SkiFootOffset     skis on your feet. Y is height, Z is fore and aft
	    PoleHandOffset    poles in your hands
	    PoleHandTilt      how far the poles splay out sideways
	    PoleTrailAngle    how far the tips trail behind you while riding
	    SkiCarryStyle     how they ride on your back -- see below
	    SkiBackOffset     where the bundle sits on your back
	    SkiBackLean       how far the tops tip back, to clear tall hair
	    SkiApexAngle      how far the skis lean into the V. AFrame only
	    SkiApexGap        air left between the tips at the top
	    SkiCarryAngle     lean. Diagonal only
	    SkiCarrySpread    gap between the skis. Diagonal and Vertical
	    PoleBackOffset    poles on your back
	    PoleBackTilt


	========================================================
	CARRYING THEM ON YOUR BACK
	========================================================

	SkiCarryStyle takes one of four values:

	    "AFrame"     up your spine with the tips leaning together above your
	                 head and the tails open below -- an upside-down V. The
	                 default, and how skis are actually carried.

	    "Diagonal"   strapped together as a pair and slung corner to corner,
	                 tips above one shoulder.

	    "Vertical"   dead straight and parallel.

	    "Crossed"    an X across your back. Nobody carries skis this way.

	For AFrame, SkiApexAngle is the only number worth touching -- how far the
	skis lean in. The sideways offset that makes the tips actually meet is
	worked out from it, so the apex stays clean whatever angle you pick. Bigger
	angle means a wider stance at the tails. SkiApexGap leaves a little air
	between the tips so they don't visibly intersect.


	========================================================
	THE CARRY STRAP
	========================================================

	A sling over one shoulder, plus a pair of bands cinched round the skis so
	the pair reads as strapped together rather than floating in formation.

	It only appears while the skis are on your back. Strap in and the whole
	thing hides, which is what you'd do with a real one.

	    EnableStrap        false removes it entirely
	    StrapShoulder      1 for the right shoulder, -1 for the left
	    StrapTilt          how diagonally the sling lies. 0 is vertical
	    StrapWidth         and StrapThickness, StrapLength
	    StrapColor
	    StrapCinchSpacing  how far the bands sit either side of the boot
	    StrapCinchWidth

	The cinch bands are joined to the skis themselves, so they follow whatever
	SkiCarryStyle is set without any extra work.

	SKIS SINK INTO THE GROUND A LITTLE
	  Expected for now. Nothing controls standing height yet, so the skis are
	  mounted with their base level with the floor and their top tucked slightly
	  inside the leg. When the movement half goes in, the ride height is set
	  exactly and this stops being a compromise.

	FACING THE WRONG WAY
	  -Z is forward in Roblox part space, so the ski tips point that way. If
	  something is backwards it is almost always a sign flip in the offsets, not
	  a rotation.


	========================================================
	THE SHAPE OF THEM
	========================================================

	The skis are built from parts, so there is no asset to source and nothing to
	break when the package moves between places.

	    SkiLength                       tip to tail
	    SkiTipWidth / WaistWidth /
	      SkiTailWidth                  the sidecut -- keep Waist smallest
	    SkiTipRise, SkiTipSegments      the swept nose
	    SkiCamber                       how far the middle sits proud. 0 is flat
	    SkiColor, SkiMaterial           white painted wood by default
	    BindingToeSize / HeelSize       the two binding pieces
	    BindingSpacing                  how far apart they clamp. Under about
	                                      0.5 they disappear inside the leg

	    PoleLength                      shaft BELOW the grip, not the whole pole
	    PoleGripLength, PoleGripThickness
	    PoleBasketDiameter, PoleBasketHeight

	USING YOUR OWN MESH INSTEAD

	Put an uploaded id in SkiMeshId or PoleMeshId and it is used in place of the
	generated parts, with the same joints and the same offsets. A mesh's origin
	and forward axis are whatever the artist left them as, so expect to need
	SkiMeshScale and SkiMeshRotation (degrees) to make it fit.

	Leave the ids empty and you get the built-in shape.


	========================================================
	HOW IT RIDES
	========================================================

	The downhill pull is gravity with its ground-normal component removed. Flat
	ground gives zero, steep ground gives a lot, and there is no slope-angle
	special case anywhere in the code.

	Sideways speed is treated completely differently from forward speed. The
	edges scrub sideways drift off hard, and a fraction of what they scrub comes
	back as forward speed. That is carving, and it is why holding a clean line
	costs you less than sliding through a turn. THE RATIO OF LateralDrag TO
	ForwardDrag IS THE ENTIRE FEEL OF THE SYSTEM -- tune that before anything
	else.

	Gravity down a slope accelerates you LINEARLY, not exponentially. What makes
	it feel like it runs away is that almost nothing takes the speed back off
	you: along-ski drag is tiny, so you keep what you earn, and quadratic air
	drag sets a terminal speed you approach slowly. Tuck and that goes up again.
	If you want steeps to bite harder, raise SlopeAccelGain.

	Jumping pushes you along the GROUND NORMAL rather than straight up, so
	launching off a lip throws you along the slope. You keep your momentum
	through the jump.

	Walking is left entirely to the Humanoid. The sim only takes over once
	you're stood on something steeper than SlideEnterAccel, and hands back when
	the ground flattens out AND you've nearly stopped.

	Landings are scored on two things -- whether the skis point where you're
	actually travelling, and whether they're flat to the ground you're hitting.
	Whichever is worse wins. Inside LandingCleanAngle you keep everything, past
	LandingCrashAngle you eat it, and in between you lose speed in proportion.

	Wiping out properly ragdolls you: R6's joints are swapped for ball sockets,
	the limbs go limp, and you tumble for CrashDuration before getting up. The
	skis come off on the way down. This runs on the SERVER, so everyone sees it.

	NOT IN YET: tricks and scoring. Air pitch is already wired in SkiPhysics but
	switched off in the controller -- flips with nothing scoring them just means
	landing backwards for free.


	========================================================
	POSES
	========================================================

	The stance, carve, tuck, snowplow and air poses are procedural -- built out
	of R6 joint rotations, no animation editor needed.

	THE STANCE, AND THE ONE NUMBER THAT DRIVES IT

	Real skiing posture is knees bent, shins on the front of the boots, weight
	forward, hands ahead. R6 has no knee. The leg is one rigid piece from hip to
	sole and no amount of tuning changes that.

	So the crouch is the whole leg angled forward from the hip -- the hip Z value
	in each pose. Everything else follows from it automatically:

	  * The skis would tilt with the legs, since they're welded to them. The
	    pose counter-rotates the ski joints by the same angle to keep them flat.
	    THIS is what keeps the skis level, not holding the legs vertical.

	  * Swinging the leg forward lifts the foot, because less of the leg's
	    length is vertical. Ride height drops by exactly that much, which puts
	    the skis back on the snow -- and is what makes the crouch real instead
	    of a character hovering with its feet out in front.

	    That drop is worked out from the rig, not tuned, and it has two halves:
	    the foot lifting, and the ski pivoting DOWN because it's mounted behind
	    the leg's centre line (SkiFootOffset.Z). They partly cancel. Change
	    SkiFootOffset and the sums follow on their own -- but if you ever see
	    the skis buried in the snow in a deep stance, that relationship is
	    where to look.

	THE HIPS SIT AT ZERO IN EVERY POSE, so the legs stay vertical and the skis
	lie genuinely flat. The whole stance is carried by the torso lean instead.

	Zeroing them is not enough on its own, and this is worth knowing if you ever
	edit the poses. R6 hangs the legs off the TORSO, and RootJoint is what
	pitches the torso -- so leaning the body forward swings the legs backward
	with it and tips the skis nose-up, hips or no hips. The pose feeds that lean
	back into the hips with the opposite sign to hold the legs upright.

	Which means a pose's hip Z is the leg angle you ACTUALLY get, measured from
	vertical. Change the torso lean as much as you like; the legs stay put.

	That is a hard limit of the rig, not a tuning choice. R6's leg is one block a
	stud deep with no ankle, so swinging it forward tilts the foot with it while
	the ski underneath stays flat -- the heel lifts by about a stud times
	sin(angle) and the character reads as standing on tiptoe. A knee bend and
	flat feet cannot both exist without an ankle to absorb the difference, and
	flat feet are the one people notice.

	The machinery to angle the legs is still there and still correct: put a
	number back into a pose's hip Z and the ski counter-rotation and the ride
	height both follow on their own. It is the LOOK that doesn't survive it, not
	the maths. There is no separate crouch setting and deliberately no
	TuckHoverDrop.

	The snowplow adds a hip Y twist on top -- that's what points the tips
	together into the wedge.


	========================================================
	EFFECTS
	========================================================

	    EnableSpray            snow off the edges
	    SprayMaxRate           how much at full tilt
	    SpraySaturationSpeed   sideways speed that reaches full rate
	    SprayMaterials         what throws snow. Rock throws nothing
	    EnableLandingPuff      a burst when you touch down
	    LandingPuffSpeed       impact that gives a full-sized burst
	    EnableTrails           tracks left behind in the snow
	    TrailLifetime          seconds a track lingers. Also the cost of it
	    TrailWidth             how wide each track is
	    EnableWindRush         streaks past the camera at speed
	    WindRushSpeed          nothing happens below this
	    EnableSpeedFov         camera stretch with speed
	    MaxFovBoost            degrees added at MaxSpeed
	    EnableSpeedHud         the number on screen

	TRACKS run off SPEED, not sideways scrub: you leave a line wherever you go,
	not only where you turn. They still cut on rock, same as the spray.
	TrailLifetime is the one to watch, because it is both how long a track
	lingers and how much ribbon is on screen at once. Seven seconds looks good
	with a few people and less good with twenty.

	THE WIND RUSH is made of stationary particles. They don't fly past you, you
	fly past them, which is why it scales itself honestly off your real movement
	with no velocity maths anywhere. Nothing happens below WindRushSpeed on
	purpose: an effect that is always on stops telling you anything, and this
	one's whole job is marking the point where fast becomes too fast.

	The rush and the readout are LOCAL ONLY -- one camera, one screen, yours.
	Tracks and spray show up for everyone.

	SPRAY IS DRIVEN BY SIDEWAYS SPEED, not by how fast you're going. That's the
	honest measure: a dead-straight schuss at full tilt throws almost nothing and
	a hard carve throws a wall of it at half the speed. Drive it off total speed
	and it just blasts constantly, which reads as fog rather than snow.

	It's also gated on the material under you, so skiing off snow onto rock kills
	it instantly. That contrast is most of what makes the snow feel like snow
	rather than a white floor.

	Nothing here can affect how the skis ride, and every piece switches off on
	its own. The system rides identically with all of it disabled.


	========================================================
	SEEING OTHER PLAYERS SKI
	========================================================

	Their gear and their movement replicate on their own -- the gear is built on
	the server, and position is ordinary character replication. What does NOT
	replicate is anything cosmetic: joint poses, particles and sounds made on a
	client are only ever seen by that client.

	So each client publishes five numbers -- state, speed, sideways speed, lean
	and whether it's on snow -- the server writes them as character attributes,
	and every other client renders from those using exactly the same pose, spray
	and sound code the local player uses. Only the source of the numbers differs.

	    StateBroadcastRate   how often those go up, in seconds
	    SpeedEpsilon         how much each has to move before it's worth sending
	    ScrubEpsilon
	    LeanEpsilon

	The epsilons matter more than the rate. Straight-line skiing barely changes
	any of these, so without them you'd push five attribute writes per player ten
	times a second whatever they were doing. Raise them if a busy hill gets
	expensive; lower them if remote skiers look steppy.

	The crash sound is the one piece played from the SERVER, in SkiRagdoll,
	because a client-side sound is silent to everyone watching -- and a wipeout
	is the sound other people most want to hear. Jump and landing one-shots are
	still local.


	========================================================
	SOUND NEEDS YOUR OWN ASSET IDS
	========================================================

	SKIING SHIPS SILENT, AND THAT IS DELIBERATE. Roblox audio is private to the
	place that owns it, so an id lifted from another game plays as silence with
	no error and nothing in Output -- which looks exactly like a broken install.
	Better to ship blanks and have you fill them in.

	View > Toolbox > Audio, search, right click, Copy Asset ID. You'll get one
	warning in Output until at least one loop is set. Any slot left empty is
	skipped, so fill in as many or as few as you like.

	    GlideSoundId   skis running over snow. Follows SPEED. The workhorse --
	                   if you only set one, set this. Pick something that loops
	                   without an audible seam.
	    CarveSoundId   the edges biting. Follows SIDEWAYS speed, same as the
	                   spray, so it arrives when you turn instead of droning all
	                   the way down. A harsher scrape than the glide.
	    WindSoundId    follows speed, and the only one that keeps going while
	                   you're in the air.
	    JumpSoundId    one-shot on takeoff
	    LandSoundId    one-shot, louder and pitched down the harder you land
	    CrashSoundId   one-shot on a wipeout

	Volumes are GlideMaxVolume / CarveMaxVolume / WindMaxVolume / OneShotVolume.
	Pitch climbs with speed between GlidePitchSlow and GlidePitchFast, which is
	most of what stops a loop sounding like it's just playing underneath you.

	Glide and carve both cut when you ski off snow onto rock, the same rule the
	spray follows.

	LOCAL TO YOU, like the poses and the spray -- these are made on the client,
	so nobody else hears them.


	========================================================
	CARVING
	========================================================

	A turn is not one lean. Four things happen at once, and each has a setting:

	    MaxEdgeAngle      how far the SKIS roll onto their edges. The big one --
	                      it carries the whole look of a carve.

	    MaxLegTip         how far the LEGS lean over. Small, and it has to be.

	    MaxLeanAngle      how far the TORSO inclines. Also small, and less than
	                      the legs, which gives the bent-at-the-hip shape.

	    NeckCounterRoll   how much of that lean the head cancels, so you keep
	                      looking level instead of tipping your head over with
	                      your body. This is the difference between angulation
	                      and just falling sideways.

	    MaxCounterTwist   the upper body keeps facing down the hill while the
	                      legs turn underneath. The thing that makes a skier
	                      look like a skier rather than a plank pivoting.

	WHY MaxLegTip HAS TO STAY SMALL, even though a real skier's legs go right
	over: R6 has no knee and no ankle. Tipping a leg pivots the whole thing about
	the hip, so the foot swings through an arc rather than staying planted. At
	0.7 radians on a two-stud leg that is over a stud sideways, and the boot walks
	clean off the ski. A real leg absorbs all of that below the hip.

	So the skis carry the edge angle and the legs only suggest it. Push MaxLegTip
	past about 0.25 and you will watch the character step off its own skis.

	The gap between the legs and the torso is what gives you angulation: the
	upper body staying comparatively upright over legs that have gone over,
	visibly bent at the hip. Set them equal and you get a plank tipping sideways,
	which reads as falling rather than carving.

	IF THE TURN LOOKS RIGHT BUT MIRRORED, don't touch any of those four. Flip
	CarveDirection to -1 -- it negates all of them together.

	This layer is continuous and sits on top of whichever pose is active. The
	poses are fixed shapes you blend between; this follows the steering stick
	frame by frame.


	========================================================
	POLE PLANTS
	========================================================

	A skier taps the snow with the inside pole as each new turn begins. It's the
	rhythm you recognise a skier by from a distance, more than the turns are.

	    EnablePolePlants     off switch
	    PolePlantLean        how committed a turn has to be to earn one. Raise
	                           it and only proper carves get a plant
	    PolePlantCooldown    stops a wobble at speed becoming frantic tapping
	    PolePlantDuration    how long the arm is down
	    PolePlantReach       how far it swings, in radians

	Triggered by the lean crossing sides rather than by a timer, so plants land
	on your actual turns instead of metronoming through them. That also means
	they replicate for free: lean is already one of the values sent round, so
	other players plant poles with no extra plumbing.

	The default Animate script is left running the whole time. Animations write
	Motor6D.Transform, these poses write C0, and the engine applies BOTH -- so an
	idle or jump clip underneath layers on top of the ski stance rather than
	being replaced by it. The pose zeroes Transform each frame to cancel that.

	Worth knowing because the obvious alternative is a trap: stopping Animate's
	tracks and disabling the states it watches also stops the clips, but leaves
	Animate with nothing to wake it up afterwards, so the character stands frozen
	after unequipping until something forces a state change.

	Joint changes made on the client don't replicate, so a pose only exists on
	the screen of whoever set it. Other players are posed from replicated state
	instead -- see SEEING OTHER PLAYERS SKI above. Put an R6 animation id into
	SkiConfig.Animations and that slot switches to a real animation instead,
	which goes through the Animator and does replicate. Each of Stance, Carve,
	Tuck, Brake and Air can be swapped independently.


	========================================================
	TUNING: ReplicatedStorage.Ski.SkiConfig
	========================================================

	    LateralDrag           edge grip. TUNE THIS FIRST
	    ForwardDrag           along-ski friction, low so you keep speed
	    CarveRecovery         how much a clean turn pays you back
	    SlopeAccelGain        how hard steep ground bites
	    AirDrag               sets terminal speed
	    TuckDragMultiplier    how much a tuck is worth
	    SurfaceFriction       per-material grip, Terrain and parts alike
	    SlideEnterAccel       how steep before you start sliding
	    BrakeDecel            must beat the downhill pull on your steepest run
	    TurnRate              steering at a standstill
	    TurnSpeedFalloff      how much wider turns get at speed
	    JumpImpulse           launch speed along the ground normal
	    EquipGrace            settling-in time when you strap in: no jumping
	                            and no wiping out for this long
	    HoverHeight           ride height. Tied to SkiFootOffset -- see below
	    GroundClearance       gap under the skis. Raise if they clip on slope
	                            changes, 0 to sit flush
	    NormalSmoothing       raise if the skis jitter on Terrain
	    LandingCrashAngle     how sloppy a landing gets before you wipe out
	    CrashDuration         how long you're on the floor afterwards
	    MaxLeanAngle          how far you roll into a turn. Cosmetic
	    DebugLog              prints every state change to Output

	Any part can carry a number attribute "SkiFriction" to override its material.
	Lower is slipperier: 0.002 is ice, 0.005 snow, 0.14 rock, 0.30 near enough a
	stop.


	========================================================
	SNOW IS ALMOST FRICTIONLESS
	========================================================

	Snow, ice and glacier are tuned to give up almost nothing -- snow costs you
	about 1 stud/sec^2. You keep what you earn, and a long flat run-out barely
	slows you down.

	TWO THINGS FOLLOW FROM THAT.

	You will not coast to a stop any more. From full speed on the flat, friction
	alone needs well over a minute. Braking is how you stop now. If you would
	rather glide back to a halt on your own, snow around 0.03 does it.

	Top speed is now set almost entirely by AirDrag, since nothing else is
	taking much off you. If steep runs get faster than you can steer, raise
	AirDrag before you touch anything else -- it only bites at speed, so it
	caps the top end without making slow skiing feel sticky.

	ForwardDrag is the other half of this. It is a flat per-second drag that
	applies on every surface, and at the old 0.35 it was doing four times more
	braking at speed than snow was -- so which surface you were on hardly
	mattered. It is 0.05 now, which is what lets SurfaceFriction actually decide
	how a surface feels. Raise it if EVERYTHING is too slippery; use
	SurfaceFriction if it's one material.


	========================================================
	IF IT RIDES WRONG
	========================================================

	YOU SLIDE ON GROUND THAT SHOULD BE WALKABLE
	  Raise SlideEnterAccel. It's the downhill pull, in studs/sec^2, at which
	  walking becomes sliding -- 14 is about a 4 degree slope.

	YOU SLIDE STRAIGHT DOWNHILL INSTEAD OF HOLDING A TRAVERSE
	  LateralDrag is too low. This is the number that makes skis skis.

	THE SKIS JITTER ON SMOOTH TERRAIN
	  Terrain normals are noisy voxel data. Raise NormalSmoothing. If they then
	  feel late to follow the ground, you've gone too far.

	THE SKIS CLIP THROUGH THE GROUND
	  Raise GroundClearance. It is the deliberate gap between the ski bases and
	  the snow, measured from the lowest part of the ski with camber included,
	  and it exists to absorb the hover spring overshooting. HoverHeight alone
	  puts the skis flush, which leaves no room for that, and coming off a slope
	  onto the flat is where it happens.

	  If they clip EVERYWHERE rather than at transitions, suspect the geometry
	  instead: SkiCamber hangs the tip and tail below the waist, and the ski is
	  positioned by its waist. That relationship is worked out in SkiPose rather
	  than tuned, but it is the first place to look.

	  The ground is sampled at ONE point, under the boot, and that is on purpose.
	  Sampling along the ski and taking whichever came back closest looks like it
	  should help with exactly this, and it trades the problem for a worse one:
	  any higher ground near you starts lifting you, so you float up to meet a
	  slope before reaching it and hover permanently over uneven ground.

	YOU RIDE UP A BANK YOU SHOULD HAVE STOPPED AGAINST
	  MaxGroundAngle decides what counts as ground rather than wall. Lower it if
	  something steep is still being treated as rideable.

	BRAKING WON'T HOLD YOU ON A STEEP PITCH
	  BrakeDecel has to beat SlopeAccelGain * gravity * sin(slope). At the
	  defaults a 40 degree slope pulls about 69, so 95 holds it comfortably.

	THE CHARACTER FLOATS, OR THE SKIS SINK
	  HoverHeight, and it is not a free number: 3.0 works because R6's root sits
	  exactly 3 studs above the soles and SkiFootOffset already puts the ski
	  bases level with the soles. Move one and the other has to follow.

	YOU CATCH ON TERRAIN AND STOP DEAD
	  Arm and leg collisions are turned off while the sim is driving, and the
	  Torso is left collidable so trees and walls still stop you. If you're
	  catching on the GROUND rather than on objects, raise HoverHeight.

	"INFINITE YIELD POSSIBLE ON ..." IN OUTPUT
	  Something is looking for an instance that was never installed. Remotes fix
	  themselves, so this means one of the folders in the install list did not
	  make it -- check the tree above against what is actually in your game.

	  If it names something under Common, you almost certainly replaced that
	  folder instead of merging into it. Common is shared between packages: Ski
	  needs SpeedService, Variable Snowstorm needs CharacterCache, and both have
	  to be sitting in there together.

	YOU FLOAT AFTER A CRASH AND NEVER COME DOWN
	  Something left the gravity-cancelling force behind. While the sim drives,
	  a VectorForce called SkiGravityCancel holds up exactly your weight, and if
	  it outlives the sim you hang in the air with no way out. It is switched
	  off before the crash is even reported, destroyed on every exit path, and
	  swept for again on the way in -- so this should be impossible now. If it
	  ever happens again, look for SkiGravityCancel under HumanoidRootPart.

	YOU STICK IN PLACE WHEN YOU CRASH
	  Turn DebugLog on. A working wipeout prints "wiped out (5 joints limp)" and
	  then "back up" about CrashDuration later. If the first line says 0 joints,
	  the rig is not R6. If the second never appears, recovery is failing and
	  there will be a warning next to it.


	========================================================
	SPEED MODIFIERS
	========================================================

	SpeedService is the only thing allowed to assign Humanoid.WalkSpeed. The
	skis register as a modifier named "Ski", so sprinting, weather and skis all
	stack instead of overwriting each other:

	    final = base * (all multipliers) + (all additions)

	The penalty applies only while the skis are on your feet. Carrying them on
	your back walks at normal speed.

	Runs happily alongside Variable Snowstorm -- both use this same file, so a
	blizzard and a pair of skis multiply together rather than one winning.

]]

return nil

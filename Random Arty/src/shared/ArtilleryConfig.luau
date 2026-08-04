--[[
	ArtilleryConfig
	Every tunable number for the barrage lives here so you never have to dig
	through the server or client logic to retune the look and feel.

	Shared between server and client, so both sides always agree on thresholds.
]]

local ArtilleryConfig = {}

-- ============================================================
-- BARRAGE CYCLE  (server only)
-- ============================================================

ArtilleryConfig.Enabled = true

-- Seconds between barrages. A random value inside the range is rolled every
-- time one ends, so shelling never becomes something you can set a watch by.
ArtilleryConfig.BarrageInterval = NumberRange.new(120, 300)

-- Shells per barrage. Centaura runs "over a dozen" and that is the number that
-- makes a barrage read as a barrage rather than a few stray hits.
ArtilleryConfig.ShellsPerBarrage = NumberRange.new(15, 25)

-- Seconds between one shell launching and the next. Small values land the
-- barrage almost at once; large values walk it across the ground.
ArtilleryConfig.ShellSpacing = NumberRange.new(0.2, 1)

--[[
	Seconds of audible warning before the first shell lands. THIS IS THE
	MECHANIC, not decoration -- it is the only reason a barrage is survivable.

	Your real reaction time is this PLUS ShellFlightTime, because the shells are
	visible arcing in for the whole flight. At 12 + 6.5 that is eighteen-odd
	seconds between the guns going off and the first crater, which is enough to
	cross open ground and get behind something.

	Under about 4 nobody reaches cover at all and the whole thing reads as
	arbitrary rather than dangerous.
]]
ArtilleryConfig.BarrageWarningLead = 12

--[[
	Players below this count skip the barrage entirely. Shelling an empty server
	is wasted work, and shelling a single person is just bullying.

	THIS IS THE #1 REASON BARRAGES "ONLY WORK VIA DEBUG". DebugBarrageNow does
	not check this at all -- it always fires -- so testing solo or with a small
	group makes the natural timer look broken when it is just never satisfied.
	The natural loop now logs when it skips a cycle for this reason (DebugLog),
	so check Output before assuming it is not running.

	Set to 1 while testing alone.
]]
ArtilleryConfig.MinPlayersForBarrage = 4

-- ============================================================
-- TARGETING  (server only)
-- ============================================================

-- Players within this of each other count as a cluster. The barrage epicenter
-- is picked weighted by cluster size, so crowds draw fire the way they do in
-- Centaura -- but a lone player is never immune, just less likely.
ArtilleryConfig.ClusterRadius = 120

-- How far the epicenter is thrown off the player it was picked from. Keep this
-- comfortably larger than KillRadius or the barrage stops reading as area
-- denial and starts reading as the game sniping one specific person.
ArtilleryConfig.EpicenterJitter = 40

-- How wide the shells scatter around that epicenter.
ArtilleryConfig.ShellScatterRadius = 90

-- Exponent on the scatter roll. 0.5 spreads shells evenly across the disc,
-- lower packs them toward the middle. 0.7 gives a dense center with stragglers.
ArtilleryConfig.ScatterCenterBias = 0.7

-- Impacts are snapped to whatever surface is under them. This is how far up the
-- snap ray starts -- it has to clear the tallest thing on your map or shells
-- will detonate inside rooftops.
ArtilleryConfig.GroundSnapHeight = 2000

-- How far below the epicenter the snap ray is allowed to find ground. Stops a
-- shell aimed at a rooftop from tunnelling to the terrain hundreds of studs
-- below and detonating out of sight.
ArtilleryConfig.GroundSnapDepth = 400

-- Parts tagged with this (CollectionService) are never shelled. Tag your spawn
-- areas. Rerolled impacts fall back to the epicenter if every roll lands in a
-- safe zone, so an over-tagged map quietly loses its artillery rather than
-- hanging.
ArtilleryConfig.SafeZoneTag = "ArtillerySafeZone"

-- How many times a single shell retries before giving up on avoiding a safe
-- zone and simply being skipped.
ArtilleryConfig.SafeZoneRetries = 6

--[[
	PLAYERS UNDER A ROOF ARE NOT AIMED AT.

	A battery a kilometre away cannot see through a bunker, so a player indoors
	is dropped from the list the epicenter is picked from -- and stops counting
	toward anyone else's cluster weight along with it.

	THIS IS NOT A SHIELD, and the difference matters. It only decides where the
	guns AIM. A shell aimed at the squad outside your door still lands outside
	your door, and the blast that follows does not care what you are standing
	under -- the roof only helps you there through the damage cover check, which
	is a separate thing further down and does not apply in the kill sphere at
	all.

	If every player is indoors the barrage is skipped and logged, rather than
	falling back to shelling someone anyway.
]]
ArtilleryConfig.SkipShelteredPlayers = true

-- How far up the shelter rays look for a roof. It only has to clear the tallest
-- interior on your map -- not the sky -- so this can stay well under
-- GroundSnapHeight.
ArtilleryConfig.ShelterCheckHeight = 300

-- How far out the four side rays are cast from the player. Roughly a doorway's
-- width: wide enough that standing in an opening is not read as being inside,
-- narrow enough that being properly indoors still registers.
ArtilleryConfig.ShelterSampleRadius = 6

-- What fraction of the five rays must be blocked to count as sheltered. 0.5 is
-- three of five. Raise it toward 1 to only spare players fully enclosed; lower
-- it to spare anyone under any overhang at all.
ArtilleryConfig.ShelterBlockedThreshold = 0.5

-- ============================================================
-- TRAJECTORY  (shared -- both sides must agree or visuals miss the crater)
-- ============================================================

-- Seconds from launch to impact. Also how long the trail is visible arcing
-- overhead and how long you have to watch it coming, so it is the main knob on
-- both the look and how fair the whole thing feels.
ArtilleryConfig.ShellFlightTime = NumberRange.new(5, 7)

--[[
	Downward acceleration on the shell, studs/sec^2. NOT workspace.Gravity and
	it does not have to match it -- the shell is drawn, never simulated.

	CHANGE THIS WHENEVER YOU CHANGE ShellFlightTime. The launch velocity is
	SOLVED so the shell lands exactly on target, and its upward component works
	out to roughly 0.5 * gravity * flightTime. Double the flight time at fixed
	gravity and the shell is fired twice as hard upward -- it climbs out of
	sight and drops back in, instead of arcing.

	To keep the same arc SHAPE at a new flight time, scale gravity by the
	inverse square of the change: going from 3.8s to 7.25s is 1.9x longer, so
	gravity drops by 1.9^2 -- from 180 to about 50.
]]
ArtilleryConfig.ShellGravity = 20

-- Where the shell comes from, relative to its impact point: this far
-- horizontally, back along the battery heading.
ArtilleryConfig.ShellLaunchDistance = NumberRange.new(900, 1300)

-- ...and this far up. Together with flight time and gravity these decide the
-- apex. Raise it for a steeper, more vertical plunge.
ArtilleryConfig.ShellLaunchHeight = NumberRange.new(550, 800)

-- Compass heading the guns fire from, in degrees. Every shell in one barrage
-- shares it, so the trails arc in roughly parallel -- that is what makes it
-- read as guns at a position rather than random junk falling out of the sky.
ArtilleryConfig.BatteryHeading = 45

-- Set true to roll a fresh heading per barrage instead of using the fixed one
-- above. Good for maps with no established frontline.
ArtilleryConfig.RandomBatteryHeading = false

-- Per-shell wobble on that heading, degrees. Zero makes the trails perfectly
-- parallel, which looks artificial.
ArtilleryConfig.BatteryHeadingSpread = 15

-- ============================================================
-- SHELL LOOK  (client only)
-- ============================================================

ArtilleryConfig.ShellSize = Vector3.new(0.8, 0.8, 2.4)
ArtilleryConfig.ShellColor = Color3.fromRGB(255, 176, 92)

-- Seconds of trail left behind the shell. This is the single biggest knob on
-- the effect: it sets how much of the arc is on screen at once. Long lifetimes
-- draw a streak across the whole sky, short ones a comet.
ArtilleryConfig.TrailLifetime = 1.2

ArtilleryConfig.TrailWidth = 2.4

-- Head and tail colors of the streak.
ArtilleryConfig.TrailColor = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 190)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 148, 48)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 30, 10)),
})

-- LightEmission is what makes the trail glow without costing a light source.
-- 1 means it ignores the scene's lighting entirely and always reads bright,
-- which is what you want for something seen against a dark or foggy sky.
ArtilleryConfig.TrailLightEmission = 1

-- Optional streak texture. Empty uses Roblox's default flat trail, which is
-- already fine. A soft horizontal gradient reads better if you have one.
ArtilleryConfig.TrailTexture = ""
ArtilleryConfig.TrailTextureLength = 3

-- Hard cap on shells drawn at once. Extra shells still damage on the server,
-- they just are not rendered. Live trail segments scale with this, so it is the
-- main client performance knob.
--
-- Has to cover a whole barrage now: at a 7-second flight and ShellSpacing
-- averaging under half a second, twenty shells are launched inside the time the
-- first one is still in the air, so nearly all of them overlap. Set this below
-- ShellsPerBarrage.Max and the tail of every barrage arrives unannounced with
-- no trail to watch.
ArtilleryConfig.MaxRenderedShells = 32

-- Shells landing further than this are not drawn at all. Deliberately huge:
-- watching a barrage arc down onto someone else's position across the map is
-- most of the point, so this should exceed your map's diagonal.
ArtilleryConfig.ShellRenderDistance = 10000

-- Smoke puffs trailing the shell. Cheap, but it is per-shell, so it multiplies.
ArtilleryConfig.EnableShellSmoke = true
ArtilleryConfig.ShellSmokeRate = 24

-- ============================================================
-- IMPACT LOOK  (client only)
-- ============================================================

-- Impacts further than this draw no particles. Unlike the trail, debris and
-- dust are invisible at range anyway, so there is nothing to gain by drawing
-- them.
ArtilleryConfig.ImpactEffectDistance = 900

--[[
	THE THREE STAGES

	An impact is a sequence, not one burst. Everything firing on the same frame
	is what makes an explosion read as a single flat pop instead of something
	violent happening to the ground.

	    0.00s   DUST     a cloud appearing over the crater and opening out
	    0.04s   DEBRIS   the ground thrown out
	    0.22s   SMOKE    what is left hanging over it

	These are the delays for the second and third. Small numbers -- the gap only
	has to be long enough to read as an order of events.
]]
ArtilleryConfig.ImpactDebrisDelay = 0.04
ArtilleryConfig.ImpactSmokeDelay = 0.22

--[[
	============ [STAGE 1] DUST ============

	ONE flat image per crater, not particles and not a field of geometry --
	both were tried, and both read as many separate pieces instead of one cloud.
	It grows and sinks over its life instead of sitting static, which is what
	actually reads as dust settling rather than a stain appearing on the ground.

	IT NEEDS AN IMAGE, and it is the only impact effect left that does. If dust
	is missing entirely, it is this texture -- see the note at DustDecalTexture.
]]
ArtilleryConfig.EnableDustDecal = true
ArtilleryConfig.DustDecalTexture = "rbxassetid://14688493591"

-- Ceiling on how many can exist across a whole barrage at once. A dozen-plus
-- shells landing inside a few seconds could otherwise stack a dozen-plus of
-- these; excess impacts simply draw no dust rather than pushing the count up
-- further.
ArtilleryConfig.MaxLiveDust = 24

-- How big the image is at the moment it appears, and what it grows to, studs
-- across. Both rolled once per impact. THE GAP BETWEEN THEM IS THE EFFECT --
-- a cloud that does not visibly open out just looks like a mark that faded in.
ArtilleryConfig.DustDecalStartSize = NumberRange.new(14, 20)
ArtilleryConfig.DustDecalEndSize = NumberRange.new(52, 78)

-- Shape of the growth over the cloud's life. 1 is linear. Below 1 (0.5 here)
-- most of the growth happens immediately and the rest is a slow creep -- the
-- punch of the burst followed by the drift of settling dust. Above 1 would
-- start slow and accelerate, which reads backwards.
ArtilleryConfig.DustDecalGrowthCurve = 0.5

-- Studs above the surface at birth, and where it ends up. THIS IS THE SINK --
-- the image visibly settling down onto the ground is as much the effect as the
-- growth is. EndHeight stays just off zero so the image never sits exactly on
-- the surface it is lying on, which would flicker (z-fighting).
ArtilleryConfig.DustDecalStartHeight = 4
ArtilleryConfig.DustDecalEndHeight = 0.08

-- Degrees/sec the cloud slowly turns, direction rolled per impact. Not enough
-- to read as spinning -- enough that the mass appears to churn rather than
-- scale in place.
ArtilleryConfig.DustDecalSpin = 4

-- Seconds fully visible before it starts fading, then how long the fade itself
-- takes. Growth and sink run across BOTH added together; the hold is what
-- makes it read as a cloud hanging there rather than a flash.
ArtilleryConfig.DustDecalHoldTime = 1.4
ArtilleryConfig.DustDecalFadeTime = 2.8

-- Starting transparency. 0 is fully opaque. Above 0 lets a little of whatever
-- is under it show through immediately, which can read as a thinner cloud.
ArtilleryConfig.DustDecalStartTransparency = 0.1

-- How far the image colour is pulled toward black, after the surface tint.
-- Airborne dust does not go as dark as thrown debris -- see DebrisDarken.
ArtilleryConfig.DustDecalDarken = 0.2

-- A brief light at the crater. No visible ball, but it lifts the scene for a
-- moment, which is most of what sells a detonation on a dark map. False if you
-- want the impact entirely unlit.
ArtilleryConfig.EnableImpactLight = true
ArtilleryConfig.ImpactLightBrightness = 5
ArtilleryConfig.ImpactLightRange = 60

-- Seconds the emitter host lives before cleanup. Has to outlast the longest
-- stage delay plus the longest particle lifetime under it, or the tail of the
-- smoke is cut off in mid-air.
ArtilleryConfig.ImpactEffectLifetime = 10

-- ============ [STAGE 2] DEBRIS ============
-- Nothing is left behind. A shell throws the ground up and that is all -- no
-- decal, no scorch, no part of any kind still sitting there afterwards.

-- Colour the debris from whatever the shell actually landed on: one downward
-- raycast at the crater, then the part's Color, or Terrain:GetMaterialColor for
-- terrain. Snow throws white, mud throws brown, and nothing has to be authored.
ArtilleryConfig.DebrisMatchSurface = true

-- Used when the raycast finds nothing, or when DebrisMatchSurface is off.
ArtilleryConfig.DebrisFallbackColor = Color3.fromRGB(92, 76, 58)

--[[
	Two separate throws. The plume goes up and comes back down; the splash is
	the low, wide sheet that fans out across the ground.

	THREE THINGS SET THE RADIUS, and they fight each other:

	    Speed      how hard it is thrown
	    Lifetime   how long it has to travel before it vanishes
	    Gravity    how fast it is dragged down out of the air

	Reach is roughly speed x lifetime, but only if gravity lets it stay up that
	long. Winding speed up on its own just makes chunks disappear mid-flight,
	because they die at Lifetime no matter where they are. To go WIDER, raise
	lifetime and LOWER gravity. To go more violent without going wider, raise
	speed and gravity together.
]]
--[[
	DEBRIS IS REAL PARTS, NOT PARTICLES.

	Sprites depend on a texture asset, and every way that can go wrong fails
	silently and identically -- a moderated id, a decal id where an image id was
	needed, no texture at all (which falls back to Roblox's white sparkle). None
	of it prints anything, so you get glitter or nothing and no way to tell which
	knob is at fault.

	A Part has a size, a colour and a position. It renders, full stop, and if it
	ends up somewhere wrong you can see exactly where it went.

	They are Anchored and moved by hand each frame -- nothing under the Camera is
	physically simulated. Reach is therefore exactly predictable from the numbers
	below instead of depending on collisions.
]]
ArtilleryConfig.EnableDebrisChunks = true

-- Chunks thrown per shell. The main density knob, and the main cost -- this
-- many parts are created, animated and destroyed per impact.
ArtilleryConfig.ChunkCount = 46

-- Ceiling across ALL live chunks at once. A barrage is a dozen-plus shells
-- landing within a few seconds, so without this a heavy one could put well over
-- a thousand parts on screen. Bursts over budget are trimmed, not queued.
ArtilleryConfig.MaxLiveChunks = 400

-- Each chunk rolls its own size in here. A wide range matters more to the look
-- than the numbers do: chunks all one size read as a repeated prop, while big
-- lumps mixed with small grit read as ground.
ArtilleryConfig.ChunkSize = NumberRange.new(0.5, 2.6)

-- Random stretch on the other two axes, so chunks are uneven boxes. Cubes read
-- as voxels; irregular ones read as rubble.
ArtilleryConfig.ChunkAspect = NumberRange.new(0.45, 1.4)

ArtilleryConfig.ChunkMaterial = Enum.Material.Slate

--[[
	THE SPEED RANGE MUST START LOW. This is the one that bites.

	Every chunk rolls its own speed inside the range. Set the MINIMUM high --
	say 200 -- and nothing travels slower than that, so within half a second the
	whole burst is hundreds of studs away and there is a visible HOLE where the
	explosion just was. It reads as "the debris disappeared".

	A wide range starting low gives the real thing: a dense pile of material at
	the crater thinning out to chunks arcing away to the edges. Look at any
	explosion photo -- that gradient is the whole look.
]]
ArtilleryConfig.ChunkSpeed = NumberRange.new(25, 190)

-- Seconds before a chunk vanishes if it has not already landed.
ArtilleryConfig.ChunkLifetime = NumberRange.new(1.2, 2.6)

-- Downward acceleration, studs/sec^2. Lower keeps chunks airborne longer and
-- therefore throws them WIDER; this and ChunkSpeed together set the radius.
ArtilleryConfig.ChunkGravity = 95

-- Angle above horizontal that chunks are thrown at, in degrees. This one range
-- replaces the old plume/splash split: low angles skim out across the ground,
-- high angles go up and come back down, and rolling across the whole span every
-- time gives you both out of one throw.
ArtilleryConfig.ChunkElevation = NumberRange.new(8, 80)

-- How hard chunks tumble, radians/sec.
ArtilleryConfig.ChunkSpin = 14

--[[
	How far the debris colour is pulled toward black, after the surface tint.

	Thrown earth is shadowed and reads nearly as a silhouette against the sky --
	look at any real explosion photo and the chunks are almost black. Taking the
	surface colour raw means snow throws BRIGHT WHITE specks, which is the other
	half of why an impact can look like sparkles rather than dirt.

	0 keeps the surface colour exactly. 1 throws pure black chunks.
]]
ArtilleryConfig.DebrisDarken = 0.55

-- ============ [STAGE 3] SMOKE ============
-- What hangs over the crater once the ground has come back down.

ArtilleryConfig.ImpactSmokeSize = NumberRange.new(80,120)
ArtilleryConfig.ImpactSmokeCount = 60
ArtilleryConfig.ImpactSmokeLifetime = NumberRange.new(5, 9)
ArtilleryConfig.ImpactSmokeColor = Color3.fromRGB(74, 68, 62)

-- How fast the cloud climbs. Small positive values only -- smoke that races
-- upward reads as rocket exhaust rather than something settling.
ArtilleryConfig.ImpactSmokeRise = 1

--[[
	The smoke image, and the fallback for the ground dust decal. Smoke is now the
	LAST sprite in the system -- debris and the dust wave are both geometry -- so
	this one slot carries all the asset risk that both of those used to.

	IT SHIPS AS AN ENGINE PATH, NOT AN ID, ON PURPOSE. An engine path cannot be
	moderated, cannot be a decal id by mistake, and renders on every client with
	no upload. Ids kept going in here and kept coming out invisible. Put your own
	back if you have one that works -- but if the smoke or the ground mark ever
	vanishes again, put this line back first and you have your answer in one
	playtest.

	NEVER LEAVE IT EMPTY. A ParticleEmitter with no Texture falls back to
	Roblox's default, which is a WHITE SPARKLE.

	TWO FORMS ARE VALID, and mixing them is the classic mistake:

	    rbxassetid://13623094740                       an uploaded image
	    rbxasset://textures/particles/smoke_main.dds   an engine file

	"rbxasset://13623094740" is NEITHER -- it asks the engine for a file named
	after a number, finds nothing, and renders blank with no error. The config
	repairs that case rather than passing it through, but it is worth knowing
	because every other system you paste an id into will not.

	ImpactSmokeColor tints whatever you give it, so greyscale takes the tint
	cleanly. The engine path above is a safe fallback that can never be
	moderated away.
]]
ArtilleryConfig.SmokeTexture = "rbxasset://textures/particles/smoke_main.dds"

-- ============================================================
-- AUDIO  (client only)
-- ============================================================

ArtilleryConfig.EnableAudio = true

-- All four ship empty. Roblox audio is private by default, so an id lifted from
-- another game is silent here with no error at all -- upload or source your
-- own. Any left empty simply does not play, and the system warns once.
--
-- BatteryReport   distant thump of the guns firing, the warning
-- ShellWhistle    the incoming scream, looped, rides on the shell itself
-- ImpactNear      sharp crack for shells landing close
-- ImpactFar       hollow crump for shells landing at distance
ArtilleryConfig.BatteryReportSoundId = "rbxassetid://8261242927"
ArtilleryConfig.ShellWhistleSoundId = "rbxassetid://108749998594946"
ArtilleryConfig.ImpactNearSoundId = "rbxassetid://73652976704676"
ArtilleryConfig.ImpactFarSoundId = "rbxassetid://94838292975473"

ArtilleryConfig.BatteryReportVolume = 1.1

-- The whistle is parented to the moving shell part, so Roblox's own 3D audio
-- handles panning and falloff -- the rise as it bears down on you is free.
ArtilleryConfig.WhistleVolume = 1.3
ArtilleryConfig.WhistleRollOffMax = 10000

-- Playback speed at launch and at impact. The climb is what makes an incoming
-- shell feel like it is coming for you specifically.
ArtilleryConfig.WhistlePitchStart = 0.6
ArtilleryConfig.WhistlePitchEnd = 1.35

-- Whistle only becomes audible in the last stretch of flight, as a fraction of
-- total flight time. 0.6 means you hear it for the last 40% of the descent --
-- about 3 seconds at the current flight time, which is a scream you can place
-- and react to. Lower it and the whistle runs so long it stops reading as
-- something incoming and turns into ambience.
ArtilleryConfig.WhistleAudibleFrom = 0.1

ArtilleryConfig.ImpactVolume = 2

-- Past this distance an impact is inaudible and no sound is scheduled.
ArtilleryConfig.ImpactAudibleDistance = 4000

-- Crossover between the near crack and the far crump.
ArtilleryConfig.ImpactNearDistance = 250

-- Studs/sec used to delay the boom by distance, the way real gunfire lags. The
-- flash always arrives first. Lower stretches the gap.
ArtilleryConfig.SoundSpeed = 340

-- Ceiling on overlapping impact sounds. Past this, extra ones are dropped
-- rather than layering into mud -- and a barrage will absolutely try to layer
-- twenty of them.
ArtilleryConfig.MaxConcurrentSounds = 15

-- ============================================================
-- CAMERA SHAKE  (client only)
-- ============================================================

ArtilleryConfig.EnableCameraShake = true

-- Shake at the crater, in studs and degrees. Falls off to nothing at
-- ShakeDistance.
ArtilleryConfig.ShakeTranslation = 2.2
ArtilleryConfig.ShakeRotation = 1.6
ArtilleryConfig.ShakeDistance = 500

-- How fast the shake dies, per second. Higher is a sharper jolt.
ArtilleryConfig.ShakeDecay = 3.2

-- How fast the camera jitters. Too low reads as a drunk camera rather than a
-- concussion.
ArtilleryConfig.ShakeFrequency = 28

-- A wash of dust across the screen on close hits, drawn as a ScreenGui so it
-- adds nothing to Workspace. Peak opacity at the crater; 0 turns it off.
ArtilleryConfig.ShakeDustStrength = 0.4
ArtilleryConfig.ShakeDustColor = Color3.fromRGB(148, 132, 108)

-- ============================================================
-- DAMAGE  (server only -- must be, or clients could ignore it)
-- ============================================================

--[[
	THE ONION

	Four spheres around the crater, each one wholly inside the next. A victim is
	measured once, lands in exactly one layer, and that layer decides everything.

	    1  KillRadius        18   dead. Always. No exceptions.
	    2  DismemberRadius   34   damage, and limbs come off
	    3  DamageRadius      46   damage only
	    4  ConcussionRadius  70   dazed, no damage

	These MUST be in ascending order. Out of order, an inner sphere swallows an
	outer one and that band simply never happens -- the server checks at startup
	and warns rather than leaving you to work it out from behaviour.

	LAYER 1 IS PURE DISTANCE. Nothing modifies it: not cover, not a wall, not a
	bunker roof. If the shell lands within KillRadius of you, you are dead. Cover
	only scales the damage in layers 2 and 3.
]]

--[[
	How much the VERTICAL gap counts when measuring distance to a victim.

	1 is a true sphere -- and a true sphere is why a shell can land six studs in
	front of you on a slope and leave you standing. Height spends exactly the
	same radius budget as horizontal distance, so a 25-stud drop turns a 6-stud
	miss into a 28-stud one, which is out past the damage radius entirely.

	Below 1 the blast becomes a flattened, ground-hugging ellipsoid: it reaches
	up and down slopes, ledges and stairwells, while staying honest about how far
	it goes ACROSS the ground. At 0.6 that same shell measures 17.8 and kills.

	Raise it toward 1 if your map is flat and you want strict spherical falloff.
	Do not go to 0 -- the blast would then reach infinitely far vertically and
	shell people through floors.
]]
ArtilleryConfig.BlastVerticalScale = 0.6

-- Layer 1: inside this you die, always, and always come apart.
ArtilleryConfig.KillRadius = 22

-- Layer 2: falloff damage, and limbs are torn off -- off a corpse if it killed
-- you, off you if it did not. Must sit between KillRadius and DamageRadius.
ArtilleryConfig.DismemberRadius = 30

-- Layer 3: falloff damage only. Damage falls off from the KILL radius out to
-- here, so layer 2 is the punishing half of the same curve.
ArtilleryConfig.DamageRadius = 67

--[[
	Damage at the edge of the kill radius, falling to 0 at DamageRadius.

	KEEP THIS COMFORTABLY ABOVE A FULL HEALTH BAR. Setting it TO full health --
	100, the obvious-looking choice -- means a healthy player can never quite die
	outside the kill sphere: at one tenth of a stud past the boundary the curve
	deals 99.3, and they walk away on 1 HP. The only thing that decides whether a
	layer-2 hit kills is then how chewed-down they already were, which is
	invisible from inside the game and reads as pure randomness.

	It also puts a cliff on the boundary itself: dead and in pieces at 18.0
	studs, alive at 18.1.

	At 165 the curve stays lethal out to about 24 studs and then grades off, so
	the kill sphere has a margin around it instead of an edge:

	    18-24   dead
	    26      survives on ~16 HP
	    30      survives on ~46 HP
	    34      survives on ~70 HP
	    46      untouched
]]
ArtilleryConfig.MaxFalloffDamage = 180

-- Exponent on the falloff. 2 is the physical inverse-square feel; 1 is linear
-- and far more punishing at the edges.
ArtilleryConfig.FalloffExponent = 1.9

--[[
	Walls work IN LAYERS 2 AND 3 ONLY. The kill sphere ignores cover entirely --
	see the onion note above.

	Cover is SAMPLED, not switched: three rays go from the crater to the victim's
	head, torso and legs, and the damage scales by how many of them are blocked.
	A single ray to one point is a coin flip at any partial cover -- shuffle a
	stud sideways and the whole hit swings between full damage and a quarter of
	it, with nothing in between. Multiplier at full cover:
]]
ArtilleryConfig.EnableCoverCheck = true
ArtilleryConfig.CoverDamageReduction = 0.4

-- How far the cover ray is lifted off the ground before it is cast.
--
-- Impact points come from a downward raycast, so they sit EXACTLY on the
-- surface. A ray starting there hits the floor it is standing on immediately
-- and every shell in the open reads as fully covered -- which caps damage at
-- MaxFalloffDamage * CoverDamageReduction and stops artillery killing anyone.
-- Must stay above zero. Raise it if your ground is bumpy.
ArtilleryConfig.CoverRayLift = 3

-- Non-player humanoids (NPCs, mobs) take blast damage, concussion and
-- dismemberment on exactly the same terms players do.
--
-- Costs one spatial query per impact, which is nothing at a dozen shells every
-- couple of minutes. Turn it off if your map genuinely has no NPCs -- the query
-- still runs and still walks whatever it returns.
ArtilleryConfig.AffectNPCs = true

-- Blast also throws ragdolls and loose parts around. Purely physical.
ArtilleryConfig.BlastImpulse = 250

-- ============================================================
-- CONCUSSION  (server only)
-- ============================================================

-- Survivors near a blast are dazed for a moment. Goes through SpeedService, so
-- it composes with sprint and the snowstorm's own penalty instead of fighting
-- them.
ArtilleryConfig.EnableConcussion = true

ArtilleryConfig.ConcussionRadius = 70
ArtilleryConfig.ConcussionDuration = 4
ArtilleryConfig.ConcussionSpeedMultiplier = 0.55
ArtilleryConfig.ConcussionJumpMultiplier = 0.6

-- ============================================================
-- GORE  (server only)
-- ============================================================

-- Master switch. False turns every artillery kill into an ordinary death with
-- no limbs severed and no ragdoll -- the rest of the system is unaffected.
ArtilleryConfig.EnableGore = true

-- R6 ONLY. R15 characters take damage normally and skip dismemberment with a
-- warning, because the joint names below do not exist on them.
--
-- How many limbs come off. A direct hit takes the high end, the edge of the
-- kill radius the low end.
ArtilleryConfig.MinLimbsSevered = 1
ArtilleryConfig.MaxLimbsSevered = 4

-- A kill out in layer 3 -- past DismemberRadius -- normally dies intact, which
-- is what makes the onion readable: you can tell which layer caught someone by
-- what is left of them.
--
-- True instead makes EVERY artillery kill come apart at any distance, which is
-- what Centaura itself does. It costs you the visual distinction.
ArtilleryConfig.DismemberOnAnyKill = true

-- ---- Layer 2 survivors ----
--
-- Shrapnel from a shell that only wounded you still takes an arm. Bounded by
-- DismemberRadius up in the DAMAGE section, so surviving a near miss is not the
-- same as walking away from it.
ArtilleryConfig.EnableMaiming = true

-- Odds at the kill sphere's edge, falling to zero at DismemberRadius. 1 maims
-- every survivor in the layer.
ArtilleryConfig.MaimChance = 0.65

ArtilleryConfig.MaxLimbsMaimed = 2

-- Legs are excluded by default. An R6 Humanoid works out how high to stand from
-- its leg parts, so a living character with none hovers and walks oddly -- fine
-- on a corpse, bad on someone still playing. Arms are purely cosmetic to lose.
ArtilleryConfig.MaimIncludesLegs = false

-- Cover stops maiming outright rather than scaling it down: a wall either
-- caught the shrapnel or it did not.

-- How hard severed limbs are thrown from the crater.
ArtilleryConfig.LimbFlingSpeed = NumberRange.new(45, 95)
ArtilleryConfig.LimbSpin = 18

-- Seconds before severed limbs clean themselves up.
ArtilleryConfig.GoreLifetime = 20

--[[
	Seconds before the ragdolled corpse itself is force-removed, regardless of
	anything else. Above 0, this is a hard cap that fires no matter what.

	AT 0 THIS IS NOT "OFF" -- corpses still get cleaned up, just by a different
	mechanism. A player's corpse is destroyed the instant they respawn
	(CharacterAdded), or immediately if they leave first, because Roblox never
	does this on its own: respawning only points player.Character at a new
	Model, and the old corpse sits in Workspace untouched forever unless
	something destroys it. That used to be nothing, at any value of this
	setting including a positive one that was never actually reached in
	testing -- which is the whole reason corpses were piling up regardless of
	what this said.

	NPCs cannot respawn, so 0 here falls back to GoreLifetime for them instead
	of leaving them permanently in the world -- they would otherwise have no
	exit at all.

	Raise this above 0 if you want a corpse to keep lying there for a while
	even after the player who died has already respawned and moved on.
]]
ArtilleryConfig.CorpseLifetime = 10

-- Exposed bone in the socket, the way Centaura does it. A small white cylinder
-- welded into the stump -- no asset needed.
ArtilleryConfig.ShowStumps = true
ArtilleryConfig.StumpColor = Color3.fromRGB(232, 226, 208)

-- Blood spray from the stump. Turn off for a cleaner rating.
ArtilleryConfig.EnableBlood = true
ArtilleryConfig.BloodColor = Color3.fromRGB(112, 12, 12)

-- ============================================================
-- DEBUG
-- ============================================================

-- Prints the whole barrage lifecycle to Output, server and client.
ArtilleryConfig.DebugLog = true

-- Drops a marker at every chosen impact point as the barrage is scheduled, so
-- you can watch targeting without standing in it. Markers clear on impact.
ArtilleryConfig.DebugDrawImpacts = false

-- Seconds until the very first barrage after the server starts. Set low while
-- tuning so you are not waiting out BarrageInterval every playtest. Negative
-- uses the normal interval.
ArtilleryConfig.DebugFirstBarrageDelay = -1

return table.freeze(ArtilleryConfig)

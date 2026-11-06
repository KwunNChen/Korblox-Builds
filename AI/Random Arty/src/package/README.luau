--[[

	GIVE CREDIT TO PLAGUEBYTE!!!!! @pb6008 for any inquiries

	RANDOM ARTILLERY

	Barrages fall on wherever the players are. You hear the guns fire, you get a
	few seconds, then a dozen-odd shells arc in and anything caught in the open
	comes apart.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder in step 5.


	========================================================
	INSTALL
	========================================================

	1. Drag RandomArtillery.rbxm into ServerStorage. This creates a RandomArtillery
	   folder containing all the pieces. ServerStorage is temporary: nothing
	   runs there, which is the point. Put the .rbxm anywhere else and the server
	   scripts start running before the shared modules are loaded. Everything
	   crashes.

	2. Move three folders from RandomArtillery/ReplicatedStorage/ into the real
	   ReplicatedStorage:

	       Artillery
	       ArtilleryState
	       ArtilleryShell

	   Miss ArtilleryShell and artillery disables itself with a warning in
	   Output.

	3. Move two folders from RandomArtillery/ServerScriptService/ into the real
	   ServerScriptService:

	       Artillery
	       Common

	   If your game already has a Common folder (Variable Snowstorm, Ski, etc.),
	   open the .rbxm's Common instead and drag CharacterCache and SpeedService
	   into your existing folder rather than replacing it. They are the same
	   files.

	4. Move the Artillery folder from RandomArtillery/StarterPlayerScripts/ into:

	       StarterPlayer > StarterPlayerScripts

	   Don't skip this. It's the half that draws the shells. Miss it and barrages
	   still land and still kill people, but nothing appears in the sky and
	   there's no warning sound. That looks and plays exactly like a broken
	   install.

	5. Delete the now-empty RandomArtillery folder from ServerStorage.

	Press Play. From here, the only thing you edit is
	ReplicatedStorage.Artillery.ArtilleryConfig.


	WHEN YOU'RE DONE

	    ReplicatedStorage
	    |-- Artillery            ArtilleryConfig, ArtilleryShared
	    |-- ArtilleryState       replicated attributes
	    +-- ArtilleryShell       RemoteEvent, one packet per shell

	    ServerScriptService
	    |-- Artillery            BarrageService, ImpactService, Dismember,
	    |                        ArtilleryRuntime
	    +-- Common               CharacterCache, SpeedService

	    StarterPlayer/StarterPlayerScripts
	    +-- Artillery            ArtilleryClient, ShellRender, DebrisChunks,
	                             DustCloud, ArtilleryAudio, ArtilleryShake

	Press Play. The first barrage lands within a few minutes.


	========================================================
	DAMAGE BANDS
	========================================================

	Measured from the crater to the victim's HumanoidRootPart.

	Four spheres, each wholly inside the next. You land in exactly one, and that
	layer decides everything.

	    1  within 18    DEAD. ALWAYS. Full dismemberment
	    2  within 34    damage, and limbs come off
	    3  within 46    damage only. A kill here dies intact
	    4  within 70    dazed for a few seconds, no damage

	LAYER 1 IS PURE DISTANCE. No cover, no walls, no bunker roof: a shell that
	lands on top of you is not survivable by standing behind something. Cover
	only scales damage in layers 2 and 3.

	Layer 3 kills dying intact is what makes the onion readable: what is left of
	a body tells you which layer caught them. DismemberOnAnyKill = true makes
	every kill come apart at any range instead.

	THE RADII MUST ASCEND. Out of order an inner sphere swallows an outer one and
	that band never happens. The server checks at startup and warns.

	NPCs GET ALL OF THIS TOO, dismemberment included, on exactly the same terms
	as players. Turn AffectNPCs off if your map has none.

	If artillery seems not to kill anyone, check CoverRayLift is above zero.
	Impact points sit exactly on the ground, so a cover ray cast from one hits
	the floor it started on and every shell in the open reads as covered.


	========================================================
	IF THE DAMAGE FEELS RANDOM
	========================================================

	Turn DebugLog on. The server prints one line per victim per shell:

	    Player1 at 24.3 (21 flat, -12 up) -- LAYER 2, cover 33%,
	                             98 damage, survived (2 HP left)

	The "flat" and "up" figures tell you straight away whether a shell that
	LOOKED close was actually far away vertically.

	That usually answers it outright. The common causes:

	  LEVEL DIFFERENCE. Height counts toward the blast radius. It counts less
	  than ground distance (BlastVerticalScale is 0.6, so the blast is a
	  flattened ellipsoid that reaches up and down slopes), but a big enough
	  drop still puts you out of range. Raise it toward 1 for a true sphere.


	  TWO SHELLS OVERLAPPING. A barrage drops a shell every 0.15-0.6 seconds.
	  Being clipped twice in a second is not the same hit twice as hard, and
	  from inside the game it is indistinguishable.

	  A HEALTH BAR ALREADY CHEWED DOWN. Whether a falloff hit kills depends on
	  what is left, and you cannot see other people's health.

	  PARTIAL COVER. Damage scales by how much of you is behind something, so
	  half a wall really is half the damage.

	Three things that USED to make it random, fixed, and easy to reintroduce:

	  ForceField. Humanoid:TakeDamage is blocked by spawn protection, but
	  assigning Humanoid.Health is not, so layers 2 and 3 did nothing to a
	  fresh spawn while layer 1 killed straight through the shield. Every layer
	  now goes through one applyDamage helper that assigns Health directly, so
	  ARTILLERY PENETRATES SPAWN PROTECTION and every layer agrees about it. To
	  protect a spawn, tag it ArtillerySafeZone (see below).

	  MaxFalloffDamage set to exactly 100. A full health bar, so a healthy
	  player could never quite die outside the kill sphere: one tenth of a
	  stud past the boundary dealt 99.3 and left them standing.

	  A single cover raycast. One ray to the torso is a coin flip at partial
	  cover. Three rays now sample head, torso and legs.


	========================================================
	THIS IS R6 ONLY
	========================================================

	Dismemberment works by destroying the Motor6Ds on an R6 character's Torso.
	Those joints do not exist on R15, so an R15 character is detected, killed
	normally, and a warning is printed once.

	Set EnableGore = false if you want plain kills and no warning.


	========================================================
	TAG YOUR SPAWNS
	========================================================

	Nothing stops shells landing on a spawn until you say so. Select a part
	covering the area, open the Tags section of Properties, and add:

	    ArtillerySafeZone

	Height is ignored, so one flat plate laid over the spawn protects everything
	above it. Tag as many parts as you like.

	THIS IS THE ONLY WAY TO PROTECT A SPAWN. A ForceField does not stop
	artillery (see the damage note above).


	========================================================
	PLAYERS UNDER A ROOF ARE NOT AIMED AT
	========================================================

	A battery a kilometre away cannot see through a bunker, so anyone indoors is
	dropped from the list the barrage's centre is picked from. Five rays go up
	from each candidate; whatever stops one IS the roof, so bunkers, bridges,
	rock overhangs and tree canopy all work with nothing tagged.

	IT IS NOT A SHIELD. It only decides where the guns AIM. A shell aimed at the
	squad outside your door still lands outside your door, and the blast does not
	care what you are standing under.

	If every player is indoors the barrage is skipped and says so in Output.

	    SkipShelteredPlayers      off makes the guns ignore roofs entirely
	    ShelterBlockedThreshold   fraction of five rays that must be blocked.
	                              0.5 is three of five. Raise it on a heavily
	                              enclosed map or barrages stop happening


	========================================================
	THE ONE TEXTURE SLOT
	========================================================

	    SmokeTexture      the cloud left hanging over the crater, AND the
	                      fallback for the flat ground dust mark
	    DustDecalTexture  optional. Only if you want the flat ground mark to
	                      be a different image from SmokeTexture

	SmokeTexture is the only asset the system needs. DEBRIS AND THE DUST WAVE ARE
	REAL PARTS. They depend on no image at all, so they cannot be broken by a
	bad id.

	IT SHIPS AS AN ENGINE PATH, NOT AN ID, ON PURPOSE. An engine path cannot be
	moderated, cannot be a decal id by mistake, and renders on every client with
	no upload. Ids kept going into this slot and kept coming out invisible.

	NEVER LEAVE SmokeTexture EMPTY. A ParticleEmitter with no Texture falls back
	to Roblox's default sprite, which is a WHITE SPARKLE: the glittery confetti
	look. No amount of size or colour tuning removes it, because the sparkle
	IS the sprite.

	TWO FORMS ARE VALID, and mixing them is the classic mistake:

	    rbxassetid://13623094740                       an uploaded image
	    rbxasset://textures/particles/smoke_main.dds   an engine file

	"rbxasset://13623094740" is NEITHER. It asks the engine for a file named
	after a number, finds nothing, and renders blank with no error at all.

	THE OTHER TRAP: uploading an image to Roblox creates a DECAL, and a decal's
	id is NOT the image's id. A decal id renders nothing, silently.

	To get the right one: drop the decal onto any part in Studio, then read the
	Texture property off the Decal instance it makes. That value is the image id.

	Use a GREYSCALE image. ImpactSmokeColor tints whatever you give it.


	========================================================
	AUDIO NEEDS YOUR OWN ASSETS
	========================================================

	Roblox audio is private by default, so an id lifted from another game is
	silent here, and nothing in Output says why. Four slots in ArtilleryConfig:

	    BatteryReportSoundId   distant thump of the guns firing (THE WARNING)
	    ShellWhistleSoundId    the incoming scream, looped
	    ImpactNearSoundId      sharp crack for close shells
	    ImpactFarSoundId       hollow crump for distant ones

	View > Toolbox > Audio, right click, Copy Asset ID. Grab the AUDIO asset's
	id, not the id of a model wrapping it. That fails silently too.

	Any left empty simply does not play. The system warns once if all four are.

	BatteryReportSoundId is the one that matters. It is the only warning a
	player gets, and without it a barrage is an unannounced death.


	========================================================
	TESTING
	========================================================

	Barrages are 120-260 seconds apart. To drop one now, press Play, set the
	Client/Server toggle in the toolbar to SERVER, and run:

	    game.ReplicatedStorage.Artillery:SetAttribute("DebugBarrageNow", true)

	It resets itself to false. Watch Output for:

	    [Artillery] barrage -> 12s warning, then shells

	No print means the command never reached the server, which is almost always
	the toggle sitting on Client.

	To make every playtest open with a barrage, set

	    ArtilleryConfig.DebugFirstBarrageDelay = 10

	That runs as ordinary server code at boot, so nothing Command Bar related
	can break it.

	NATURAL TIMER NEVER FIRES, ONLY DebugBarrageNow DOES?

	  This is MinPlayersForBarrage, almost always. The natural loop skips its
	  cycle entirely below that many players online (default 4), while
	  DebugBarrageNow has no player-count check at all and always fires. Testing
	  solo or with a couple of friends means the natural timer is never
	  satisfied, no matter how long you wait.

	  The loop logs "natural barrage skipped -- N online, MinPlayersForBarrage is
	  M" every time this happens (needs DebugLog = true). If you see that, the
	  timer is fine: the player count is what is stopping it. Set
	  MinPlayersForBarrage = 1 while testing alone.

	SEEING NO SHELLS?

	  1. Did the server fire any? Look for "BARRAGE INCOMING" in Output. If it
	     isn't there, the barrage never ran. Check that someone is alive, and
	     that Enabled is true in the config.

	  2. Did it reach your client? "[Artillery/client] ready" prints at join. No
	     line means install step 4 got missed.

	  3. Looking the wrong way? Shells come in on BatteryHeading, which defaults
	     to 45 degrees. Turn to face it, or set DebugDrawImpacts = true and
	     watch the markers instead.


	========================================================
	TUNING: ReplicatedStorage.Artillery.ArtilleryConfig
	========================================================

	    BarrageInterval        seconds between barrages
	    MinPlayersForBarrage   below this online, natural timer skips its cycle.
	                           DebugBarrageNow ignores it. 1 while testing solo
	    ShellsPerBarrage       how many shells one barrage drops
	    BarrageWarningLead     seconds of warning. THE mechanic: don't go low
	    ClusterRadius          how far apart players still count as a crowd
	    SkipShelteredPlayers   players under a roof are not aimed at
	    ShelterBlockedThreshold how enclosed you must be to count. 0.5 is 3 of 5
	    EpicenterJitter        how far off the barrage lands from whoever drew it
	    ShellScatterRadius     how wide the shells spread
	    BatteryHeading         compass direction the guns fire from
	    ShellFlightTime        seconds in the air, and how long you see the arc
	    TrailLifetime          length of the streak. The main look knob
	    MaxRenderedShells      shells drawn at once. Main client perf knob
	    DebrisMatchSurface     debris made of whatever the shell hit
	    DustDecalTexture       the dust cloud's image. Falls back to SmokeTexture
	    DustDecalStartSize/End what it grows from and to. The gap IS the effect
	    DustDecalStartHeight/End the sink: where it appears, where it settles
	    MaxLiveDust            ceiling on clouds live across a whole barrage
	    ChunkCount             chunks thrown per shell. Main density knob
	    MaxLiveChunks          ceiling across every burst on screen at once
	    ChunkSpeed             MUST start low, or there is a hole at the crater
	    ChunkGravity           LOWER throws chunks wider. The real radius limit
	    ChunkElevation         degrees above horizontal. Low skims the ground
	    ImpactDebrisDelay      gap between the dust and the debris
	    ImpactSmokeDelay       gap between the dust and the smoke
	    KillRadius             instant death, always dismembers
	    DamageRadius           outer edge of the falloff
	    CoverDamageReduction   what a wall is worth. 0 makes cover total
	    MaxLimbsSevered        limbs off on a direct hit
	    EnableMaiming          limbs off survivors the blast did not kill
	    DismemberRadius        layer 2. Damage plus limbs off
	    DismemberOnAnyKill     make layer 3 kills dismember too
	    DebrisDarken           how dark the thrown earth is. Stops it glittering
	    MaimChance             odds of it at the crater's edge
	    EnableGore             false for plain kills
	    ShowStumps             exposed bone in the socket
	    EnableConcussion       survivors near a blast get dazed
	    ShakeTranslation       how hard the camera rattles
	    DebugDrawImpacts       marks where shells will land before they do
	    DebugFirstBarrageDelay seconds to the first barrage after boot


	========================================================
	HOW IT WORKS
	========================================================

	No models, and no shell part ever exists on the server.

	The server picks impact points and publishes four values per shell: where it
	launches from, where it lands, how long it flies, and the absolute time it
	arrives. Every client draws its own shell from those, and the server applies
	the damage on its own clock.

	The arc is real projectile motion, not a curve. Given the launch point, the
	impact point and the flight time, it solves for the launch velocity and then
	accelerates the shell downward the whole way, so it comes in faster than
	it went out. A Bezier of the same shape travels at constant speed and reads
	as floaty.

	Every shell in one barrage shares a heading, give or take a few degrees, so
	the trails arc in roughly parallel. That is what makes it read as guns at a
	position rather than junk falling out of the sky.

	The bright trail is a Trail with LightEmission at 1, not a light source, so
	it glows against a dark sky for free. The whole effect is parented under
	workspace.CurrentCamera, which never replicates.

	NOTHING IS LEFT BEHIND ON IMPACT. No crater, no decal, no scorch mark. A
	shell throws the ground up and that is all, and every part it creates to do
	that cleans itself up.

	AN IMPACT IS THREE STAGES, not one burst:

	    0.00s   DUST     one cloud appearing over the crater and opening out
	    0.04s   DEBRIS   the ground thrown out
	    0.22s   SMOKE    what is left hanging over it

	Firing them all on one frame is what makes an explosion read as a flat pop.
	The gaps are ImpactDebrisDelay and ImpactSmokeDelay.

	THERE IS NO EXPLOSION BALL. A brief light stays, with no visible geometry;
	EnableImpactLight = false removes that too.

	THE DUST IS ONE IMAGE, not particles and not a field of geometry. Both
	were tried, and both read as many separate pieces instead of one cloud. It
	GROWS AND SINKS over its life rather than sitting static:

	  GROWS   from DustDecalStartSize to DustDecalEndSize. Fast at first
	          (DustDecalGrowthCurve below 1), then a slow creep.
	  SINKS   from DustDecalStartHeight down to DustDecalEndHeight, as it
	          settles onto the ground.

	Plus a slow DustDecalSpin, so the mass churns instead of just scaling in
	place. It is angled to the surface normal, so it lies flat on slopes.

	THIS IS THE ONE IMPACT EFFECT LEFT THAT NEEDS AN IMAGE. Debris cannot fail;
	this can, silently: a decal id where an image id was needed renders
	nothing. If dust never shows up, DustDecalTexture (or its fallback,
	SmokeTexture) is why.

	It is still temporary: held for DustDecalHoldTime, faded over
	DustDecalFadeTime, then destroyed. EnableDustDecal turns it off.
	MaxLiveDust caps how many can exist across one barrage at once.

	The debris is made of whatever the shell landed on: one downward raycast
	reads the part's Color, or the terrain material's. Snow throws white, mud
	throws brown, and nothing has to be authored per map.

	Timing uses workspace:GetServerTimeNow(), which is the same clock on the
	server and every client. That is why the explosion lands on the same frame
	as the damage no matter what your ping is.


	========================================================
	SPEED MODIFIERS
	========================================================

	SpeedService is the only thing allowed to assign Humanoid.WalkSpeed or the
	character's jump height. The concussion effect registers a "Concussed"
	modifier and clears it when it wears off.

	Modifiers compose, so if you also run Variable Snowstorm, being concussed in
	a blizzard while sprinting stacks all three without any of them knowing
	about the others.

	One rule: never assign WalkSpeed directly once a humanoid is managed here.
	Outside writes get overwritten on the next recompute.

]]

return nil

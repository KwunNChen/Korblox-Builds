--[[

	GIVE CREDIT TO PLAGUEBYTE!!!!! @pb6008 for any inquiries

	TREK GAS GRENADE

	A throwable for TREK. You hold to cook, release to throw, and it bounces to
	a stop and vents a cloud of NERVE AGENT -- thin white smoke that kills
	anyone who breathes it, whether or not they get out of it.

	The first TREK tool that is not a gun. TREK dispatches tool behaviour on a
	ToolType string, so this installs a new handler called "Throwable" and does
	not modify a single core file.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder.


	========================================================
	REQUIRES
	========================================================

	TREK 4. The gas damage goes through ServerStorage.TREKDamageModule, which is
	part of the core install, so this package does nothing on a place without it.


	========================================================
	INSTALL
	========================================================

	Drag TREKGasGrenade.rbxm into ServerStorage, then paste tools/Install.luau
	into the Studio command bar in EDIT MODE. It moves everything and deletes the
	staging folder.

	USE IT RATHER THAN INSTALLING BY HAND. This package lands in five places and
	has gained a destination in most versions. Moving new folders in alongside
	old ones leaves two with the same name, Roblox runs both, and the stale copy
	fails on a module it has never heard of -- which reads as a broken package
	rather than a half-finished install. The installer replaces wholesale.

	By hand, if you must -- and DELETE the existing folder at each destination
	first rather than merging into it:

	1. Drag TREKGasGrenade.rbxm into ServerStorage. Nothing runs there, which is
	   the point: put it anywhere else and the server scripts start before the
	   modules they need exist.

	2. ReplicatedStorage/TREKGasGrenade   ->  ReplicatedStorage
	3. ServerScriptService/TREKGasGrenade ->  ServerScriptService
	4. ServerStorage/TREKToolHandlers/Throwable
	                                      ->  your existing
	                                          ServerStorage.TREKToolHandlers,
	                                          alongside Gun. No such folder means
	                                          TREK is not installed yet.
	5. GunConfigs/"Gas Grenade"           ->  your existing GunConfigs
	6. StarterPlayerScripts/TREKGasGrenade
	                                      ->  StarterPlayer.StarterPlayerScripts

	7. Delete the empty TREKGasGrenade staging folder.

	ON STEP 5, THE NAME MATTERS. It must match the Tool's name exactly. TREK
	resolves a tool's config by name in several places and at least one ignores
	the TConfigToUse attribute entirely, so identical names are the only
	arrangement where every lookup agrees. Do not set TConfigToUse on this tool.

	If you use Rojo, none of this applies: `rojo serve` from the package folder
	places every file itself, and keeps placing them.


	========================================================
	THE ART
	========================================================

	The grenade meshes ship separately, in GasGrenades.rbxm. Two models:

	    InactiveGasGrenade      used for BOTH the held and the thrown grenade
	    ActiveGasGrenade        shipped but unused by default

	GasConfig.Models decides which is which. Both point at the inactive model, so
	the grenade looks the same in your hand as it does in the air. Point
	Models.Thrown back at "ActiveGasGrenade" to split them again.

	Put both in ServerStorage.TREKGasGrenade. Then build a Tool:

	    - Name it exactly "Gas Grenade"
	    - Set RequiresHandle to false
	    - Put a copy of InactiveGasGrenade inside it

	Or run tools/PrepareGrenadeRig from the command bar, which does all of that
	and leaves the finished Tool in StarterPack.

	You do NOT need to weld, unanchor, or set a PrimaryPart on either model. The
	import arrives as four loose anchored MeshParts with no welds and no
	PrimaryPart every single time it is exported, so the rig is rebuilt at
	runtime from whatever the model happens to contain. Re-export the art with
	different part names and it still works.


	========================================================
	HOW IT PLAYS
	========================================================

	Hold left mouse to cook. An arc appears showing where it will land, and
	reddens as the fuse burns down. Release to throw.

	The fuse starts when you press, NOT when you release. That is the whole
	point of cooking: you spend fuse time to deny the enemy the time to walk out
	of where it lands. Hold it too long and it goes off in your hand, which is
	intended and configurable.

	Putting the grenade away does not stop the fuse. If it did, cooking would be
	free.

	Where it detonates is where it stopped rolling, not where you aimed. Bounce
	is deliberately dead -- a gas grenade that pinballs back to your feet is
	funny exactly once.


	========================================================
	THE CLOUD
	========================================================

	Gas builds up over BuildUpTime rather than appearing at full strength, and
	the damage follows the same curve as the visual density. What you see and
	what hurts you stay in step, so a cloud that looks thin is thin.

	Damage is full strength out to FullDamageRadius and tapers to nothing at
	CloudRadius. The taper is gentler than a blast curve on purpose: the rim
	should be unpleasant enough to move people, not a safe place to stand.

	Walls stop it. There is a line-of-sight raycast from the cloud centre to
	every target, and gas realistically seeping around a corner turned out to
	mean players dying behind cover with no idea why. Bodies do NOT stop it --
	a raycast that hits another character is re-fired past them.

	It damages everyone, including you and your own team. A gas cloud that
	politely ignores whoever threw it removes every interesting decision about
	where to put it. Set AffectsEveryone to false in the config if you disagree.

	Sitting in a VehicleSeat protects you, matching what TREK's own explosions
	already do.

	While a character is in gas its Humanoid carries a TGasCondition BoolValue,
	following the same convention as TBleedCondition and TParalCondition. Read
	it if you want a coughing animation, a screen effect, or a mask mechanic.
	The count is ref-counted across overlapping clouds, so two clouds will not
	have the first to expire clear a condition the second is still applying.


	========================================================
	THE NERVE AGENT
	========================================================

	ONE LUNGFUL IS FATAL. The cloud does not damage you -- it reports that you
	breathed it, and everything after that is already decided. Leaving the cloud
	does not help. Neither does the cloud expiring, or a medic.

	    dose    one tick inside the radius. Irreversible from here.
	    seize   0.35s later the body goes limp and starts convulsing
	    bleed   1.2s after that, blood from the mouth
	    death   health drains to zero across 12 seconds

	The WHOLE radius doses, at the same rate. There is no falloff here -- either
	you are breathing it or you are not.

	The THROWER gets 1.4 seconds of grace, and only the thrower. That is not
	mercy, it is playability: a throw that bounced off a doorframe should be
	survivable if you turn and run, or nobody carries one. Their team gets
	nothing, and dies exactly as fast as the enemy does.

	Health is DRAINED, not set. A player watching their own bar sees it fall; a
	kill that set Health to 0 reads as a disconnect. Each tick takes a fraction
	of MAX health, so a wounded player and a healthy one die on the same
	schedule -- which is what "the dose is lethal" means.

	From the dose they loop Nerve.Sound.Id from their Head, and their ordinary
	hurt barks are suppressed -- the drain fires a health change every tick, so
	without that a single death is roughly 48 "ow"s over the top of it. The
	switch is a SuppressHurtVoice attribute on the character, read by TREK
	Voicelines, which is a SEPARATE package: syncing this one does not carry it.

	Going limp takes the body off the player completely. The Humanoid goes into
	the Physics state (PlatformStand alone is a property its state machine walks
	back out of -- jump on the dose frame and it stands you up mid-ragdoll),
	GettingUp/Jumping/Climbing are disabled, network ownership moves to the
	server because the CLIENT owns a player's own physics and can overrule all
	of it, and they are disarmed: hands emptied and hotbar stashed out of reach.

	Everything taken is recorded first, so GasRagdoll.stop() gives it all back.
	Nothing calls it -- there is no recovery from the gas -- but start() should
	not be a one-way trapdoor, and a gas mask would need it.

	The ragdoll is R6 ONLY. TREK is an R6 framework and the joints are R6 names;
	on an R15 rig it finds nothing and leaves the character upright, still dying.

	While dying, the Humanoid carries a TNerveCondition attribute, following the
	same convention as TBleedCondition and TParalCondition. That is the hook a
	gas mask would read later.

	Nerve.Enabled = false reverts to the old irritant gas: damage by distance,
	and walking out saves you. The two are mutually exclusive.


	========================================================
	BEING GASSED
	========================================================

	Perceptual only. Nothing touches WalkSpeed, aim or controls -- you can still
	fight your way out, you just cannot see or hear well doing it.

	    vision    blur, a wash toward the gas colour, drained saturation,
	              darkened and contrastier
	    hearing   the world muffled through an equaliser, with a ring over it
	    build     full over Disorient.BuildTime in the gas, clears over FadeTime
	    who       everyone in it, thrower included -- same rule as the damage

	All of it rides one number: GasExposure, a 0-1 attribute the SERVER writes to
	the victim's Humanoid. The server owns it because the server is the only
	thing that knows who is standing in gas, and publishing a value rather than
	firing effect remotes means the worst a tampered client can do is blind
	itself.

	It is a plain attribute, so anything else can watch it -- a HUD, a medic
	system, a spectator overlay, a gas mask you build later -- without this
	package knowing they exist.

	Muffle needs a SoundGroup called Muffle in SoundService, which is where
	TREK's own concussion muffle lives. No group, no muffle; everything else
	still works. The ring borrows TREK's staged Tinnitus sound so gas and blasts
	ring with the same tone.

	The cloud also hisses -- a looping POSITIONAL sound, so you can hear roughly
	where the gas is. Sound.RollOffMax reaches well past CloudRadius on purpose:
	the warning is for people near the cloud, not confirmation for the ones
	already choking in it.


	========================================================
	TUNING
	========================================================

	Everything lives in ReplicatedStorage.TREKGasGrenade.GasConfig, documented
	in place. The module in GunConfigs is a thin shim that reads from it -- edit
	GasConfig, not the shim.

	The numbers that actually change how it feels:

	    FuseTime            how long you have, cooked or not
	    CloudRadius         how much ground one grenade denies
	    CloudDuration       how long that denial lasts
	    DamagePerTick       with TickInterval, the damage per second
	    BuildUpTime         the window a fast player has to get out
	    ThrowPower          range
	    CookKillsYou        whether cooking is a real decision

	At the defaults a player standing in the centre dies in about three seconds
	and a player who reacts does not.

	    lune run tools/configtest.luau

	checks the config for the mistakes that are invisible until someone throws
	one -- a full-damage radius larger than the cloud, a build-up longer than
	the duration, a key deleted while the source still reads it.


	========================================================
	NO AMMO HUD
	========================================================

	There is no on-screen counter, and at the default loadout there is nothing to
	count: you carry one grenade, throw it, and the tool disappears.

	TREK sources a weapon's ammo display from a MainHud Frame parented to the
	weapon's config ModuleScript -- open any GunConfigs weapon and you will see
	MainHud sitting inside it next to the sounds and animations. The Gun handler
	reads it with module:WaitForChild('MainHud') and clones it into the GunHud
	ScreenGui.

	The grenade's config is a plain module with no MainHud child, and the
	Throwable handler never looks for one, so nothing appears and nothing errors.

	The reload path IS wired -- the handler fires TREK's own Reload remote on
	your reload key -- so raising ReservedAmmo above 0 gives you a working
	resupply without touching any code.

	If you want one, the count is live at:

	    tool.TAmmo["1"].Ammo.Value        -- in hand
	    tool.TAmmo["1"].Stored.Value      -- in reserve

	Both are DoubleConstrainedValues, so :GetPropertyChangedSignal("Value")
	drives a label directly.


	========================================================
	WHAT IT DOES NOT DO
	========================================================

	No gas mask or immunity gear. TREK has no damage-typing or resistance
	system at all -- the only protection concepts in the whole codebase are a
	ResistIndirectDamage flag on destructible parts and the vehicle-seat check.
	TGasCondition is the hook to build one on.

	No cook or idle pose. Only the throw is animated -- the grenade is gripped by
	the right hand and otherwise just follows your global movement animations.

	It is joined to the HAND, not the torso, and ships no AnimPart. TREK hangs
	tools off toolAnim, a Motor6D from the torso to AnimPart, and relies on each
	weapon's animations keyframing that track to carry it into the hands. With no
	idle pose the grenade would simply park beside the chest -- attached, moving
	with the body, never following the arm, which reads as hovering in mid air.
	Without an AnimPart, checkForGun skips updateMotor and the package makes its
	own GasGrenadeGrip joint on Right Arm (R6) or RightHand (R15). GripOffset is
	that joint's C0.

	The throw animation lives in GasConfig.Animation:

	    Throw          the asset id
	    Priority       must be Action or above. TREK's global Run sits at
	                   Movement, and equal-priority tracks are BLENDED by weight,
	                   so a throw at Movement is averaged into your run cycle and
	                   reads as a twitch rather than a throw
	    ReleaseDelay   seconds from the animation starting to the grenade
	                   actually leaving. Match it to the frame your hand opens;
	                   at 0 the grenade leaves before the arm has moved
	    FadeTime       blend in and out

	It is built from the id in code rather than shipped as an Animation instance
	in an Animations folder, which is how TREK weapons do it. That means Bayonet's
	WeaponPosePriority will not see it -- it only raises tracks whose Animation
	lives in a weapon's Animations folder -- so Priority is applied directly.

	The animation has to be owned by the place owner or its group or it will not
	load. If it cannot, you get one warning and the grenade still throws.

	No impact detonation. The fuse is a timer. A grenade that went off on
	contact would not be cookable, and cooking is the mechanic.

]]

return nil

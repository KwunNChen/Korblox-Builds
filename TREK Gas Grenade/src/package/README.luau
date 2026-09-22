--[[

	GIVE CREDIT TO PLAGUEBYTE!!!!! @pb6008 for any inquiries

	TREK GAS GRENADE

	A throwable for TREK. You hold to cook, release to throw, and it bounces to
	a stop and vents a cloud of gas that damages anyone standing in it for as
	long as it lasts.

	The first TREK tool that is not a gun. TREK dispatches tool behaviour on a
	ToolType string, so this installs a new handler called "Throwable" and does
	not modify a single core file.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder in step 5.


	========================================================
	REQUIRES
	========================================================

	TREK 4. The gas damage goes through ServerStorage.TREKDamageModule, which is
	part of the core install, so this package does nothing on a place without it.


	========================================================
	INSTALL
	========================================================

	1. Drag TREKGasGrenade.rbxm into ServerStorage. This creates a
	   TREKGasGrenade folder holding all the pieces. ServerStorage is temporary:
	   nothing runs there, which is the point. Put the .rbxm anywhere else and
	   the server scripts start before the modules they need exist.

	2. Move TREKGasGrenade out of TREKGasGrenade/ReplicatedStorage/ into the real
	   ReplicatedStorage.

	3. Move TREKGasGrenade out of TREKGasGrenade/ServerScriptService/ into the
	   real ServerScriptService.

	4. Move Throwable out of TREKGasGrenade/ServerStorage/TREKToolHandlers/ into
	   your existing ServerStorage.TREKToolHandlers folder, alongside Gun.

	   If you do not have one, TREK has not been installed yet. Do that first.

	5. Move "Gas Grenade" out of TREKGasGrenade/GunConfigs/ into your existing
	   GunConfigs folder, alongside your weapons.

	   THE NAME MATTERS. It must match the Tool's name exactly. TREK resolves a
	   tool's config by name in several places, and at least one of them ignores
	   the TConfigToUse attribute entirely, so naming them identically is the
	   only arrangement where every lookup agrees. Do not set TConfigToUse on
	   this tool.

	6. Delete the empty TREKGasGrenade staging folder.


	========================================================
	THE ART
	========================================================

	The grenade meshes ship separately, in GasGrenades.rbxm. Two models:

	    InactiveGasGrenade      what the player holds
	    ActiveGasGrenade        what flies, lands, and vents

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

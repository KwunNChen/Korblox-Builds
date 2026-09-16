--[[

	TREK PARKOUR

	Vaulting and ledge mantling for TREK 4. Sprint into low cover and go over it.
	Jump at a wall, press jump again, and haul yourself up -- with your weapon
	slung and your sprint gone until you are standing.

	REQUIRES TREK 4. It hooks into whatever install you already have and does not
	modify it. Delete this folder and your install is exactly as it was.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder in step 4.

	==========================================================================
	INSTALL
	==========================================================================

	Drag TREKParkour.rbxm into ServerStorage. Always ServerStorage -- scripts do
	not execute there, which is the whole point. Drop it into ServerScriptService
	or Workspace and the server script starts running before the modules it needs
	exist, and it fails in ways that look like bugs.

	The folders inside are SIGNPOSTS. A folder called ReplicatedStorage is a
	label telling you where its CONTENTS belong. Open it and move the folder
	INSIDE it into the real service.

	1. ReplicatedStorage/  ->  move  TREKParkour  into  game.ReplicatedStorage
	2. ServerScriptService/ -> move  TREKParkour  into  game.ServerScriptService
	3. StarterPlayerScripts/ -> move TREKParkour  into
	                            game.StarterPlayer.StarterPlayerScripts
	4. Delete the empty TREKParkour wrapper folder.

	Then press Play.

	Moving a signpost itself gives you ReplicatedStorage.ReplicatedStorage.
	TREKParkour, and nothing finds anything.

	WHEN YOU'RE DONE

	    ReplicatedStorage
	      `-- TREKParkour          the modules, and the config you edit
	    ServerScriptService
	      `-- TREKParkour          the one server Script
	    StarterPlayer/StarterPlayerScripts
	      `-- TREKParkour          the one LocalScript

	There is no Common folder. Ski, Random Arty and Variable Snowstorm all ship
	one because they all change WalkSpeed and would otherwise fight each other.
	This package never touches WalkSpeed at all, so it has nothing to share and
	nothing to collide with.

	==========================================================================
	CONTROLS
	==========================================================================

	VAULT      sprint into something waist-high. No key. It just happens.
	MANTLE     jump, then press jump again while you are in the air near a ledge.

	No new keys. The mantle is on the jump button, which means it works on
	keyboard, on a gamepad and on mobile without any of them being configured.

	==========================================================================
	WHAT A MANTLE COSTS YOU
	==========================================================================

	While you are pulling yourself up:

	    your weapon is put away        and comes back when you are standing
	    sprint is switched off         and comes back when you are standing
	    you cannot steer, or cancel

	That is deliberate. A mantle is a decision, not a free movement upgrade --
	you are committing to about a second of being useless in exchange for
	getting somewhere you could not otherwise stand.

	If you have TREK Bayonet installed, its HolsterService slings the weapon
	visibly across your back for the duration instead of it vanishing. Nothing
	breaks without it; it just looks better with it.

	The weapon going away is also load-bearing, not only flavour. TREK rewrites
	your character's rotation every frame while a weapon is out, and the climb
	cannot play over the top of that. Putting the weapon away is what stops it --
	it is the same thing TREK's own gun handler does on unequip.

	==========================================================================
	TUNING: ReplicatedStorage.TREKParkour.ParkourConfig
	==========================================================================

	One file, and it is the only one you should need to open. Every value in it
	carries a comment explaining what it does and what breaks if you move it.

	The three that matter most:

	    VaultMaxHeight     where vaulting stops and mantling starts (3.5)
	    MantleMaxHeight    the tallest thing you can climb at all (7.0)
	    MantleDuration     how long you are helpless for (1.1s)

	Turn on DebugLog while you are tuning. Every refusal prints its reason, which
	is the whole diagnostic -- "too high" and "no room up there" look identical
	from the outside and are fixed by different numbers.

	==========================================================================
	ANIMATIONS
	==========================================================================

	The animation slots in the config ship EMPTY, and empty means the package
	falls back to a rough pose built out of joint angles in code. It works. It is
	not pretty.

	FOR WHOEVER IS ANIMATING:

	    Author for R6. An R6 sequence loaded onto an R15 rig gives you zero
	    tracks and an empty timeline, with no error to tell you why.

	    R6 has no knees and no ankles. A pull-up has to come from the waist, the
	    hips and the shoulders.

	    DO NOT ANIMATE THE ROOT. The game writes the character's position every
	    frame during a move. Any root motion baked into your track fights that
	    and reads as jitter. Animate the limbs against a stationary root -- the
	    game moves the body.

	There are three slots: Vault, MantleCatch and MantlePull. Fill them in one at
	a time; each one falls back independently, so a half-finished set is fine.

	One thing worth knowing before someone reports it as a bug: the fallback
	poses are drawn on your own screen only and do NOT replicate. Until the slots
	are filled in, other players see you move but not pose. Real animation tracks
	go through the Animator and are seen by everyone.

	==========================================================================
	MADE BY
	==========================================================================

	PlagueByte (pb6008 on Discord). TREK is not mine and is not included here --
	this hooks into whatever install you already have.

]]

return nil

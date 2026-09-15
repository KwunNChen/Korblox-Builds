--[[
	TREK BAYONET

	A melee thrust for TREK rifles. Press G with a bayonet-equipped weapon and
	you stab whatever is in front of you -- at any ammo count, in any fire mode,
	mid-reload. While sprinting, the character holds the rifle in a charge pose.

	No TREK script is edited. Delete this folder and your install is exactly
	what it was.

	==========================================================================
	INSTALL
	==========================================================================

	1. THIS FOLDER IS STAGING, NOT THE INSTALLED SHAPE.

	   The four folders named after services are signposts saying where their
	   contents belong. Move the INNER folder out of each one:

	       ReplicatedStorage/TREKBayonet    -> game.ReplicatedStorage
	       ServerScriptService/TREKBayonet  -> game.ServerScriptService
	       StarterPlayerScripts/TREKBayonet -> game.StarterPlayer.StarterPlayerScripts
	       ServerStorage/TREKBayonetPoses   -> game.ServerStorage

	   Then delete this staging folder.

	   TREKBayonetPoses is the only optional one -- it holds the two R6
	   animation sequences and is needed only if you want to edit and publish
	   them. Nothing breaks without it, but deleting the staging folder with it
	   still inside means re-importing the model to get them back.

	   Or select the staging folder and run this in the COMMAND BAR, which does
	   the same thing and replaces any previous install:

	       local staging = game:GetService("Selection"):Get()[1]
	       assert(staging and staging.Name == "TREKBayonet", "Select the staging folder first")
	       for _, move in ipairs({
	           { "ReplicatedStorage",    "TREKBayonet",      game:GetService("ReplicatedStorage") },
	           { "ServerScriptService",  "TREKBayonet",      game:GetService("ServerScriptService") },
	           { "StarterPlayerScripts", "TREKBayonet",      game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts") },
	           { "ServerStorage",        "TREKBayonetPoses", game:GetService("ServerStorage") },
	       }) do
	           local signpost, innerName, dest = staging:FindFirstChild(move[1]), move[2], move[3]
	           local inner = signpost and signpost:FindFirstChild(innerName)
	           assert(inner, "staging folder has no " .. move[1] .. "/" .. innerName)
	           local old = dest:FindFirstChild(innerName)
	           if old then old:Destroy() end
	           inner.Parent = dest
	       end
	       staging:Destroy()
	       print("TREKBayonet installed")

	   Left sitting in ServerStorage the package installs nothing and logs
	   nothing, because Scripts do not run there -- so there is no error to go
	   looking for.

	2. ADD A PART NAMED "Bayonet" TO YOUR WEAPON'S TOOL.

	   The knife already modelled on the KR-61 is the obvious one, and on the
	   stock KR-61 this is already done. A weapon with no such part cannot stab,
	   which is how the system knows which rifles have one -- so fitting a
	   bayonet to another rifle is a modelling job, not a config edit.

	   Only the NAME is checked and the search is recursive: a loose Part or a
	   Model of several parts, nested or not, all work. Its position and size
	   ARE the hitbox.

	   A new one built as a loose Part needs three properties, or it misbehaves
	   visibly:

	       welded to the gun    TREK only Motor6Ds AnimPart; an unwelded part
	                            drops to the floor on equip
	       CanCollide = false   or the blade snags on walls and shoves you
	       Massless = true      or it drags on the character's physics

	3. PASTE THE BayonetWeaponMode BLOCK INTO THAT WEAPON'S CONFIG MODULE,
	   inside the same `local configs = { ... }` table that holds [1]. Read the
	   comments at the top of it: the index 9 and the missing MagCapacity are
	   both deliberate and both load-bearing.

	4. RESTART THE PLAYTEST. SetUpGuns caches every weapon module at server
	   start, so config edits need a fresh run.

	5. OPTIONAL: put your own animation ids into BayonetConfig. Until you do,
	   the bayonet still damages -- it just does it without a pose.

	CHECK IT WORKED. Two lines on a playtest:

	    [TREKBayonet] service ready -- blade hitbox padded ...
	    [TREKBayonet] controller ready -- press G to stab

	Only the first means the StarterPlayerScripts half is missing. Neither
	means nothing was installed. It waits on TREK_INSTALLED itself, so load
	order does not matter.

	==========================================================================
	TUNING -- ReplicatedStorage > TREKBayonet > BayonetConfig
	==========================================================================

	    Key               "G"    F is NOT free: TREK binds it to sprint
	    HitPadSide        1.25   how far off-centre your aim can be
	    HitPadVertical    2.5    how much height difference is forgiven
	    HitPadForward     1.5    reach past the tip
	    HitWindow         0.35   how long the blade keeps being tested
	    Cooldown          1.2    seconds between thrusts
	    RequireSprint     false  true = only stab while sprinting
	    Debug             false  true = every stab reports itself

	DAMAGE IS NOT HERE. It lives in the [9] block of the weapon module.

	Keys taken by TREK: F, C, R, Q, T, N, V, LeftShift, LeftControl. G, X and B
	are free.

	==========================================================================
	WHEN A STAB DOES NOT LAND
	==========================================================================

	Set Debug = true and press G. Every stab then prints one line naming the
	cause, and the three outcomes are told apart on purpose:

	    REFUSED   never got as far as detection -- cooldown, no tool, no
	              Bayonet part, no [9] block. The line says which.
	    MISS      it swept and came up short, and reports how many studs
	              outside the box the nearest person was. Add that number to
	              the padding it was short on.
	    hit       what was hit, in which limb, on which sample.

	A miss also reports how far the blade travelled during the sweep. A stud or
	more means the server watched a real thrust and the box was short. Near
	zero means the server never saw the animation, which padding cannot fix.

	==========================================================================
	WHY IT WORKS AT 0 AMMO
	==========================================================================

	Not because the magazine is large. Because there is no magazine.

	Both of TREK's ammo-store builders skip any mode block with no MagCapacity,
	so the [9] block creates no ammo counter at all. There is nothing to
	deplete and no check to fail. The stab also never enters the gun handler's
	shoot(), which is what gates on ammo in the first place -- and, usefully,
	is also what cancels your sprint when you attack. That is why the charge
	survives the thrust with no workaround.

	==========================================================================
	THE CLIENT DECIDES NOTHING
	==========================================================================

	The stab request carries nothing at all, and needs nothing.

	The hitbox IS the bayonet part. It is welded to the character, so the
	server knows where it is and sweeps it as the thrust animation drives it
	forward, asking what it overlapped. Target selection, team checks and
	damage all stay server-side, and there is no position for a client to
	misreport.

	This is why it does not reuse TREK_Remotes.Damage: ServerRays is false in
	GlobalConfigs, so TREK's own distance check never runs and handleDamage
	takes its origin position straight from the client. Fine for a rifle you
	can see down; not fine for a melee attack whose whole balance is its reach.

	Kill credit still goes through TREK: damage is applied with
	TREKDamageModule.DamagePlayer, which tags the victim with the same
	WeaponTag the kill feed reads.

	NPCs are valid targets, deliberately -- dummies and clones are most of what
	anyone tests against.

	==========================================================================
	LIMITS
	==========================================================================

	THealth props and TVehicle are not valid targets: stabbing a tank does
	nothing. There is no bayonet-specific voice bark, though a bayonet KILL
	fires the existing Kill bark from TREK Voicelines with no changes.

	==========================================================================
	MADE BY
	==========================================================================

	PlagueByte (pb6008 on Discord). TREK itself is not mine and is not included
	here -- this hooks into whatever TREK install you already have.
]]

return nil

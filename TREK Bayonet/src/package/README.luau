--[[
	TREK BAYONET

	A melee FIRE MODE for TREK rifles. Press V to switch from the rifle to the
	blade, click to thrust -- at any ammo count, mid-reload, while sprinting.

	REQUIRES TREK CUSTOM BULLETS as your gun handler. Vanilla TREK has no
	BulletType field and will ignore this entirely.

	No TREK script is edited. The bayonet plugs into Custom Bullets' own
	extension point, the BulletTypes folder.

	==========================================================================
	INSTALL
	==========================================================================

	0. FIRST, RENAME EVERY BulletType IN EVERY WEAPON CONFIG.

	   Custom Bullets resolves BulletType by module NAME, not by number:

	       BulletType = 1;          ->  BulletType = 'Hitscan';
	       BulletType = 2;          ->  BulletType = 'Projectile';

	   This is not optional. The handler does

	       local bulletType = bulletTypes[config[i].BulletType]
	       if not(bulletType) then return end

	   and that `return` is at SCRIPT scope, above the line that connects the
	   mouse. One weapon with a leftover number exits the handler and EVERY GUN
	   IN THE PLACE silently stops responding. The loop walks pairs(), so which
	   weapon triggers it changes between runs.

	1. THIS FOLDER IS STAGING, NOT THE INSTALLED SHAPE.

	       ReplicatedStorage/TREKBayonet    -> game.ReplicatedStorage
	       ServerScriptService/TREKBayonet  -> game.ServerScriptService
	       BulletTypes/Bayonet              -> see below

	   Then delete this staging folder.

	   BAYONET IS THE ONE THAT NEEDS JUDGEMENT. Where BulletTypes lives depends
	   on how TREK is installed in your place:

	     * TREK built at runtime by Workspace.Installer -> inside the Installer's
	       tree, in the same BulletTypes folder Custom Bullets put Hitscan in.

	     * ReplicatedStorage.TREK_SERVICES exists in edit mode ->
	       TREK_SERVICES > TREK_Modules > BulletTypes.

	   The rule that covers both: PUT IT NEXT TO Hitscan, Projectile AND Melee.
	   If it is not beside them it will not be found, and BulletType = 'Bayonet'
	   takes the whole handler down as described in step 0.

	2. PASTE THE BayonetWeaponMode BLOCK into the weapon's config module, inside
	   the same `local configs = { ... }` table that holds [1]. Read the comments
	   at the top of it -- the index 2, the infinite MagCapacity and
	   CanReload = false are each load-bearing for a different reason.

	3. ADD A PART NAMED "Bayonet" INSIDE THE WEAPON'S TOOL.

	   Already true on the stock KR-61: Tool > Weapon > Bayonet. Only the NAME is
	   checked and the search is recursive. Its position and size ARE the hitbox.

	   A new one built as a loose Part needs three properties, or it misbehaves
	   visibly: welded to the gun (TREK only Motor6Ds AnimPart, so an unwelded
	   part drops to the floor on equip), CanCollide = false, Massless = true.

	4. ADD A PART NAMED "2Barrel" TO THE TOOL, at the blade, WITH NO
	   PARTICLE EMITTERS.

	   Without it currentBarrel falls back to the rifle muzzle, and every swing
	   fires a muzzle flash and a gunshot on everyone else's screen. Adding a
	   "2Fire" sound to the weapon module replaces the gunshot with a stab.

	5. NAME THE THRUST ANIMATION "2Recoil" in the weapon module's Animations
	   folder. determineAnim prefixes the mode number and falls back to the
	   unprefixed name, so 2Recoil plays on a swing while Recoil still plays when
	   you fire the rifle. "2Idle" and "2SprintHold" do the same for the held and
	   charging poses.

	   An animation with no AnimPart track parks the whole weapon at the torso
	   origin, because TREK's toolAnim joint is built with identity C0/C1 and the
	   pose is the only thing that places the gun. Author against a rig with the
	   weapon attached.

	6. RESTART THE PLAYTEST. TAmmo is built once, lazily, so a tool that already
	   has one never gains a "2" entry -- and SetUpGuns caches weapon modules at
	   server start anyway.

	CHECK IT WORKED. One line on a playtest:

	    [TREKBayonet] service ready -- fire mode [2], blade hitbox padded ...

	There is no second line; the client half is a bullet type now, not a script.

	==========================================================================
	TUNING -- ReplicatedStorage > TREKBayonet > BayonetConfig
	==========================================================================

	    ConfigIndex        2      which mode block the bayonet is
	    HitPadSide         1.25   how far off-centre your aim can be
	    HitPadVertical     2.5    how much height difference is forgiven
	    HitPadForward      1.5    reach past the tip
	    HitWindow          0.35   how long the blade keeps being tested
	    RestoreSprint      true   keep sprinting through the swing
	    Debug              false  true = every swing reports itself

	DAMAGE, FIRE RATE AND ANIMATIONS ARE NOT HERE. They live in the weapon's [2]
	block and its Animations folder, because the bayonet is a fire mode rather
	than a system bolted on beside one. There is no Cooldown either: the server
	derives its rate limit from the same RoundsPerMinute the handler paces swings
	with, so there is one number to change.

	==========================================================================
	WHEN A SWING DOES NOT LAND
	==========================================================================

	Set Debug = true and swing. Every swing prints one line naming the cause.

	    REFUSED   never got as far as detection -- rate limit, no tool, no
	              Bayonet part, no [2] block. The line says which.
	    MISS      it swept and came up short, and reports how many studs outside
	              the box the nearest person was. Add that to the padding.
	    hit       what was hit, in which limb, on which sample.

	A miss also reports how far the blade travelled during the sweep. A stud or
	more means the server watched a real thrust and the box was short. Near zero
	means the server never saw the animation, which padding cannot fix.

	IF NO GUN IN THE PLACE RESPONDS AT ALL, it is step 0 or the placement of the
	Bayonet module -- not the bayonet itself.

	==========================================================================
	WHY IT WORKS AT 0 AMMO
	==========================================================================

	The mode has a magazine that cannot be emptied.

	A fire mode goes through shoot(), which decrements ammo unconditionally, so
	a block with no MagCapacity has no LocalTAmmo entry and errors on every
	swing. MagCapacity = math.huge instead: inf - 1 is still inf, the magazine
	never empties, and you are never diverted into a reload. useSharedClip is
	false so swinging cannot drain the rifle's clip.

	(An earlier build of this package did the opposite -- it OMITTED MagCapacity
	to stay out of the ammo system entirely. That worked because the bayonet had
	its own key and never entered shoot(). As a fire mode it must.)

	==========================================================================
	THE CLIENT DECIDES NOTHING
	==========================================================================

	The swing sends one empty message. The hitbox IS the bayonet part, welded to
	the character, so the server knows where it is and sweeps it as the thrust
	drives it forward. Target selection, team checks and damage all stay
	server-side, and there is no position for a client to misreport.

	This is why it does not use the Melee bullet type that ships with Custom
	Bullets: that one detects on the client and reports through
	TREK_Remotes.Damage, which takes its origin from the client and does not
	check it, because ServerRays is false. Fine for a rifle; not for a melee
	attack whose whole balance is its reach.

	Kill credit still goes through TREK: TREKDamageModule.DamagePlayer tags the
	victim with the same WeaponTag the kill feed reads.

	NPCs are valid targets, deliberately -- dummies and clones are most of what
	anyone tests against.

	One thing the server CANNOT check is which fire mode you are in; TREK keeps
	no server-side mode state. A modified client could swing without switching to
	mode 2. Rate limit, team checks, the blade and the geometry all still apply.

	==========================================================================
	LIMITS
	==========================================================================

	THealth props and TVehicle are not valid targets: stabbing a tank does
	nothing. There is no bayonet-specific voice bark, though a bayonet KILL fires
	the existing Kill bark from TREK Voicelines with no changes.

	==========================================================================
	MADE BY
	==========================================================================

	PlagueByte (pb6008 on Discord). TREK and TREK Custom Bullets are not mine and
	are not included here -- this hooks into whatever install you already have.
]]

return nil

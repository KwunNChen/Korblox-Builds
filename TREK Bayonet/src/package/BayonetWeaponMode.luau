--[[
	PASTE THIS INTO YOUR WEAPON MODULE.

	This is not a script that runs. It is the block you add to the KR-61
	Bonecrusher's config module (or any rifle you fit a bayonet to), inside the
	same `local configs = { ... }` table that already holds [1].

	It holds the bayonet's damage numbers. The server reads them straight off
	this block, so TREK's own falloff, armour and gib code can be reused
	unchanged.

	----------------------------------------------------------------------------
	TWO THINGS ABOUT THIS BLOCK ARE LOAD-BEARING. Do not "tidy" either of them.
	----------------------------------------------------------------------------

	1. THE INDEX IS 9, NOT 2.

	   TREK's switchModes walks fire modes by increment:

	       if (currentMode == 1 and not config[currentMode + 1]) then return end

	   A block at [2] would put the bayonet in the V cycle, so the player could
	   switch into a "fire mode" that cannot shoot. With nothing at [2], that
	   walk stops dead and V does nothing -- while the bayonet service can still
	   look this block up directly by index.

	   If you already use [2] and [3] for real fire modes, that is fine. Keep
	   the bayonet at 9 and leave a gap.

	2. THERE IS NO MagCapacity, AND THAT IS WHY IT WORKS AT 0 AMMO.

	   Both ammo-store builders skip any mode block without one:

	       if not config['MagCapacity'] then continue end

	   So this block creates no LocalTAmmo["9"] and no TAmmo["9"]. There is no
	   magazine to empty and no ammo check to fail -- the bayonet is simply
	   outside the ammo system rather than having a very large amount of it.

	   Do NOT "fix" this by adding MagCapacity = math.huge. The HUD does
	   string.format("%03d", Ammo.Value) and Ammo.Value / maxAmmo, which render
	   infinity as -9223372036854775808 and NaN.

	   Every OTHER field below is here because TREK's gun handler builds a
	   modeStuff entry for every table in the config at load, and does

	       ProjectileTypes[tabl.ProjectileName]

	   which throws on nil and would break the whole weapon. They are inert for
	   a bayonet but they have to exist.
]]

return {

	[9] = {
		-- ===== The numbers worth tuning =====

		Damage = 100,             -- one thrust, one kill
		headShotMultiplier = 1,   -- no headshots on a stab
		ArmourDamage = 0,         -- does nothing to THealth props or vehicles
		limbRemovalChance = 100, -- every stab takes a limb (R6 only); 0 to turn gore off

		-- Range is the blade's own geometry now, not a number. A hit means the
		-- bayonet was overlapping the target, so the distance passed to TREK's
		-- falloff is ~0 and these never bite. They stay non-infinite only so a
		-- stray call can never produce damage at range.
		fallOffStart = 8,
		fallOffEnd = 10,

		TeamKill = false,

		-- ===== Inert, but required to exist (see note 2 above) =====

		GunType = 2,
		BulletType = 1,
		RayType = 'FakeProjectile',
		ImpactEffect = 'Standard',

		ProjectileName = 'Bullet',
		ProjectileVelocity = 2000,
		ProjectileAcceleration = Vector3.new(0, -workspace.Gravity, 0),

		TurnToTarget = true,
		VerticalTurning = true,

		Charged = false,
		ChargeTime = 0,
		WindDownTime = 0,

		CanSuppress = false,
		ExtraSuppression = false,

		Distance = 8,

		baseSpread = 0,
		zoomSpreadAddition = 0,
		jumpSpreadAddition = 0,
		crouchSpreadAddition = 0,
		oneHandedSpreadAddition = 0,

		explosiveRays = false,
		explosionsIgnoreWalls = false,
		explosionName = 'Explosion',

		RaysPerShot = 1,
		BurstAmount = 1,
		RoundsPerMinute = 60,

		useSharedClip = false,
		ReservedAmmo = 0,

		CanReload = false,
		ReloadType = 1,
		ReloadSpeed = 1,

		CanZoom = false,
		Scope = false,
		ScopeType = 'Classic',
		ZoomFov = 70,

		TeamRayColour = false,
		CustomRayColour = Color3.fromRGB(255, 255, 255),
	},

}

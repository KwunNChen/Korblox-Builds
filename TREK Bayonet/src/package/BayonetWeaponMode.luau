--[[
	PASTE THIS INTO YOUR WEAPON MODULE.

	This is not a script that runs. It is the block you add to the KR-61
	Bonecrusher's config module (or any rifle you fit a bayonet to), inside the
	same `local configs = { ... }` table that already holds [1].

	It makes the bayonet a FIRE MODE. Press V in game and you switch from the
	rifle to the blade.

	Requires TREK Custom Bullets as the gun handler -- vanilla TREK has no
	BulletType field and will ignore this entirely.

	----------------------------------------------------------------------------
	FOUR THINGS HERE ARE LOAD-BEARING. Do not "tidy" any of them.
	----------------------------------------------------------------------------

	1. THE INDEX IS 2, AND IT USED TO BE 9 FOR THE OPPOSITE REASON.

	   switchModes walks fire modes by increment:

	       if (currentMode == 1 and not config[currentMode + 1]) then return end

	   An earlier version of this system put the bayonet at [9] SO THAT V could
	   never reach it -- it was triggered by its own key and only borrowed the
	   block for its numbers. The bayonet is a fire mode now, so it has to sit
	   exactly where that walk lands.

	   If you already use [2] for a real fire mode, move the bayonet to the end
	   of the run (the first free index after your last mode) and set
	   BayonetConfig.ConfigIndex to match. It must be reachable by incrementing.

	2. BulletType MUST BE SPELLED EXACTLY "Bayonet".

	   The gun handler resolves it by module name:

	       local bulletType = bulletTypes[config[i].BulletType]
	       if not(bulletType) then return end

	   That `return` is at SCRIPT scope, not loop scope. A typo here does not
	   break the bayonet -- it exits the handler before the mouse is connected,
	   and EVERY weapon in the place stops responding. If guns suddenly do
	   nothing at all, this line is the first place to look.

	3. MagCapacity = math.huge, AND IT MUST BE A NUMBER, NOT 'INF'.

	   A melee mode still goes through shoot(), which does

	       tool.LocalTAmmo[mode].Ammo.Value -= 1

	   unconditionally. Omitting MagCapacity -- which is how the old [9] block
	   stayed out of the ammo system -- now means no LocalTAmmo entry and an
	   error on every swing. Infinity works because inf - 1 is still inf: the
	   mode never runs dry, so the bayonet swings at 0 rifle ammo without being
	   outside the ammo system at all.

	   TREK's own "infinite" sentinel is the STRING 'INF', but the client's
	   ammo store assigns ReservedAmmo straight onto a DoubleConstrainedValue,
	   which rejects a string. Use the number.

	4. CanReload = false, AND IT PREVENTS A REAL BUG.

	   Because ReservedAmmo is math.huge rather than 'INF', TREK's reload
	   handler misses its early return and computes

	       local difference = (config.MagCapacity - loaded.Value)   -- inf - inf

	   which is NaN, and writes it into your ammo values. CanReload = false is
	   checked in reloadSecurityChecks before any of that can be reached, so
	   pressing R in this mode simply does nothing.

	----------------------------------------------------------------------------
	AND ONE THING THAT IS NOT IN THIS FILE
	----------------------------------------------------------------------------

	The animation. Name it "2Recoil" and put it in the weapon module's
	Animations folder -- determineAnim prefixes the mode number and falls back to
	the unprefixed name, so "2Recoil" plays on a bayonet swing while "Recoil"
	still plays when you fire the rifle. "2Idle" and "2SprintHold" do the same
	for the held pose and the charge.
]]

return {

	[2] = {
		-- ===== What makes this the bayonet =====

		BulletType = 'Bayonet', -- exact spelling, see note 2
		GunType = 2, -- semi: one swing per click

		-- ===== The numbers worth tuning =====

		Damage = 100, -- one thrust, one kill
		headShotMultiplier = 1, -- no headshots on a stab
		ArmourDamage = 0, -- does nothing to THealth props or vehicles
		limbRemovalChance = 100, -- every stab takes a limb (R6 only); 0 to turn gore off

		RoundsPerMinute = 50, -- ~1.2s between swings; the server rate-limits from this too

		-- Range is the blade's own geometry, not a number. A hit means the
		-- bayonet was overlapping the target, so the distance passed to TREK's
		-- falloff is ~0. Infinity here disables falloff outright.
		fallOffStart = math.huge,
		fallOffEnd = math.huge,

		TeamKill = false,

		-- ===== Ammo: see notes 3 and 4 =====

		MagCapacity = math.huge,
		ReservedAmmo = math.huge,
		useSharedClip = false, -- must not share the rifle's clip, or swinging drains it
		CanReload = false,
		ReloadType = 1,
		ReloadSpeed = 1,
		ReloadOnlyWithEmptyMag = false,

		-- ===== Inert, but required to EXIST =====
		--
		-- Two different handlers read these without a nil check.
		--
		-- VANILLA TREK builds a modeStuff entry for every table in the config at
		-- load and does
		--
		--     ProjectileTypes[tabl.ProjectileName]
		--
		-- which throws on nil and takes the WHOLE WEAPON down -- not just this
		-- mode. So ProjectileName and friends stay here even though a bayonet
		-- fires nothing, purely so a half-finished install cannot brick the gun.
		--
		-- TREK's damage and gibs modules index the rest at damage time.

		ProjectileName = 'Bullet',
		ProjectileVelocity = 2000,
		ProjectileAcceleration = Vector3.new(0, -workspace.Gravity, 0),
		RayType = 'FakeProjectile',

		ImpactEffect = nil,
		CollisionGroup = nil,

		TurnToTarget = true,
		VerticalTurning = true,

		Charged = false,
		ChargeTime = 0,
		WindDownTime = 0,

		Distance = 8, -- unused by this bullet type; the geometry decides reach

		baseSpread = 0,
		zoomSpreadAddition = 0,
		jumpSpreadAddition = 0,
		crouchSpreadAddition = 0,
		oneHandedSpreadAddition = 0,

		CameraRecoil = false,
		RecoilX = 0,
		RecoilY = 0,
		RecoilZ = 0,
		RecoilZoomMultiplier = 1,
		RecoilCrouchMultiplier = 1,

		FiringShakesCamera = false,
		CameraShakeMagnitude = 0,
		CameraShakeRoughness = 0,
		CameraShakeFadeInTime = 0,
		CameraShakeFadeOutTime = 0,
		CameraShakeZoomMultiplier = 1,
		CameraShakeCrouchMultiplier = 1,

		explosiveRays = false,
		explosionsIgnoreWalls = false,
		explosionName = 'Explosion',
		explosionRadius = 0,
		explosionFullDamageRadius = 0,

		CanSuppress = false,
		ExtraSuppression = false,

		RaysPerShot = 1,
		BurstAmount = 1,

		CanZoom = false,
		Scope = false,
		ScopeType = 'Classic',
		ZoomFov = 70,

		TeamRayColour = false,
		CustomRayColour = Color3.fromRGB(255, 255, 255),
	},

}

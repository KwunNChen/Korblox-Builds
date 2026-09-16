	--[[
	GUN TYPES:
		1 = Automatic
		2 = SemiAutomatic
		3 = Burst
	--
	RELOAD TYPES:
		1 = Reload by changing your mag
		2 = Reload by recharging your weapon(+1 bullet every X seconds, X being your ReloadSpeed)
		3 = Same as 2, but the weapon will start recharging automatically without any input, even if unequipped
	--
	BULLET TYPES(DEFINES YOUR WEAPON BEHAVIOUR WHEN FIRED):
		Hitscan
		Projectiles
		Melee
	--
	PROJECTILE TYPES(THE MODEL YOUR PROJECTILES WILL USE):
		Bullet
		Grenade
		Flare
		Missile
	--
	RAY TYPES(WHAT YOUR WEAPON RAYS WILL LOOK LIKE IF USING BULLET TYPE 1)l
		FakeProjectile (Classic TREK fake projectiles)
		Ray (Regular laser beams)
	--
	EXPLOSION TYPES(WHICH EXPLOSION PARTICLES WILL APPEAR ON IMPACT):
		SmallExplsoion
		Explosion
		BigExplosion
		Invisibile
	--
	SCOPE TYPES(WHICH SCOPE THIS GUN WILL HAVE, ONLY AFFECTS VISUALS):
		Classic
		Futuristic
	]]

local configs = {
	ToolType = 'Gun';
	--Which Tool Handler this weapon will use, the only vanilla tool handler is "Gun"
	--You can add more Tool Handlers using plugins or by changing the core module

	--[[
	HOW TO ADD MORE MODES TO THE WEAPON:
	All the mode configs are inside dictionaries:
	EXAMPLE:
		[1] = {
			[...] = ...;
			[...] = ...;
		};
	Clone the first dictionary and add it below, rename it to the number following the previous one
	EXAMPLE:
		[1] = {
			[...] = ...;
			[...] = ...;
		};
		[2] = {
			[...] = ...;
			[...] = ...;
		};
	PRESS V (CONFIGURABLE IN GLOBAL CONFIGS) TO CHANGE YOUR MODE
	]]
	
	[1] = {
		GunType = 2; -- refer to Gun Types
		BulletType = "Hitscan"; -- refer to Bullet Types
		RayType = 'FakeProjectile'; -- refer to Ray Types
		ImpactEffect = 'Standard'; -- refer to Impact Effects, change to nil (no quotes) to have none

		CollisionGroup = nil; -- The name of the collision group that'll be used by this mode.

		ProjectileName = 'Bullet'; -- refer to Projectile Types
		ProjectileVelocity = 4000; -- the velocity of your projectile
		ProjectileAcceleration = Vector3.new(0, -workspace.Gravity, 0); --projectile acceleration
		--Vector3.new(0, -workspace.Gravity, 0) - BulletDrop
		--Vector3.new(0, 0, 0) - No BulletDrop

		TurnToTarget = true; -- if true, the character will always turn towards the mouse cursor, unless sprinting, holstering, or reloading.
		VerticalTurning = true; -- if true, the character's arms and head will follow the cursor in the Y axis (does not replicate to others atm)

		Charged = false, -- Whether your weapon will have a delay between mouse click and gun shot (along with an animation)
		ChargeTime = 0.4, -- How long will the delay last for
		WindDownTime = 0.0001, -- The amount of time until you can fire again, only works if Charged is set to true

		TeamKill = false; -- If true, the weapon will kill your teammates (while in this mode)
		Damage = 30, -- Damage done to players
		headShotMultiplier = 2, -- Headshot multiplier (Damage * headShotMultiplier)
		ArmourDamage = 0, -- Damage done to parts with THealth values

		fallOffStart = 60, -- The amount of studs after which your weapon's damage will start dropping
		fallOffEnd = 1200, -- The amount of studs after which your weapon will stop damaging

		CanSuppress = false, -- If true, your weapon will suppress players near the area you hit
		ExtraSuppression = false, -- If true, your weapon will shake cameras of players near the area you hit
		limbRemovalChance = 0, -- The chance of destroying enemy player's limb upon impact(R6 ONLY)

		Distance = 100000; -- How far your rays or projectiles can go

		baseSpread = 0.5, -- Standard weapon spread (X amount of studs added to your target position)
		zoomSpreadAddition = 0, -- The amount of spread added by zooming
		jumpSpreadAddition = 2, -- The amount of spread added while in air
		crouchSpreadAddition = -0.5, -- The amount of spread added while crouching
		oneHandedSpreadAddition = 2, -- The amount of spread added if your LeftArm has been destroyed
		--[[
		HINT: Keep zoomSpreadAddition and crouchSpreadAddition negative to reduce the weapon spread
		when zooming and croucing
		]]

		--[[
		YOU CAN MAKE THE CAMERA RECOIL PICK A NUMBER IN A CERTAIN RANGE BY CHANGING AN OPTION FROM A NUMBER
		TO A TABLE OF 2 NUMBERS LIKE {-1,1}
		]]
		CameraRecoil = true; -- If true, your camera will recoil on each shot
		RecoilX = 6; -- Vertical (Despite being X, yes.) recoil
		RecoilY = {-9,9}; -- Horizontal (Despite being Y, yes.) recoil
		RecoilZ = {-9,9}; -- Diagonal recoil i think.

		RecoilZoomMultiplier = 0.7; -- The number to multiply all the recoil options by when zooming
		RecoilCrouchMultiplier = 0.5; -- The number to multiply all the recoil options by when crouching

		FiringShakesCamera = true; -- if true, your camera will shake from each shot
		CameraShakeMagnitude = 2.7; -- the magnitude of the shake
		CameraShakeRoughness = 2; -- the roughness of the shake
		CameraShakeFadeInTime = 0.02; -- the time it takes for the camera to get into the shaking state
		CameraShakeFadeOutTime = 0.02; -- the time it takes for the camera to get out of the shaking state

		CameraShakeZoomMultiplier = 0.5; -- the amount magnitude and roughness will be multiplied by when zooming
		CameraShakeCrouchMultiplier = 0.5; -- the amount magnitude and roughness will be multiplied by when crouching

		explosiveRays = false; -- If true, your rays and projectiles will become explosive
		explosionsIgnoreWalls = false; --If true, your explosions will not consider obstacles between them and targets
		explosionName = 'Explosion'; -- refer to Impact Types
		explosionRadius = 16; -- The radius of your explosion
		explosionFullDamageRadius = 10; -- The radius in which explosion damage will be applied fully.
		-- Targets outside of the explosionFullDamageRadius will receive reduced damage depending on the distance from the explosion.

		RaysPerShot = 1; -- The amount of rays or projectiles your weapon will fire per 1 shot
		BurstAmount = 3; -- The amount of rays or projectiles your weapon will fire in burst mode
		RoundsPerMinute = 30; -- The firerate of your weapon

		useSharedClip = true; -- If true, this mode will share its ammo with the 1st weapon mode
		MagCapacity = 5; -- Rounds in 1 magazine
		ReservedAmmo = math.huge; -- How much total ammo this weapon comes with (change to math.huge for unlimited ammo)

		CanReload = true; -- If true, you will be able to reload this weapon
		ReloadType = 1; -- Refer to Reload Types
		ReloadSpeed = 4; -- The amount of seconds it takes to reload your weapon. Applies to all reload types.
		ReloadOnlyWithEmptyMag = false; -- If true, you will only be able to reload this weapon if it has no ammo left 

		CanZoom = false; -- If true, this weapon will let you zoom in
		Scope = true; -- If true, this weapon will force you into first person and enable a scope when zooming
		ScopeType = "Classic"; -- Refer to Scope Types
		ZoomFov = 30; -- Your Field of View when zoomed in

		TeamRayColour = false; -- If true, your weapon rays will have the same colour as your team (Bullet Type 1 only)
		CustomRayColour = Color3.fromRGB(255, 128, 106); -- If TeamRayColour is false, then your rays will be of this colour
	};

	[2] = {
		GunType = 1; -- refer to Gun Types
		BulletType = "Melee"; -- refer to Bullet Types
		ImpactEffect = nil; -- refer to Impact Effects, change to nil (no quotes) to have none

		MeleeDuration = 0.2; -- duration of which the melee attack can do damage
		MeleeIFrames = 0.2; -- time after hitting a target when you can hit said target again

		TurnToTarget = true; -- if true, the character will always turn towards the mouse cursor, unless sprinting, holstering, or reloading.
		VerticalTurning = true; -- if true, the character's arms and head will follow the cursor in the Y axis (does not replicate to others atm)

		Charged = true, -- Whether your weapon will have a delay between mouse click and gun shot (along with an animation)
		ChargeTime = 0, -- How long will the delay last for
		WindDownTime = 0.05, -- The amount of time until you can fire again, only works if Charged is set to true

		Damage = 8, -- Damage done to players
		headShotMultiplier = 1, -- Headshot multiplier (Damage * headShotMultiplier)
		ArmourDamage = 0, -- Damage done to parts with THealth values

		fallOffStart = math.huge, -- The amount of studs after which your weapon's damage will start dropping
		fallOffEnd = math.huge, -- The amount of studs after which your weapon will stop damaging
		-- Change fallOffStart and fallOffEnd to math.huge to disable damage fall off with distance

		Distance = 5.5; -- How far your rays or projectiles can go

		--[[
		YOU CAN MAKE THE CAMERA RECOIL PICK A NUMBER IN A CERTAIN RANGE BY CHANGING AN OPTION FROM A NUMBER
		TO A TABLE OF 2 NUMBERS LIKE {-1,1}
		]]
		CameraRecoil = false; -- If true, your camera will recoil on each shot
		RecoilX = 6; -- Vertical (Despite being X, yes.) recoil
		RecoilY = {-9,9}; -- Horizontal (Despite being Y, yes.) recoil
		RecoilZ = {-9,9}; -- Diagonal recoil i think.

		RecoilZoomMultiplier = 0.7; -- The number to multiply all the recoil options by when zooming
		RecoilCrouchMultiplier = 0.5; -- The number to multiply all the recoil options by when crouching

		BurstAmount = 3; -- The amount of rays or projectiles your weapon will fire in burst mode
		RoundsPerMinute = 140; -- The firerate of your weapon

		useSharedClip = false; -- If true, this mode will share its ammo with other modes that have this enabled
		MagCapacity = math.huge; -- Rounds in 1 magazine
		ReservedAmmo = math.huge; -- How much total ammo this weapon comes with (change to math.huge for unlimited ammo)

		CanReload = false; -- If true, you will be able to reload this weapon
		ReloadType = 1; -- Refer to Reload Types
		ReloadSpeed = 3; -- The amount of seconds it takes to reload your weapon. Applies to all reload types.

		CanZoom = false; -- If true, this weapon will let you zoom in
		Scope = false; -- If true, this weapon will force you into first person and enable a scope when zooming
		ScopeType = "Classic"; -- Refer to Scope Types
		ZoomFov = 50; -- Your Field of View when zoomed in

		TeamRayColour = false; -- If true, your weapon rays will have the same colour as your team (Bullet Type 1 only)
		CustomRayColour = Color3.fromRGB(255, 246, 161); -- If TeamRayColour is false, then your rays will be of this colour
	};

}

return configs


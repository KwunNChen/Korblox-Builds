local projectile = {}

local FASTCAST = require(shared.S.TREK_Modules.FastCastRedux)
local effects = require(shared.S.TREK_Modules.EffectsModule)
local impactEffects = require(shared.S.TREK_Modules.ImpactParticlesModule)

function projectile.new(data)
	local object = {}
	
	local module
	if data.Tool:GetAttribute('TConfigToUse') then
		module = shared.S.GunConfigs:FindFirstChild(data.Tool:GetAttribute('TConfigToUse'), true)
	else
		module = shared.S.GunConfigs:FindFirstChild(data.Tool.Name, true)
	end

	local config = require(module)
	
	local caster = FASTCAST.new()
	FASTCAST.VisualizeCasts = false
	
	local fastCastBehavior = FASTCAST.newBehavior()
	fastCastBehavior.RaycastParams = data.ModeStuff.rayParams
	fastCastBehavior.MaxDistance = data.Config.Distance
	fastCastBehavior.Acceleration = data.Config.ProjectileAcceleration
	fastCastBehavior.CosmeticBulletTemplate = shared.S.TREK_EffectsStorage.ProjectileTypes[data.Config.ProjectileName]
	fastCastBehavior.CosmeticBulletContainer = workspace:WaitForChild('IgnoreList')
	
	local function checkForWall(barrel, spread)	
		local origin = data.Character.Head.Position
		local ending = spread
		local direction = (ending - origin).Unit * math.huge
		-- (origin - ending).Magnitude

		local ray = workspace:Raycast(origin, direction, data.ModeStuff.rayParams)
		if ray then return true, ray.Position end

		return false
	end
	
	local function renderHit(caster, rayresult, veloccity, bullet, normal)
		local modeToUse = caster.UserData.ModeOverride or data.Mode

		if data.Config.CanSuppress then effects.Suppress.DrawEffect(data.Player,data.Character,bullet,config[modeToUse].ExtraSuppression) end

		if not rayresult then return end
		if not rayresult.Instance then return end

		local particleType = config[modeToUse].ImpactEffect
		if not particleType then return end
		if not impactEffects[particleType] then return end

		impactEffects[particleType].DrawEffect(rayresult.Position, rayresult.Instance.Color)
	end
	
	local function onRayHit(cast, raycastResult, segmentVelocity, cosmeticBulletObject)
		local obj = raycastResult.Instance
		local pos = raycastResult.Position
		local normal = raycastResult.Normal

		if not obj then return end

		--renderHit(cast, raycastResult, segmentVelocity, cosmeticBulletObject, normal)

		if data.Config.explosiveRays then
			local mode = data.Mode
			if cast.UserData.ModeOverride then mode = cast.UserData.ModeOverride end
			shared.S.TREK_Remotes.Explosion:FireServer(pos, mode)
		end

		if cast.UserData.NoDamage then return end
		data.DamageFunction(obj)
	end
	 
	function object.fire(barrel, spread)
		local dir
		local blocked, blockingPosition = checkForWall(barrel, spread)

		if blocked then
			dir = (blockingPosition - barrel.Position).Unit * data.Config.Distance
		else
			dir = (spread - barrel.Position).Unit * data.Config.Distance
		end

		local cast = caster:Fire(barrel.Position, dir, data.Config.ProjectileVelocity, fastCastBehavior)

		shared.S.TREK_Remotes.ProjectileRemote:FireServer(data.Tool.Name, barrel.Position, dir, data.Config.ProjectileVelocity, fastCastBehavior, data.Mode)
		shared.S.TREK_Remotes.ProjectileBind:Fire(data.Tool.Name, barrel.Position, dir, data.Config.ProjectileVelocity, fastCastBehavior, data.Config.CanSuppress, data.Config.ExtraSuppression, data.Config.ImpactEffect)
		--(name, pos, dir, vel, behavior, cansuppress, extrasuppression, impacteffect)

		if cast.RayInfo.CosmeticBulletObject then
			cast.RayInfo.CosmeticBulletObject:Destroy()
		end
	end


	local function castEnded(caster)

	end

	local function lengthChanged(thecaster, lastpoint, direction, displacement, velocity, bulletobj)

	end
	
	caster.RayHit:Connect(onRayHit)
	caster.LengthChanged:Connect(lengthChanged)
	caster.CastTerminating:Connect(castEnded)
	
	return object
end

return projectile

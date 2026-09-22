local hitscan = {}

local function findPlrAndChar(part)
	if not part then return nil end
	if not part.Parent then return nil end

	local object = part
	local hum

	while object and object.Parent ~= nil do
		hum = object:FindFirstChild("Humanoid")

		if hum or object.Parent == workspace then break end

		object = object.Parent
	end

	if not hum then return nil, nil end

	local plr2 = game.Players:GetPlayerFromCharacter(object.Parent)

	if plr2 then return plr2, object.Parent end

	return nil, object
end

function hitscan.new(data)
	local object = {}
	
	local function createRayInfoTable(start, dest, TargetSurface)
		local rayInfo = {}
		local customInfo = data.Config.CustomRayInfo

		rayInfo.Start = start
		rayInfo.Destination = dest
		rayInfo.Color = data.Config.CustomRayColour
		rayInfo.ProjectileType = data.Config.ProjectileName
		rayInfo.CanSuppress = data.Config.CanSuppress
		rayInfo.ImpactEffect = data.Config.ImpactEffect
		rayInfo.TargetSurface = TargetSurface
		rayInfo.RayType = data.Config.RayType
		rayInfo.Distance = data.Config.Distance

		if customInfo then
			for name, value in pairs(customInfo) do
				rayInfo[name] = value
			end
		end

		return rayInfo
	end

	local function rayFunctions(ray, spread)
		local isplayer = false
		local mat

		if not ray then return isplayer,mat,spread end

		data.DamageFunction(ray.Instance)

		local plr, chr = findPlrAndChar(ray.Instance)
		if plr then isplayer = true end
		mat = ray.Instance.Color

		return isplayer,mat,ray.Position
	end

	function object.fire(barrel, spread)
		local visualOrigin = barrel.Position
		local origin = data.Character.Head.Position
		local direction = (spread - origin).Unit * data.Config.Distance

		local ray = workspace:Raycast(origin, direction, data.ModeStuff.rayParams)

		local isplayer,mat,hitpos = rayFunctions(ray, spread)

		if data.Config.explosiveRays then 
			shared.S.TREK_Remotes.Explosion:FireServer(hitpos, data.Mode)
		end

		local localInfo = createRayInfoTable(visualOrigin, hitpos, mat)

		shared.S.TREK_Remotes.RayBind:Fire(localInfo)
		shared.S.TREK_Remotes.RayRemote:FireServer(visualOrigin, hitpos, mat, data.Mode)
	end

	return object

end

return hitscan

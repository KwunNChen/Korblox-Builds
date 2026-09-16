local melee = {}

local SHAPECASTHITBOX = require(shared.S.TREK_Modules.ShapecastHitbox)

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

--[[
		bulletData.Barrel
		bulletData.Config
		bulletData.ModeStuff
		bulletData.Spread
		bulletData.Character
		bulletData.Mode
		bulletData.DamageFunction
]]

function melee.new(data)
	local object = {}
	
	local barrel = (data.Tool:FindFirstChild(tostring(data.Mode)..'Barrel') and data.Tool[tostring(data.Mode)..'Barrel']) or data.Tool.Barrel
	
	local shapeCastHitbox = SHAPECASTHITBOX.new(
		barrel,
		data.ModeStuff.rayParams)
	local previousHits = {}
	local iFrames = data.Config.MeleeIFrames or data.Config.MeleeDuration
	
	local function onShapeCastHitboxHit(raycastResult, hitbox) -- melee
		local obj = raycastResult.Instance
		local pos = raycastResult.Position

		if not obj then return end

		local enplr, enchr = findPlrAndChar(obj)
		local isTHealth = obj:FindFirstChild('THealth')
		local isTVehicle = obj:FindFirstAncestor('TVehicle')

		local identifier = enchr or isTHealth or isTVehicle
		if identifier then
			local pastTime = previousHits[identifier] or 0
			if pastTime + iFrames > time() then
				return
			end
			previousHits[identifier] = time()
		end
		--[[for i, t in pairs(previousHits) do
			if t + iFrames < time() then
				previousHits[i] = nil
			end
		end]]

		data.DamageFunction(obj)
	end
	

	function object.fire(barrel, spread)
		shapeCastHitbox:HitStart(data.Config.MeleeDuration)
	end
	
	shapeCastHitbox:OnHit(onShapeCastHitboxHit)

	return object

end

return melee

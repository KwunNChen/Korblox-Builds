--[[
	Random skin tone. Settings.RandomAppearance off keeps the model's own.
]]

local skinOptions = {"Wheat","Cashmere","Beige","Khaki","Buttermilk","Pastel yellow"}

local marine = script.Parent.Parent.Parent

if marine.Settings.RandomAppearance.Value then
	local waited = 0
	while not marine:GetAttribute("BloxianCloned") and waited < 5 do
		waited += task.wait()
	end

	--Korblox presets paint their own skin in UniformModule.
	if string.find(marine:GetAttribute("UniformPreset") or "","^Korblox") then
		return
	end

	local randomSkin = BrickColor.new(skinOptions[math.random(#skinOptions)])
	local bc = marine["Body Colors"]
	bc.HeadColor = randomSkin
	bc.LeftArmColor = randomSkin
	bc.RightArmColor = randomSkin
	bc.LeftLegColor = randomSkin
	bc.RightLegColor = randomSkin
	bc.TorsoColor = randomSkin
end

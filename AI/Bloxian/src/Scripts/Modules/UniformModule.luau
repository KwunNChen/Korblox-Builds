--[[
	Uniforms: what a soldier wears. A preset is a list of rules; every rule that
	matches him is applied once he has spawned.

	A rule matches on whichever of these it names; leave one out to match everyone:
		unit    "Infantry", "Sniper", "Spotter", "Rocketeer", "Loader", "Pilot",
		        "Special Recon"
		role    "Rifleman" or "Radioman"
	and sets:
		morph   a model in ServerStorage.BloxiaMorphs: its Shirt, Pants and gear go
		        on him, each piece where it sits on the morph's body
		skin    a Color3 for his whole body
]]

local uniform = {}

local ServerStorage = game:GetService("ServerStorage")

local modules = script.Parent
local marine = modules.Parent.Parent
local mySettings = marine.Settings

--Uniform presets: the spawner panel's Uniform row picks one by name. To add one,
--put it here and its name in the Uniform row in SpawnerClient.
uniform.presets = {
	Bloxia = {
		{unit = "Infantry", role = "Rifleman", morph = "Infantry"},
		{unit = "Infantry", role = "Radioman", morph = "Radioman"},
		{unit = "Sniper", morph = "Sniper"},
		{unit = "Spotter", morph = "Sniper"},
		{unit = "Special Recon", morph = "SpecOps"},
		{unit = "Rocketeer", morph = "Infantry"},
		{unit = "Loader", morph = "Infantry"},
		{unit = "Pilot", morph = "Infantry"},
	},
	--Tower Assault's CBRN squad (ServerStorage.TowerBosses): full hazmat on everyone.
	CBRN = {
		{morph = "Hazmat"},
	},
	Korblox = {
		{skin = BrickColor.new("Institutional white").Color},
		{unit = "Infantry", role = "Rifleman", morph = "KorbloxInfantry"},
		{unit = "Infantry", role = "Radioman", morph = "KorbloxRadioman"},
		{unit = "Sniper", morph = "KorbloxInfantry"},
		{unit = "Spotter", morph = "KorbloxInfantry"},
		{unit = "Special Recon", morph = "KorbloxInfantry"},
		{unit = "Rocketeer", morph = "KorbloxInfantry"},
		{unit = "Loader", morph = "KorbloxInfantry"},
		{unit = "Pilot", morph = "KorbloxInfantry"},
	},
	KorbloxNaval = {
		{skin = BrickColor.new("Institutional white").Color},
		{unit = "Infantry", role = "Rifleman", morph = "NavalRaider"},
		{unit = "Infantry", role = "Radioman", morph = "NavalRaiderVest"},
		{unit = "Sniper", morph = "NavalRaiderVest"},
		{unit = "Spotter", morph = "NavalRaiderVest"},
		{unit = "Special Recon", morph = "NavalRaiderVest"},
		{unit = "Rocketeer", morph = "NavalRaider"},
		{unit = "Loader", morph = "NavalRaider"},
		{unit = "Pilot", morph = "NavalRaider"},
	},
}

--What a soldier with no preset of his own wears: placed by hand, or bailed out.
local DEFAULT_PRESET = "Bloxia"
if not uniform.presets[marine:GetAttribute("UniformPreset")] then
	marine:SetAttribute("UniformPreset",DEFAULT_PRESET)
end

local function weldTo(bodyPart,part,name)
	part.Name = name
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = part
	weld.Parent = part
	part.Parent = marine
end

local function wearMorph(name)
	local folder = ServerStorage:FindFirstChild("BloxiaMorphs")
	local morph = folder and folder:FindFirstChild(name)
	if not morph then
		warn("[Bloxian] no morph "..name.." in ServerStorage.BloxiaMorphs")
		return
	end

	for _,className in ipairs({"Shirt","Pants"}) do
		local clothing = morph:FindFirstChildOfClass(className)
		local old = marine:FindFirstChildOfClass(className)
		if clothing and old then
			old:Destroy()
		end
		if clothing then
			clothing:Clone().Parent = marine
		end
	end

	for index,part in ipairs(morph:GetDescendants()) do
		if part:IsA("BasePart") and part.Parent ~= morph then
			local body = morph:FindFirstChild(part:GetAttribute("Body") or "Torso")
			local mine = marine:FindFirstChild(body.Name)
			if mine then
				local piece = part:Clone()
				for _,joint in ipairs(piece:GetChildren()) do
					if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
						joint:Destroy()
					end
				end
				piece.Anchored = false
				piece.CastShadow = false
				piece.CFrame = mine.CFrame*body.CFrame:ToObjectSpace(part.CFrame)
				weldTo(mine,piece,"Morph"..index)
			end
		end
	end
end

local LIMBS = {"Head","Torso","Left Arm","Right Arm","Left Leg","Right Leg","UpperTorso","LowerTorso","LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand","LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot"}

local function paintSkin(color)
	local colors = marine:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	for _,field in ipairs({"HeadColor3","TorsoColor3","LeftArmColor3","RightArmColor3","LeftLegColor3","RightLegColor3"}) do
		colors[field] = color
	end
	colors.Parent = marine
	for _,name in ipairs(LIMBS) do
		local part = marine:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local function matches(rule)
	local unitValue = mySettings:FindFirstChild("Unit")
	local roleValue = mySettings:FindFirstChild("Role")
	return (rule.unit == nil or rule.unit == (marine:GetAttribute("Unit") or unitValue and unitValue.Value or "Infantry"))
		and (rule.role == nil or rule.role == (marine:GetAttribute("Role") or roleValue and roleValue.Value))
end

--Waits for the respawn copy to be taken first, or it would carry the uniform too,
--and for RadioModule to roll his Role, or rules naming a role would miss him.
task.spawn(function()
	local waited = 0
	while not (marine:GetAttribute("BloxianCloned") and marine:GetAttribute("Role")) and waited < 5 do
		waited += task.wait()
	end
	for _,rule in ipairs(uniform.presets[marine:GetAttribute("UniformPreset")]) do
		if matches(rule) then
			if rule.morph then
				wearMorph(rule.morph)
			end
			if rule.skin then
				paintSkin(rule.skin)
			end
		end
	end
end)

return uniform

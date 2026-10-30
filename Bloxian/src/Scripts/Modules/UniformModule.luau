--[[
	Uniforms: what a soldier wears, by team, unit and role. Every rule that
	matches him is applied, top to bottom, once he has spawned.

	A rule matches on whichever of these it names; leave one out to match everyone:
		team    Settings.Team, e.g. "Hostile" or a Roblox team's name
		unit    "Infantry", "Sniper", "Spotter", "Rocketeer", "Loader" or "Pilot"
		role    "Rifleman" or "Radioman"
	and can set:
		accessories   catalog ids to wear: hats, packs, vests, jackets, suits
		helmet        false takes his helmet off
		face          false takes off his random face accessory (beard, mask, glasses)
		remove        names of other kit to take off
		shirt, pants  catalog ids of a classic Shirt or Pants
		offset        a CFrame nudging the rule's accessories from where they sit

	Layered clothing (jackets, sweaters, suits) cannot stretch over these R6
	bodies, so it is worn rigidly on the body part its attachment names,
	usually the torso: it does not swing with the arms and legs.
]]

local uniform = {}

local InsertService = game:GetService("InsertService")

local modules = script.Parent
local marine = modules.Parent.Parent
local mySettings = marine.Settings

--Dark Grass Camouflage Ghillie, by interesting...: rigid accessories, so the
--shoulder pieces move with the arms. Head, body, left and right shoulder, legs.
local GHILLIE = {18291961528,18291972030,18291985832,18291992179,18291997187}

--Olive Rucksack: the AT team's Loader carries the spare rounds in it.
local OLIVE_RUCKSACK = 11914890171

--Apache crews that bailed out: Realistic Military Pilot Aviator Helmet and the
--USAF Pilot Flight Suit shirt and pants.
local AVIATOR_HELMET = 88312962939182
local FLIGHT_SUIT_SHIRT = 126970663663675
local FLIGHT_SUIT_PANTS = 124011055669062

uniform.rules = {
	{unit = "Sniper", accessories = GHILLIE, helmet = false, face = false},
	{unit = "Spotter", accessories = GHILLIE, helmet = false, face = false},
	{unit = "Loader", accessories = {OLIVE_RUCKSACK}},
	{unit = "Pilot", accessories = {AVIATOR_HELMET}, helmet = false, face = false, remove = {"Comtacs no not the person"},
		shirt = FLIGHT_SUIT_SHIRT, pants = FLIGHT_SUIT_PANTS},
	--{team = "Hostile", unit = "Infantry", shirt = 0, pants = 0},
}

--The helmet a rule with helmet = false takes off, by name.
uniform.HELMET_NAMES = {"Accessory (K-Pot Covered)","ACH"}

local BODY_PARTS = {"Torso","Head","Left Arm","Right Arm","Left Leg","Right Leg"}

--Shared with RandomizeAppearance: each asset downloads once per server.
_G.BloxianAccessoryCache = _G.BloxianAccessoryCache or {}
_G.BloxianAccessoryLoading = _G.BloxianAccessoryLoading or {}
local cache = _G.BloxianAccessoryCache
local loading = _G.BloxianAccessoryLoading

--The catalog asset's Accessory (or Shirt, or Pants), held out of the world. nil if it did not load.
function uniform.template(id,className)
	className = className or "Accessory"
	if cache[id] then
		return cache[id]
	end
	if loading[id] then
		while loading[id] do
			task.wait(0.1)
		end
		return cache[id]
	end
	loading[id] = true

	local ok,model = pcall(InsertService.LoadAsset,InsertService,id)
	if ok and model then
		local item = model:FindFirstChildWhichIsA(className,true)
		if item then
			item.Parent = nil
			cache[id] = item
		end
		model:Destroy()
	end
	if not cache[id] then
		warn("[Bloxian] could not load "..className.." "..id)
	end

	loading[id] = nil
	return cache[id]
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

--The body part carrying an attachment of this name, or nil.
local function bodyPartWith(attachmentName)
	for _,partName in ipairs(BODY_PARTS) do
		local part = marine:FindFirstChild(partName)
		if part and part:FindFirstChild(attachmentName) then
			return part
		end
	end
	return nil
end

--Puts a catalog accessory on him, lined up the way Roblox would wear it: the
--accessory's attachment on the matching one of his body. bodyPart and
--defaultAttachment are used when his body has no match. False if it did not load.
function uniform.wear(id,name,bodyPart,defaultAttachment,offset)
	local template = uniform.template(id)
	local handle = template and template:FindFirstChild("Handle")
	if not handle or not marine.Parent then
		return false
	end

	handle = handle:Clone()
	for _,child in ipairs(handle:GetChildren()) do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("WrapLayer") then
			child:Destroy()
		end
	end

	local own = handle:FindFirstChildWhichIsA("Attachment")
	local part = own and bodyPartWith(own.Name) or bodyPart or marine:FindFirstChild("Torso")
	if not part then
		return false
	end
	local body = own and part:FindFirstChild(own.Name) or (defaultAttachment and part:FindFirstChild(defaultAttachment))
	local bodyCFrame = body and body.WorldCFrame or part.CFrame
	handle.CFrame = bodyCFrame*(offset or CFrame.identity)*(own and own.CFrame:Inverse() or CFrame.identity)
	weldTo(part,handle,name)
	return true
end

function uniform.removeHelmet()
	for _,name in ipairs(uniform.HELMET_NAMES) do
		local helmet = marine:FindFirstChild(name)
		if helmet then
			helmet:Destroy()
		end
	end
end

local function setClothing(id,className)
	local template = uniform.template(id,className)
	if not template or not marine.Parent then
		return
	end
	local old = marine:FindFirstChildOfClass(className)
	if old then
		old:Destroy()
	end
	template:Clone().Parent = marine
end

local function matches(rule)
	local unitValue = mySettings:FindFirstChild("Unit")
	local roleValue = mySettings:FindFirstChild("Role")
	return (rule.team == nil or rule.team == mySettings.Team.Value)
		and (rule.unit == nil or rule.unit == (marine:GetAttribute("Unit") or unitValue and unitValue.Value or "Infantry"))
		and (rule.role == nil or rule.role == (marine:GetAttribute("Role") or roleValue and roleValue.Value))
end

local function dress()
	for _,rule in ipairs(uniform.rules) do
		if matches(rule) then
			if rule.helmet == false then
				uniform.removeHelmet()
			end
			if rule.face == false then
				--RandomizeAppearance checks this before putting one on.
				marine:SetAttribute("NoFaceAccessory",true)
				for _,part in ipairs(marine:GetChildren()) do
					if part:GetAttribute("FaceAccessory") then
						part:Destroy()
					end
				end
			end
			for _,name in ipairs(rule.remove or {}) do
				local item = marine:FindFirstChild(name)
				if item then
					item:Destroy()
				end
			end
			if rule.shirt then
				setClothing(rule.shirt,"Shirt")
			end
			if rule.pants then
				setClothing(rule.pants,"Pants")
			end
			for _,id in ipairs(rule.accessories or {}) do
				uniform.wear(id,"Uniform"..id,nil,nil,rule.offset)
			end
		end
	end
end

--Waits for the respawn copy to be taken first, or it would carry the uniform too.
task.spawn(function()
	local waited = 0
	while not marine:GetAttribute("BloxianCloned") and waited < 5 do
		waited += task.wait()
	end
	dress()
end)

return uniform

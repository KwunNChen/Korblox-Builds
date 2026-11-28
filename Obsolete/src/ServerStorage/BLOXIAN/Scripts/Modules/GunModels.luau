--[[
	The gun each weapon shows. The M4 mesh stays the gun every script holds
	(its welds, hinge, sounds and Barrel attachment); a weapon listed here hides
	the mesh and welds a model from ServerStorage.BloxianGuns to it, then moves
	the Barrel attachment to the new muzzle and swaps in the model's own
	magazine for reloads. A weapon not listed, or whose model is missing, keeps
	the M4 mesh.

	The models ship in assets/guns. Per model:
		model         its name in ServerStorage.BloxianGuns
		reference     the part it is placed by (optional; "Mag" otherwise)
		forward       turns the model so its muzzle points down the M4's -Z
		boreAboveMag  height of the barrel's line above the reference part, in the model's studs
		scale         size on the soldier against the model's own size
		at            where that point (on the bore, above the magazine) goes on the M4
		muzzle        where the Barrel attachment goes on the M4

	The M4's own space: -Z is toward the muzzle, +Y is up, the bore is at
	Y = 0.24 and the hand grips at Z = 1.1.
]]

local gunModels = {}

local ServerStorage = game:GetService("ServerStorage")

local marine = script.Parent.Parent.Parent
local m4 = marine.M4

local FOLDER_NAME = "BloxianGuns"

local M4A1 = {
	model = "M4A1",
	forward = CFrame.identity,
	boreAboveMag = 0.51,
	scale = 1.14,
	at = Vector3.new(0,0.24,0.23),
	muzzle = Vector3.new(0,0.24,-2.45),
}

local FAL = {
	model = "FAL",
	forward = CFrame.Angles(0,math.pi,0),
	boreAboveMag = 0.62,
	scale = 0.81,
	at = Vector3.new(0,0.24,0.3),
	muzzle = Vector3.new(0,0.24,-3.3),
}

local AWP = {
	model = "AWP",
	forward = CFrame.Angles(0,math.pi/2,0),
	boreAboveMag = 0.21,
	scale = 1.66,
	at = Vector3.new(0,0.24,0.48),
	muzzle = Vector3.new(0,0.24,-3.45),
}

local M249 = {
	model = "M249",
	forward = CFrame.Angles(0,-math.pi/2,0),
	boreAboveMag = 0.42,
	scale = 1.6,
	at = Vector3.new(0,0.24,0.3),
	muzzle = Vector3.new(0,0.24,-3),
}

--Benelli M4: no magazine, placed by its body. If it shows backwards, set forward
--to CFrame.Angles(0,math.pi,0).
local BENELLI = {
	model = "Benelli",
	reference = "Body",
	forward = CFrame.identity,
	boreAboveMag = 0.28,
	scale = 1.1,
	at = Vector3.new(0,0.24,0.3),
	muzzle = Vector3.new(0,0.24,-2.45),
}

local XM177_M203 = {
	model = "XM177M203",
	forward = CFrame.identity,
	boreAboveMag = 0.46,
	scale = 1.22,
	at = Vector3.new(0,0.24,0.23),
	muzzle = Vector3.new(0,0.24,-2.15),
}

--AR-18 with its 3x20 optic.
local AR18 = {
	model = "AR18",
	forward = CFrame.Angles(0,-math.pi/2,0),
	boreAboveMag = 0.47,
	scale = 1,
	at = Vector3.new(0,0.24,0.34),
	muzzle = Vector3.new(0,0.24,-2.53),
}

--Korblox FN FAL, bayonet fixed.
local FNFAL = {
	model = "FNFAL",
	forward = CFrame.Angles(0,math.pi,0),
	boreAboveMag = 0.6,
	scale = 1,
	at = Vector3.new(0,0.24,0.3),
	muzzle = Vector3.new(0,0.24,-2.59),
}

--Korblox KZW-A-4 bolt-action: no magazine, placed by its body.
local KZW_A4 = {
	model = "KZW-A-4",
	reference = "Body",
	forward = CFrame.Angles(0,math.pi,0),
	boreAboveMag = 0.3,
	scale = 1,
	at = Vector3.new(0,0.24,0.1),
	muzzle = Vector3.new(0,0.24,-2.67),
}

--Korblox Naval Infantry's rifle, wooden furniture.
local NAVAL_RIFLE = {
	model = "NavalRifle",
	forward = CFrame.Angles(0,math.pi,0),
	boreAboveMag = 0.35,
	scale = 1,
	at = Vector3.new(0,0.24,0.3),
	muzzle = Vector3.new(0,0.24,-2.91),
}

gunModels.models = {
	Rifle = FAL,
	Carbine = FAL,
	LMG = M249,
	JuggernautLMG = M249,
	Sniper = AWP,
	Shotgun = BENELLI,
	M203 = XM177_M203,
}

--Guns a uniform preset (UniformModule) swaps in for its own soldiers, by unit
--(Settings.Unit) first, then by weapon. Shotguns always keep their own model.
gunModels.presets = {
	Bloxia = {Rifle = AR18, Carbine = AR18, DMR = AR18},
	Korblox = {Rifle = FNFAL, Carbine = FNFAL, DMR = KZW_A4, Sniper = KZW_A4, Spotter = KZW_A4},
	KorbloxNaval = {
		Rifle = NAVAL_RIFLE, Carbine = NAVAL_RIFLE, DMR = NAVAL_RIFLE, LMG = NAVAL_RIFLE,
		Sniper = NAVAL_RIFLE, M203 = NAVAL_RIFLE,
	},
}

local function scalePart(part,scale)
	part.Size *= scale
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		if mesh.MeshType == Enum.MeshType.FileMesh then
			mesh.Scale *= scale
		end
		mesh.Offset *= scale
	end
end

function gunModels.fit(weaponName)
	local preset = gunModels.presets[marine:GetAttribute("UniformPreset") or "Bloxia"]
	local unitValue = marine.Settings:FindFirstChild("Unit")
	local unit = marine:GetAttribute("Unit") or unitValue and unitValue.Value
	local spec = weaponName ~= "Shotgun" and preset and (preset[unit] or preset[weaponName]) or gunModels.models[weaponName]
	local folder = ServerStorage:FindFirstChild(FOLDER_NAME)
	local template = spec and folder and folder:FindFirstChild(spec.model)
	local templateReference = template and template:FindFirstChild(spec.reference or "Mag")
	if not templateReference or m4:FindFirstChild("GunModel") then
		return
	end

	local holder = template:Clone()
	holder.Name = "GunModel"
	holder:SetAttribute("GunName",template.Name) --the kill feed's icon (ServerScriptService.Medical)
	local reference = CFrame.new(templateReference.Position + Vector3.new(0,spec.boreAboveMag,0))
	local place = m4.CFrame*CFrame.new(spec.at)*spec.forward

	for _,part in ipairs(holder:GetDescendants()) do
		if part:IsA("BasePart") then
			local relative = reference:ToObjectSpace(part.CFrame)
			part.CFrame = place*CFrame.new(relative.Position*spec.scale)*relative.Rotation
			scalePart(part,spec.scale)
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = false

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = m4
			weld.Part1 = part
			weld.Parent = part
		end
	end
	holder.Parent = m4

	m4.Transparency = 1
	local barrel = m4:FindFirstChild("Barrel")
	if barrel then
		barrel.Position = spec.muzzle
	end
	local oldMag = marine:FindFirstChild("Mag")
	if oldMag then
		oldMag.Transparency = 1
	end
end

return gunModels

--[[
	PrepareGrenadeRig
	Command-bar helper. Turns the raw GasGrenades import into a working Tool.

	Paste into the Studio command bar with the place open, or drop it in
	ServerStorage and run it once from the Explorer context menu.

		- Finds ActiveGasGrenade and InactiveGasGrenade wherever they are
		- Moves them into ServerStorage.TREKGasGrenade, which is where the
		  service looks for them
		- Rigs both: PrimaryPart, welds, unanchored, sane collision
		- Builds a "Gas Grenade" Tool around the inactive model, welded into one
		  body, and leaves it in StarterPack

	It deliberately does NOT create an AnimPart. That part is how TREK hangs a
	tool off the torso, which is right for a rifle and wrong for a grenade: with
	no idle animation to carry it into the hands, a torso-joined grenade hovers
	at a fixed spot beside the chest. GasService joins it to the right hand at
	runtime instead.

	None of this is strictly required. GasService runs the same routine at
	runtime, every time, because the .rbxm arrives anchored and unwelded on every
	re-export. Running this means you can see the result in Studio instead of
	taking it on faith, and it gives you the Tool.

	Self-contained on purpose -- it must work before Rojo has synced anything.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")

local TOOL_NAME = "Gas Grenade"
local WELD_TAG = "GasRigWeld"

local function largestPart(model)
	local best, bestVolume = nil, -1
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best, bestVolume = descendant, volume
			end
		end
	end
	return best
end

-- Replaces a weld that points at a different anchor, rather than trusting the
-- tag alone. A re-rig against a new anchor would otherwise keep the old joint.
local function weldTo(anchor, part)
	local existing = part:FindFirstChild(WELD_TAG)
	if existing and existing:IsA("WeldConstraint") then
		if existing.Part0 == anchor and existing.Part1 == part then
			return
		end
		existing:Destroy()
	end
	local weld = Instance.new("WeldConstraint")
	weld.Name = WELD_TAG
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
end

-- The thrown model: one collidable root, everything else welded and massless.
local function prepareThrownRig(model)
	local root = model.PrimaryPart or largestPart(model)
	if not root then
		return nil
	end

	model.PrimaryPart = root

	for _, descendant in ipairs(model:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		descendant.Anchored = false
		descendant.CanQuery = false
		descendant.CanTouch = false

		if descendant == root then
			descendant.CanCollide = true
			descendant.Massless = false
			continue
		end

		descendant.CanCollide = false
		descendant.Massless = true
		weldTo(root, descendant)
	end

	return root
end

--[[
	The held model: one welded body, and deliberately NO AnimPart.

	AnimPart is how TREK hangs a tool off the torso -- checkForGun sees one and
	points the character's toolAnim Motor6D at it. Right for a rifle, whose
	animations carry it into the hands; wrong for a grenade with no idle pose,
	which then hovers at a fixed spot beside the chest instead of following the
	arm. Without an AnimPart, checkForGun skips that entirely and GasService
	joins the grenade to the right hand at runtime instead.
]]
local function prepareHeldRig(tool)
	local model = tool:FindFirstChild("InactiveGasGrenade")
	if not model or not model:IsA("Model") then
		return nil
	end

	local root = model.PrimaryPart or largestPart(model)
	if not root then
		return nil
	end

	model.PrimaryPart = root

	-- Remove one left by an older build, wherever it ended up.
	local stale = tool:FindFirstChild("AnimPart") or model:FindFirstChild("AnimPart", true)
	if stale then
		stale:Destroy()
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		descendant.Anchored = false
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		descendant.Massless = true

		if descendant ~= root then
			weldTo(root, descendant)
		end
	end

	return root
end

local function findModel(name)
	for _, child in ipairs(ServerStorage:GetChildren()) do
		if child.Name == "TREKGasGrenade" then
			local found = child:FindFirstChild(name)
			if found then
				return found
			end
		end
	end

	return game:FindFirstChild(name, true)
end

local active = findModel("ActiveGasGrenade")
local inactive = findModel("InactiveGasGrenade")

if not active or not inactive then
	warn(string.format(
		"[PrepareGrenadeRig] Missing model(s): %s%s. Import GasGrenades.rbxm first.",
		active and "" or "ActiveGasGrenade ",
		inactive and "" or "InactiveGasGrenade"
	))
	return
end

local folder = nil
for _, child in ipairs(ServerStorage:GetChildren()) do
	if child.Name == "TREKGasGrenade" and child:IsA("Folder") and not child:FindFirstChild("ServerStorage") then
		folder = child
		break
	end
end

if not folder then
	folder = Instance.new("Folder")
	folder.Name = "TREKGasGrenade"
	folder.Parent = ServerStorage
end

active.Parent = folder

--[[
	The Tool gets its own copy of the inactive model. The one in ServerStorage
	stays pristine so re-running this never builds a Tool around an already-rigged
	model that has drifted.
]]
local held = inactive:Clone()
inactive.Parent = folder

local existingTool = StarterPack:FindFirstChild(TOOL_NAME)
if existingTool then
	existingTool:Destroy()
end

local tool = Instance.new("Tool")
tool.Name = TOOL_NAME

--[[
	No part in the import is called Handle, and Roblox will not equip a
	RequiresHandle tool without one. GasService joins the model to the right hand
	with its own Motor6D at runtime instead.
]]
tool.RequiresHandle = false
tool.CanBeDropped = false

--[[
	Keeps TREK Bayonet's HolsterService from slinging it across the back.

	That service treats any Tool with an AnimPart as a rifle. This tool has none,
	so it is already excluded -- but the attribute states the intent outright and
	survives anyone adding an AnimPart later. Baked in here as well as set at
	runtime so the tool is correct the moment it exists in the place.
]]
tool:SetAttribute("NoHolster", true)

held.Parent = tool

local heldRoot = prepareHeldRig(tool)
prepareThrownRig(active)

tool.Parent = StarterPack

if not heldRoot then
	warn("[PrepareGrenadeRig] Built the tool but could not rig the held model.")
	return
end

print(string.format(
	"[PrepareGrenadeRig] Rigged both models, staged them in ServerStorage.TREKGasGrenade, "
		.. "and put a %q tool in StarterPack.",
	TOOL_NAME
))

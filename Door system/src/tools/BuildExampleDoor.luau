-- Studio-only. Drops a working, correctly-tagged example door into Workspace
-- so the system can be playtested before any real art exists. Never runs in
-- game -- call it from the Command Bar:
--
--   require(game.ServerStorage.KorbloxBlastDoor.Tools.BuildExampleDoor).build(workspace)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorFolder = ReplicatedStorage:WaitForChild("BlastDoor")
local Config = require(DoorFolder:WaitForChild("DoorConfig"))

local BuildExampleDoor = {}

local LEAF_SIZE = Vector3.new(4, 9, 1)

local function makeLeaf(name: string, offsetX: number, cframe: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = LEAF_SIZE
	part.Anchored = true
	part.Material = Enum.Material.DiamondPlate
	part.Color = Color3.fromRGB(90, 90, 100)
	part.CFrame = cframe * CFrame.new(offsetX, 0, 0)
	return part
end

function BuildExampleDoor.build(parent: Instance, cframe: CFrame?)
	local base = cframe or CFrame.new(0, LEAF_SIZE.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = "ExampleBlastDoor"

	local left = makeLeaf(Config.LeftPartName, -LEAF_SIZE.X / 2, base)
	left.Parent = model

	local right = makeLeaf(Config.RightPartName, LEAF_SIZE.X / 2, base)
	right.Parent = model

	local button = Instance.new("Part")
	button.Name = Config.ButtonPartName
	button.Size = Vector3.new(1, 1, 0.3)
	button.Anchored = true
	button.Material = Enum.Material.Neon
	button.Color = Color3.fromRGB(200, 40, 40)
	button.CFrame = base * CFrame.new(LEAF_SIZE.X + 1, -2, LEAF_SIZE.Z)
	button.Parent = model

	model.Parent = parent
	CollectionService:AddTag(model, Config.DoorTag)

	return model
end

return BuildExampleDoor

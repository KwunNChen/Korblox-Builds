local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorFolder = ReplicatedStorage:WaitForChild("BlastDoor")
local Config = require(DoorFolder:WaitForChild("DoorConfig"))
local DoorService = require(script.Parent:WaitForChild("DoorService"))

local function setup(instance: Instance)
	if not instance:IsA("Model") then
		warn(string.format("[BlastDoor] %s is tagged %s but is not a Model -- skipped", instance:GetFullName(), Config.DoorTag))
		return
	end
	DoorService.create(instance)
end

for _, instance in CollectionService:GetTagged(Config.DoorTag) do
	setup(instance)
end
CollectionService:GetInstanceAddedSignal(Config.DoorTag):Connect(setup)
CollectionService:GetInstanceRemovedSignal(Config.DoorTag):Connect(function(instance)
	if instance:IsA("Model") then
		DoorService.destroy(instance)
	end
end)

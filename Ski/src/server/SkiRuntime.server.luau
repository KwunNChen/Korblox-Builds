local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Shared = require(SkiFolder:WaitForChild("SkiShared"))
local SkiService = require(script.Parent:WaitForChild("SkiService"))

SkiService.init(Shared.ensureRemotes())

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		SkiService.onCharacterAdded(player, character)
	end)

	if player.Character then
		SkiService.onCharacterAdded(player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(SkiService.onPlayerRemoving)

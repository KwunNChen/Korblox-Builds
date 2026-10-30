--!strict
-- Holds each respawn until that player's death screen has finished.
--
-- CharacterAutoLoads goes off for the whole place, so this script owns every
-- spawn: the first one on join, and each one after a death. A player respawns
-- when their client fires Finished, or after MaxRespawnWait -- whichever comes
-- first. An admin LoadCharacter still works; it just cuts the screen short.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Folder = ReplicatedStorage:WaitForChild("SkullDeathScreen")
local Config = require(Folder:WaitForChild("DeathScreenConfig")) :: any

-- Rebuilt rather than shipped, so the package never depends on a remote
-- surviving the install.
local finished = Folder:FindFirstChild("Finished") :: RemoteEvent?
if not finished then
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Finished"
	remote.Parent = Folder
	finished = remote
end
assert(finished)

Players.CharacterAutoLoads = false

-- The death each player is waiting on. A fresh table per death, so a timeout
-- armed by an earlier death cannot respawn someone during a later one.
local pending: { [Player]: {} } = {}

local function respawn(player: Player, token: {}?)
	local current = pending[player]
	if current == nil then
		return
	end
	if token and token ~= current then
		return
	end
	pending[player] = nil
	if player.Parent then
		player:LoadCharacter()
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Once(function()
		local token = {}
		pending[player] = token
		task.delay(Config.MaxRespawnWait, respawn, player, token)
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player:LoadCharacter()
end

finished.OnServerEvent:Connect(function(player)
	respawn(player)
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
end)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

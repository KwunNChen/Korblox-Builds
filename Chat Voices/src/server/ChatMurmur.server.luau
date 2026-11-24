-- ChatMurmur: talk blips from the speaker's head when they chat.
-- One blip per few characters of spoken text (*actions* are silent).
-- Each life gets its own pitch, kept until the player respawns.
local Players = game:GetService("Players")

local SOUND_ID = "rbxassetid://104124379407588" -- Voice Blip
local CHARS_PER_BLIP = 3
local MAX_BLIPS = 12
local BLIP_GAP = 0.09
local VOLUME = 0.6
local PITCH_MIN, PITCH_MAX = 0.7, 1.4

local rng = Random.new()
local generation = {} -- [player] = number; a new message cancels the old one

-- made on spawn so clients have it loaded before anyone talks; pitch is rolled here
local function addSound(character: Model)
	local head = character:WaitForChild("Head", 10)
	if not (head and head:IsA("BasePart")) or head:FindFirstChild("ChatMurmur") then return end
	local sound = Instance.new("Sound")
	sound.Name = "ChatMurmur"
	sound.SoundId = SOUND_ID
	sound.Volume = VOLUME
	sound.PlaybackSpeed = rng:NextNumber(PITCH_MIN, PITCH_MAX)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 60
	sound.Parent = head
end

local function onChatted(player: Player, message: string)
	local first = message:sub(1, 1)
	if first == "/" or first == ":" then return end -- chat / Adonis commands

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local sound = head and head:FindFirstChild("ChatMurmur") :: Sound?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (sound and humanoid and humanoid.Health > 0) then return end

	local spoken = message:gsub("%*.-%*", "") -- *actions* aren't spoken
	local length = #spoken:gsub("%s", "")
	if length == 0 then return end
	local blips = math.clamp(math.ceil(length / CHARS_PER_BLIP), 1, MAX_BLIPS)

	local gen = (generation[player] or 0) + 1
	generation[player] = gen

	for _ = 1, blips do
		if generation[player] ~= gen or not sound.Parent then return end
		sound.TimePosition = 0
		sound:Play()
		task.wait(BLIP_GAP)
	end
	if generation[player] == gen then sound:Stop() end -- don't let the clip trail past the message
end

local function onPlayer(player: Player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
	player.CharacterAdded:Connect(addSound)
	if player.Character then task.spawn(addSound, player.Character) end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
Players.PlayerRemoving:Connect(function(player)
	generation[player] = nil
end)

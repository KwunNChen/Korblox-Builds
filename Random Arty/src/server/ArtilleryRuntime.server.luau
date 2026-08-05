-- Entry point. Starts the barrage cycle and wires up the debug knobs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local BarrageService = require(script.Parent:WaitForChild("BarrageService"))

local DEBUG_ATTRIBUTE = "DebugBarrageNow"

--[[
	StreamingEnabled + a character that gets heavily restructured (ragdolled)
	and then destroyed again within a few seconds -- exactly an artillery kill
	-- can desync per-part on a client and leave a frozen, T-posed remnant
	behind even after the server has genuinely destroyed the real Instance.

	Atomic makes a Model stream in and out as one indivisible unit instead of
	piecemeal, which is Roblox's own fix for this. It has to be set from the
	moment the character SPAWNS, not reactively right before it dies -- by
	then it has already been streaming under the default mode for however
	long it was alive, and that is already locked in for any client it has
	replicated to.
]]
local function claimStreaming(character: Model)
	pcall(function()
		character.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
end

local function watchPlayer(player: Player)
	if player.Character then
		claimStreaming(player.Character)
	end
	player.CharacterAdded:Connect(claimStreaming)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

BarrageService.start()

-- Set true to drop a barrage immediately. Resets itself, same contract as the
-- snowstorm's DebugThunder -- the Command Bar runs its own VM, so an attribute
-- is the only thing that reliably reaches a running server script.
ArtilleryFolder:SetAttribute(DEBUG_ATTRIBUTE, false)

ArtilleryFolder:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
	if ArtilleryFolder:GetAttribute(DEBUG_ATTRIBUTE) ~= true then
		return
	end

	ArtilleryFolder:SetAttribute(DEBUG_ATTRIBUTE, false)

	if not Config.Enabled then
		warn("[Artillery] DebugBarrageNow ignored -- Enabled is false in ArtilleryConfig.")
		return
	end

	if BarrageService.isActive() then
		print("[Artillery] barrage already running")
		return
	end

	if BarrageService.triggerNow() then
		print(string.format("[Artillery] barrage -> %.0fs warning, then shells", Config.BarrageWarningLead))
	else
		warn("[Artillery] barrage could not start -- the service never came up. Check Output above.")
	end
end)

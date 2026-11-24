-- Entry point. Starts the barrage cycle and wires up the debug knobs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local BarrageService = require(script.Parent:WaitForChild("BarrageService"))

local DEBUG_ATTRIBUTE = "DebugBarrageNow"

--[[
	StreamingEnabled + a character that gets heavily restructured (ragdolled)
	and then destroyed again within a few seconds, exactly an artillery kill
	-- can desync per-part on a client and leave a frozen, T-posed remnant
	behind even after the server has genuinely destroyed the real Instance.

	Atomic makes a Model stream in and out as one indivisible unit instead of
	piecemeal, which is Roblox's own fix for this. It has to be set from the
	moment the character spawns, not reactively right before it dies, by
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

-- Anything else on the server calls a fire mission through this, so it never
-- has to know where this package was installed:
--     ServerStorage.ArtilleryFireMission:Invoke(position, mission?) -> ok, info
-- mission.caller (a character: the barrage stops if he dies) and
-- mission.gunship (a model with a Muzzle attachment the shells leave from).
-- The Bloxian Spawner's Kinetic Events tab uses it. A Bindable in ServerStorage is server-only, so no
-- client can call in artillery.
local fireMission = Instance.new("BindableFunction")
fireMission.Name = "ArtilleryFireMission"
fireMission.OnInvoke = function(position: Vector3, mission: any)
	if typeof(position) ~= "Vector3" then
		return false, "position must be a Vector3"
	end
	local checked = nil
	if type(mission) == "table" then
		checked = {
			caller = typeof(mission.caller) == "Instance" and mission.caller:IsA("Model") and mission.caller or nil,
			gunship = typeof(mission.gunship) == "Instance" and mission.gunship:IsA("Model") and mission.gunship or nil,
		}
	end
	return BarrageService.fireMission(position, checked)
end
fireMission.Parent = game:GetService("ServerStorage")

-- The artillery's impact effect with no shell and no damage, for other server
-- scripts' explosions (the F-4 Phantom, aircraft crashing):
--     ServerStorage.ArtilleryBlast:Fire(position, scale?)    -- scale 1 is a shell
local blastEvent = ReplicatedStorage:FindFirstChild("ArtilleryBlast")
local blast = Instance.new("BindableEvent")
blast.Name = "ArtilleryBlast"
blast.Event:Connect(function(position: Vector3, scale: number?)
	if blastEvent and typeof(position) == "Vector3" then
		blastEvent:FireAllClients(position, if type(scale) == "number" then scale else 1)
	end
end)
blast.Parent = game:GetService("ServerStorage")

-- Set true to drop a barrage immediately. Resets itself, same contract as the
-- snowstorm's DebugThunder: the Command Bar runs its own VM, so an attribute
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

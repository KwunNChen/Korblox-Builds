--!strict
--[[
	The only LocalScript in this package. Input, state machine, and the frame
	loop that drives a move once one starts.

	It lives in StarterPlayerScripts, not StarterCharacterScripts, and that is a
	deliberate choice rather than a convention. TREK's own movement scripts live
	in StarterCharacterScripts and there is a known failure where a place ends up
	with two copies running -- see TREK Bayonet/tools/SprintDiagnostic.client.luau,
	which was written to catch exactly that. One keypress then does everything
	twice. Running once per player instead of once per life sidesteps the whole
	class of problem, and the guard below catches anyone who moves this file.

	Phase 0: wiring and teardown only. Nothing is detected and nothing moves.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local package = ReplicatedStorage:WaitForChild("TREKParkour", 20)
if not package then
	warn("[TREKParkour] ReplicatedStorage.TREKParkour is missing -- parkour is off. See install step 1.")
	return
end

local Config = require(package:WaitForChild("ParkourConfig"))
local Shared = require(package:WaitForChild("ParkourShared"))

--[[
	If a second copy of this script starts, the first one wins and the second
	returns quietly. Two controllers would both watch JumpRequest and both fire
	the remote, and the server would reject the duplicate as a rate-limit
	violation -- which looks exactly like a broken mantle.
]]
if _G.__TREKParkourController then
	warn("[TREKParkour] a second ParkourController started -- ignoring it. Only one copy should be installed.")
	return
end
_G.__TREKParkourController = true

local player = Players.LocalPlayer

local State = table.freeze({
	Idle = "Idle",
	Vaulting = "Vaulting",
	Mantling = "Mantling",
	Recovering = "Recovering",
})

type Session = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	state: string,
	cooldownUntil: number,
	lastJumpAt: number,
	connections: { RBXScriptConnection },
}

local session: Session? = nil

local function log(format: string, ...: any)
	if Config.DebugLog then
		print("[TREKParkour] " .. string.format(format, ...))
	end
end

--[[
	Tear down whatever is running. Safe on a session that never started a move,
	safe to call twice, and it must stay that way -- every abort path funnels
	through here, including ones that fire a frame apart.
]]
local function endSession(reason: string)
	local current = session
	if not current then
		return
	end
	session = nil

	for _, connection in current.connections do
		connection:Disconnect()
	end

	log("session ended (%s)", reason)
end

local function beginSession(character: Model)
	endSession("new character")

	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		warn("[TREKParkour] character arrived without a Humanoid or a root -- parkour is off for this life.")
		return
	end

	-- TREK's per-character config carries the flags this package reads and sets.
	-- Without it there is no sprint to veto and no UsingAbility to claim.
	if not character:WaitForChild("TREK_PlrConfig", 15) then
		warn("[TREKParkour] no TREK_PlrConfig on this character -- parkour is off for this life.")
		return
	end

	local current: Session = {
		character = character,
		humanoid = humanoid,
		root = root,
		state = State.Idle,
		cooldownUntil = 0,
		lastJumpAt = 0,
		connections = {},
	}

	table.insert(
		current.connections,
		humanoid.Died:Connect(function()
			endSession("died")
		end)
	)

	table.insert(
		current.connections,
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				endSession("character removed")
			end
		end)
	)

	session = current
	log("session started")
end

player.CharacterAdded:Connect(beginSession)
if player.Character then
	task.spawn(beginSession, player.Character)
end

player.CharacterRemoving:Connect(function()
	endSession("character removing")
end)

log("client ready -- vault %s, mantle %s", tostring(Config.EnableVault), tostring(Config.EnableMantle))

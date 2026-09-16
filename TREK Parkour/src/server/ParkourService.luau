--!strict
--[[
	The server's half. It owns the things a client must not be trusted with:
	the mid-move flag, the sprint veto, the weapon, and the budget.

	It does NOT own the motion. The player's own client has network ownership of
	their character, so there is no authority here to take -- a server that tried
	to drive the body would be fighting for something it does not have. What it
	owns instead is whether a claimed move is plausible, and what it costs.

	Phase 0: player and character tracking, and the teardown that every later
	phase depends on. No moves are accepted yet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TREKParkour"):WaitForChild("ParkourConfig"))
local Shared = require(ReplicatedStorage:WaitForChild("TREKParkour"):WaitForChild("ParkourShared"))

local ParkourService = {}

--[[
	One record per player, holding whatever move is in flight.

	Weak keys so a player who leaves mid-move is collected rather than pinned
	here by their own unfinished mantle.
]]
local active: { [Player]: { action: string, startedAt: number, expected: Vector3, tool: Tool? } } =
	setmetatable({}, { __mode = "k" }) :: any

local lastAccepted: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local outcome: BindableEvent? = nil

local function log(format: string, ...: any)
	if Config.DebugLog then
		print("[TREKParkour] " .. string.format(format, ...))
	end
end

ParkourService.log = log

--[[
	Put everything back, whatever state it was in.

	Every path out of a move ends here -- completion, death, respawn, seating,
	the watchdog, a player leaving. It must be safe to call on a character that
	never started a move, and safe to call twice, because under a bad enough
	connection it will be.
]]
function ParkourService.release(player: Player, reason: string)
	local record = active[player]
	if not record then
		return
	end
	active[player] = nil

	local character = player.Character
	if not character then
		log("%s: released (%s) -- no character", player.Name, reason)
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	Shared.setUsingAbility(character, false)

	local config = character:FindFirstChild("TREK_PlrConfig")
	local canSprint = config and config:FindFirstChild("CanSprint")
	if canSprint and canSprint:IsA("BoolValue") then
		--[[
			Only hand sprint back if they are not sitting in something.

			TREK's own seat handler clears CanSprint while seated and restores it
			on exit. If we blindly wrote true here for a player who got seated
			mid-move, we would unlock sprinting inside a vehicle and TREK would
			have no idea why.
		]]
		if humanoid and not humanoid.SeatPart then
			canSprint.Value = true
		end
	end

	-- Give the weapon back, but only to someone alive enough to hold it.
	if record.tool and humanoid and humanoid.Health > 0 and record.tool.Parent then
		pcall(function()
			humanoid:EquipTool(record.tool :: Tool)
		end)
	end

	log("%s: released (%s)", player.Name, reason)
end

local function onCharacterAdded(player: Player, character: Model)
	-- A new body cannot be mid-move, whatever the old one was doing.
	active[player] = nil

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid.Died:Connect(function()
		ParkourService.release(player, "died")
	end)

	--[[
		TREK_PlrConfig is a Configuration TREK clones onto every character, so it
		arrives with the body rather than before it. Deferring keeps this off the
		critical path of the spawn.
	]]
	task.defer(function()
		if character:WaitForChild("TREK_PlrConfig", 10) then
			Shared.setUsingAbility(character, false)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function ParkourService.init(package: Folder)
	outcome = package:FindFirstChild(Shared.OutcomeName) :: BindableEvent?

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		lastAccepted[player] = nil
	end)

	log("server ready")
end

return ParkourService

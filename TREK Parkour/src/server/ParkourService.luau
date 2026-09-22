--!strict
--[[
	The server's half. It owns the things a client must not be trusted with:
	the mid-move flag, the sprint veto, the weapon, and the budget.

	It does NOT own the motion. The player's own client has network ownership of
	their character, so there is no authority here to take -- a server that tried
	to drive the body would be fighting for something it does not have. What it
	owns instead is whether a claimed move is plausible, and what it costs.

	--------------------------------------------------------------------------
	WHAT THE VALIDATION IS AND IS NOT FOR
	--------------------------------------------------------------------------

	Someone who wants to teleport already can -- that is what network ownership
	means. These bounds exist so that this package is not a CONVENIENT way to do
	it, not because they stop a determined exploiter.

	Nobody is kicked. TREK's only kick is its anti-hitbox-expansion check, and
	booting a player over a laggy vault would be a worse outcome than the vault.
	A claim outside the bounds is refused and logged, and that is all.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local package = ReplicatedStorage:WaitForChild("TREKParkour")
local Config = require(package:WaitForChild("ParkourConfig"))
local Shared = require(package:WaitForChild("ParkourShared"))
local Lockout = require(script.Parent:WaitForChild("ParkourLockout"))

local ParkourService = {}

type Record = {
	id: number,
	action: string,
	expected: Vector3,
	tool: Tool?,
}

-- Weak keys so a player who leaves mid-move is collected rather than pinned
-- here by their own unfinished mantle.
local active: { [Player]: Record } = setmetatable({}, { __mode = "k" }) :: any
local lastAccepted: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local nextId = 0
local outcome: BindableEvent? = nil

local function announce(player: Player, action: string, phase: string)
	if outcome then
		outcome:Fire(player, action, phase)
	end
end

--[[
	Put everything back, whatever state it was in.

	Every path out ends here -- completion, death, respawn, seating, the
	watchdog, a player leaving. It must be safe on a character that never
	started a move, and safe to call twice, because under a bad enough
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
		Shared.log("%s: released (%s) -- no character", player.Name, reason)
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	Lockout.release(character, humanoid, record.tool)

	announce(player, record.action, Shared.Phase.Finish)
	Shared.log("%s: %s released (%s)", player.Name, record.action, reason)
end

--[[
	Rejects anything that is not a finite Vector3 inside the world. NaN is
	checked with v ~= v because it is the only value that fails that test, and
	it is what arrives when a client sends arithmetic that went wrong.
]]
local function cleanVector(value: unknown): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end

	local vector = value :: Vector3
	for _, component in { vector.X, vector.Y, vector.Z } do
		if component ~= component or math.abs(component) > 20000 then
			return nil
		end
	end

	return vector
end

local function onBegin(player: Player, payload: unknown)
	local now = os.clock()

	-- Cheapest test in the function, so it runs first. A duplicate claim from a
	-- client that is already mid-move exits here rather than after two vector
	-- validations and three instance lookups.
	if active[player] then
		return
	end

	-- Dropped silently. Roblox reorders under lag, and a legitimate double-fire
	-- is not evidence of anything worth logging.
	if now - (lastAccepted[player] or 0) < Config.Cooldown then
		return
	end

	if type(payload) ~= "table" then
		return
	end

	local claim = payload :: { action: unknown, start: unknown, finish: unknown }

	if type(claim.action) ~= "string" then
		return
	end
	local action = claim.action :: string

	-- Resolving the shape IS the validation: an action with no shape is not a
	-- move this package knows about.
	local shape = Shared.moveShape(action)
	if not shape then
		return
	end

	local start = cleanVector(claim.start)
	local finish = cleanVector(claim.finish)
	if not start or not finish then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end

	local blocked = Shared.blockReason(character, humanoid)
	if blocked then
		Shared.log("%s: refused %s -- %s", player.Name, action, blocked)
		return
	end

	--[[
		THE CHECK THAT ACTUALLY CLOSES THE HOLE.

		Bounding the move's LENGTH on its own is worthless: a client that lies
		about where it started gets a full-length move from anywhere on the map.
		This measures the claimed start against a position the server got from
		Roblox's own replication, so the length bound below means something.
	]]
	if (start - root.Position).Magnitude > Config.StartTolerance then
		Shared.log("%s: refused %s -- claimed start is %.0f studs from where it is",
			player.Name, action, (start - root.Position).Magnitude)
		return
	end

	--[[
		Bounded in all three directions.

		The downward bound is not symmetry for its own sake: no legal reading
		produces a descent at all, because `land` derives from the top surface the
		probe found, which is always above the soles. Without it a claim was a
		free MaxReach-out, unbounded-DOWN displacement at the cooldown rate --
		which is a more useful primitive to an exploiter than the upward one this
		was guarding.
	]]
	local delta = finish - start
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if horizontal > Config.MaxReach or delta.Y > Config.MantleMaxHeight or delta.Y < -Config.MaxDescent then
		Shared.log("%s: refused %s -- reach %.1f out, %.1f up", player.Name, action, horizontal, delta.Y)
		return
	end

	lastAccepted[player] = now
	nextId += 1

	--[[
		The mantle is the expensive one and the vault is meant to be free. Both
		claim UsingAbility so other systems can see a move in progress, but what
		each costs is read from the move's own shape rather than branched on here.
	]]
	local cost: Lockout.Cost = {
		holster = shape.holsters,
		blockSprint = shape.blocksSprint,
	}

	local record: Record = {
		id = nextId,
		action = action,
		expected = finish,
		tool = Lockout.apply(character, humanoid, cost),
	}
	active[player] = record

	announce(player, action, Shared.Phase.Begin)
	Shared.log("%s: %s accepted", player.Name, action)

	--[[
		The watchdog, and it is not optional.

		A dropped ParkourEnd would otherwise leave a player permanently
		disarmed and sprint-locked. The client's report is an optimisation; this
		is the path that is guaranteed to run.

		The id check stops a stale timer from tearing down a NEWER move that
		started after this one finished.
	]]
	task.delay(shape.duration + Config.WatchdogGrace, function()
		local current = active[player]
		if current and current.id == record.id then
			ParkourService.release(player, "watchdog")
		end
	end)
end

local function onEnd(player: Player, payload: unknown)
	local record = active[player]
	if not record then
		return
	end

	--[[
		Where they ended up versus where they said they were going. Logged, not
		punished: an explosion mid-climb, a moving platform under the landing
		spot, or a server hitch all produce this same signature, and yanking a
		legitimate player back is worse than a cheater gaining a few studs.
	]]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and type(payload) == "table" then
		local drift = (root.Position - record.expected).Magnitude
		if drift > Config.ArrivalTolerance then
			Shared.log("%s: %s ended %.0f studs from where it was headed", player.Name, record.action, drift)
		end
	end

	ParkourService.release(player, "reported")
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
		TREK_PlrConfig is a Configuration TREK clones onto every character, so
		it arrives with the body rather than before it. Deferring keeps this off
		the critical path of the spawn.
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

	player.CharacterRemoving:Connect(function()
		ParkourService.release(player, "respawning")
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function ParkourService.init(package: Folder)
	outcome = package:FindFirstChild(Shared.OutcomeName) :: BindableEvent?

	local begin = package:FindFirstChild("ParkourBegin")
	local finish = package:FindFirstChild("ParkourEnd")

	if begin and begin:IsA("RemoteEvent") then
		begin.OnServerEvent:Connect(onBegin)
	else
		Shared.warn("ParkourBegin missing -- moves cannot be claimed this session.")
	end

	if finish and finish:IsA("RemoteEvent") then
		finish.OnServerEvent:Connect(onEnd)
	else
		Shared.warn("ParkourEnd missing -- moves will only end on the watchdog.")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		lastAccepted[player] = nil
	end)

	Shared.log("server ready")
end

return ParkourService

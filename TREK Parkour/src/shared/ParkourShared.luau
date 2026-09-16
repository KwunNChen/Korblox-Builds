--!strict
--[[
	Shared vocabulary and plumbing. No behaviour lives here -- this is the file
	both halves agree on so they cannot drift apart.

	The refusal check (blockReason) is here rather than on either side on
	purpose. The client runs it to avoid firing a remote it knows will be
	rejected; the server runs it again because the client's answer is a claim,
	not a fact. One copy, two callers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("ParkourConfig"))

local ParkourShared = {}

-- How long a client waits for a remote the server creates at runtime before it
-- gives up and turns that feature off for the session.
local REMOTE_WAIT = 10

ParkourShared.Action = table.freeze({
	Vault = "Vault",
	Mantle = "Mantle",
})

ParkourShared.Phase = table.freeze({
	Begin = "Begin",
	Finish = "Finish",
})

ParkourShared.RemoteNames = table.freeze({ "ParkourBegin", "ParkourEnd" })

ParkourShared.OutcomeName = "ParkourOutcome"

-- ============================================================
-- REMOTES
-- ============================================================

--[[
	Server side. Built at runtime rather than declared in the project file, so an
	install that predates a new remote grows one instead of half-working.

	These live inside ReplicatedStorage.TREKParkour, not in TREK's own
	TREK_Remotes folder. That folder is TREK's, and a stray RemoteEvent in it is
	exactly the kind of thing that makes a later TREK update ambiguous to debug.
]]
function ParkourShared.ensureRemotes(): Folder
	local package = script.Parent :: Folder

	for _, name in ParkourShared.RemoteNames do
		if not package:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = package
		end
	end

	-- Server-to-server only. Other packages (Voicelines, say) connect to this to
	-- bark on a pull-up. There is nothing here a client needs or should be told.
	if not package:FindFirstChild(ParkourShared.OutcomeName) then
		local outcome = Instance.new("BindableEvent")
		outcome.Name = ParkourShared.OutcomeName
		outcome.Parent = package
	end

	return package
end

-- Client side. Bounded, because a missing remote should disable a feature, not
-- hang the controller forever.
function ParkourShared.getRemote(name: string): RemoteEvent?
	local package = ReplicatedStorage:WaitForChild("TREKParkour", REMOTE_WAIT)
	if not package then
		return nil
	end

	local remote = package:WaitForChild(name, REMOTE_WAIT)
	if not remote or not remote:IsA("RemoteEvent") then
		warn(string.format("[TREKParkour] %s missing after %ds -- parkour is off this session.", name, REMOTE_WAIT))
		return nil
	end

	return remote
end

-- ============================================================
-- THE REFUSAL CHECK
-- ============================================================

--[[
	Returns a reason string if this character must not start a move, or nil if it
	may. Ordered cheapest test first.

	The PlatformStand and TParalCondition tests are not paranoia. TREK sets
	PlatformStand on a player who has lost both legs and never clears it -- that
	is its paralysis marker. If we started a move on such a character we would
	restore PlatformStand to false when we finished, and cure them.
]]
function ParkourShared.blockReason(character: Model, humanoid: Humanoid): string?
	if humanoid.Health <= 0 then
		return "dead"
	end

	--[[
		Every pose and every height in this package is R6. An R6 animation loads
		onto an R15 rig with zero tracks and an empty timeline, and the
		procedural fallback looks for Motor6Ds ("Right Shoulder", "Left Hip")
		that do not exist there.

		Refusing turns a crash into an absent feature, which is the right trade
		for a rig that should never appear in a TREK place anyway.
	]]
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return "not an R6 rig"
	end

	if humanoid.SeatPart then
		return "seated in " .. humanoid.SeatPart.Name
	end

	if humanoid.PlatformStand then
		return "already PlatformStand -- ragdolled or paralysed"
	end

	if humanoid:FindFirstChild("TParalCondition") then
		return "paralysed (TParalCondition)"
	end

	-- The place's tempclimb script owns the Climbing state and animates it at
	-- Action4. We stay out of its way entirely rather than racing it.
	if humanoid:GetState() == Enum.HumanoidStateType.Climbing then
		return "on a ladder"
	end

	local config = character:FindFirstChild("TREK_PlrConfig")
	local using = config and config:FindFirstChild("UsingAbility")
	if using and (using :: BoolValue).Value then
		return "already mid-move"
	end

	return nil
end

--[[
	TREK_PlrConfig.UsingAbility is a BoolValue TREK ships on every character and
	never reads or writes. It is already replicated and already per-life, which
	makes it the natural home for "this player is mid-parkour" -- any other
	system can read it without knowing this package exists.
]]
function ParkourShared.setUsingAbility(character: Model, value: boolean)
	local config = character:FindFirstChild("TREK_PlrConfig")
	local using = config and config:FindFirstChild("UsingAbility")
	if using and using:IsA("BoolValue") then
		using.Value = value
	end
end

-- ============================================================
-- GEOMETRY HELPERS
-- ============================================================

--[[
	World Y of the player's soles.

	The HipHeight term matters: TREK's crouch sets HipHeight to -1.1 on R6, so a
	crouching player's root is 1.1 studs closer to their feet. A fixed offset
	would misread every obstacle height by that much, and the vault/mantle bands
	are only 2.5 studs wide.
]]
function ParkourShared.solesY(root: BasePart, humanoid: Humanoid): number
	return root.Position.Y - (Config.RootToSoles + humanoid.HipHeight)
end

--[[
	Every cast this package makes must exclude workspace.IgnoreList. It is where
	TREK parks bullets, casings and gibs -- a ledge probe that does not exclude
	it will happily latch onto a round in flight.
]]
local function ignoreFor(character: Model): { Instance }
	local ignore: { Instance } = { character }
	local list = workspace:FindFirstChild("IgnoreList")
	if list then
		table.insert(ignore, list)
	end
	return ignore
end

function ParkourShared.newCastParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = ignoreFor(character)
	return params
end

-- The same exclusions, for the "is there room to stand up there" check.
function ParkourShared.newOverlapParams(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreFor(character)
	return params
end

local function flatten(vector: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-4 then
		return fallback
	end
	return flat.Unit
end

--[[
	Which way the player is actually GOING, flattened.

	This is deliberately not the look vector. While a weapon with TurnToTarget is
	equipped, TREK's HeadAndArmsController forces the root's yaw to wherever the
	mouse is pointing, every frame -- so LookVector is where you are AIMING, and
	using it would have you vaulting the wall you are looking at rather than the
	one you are running into.

	MoveDirection is the player's input in world space and is valid airborne too,
	so it is right for both moves. It falls back to the look vector only when
	there is no input at all, which for a vault means no vault anyway.
]]
function ParkourShared.travelDirection(root: BasePart, humanoid: Humanoid): Vector3
	local fallback = flatten(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	return flatten(humanoid.MoveDirection, fallback)
end

-- ============================================================
-- MATHS
-- ============================================================

function ParkourShared.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Ease in and out. Linear motion up a wall reads as a lift, not a climb.
function ParkourShared.smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--[[
	A point along the move at time t (0..1), bulged upward so the character
	throws its weight over the lip instead of sliding up the face.

	The bulge is a parabola peaking at the midpoint, scaled by the height gained,
	so a tall mantle arcs more than a short vault without a second setting.
]]
function ParkourShared.arcPoint(from: Vector3, to: Vector3, t: number, arcHeight: number): Vector3
	local eased = ParkourShared.smoothstep(t)
	local flat = from:Lerp(to, eased)
	local climb = math.max(to.Y - from.Y, 0)
	local bulge = 4 * eased * (1 - eased) * climb * arcHeight
	return flat + Vector3.new(0, bulge, 0)
end

return table.freeze(ParkourShared)

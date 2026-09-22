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

--[[
	What each move is, as data.

	This exists because "is this the mantle" was being re-derived in five
	separate places -- the cost, the watchdog duration, the probe origin, the
	classifier -- and every one of them was a branch that a third move would have
	to be threaded through by hand.

	The config stays flat (Vault* / Mantle* keys) on purpose: it is documented as
	the one file a non-programmer edits, and a table of tables reads worse for
	that person. This is the flat config gathered into a shape for code, built
	once at load rather than per call.
]]
local SHAPES = {
	[ParkourShared.Action.Vault] = table.freeze({
		duration = Config.VaultDuration,
		holsters = Config.VaultHolstersWeapon,
		blocksSprint = Config.VaultBlocksSprint,
	}),
	[ParkourShared.Action.Mantle] = table.freeze({
		duration = Config.MantleDuration,
		holsters = Config.MantleHolstersWeapon,
		blocksSprint = Config.MantleBlocksSprint,
	}),
}

export type MoveShape = { duration: number, holsters: boolean, blocksSprint: boolean }

function ParkourShared.moveShape(action: string): MoveShape?
	return SHAPES[action]
end

ParkourShared.RemoteNames = table.freeze({ "ParkourBegin", "ParkourEnd" })

ParkourShared.OutcomeName = "ParkourOutcome"

-- ============================================================
-- LOGGING
-- ============================================================

local PREFIX = "[TREKParkour] "

-- One definition, because there were three identical ones and a fourth site
-- open-coding the same DebugLog check. Anything that changes about debug output
-- -- a level, a Studio-only gate, routing somewhere other than print -- should
-- be one edit, not four.
function ParkourShared.log(format: string, ...: any)
	if Config.DebugLog then
		print(PREFIX .. string.format(format, ...))
	end
end

-- Warnings are not gated on DebugLog: a warning means something is broken, and
-- it is needed most by the person who has not turned debugging on.
function ParkourShared.warn(format: string, ...: any)
	warn(PREFIX .. string.format(format, ...))
end

-- ============================================================
-- TREK_PlrConfig
-- ============================================================

--[[
	TREK ships a Configuration called TREK_PlrConfig on every character, holding
	the sprint flags and one BoolValue -- UsingAbility -- that no TREK code ever
	reads or writes. That is where "this player is mid-parkour" lives, so any
	other system can see it without knowing this package exists.

	Every read goes through here. There were three hand-rolled copies of this
	walk, and one of them had lost its IsA guard and would have cast-errored on
	a child of the wrong class rather than refusing.
]]
function ParkourShared.boolValue(character: Model, name: string): BoolValue?
	local config = character:FindFirstChild("TREK_PlrConfig")
	local value = config and config:FindFirstChild(name)
	if value and value:IsA("BoolValue") then
		return value
	end
	return nil
end

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

	local using = ParkourShared.boolValue(character, "UsingAbility")
	if using and using.Value then
		return "already mid-move"
	end

	return nil
end

function ParkourShared.setUsingAbility(character: Model, value: boolean)
	local using = ParkourShared.boolValue(character, "UsingAbility")
	if using then
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

--[[
	Memoised per character, weak-keyed so a dead character takes its params with
	it.

	These were being rebuilt on every probe -- ten times a second while moving,
	forty with the debug tool running. Assigning FilterDescendantsInstances is
	not a field write: it copies the array across to the engine and rebuilds the
	filter, so the cost was real rather than theoretical.

	The filter contents are constant for a character's whole life, which is what
	makes caching safe. The one thing that can change is IgnoreList appearing
	after the first probe, so a params set built before it existed is discarded
	rather than kept.
]]
type Cache<T> = { values: { [Model]: T }, hadIgnoreList: { [Model]: boolean } }

local function newCache<T>(): Cache<T>
	return {
		values = setmetatable({}, { __mode = "k" }) :: any,
		hadIgnoreList = setmetatable({}, { __mode = "k" }) :: any,
	}
end

--[[
	Each kind tracks its own "was IgnoreList present when I was built" flag. A
	single shared flag would let one cache rebuilding mark the other fresh, and
	the stale one would go on excluding nothing for the rest of the life.
]]
local function cached<T>(cache: Cache<T>, character: Model, build: (Model) -> T): T
	local hasList = workspace:FindFirstChild("IgnoreList") ~= nil
	local value = cache.values[character]

	if value ~= nil and (cache.hadIgnoreList[character] or not hasList) then
		return value
	end

	value = build(character)
	cache.values[character] = value
	cache.hadIgnoreList[character] = hasList
	return value
end

local raycastCache: Cache<RaycastParams> = newCache()
local overlapCache: Cache<OverlapParams> = newCache()

function ParkourShared.castParams(character: Model): RaycastParams
	return cached(raycastCache, character, function(chr)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		params.FilterDescendantsInstances = ignoreFor(chr)
		return params
	end)
end

-- The same exclusions, for the "is there room to stand up there" check.
function ParkourShared.overlapParams(character: Model): OverlapParams
	return cached(overlapCache, character, function(chr)
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreFor(chr)
		return params
	end)
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
	-- The fallback is built only when it is needed. On the vault poll it never
	-- is -- that path only runs above MinApproachSpeed, so MoveDirection always
	-- has magnitude -- and computing it eagerly cost a CFrame read, two Vector3
	-- allocations and a normalise per probe for nothing.
	local moving = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
	if moving.Magnitude >= 1e-4 then
		return moving.Unit
	end

	return flatten(root.CFrame.LookVector, Vector3.new(0, 0, -1))
end

--[[
	Where the root is at the hang, and where it ends up standing.

	These live here rather than at their call sites because three places need to
	agree on them: the detector computing the landing, the controller computing
	the grab, and ParkourRig drawing the markers an animator keyframes against.
	The rig tool's whole purpose is to show where the game actually drives the
	root, so a second copy of the formula there defeats it.
]]
function ParkourShared.grabPoint(facePoint: Vector3, topY: number, direction: Vector3): Vector3
	return Vector3.new(facePoint.X, topY, facePoint.Z) - direction * Config.GrabPullback
end

function ParkourShared.landPoint(facePoint: Vector3, topY: number, direction: Vector3): Vector3
	return Vector3.new(facePoint.X, topY + Config.RootToSoles, facePoint.Z) + direction * Config.LandInset
end

-- ============================================================
-- MATHS
-- ============================================================

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
--[[
	The mantle is two beats, not one.

	  from -> grab   haul up the face until the root is level with the lip
	  grab -> to     swing over and stand up on top

	A single arc from start to finish cuts diagonally through the corner of the
	wall, which clips through it. Splitting at the lip is what makes it read as
	a climb rather than a float. Each segment is eased independently so there is
	a deliberate beat of hanging where they meet.
]]
function ParkourShared.mantlePoint(from: Vector3, grab: Vector3, to: Vector3, t: number, hang: number): Vector3
	if t <= hang then
		local local_t = if hang > 0 then t / hang else 1
		return from:Lerp(grab, ParkourShared.smoothstep(local_t))
	end

	local local_t = if hang < 1 then (t - hang) / (1 - hang) else 1
	return grab:Lerp(to, ParkourShared.smoothstep(local_t))
end

function ParkourShared.arcPoint(from: Vector3, to: Vector3, t: number, arcHeight: number): Vector3
	local eased = ParkourShared.smoothstep(t)
	local flat = from:Lerp(to, eased)
	local climb = math.max(to.Y - from.Y, 0)
	local bulge = 4 * eased * (1 - eased) * climb * arcHeight
	return flat + Vector3.new(0, bulge, 0)
end

return table.freeze(ParkourShared)

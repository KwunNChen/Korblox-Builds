-- Helpers shared by the server and client ski code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("SkiConfig"))

local SkiShared = {}

--[[
	Character attributes. WRITTEN BY THE SERVER, always.

	Attributes only replicate server -> client, so a client setting these on its
	own character would be talking to itself. That round trip is the entire
	reason the cosmetics are driven this way: everything below exists so other
	people's clients can pose, spray and sound a skier they aren't simulating.
]]
SkiShared.Attr = table.freeze({
	Equipped = "SkiEquipped", -- gear is on your feet rather than your back
	State = "SkiState", -- which pose to hold
	Speed = "SkiSpeed", -- sound volume and pitch
	Scrub = "SkiScrub", -- sideways speed: spray rate and carve sound
	Lean = "SkiLean", -- -1 to 1, drives the whole carving overlay
	OnSnow = "SkiOnSnow", -- gates spray and the glide/carve loops
})

-- The states a skier can be in. Shared so the server can reject anything else
-- rather than writing whatever string a client felt like sending.
SkiShared.State = table.freeze({
	Walking = "Walking",
	Riding = "Riding",
	Braking = "Braking",
	Airborne = "Airborne",
})

-- ============================================================
-- MATH  (used by SkiPhysics, which is dormant -- see SkiConfig)
-- ============================================================

-- Framerate-independent smoothing. `smoothing` is a time constant in seconds.
function SkiShared.damp(current: number, target: number, smoothing: number, dt: number): number
	if smoothing <= 0 then
		return target
	end
	return target + (current - target) * math.exp(-dt / smoothing)
end

-- Same curve, for vectors. Used for the ground normal and velocity smoothing.
function SkiShared.dampVector(current: Vector3, target: Vector3, smoothing: number, dt: number): Vector3
	if smoothing <= 0 then
		return target
	end
	local alpha = math.exp(-dt / smoothing)
	return target + (current - target) * alpha
end

function SkiShared.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Drops the component of `vector` that points along `normal`, leaving only what
-- lies in the plane. The backbone of the whole sim: gravity projected this way
-- IS the downhill pull, with no special-casing for flat ground.
function SkiShared.projectOnPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

-- Safe normalize -- returns the fallback rather than NaN on a zero vector.
function SkiShared.safeUnit(vector: Vector3, fallback: Vector3): Vector3
	local length = vector.Magnitude
	if length < 1e-6 then
		return fallback
	end
	return vector / length
end

-- ============================================================
-- GROUND
-- ============================================================

-- Build once per system and reuse; do not allocate per cast.
function SkiShared.newGroundParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

-- Friction coefficient for whatever the ground probe hit. Checks the per-part
-- attribute override first, then the material table, then the default -- so
-- Terrain and BaseParts resolve through exactly the same path.
function SkiShared.frictionFor(result: RaycastResult): number
	local instance = result.Instance
	if instance then
		local override = instance:GetAttribute(Config.FrictionAttribute)
		if type(override) == "number" then
			return override
		end
	end

	return Config.SurfaceFriction[result.Material] or Config.DefaultFriction
end

-- ============================================================
-- REMOTES
-- ============================================================

SkiShared.RemoteNames = table.freeze({ "SkiEquip", "SkiCrash", "SkiState" })

--[[
	SERVER ONLY. Creates the folder and any missing remotes.

	Installs go stale -- someone drops in new scripts and keeps the SkiRemotes
	folder they already had. Adding a remote then meant every WaitForChild for it
	yielded forever, which does not fail loudly: it silently hangs whichever
	script asked, and everything after that line in it never runs.

	Building them here means the Rojo-declared copies are a convenience rather
	than a requirement, and updating the scripts alone is enough.
]]
function SkiShared.ensureRemotes(): Folder
	local folder = ReplicatedStorage:FindFirstChild("SkiRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SkiRemotes"
		folder.Parent = ReplicatedStorage
	end

	for _, name in SkiShared.RemoteNames do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end

	return folder :: Folder
end

-- CLIENT SIDE. Bounded, and nil rather than an infinite yield -- callers warn
-- and carry on with that feature off instead of hanging the whole script.
function SkiShared.getRemotes(): Folder?
	return ReplicatedStorage:WaitForChild("SkiRemotes", 10) :: Folder?
end

function SkiShared.getRemote(folder: Folder, name: string): RemoteEvent?
	local remote = folder:WaitForChild(name, 10)
	if not remote then
		warn(string.format("[Ski] SkiRemotes.%s missing after 10s -- that feature is off this session.", name))
		return nil
	end
	return remote :: RemoteEvent
end

return table.freeze(SkiShared)

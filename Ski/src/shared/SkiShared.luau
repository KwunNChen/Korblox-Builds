local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("SkiConfig"))

local SkiShared = {}

SkiShared.Attr = table.freeze({
	Equipped = "SkiEquipped",
	State = "SkiState",
	Speed = "SkiSpeed",
	Scrub = "SkiScrub",
	Lean = "SkiLean",
	OnSnow = "SkiOnSnow",
})

SkiShared.State = table.freeze({
	Walking = "Walking",
	Riding = "Riding",
	Braking = "Braking",
	Airborne = "Airborne",
})

function SkiShared.damp(current: number, target: number, smoothing: number, dt: number): number
	if smoothing <= 0 then
		return target
	end
	return target + (current - target) * math.exp(-dt / smoothing)
end

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

function SkiShared.projectOnPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

function SkiShared.safeUnit(vector: Vector3, fallback: Vector3): Vector3
	local length = vector.Magnitude
	if length < 1e-6 then
		return fallback
	end
	return vector / length
end

function SkiShared.newGroundParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

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

SkiShared.RemoteNames = table.freeze({ "SkiEquip", "SkiCrash", "SkiState" })

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

local walkAnimOriginals = setmetatable({}, { __mode = "k" })

function SkiShared.setWalkAnimation(character: Model, animationId: string?)
	local animate = character:FindFirstChild("Animate")
	local walk = animate and animate:FindFirstChild("walk")
	local walkAnim = walk and walk:FindFirstChild("WalkAnim")
	if not (walkAnim and walkAnim:IsA("StringValue")) then
		return
	end

	if walkAnimOriginals[walkAnim] == nil then
		walkAnimOriginals[walkAnim] = walkAnim.Value
	end

	if animationId and animationId ~= "" then
		local digits = animationId:match("^%d+$")
		walkAnim.Value = if digits then "rbxassetid://" .. digits else animationId
	else
		walkAnim.Value = walkAnimOriginals[walkAnim]
	end
end

return table.freeze(SkiShared)

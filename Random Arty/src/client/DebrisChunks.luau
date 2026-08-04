--[[
	DebrisChunks
	The ground thrown out of a crater, as REAL PARTS rather than particles.

	WHY NOT A ParticleEmitter. Sprites depend on a texture asset, and every way
	that can go wrong fails silently and identically: a moderated id, a decal id
	used where an image id was needed, an engine path fed through an id parser,
	or simply no texture at all -- which falls back to Roblox's white sparkle.
	None of those print anything. You just get glitter, or nothing, and no way to
	tell which knob is at fault.

	A Part cannot fail that way. It has a size, a colour and a position, it
	renders, and if it is in the wrong place you can see exactly where it went.

	NO PHYSICS. These are parented under workspace.CurrentCamera so they never
	replicate, and nothing under the Camera is simulated -- so they are Anchored
	and moved by hand each frame along the same ballistic curve the shells use.
	That is a feature, not a workaround: reach becomes exactly predictable
	instead of depending on collisions, and 300 CFrame writes are far cheaper
	than 300 physics assemblies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Shared = require(ArtilleryFolder:WaitForChild("ArtilleryShared"))

local DebrisChunks = {}

type Chunk = {
	part: BasePart,
	origin: Vector3,
	velocity: Vector3,
	spin: Vector3,
	born: number,
	lifetime: number,
	groundY: number,
}

local live: { Chunk } = {}
local container: Folder?

local ACCEL = Vector3.new(0, -1, 0)

-- Same camera guard as ShellRender: comparing two nils would hand back an
-- orphaned folder forever and draw nothing.
local function getContainer(): Folder
	local camera = workspace.CurrentCamera

	if container and camera and container.Parent == camera then
		return container :: Folder
	end

	if container then
		(container :: Folder):Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "ArtilleryDebris"
	folder.Parent = camera
	container = folder
	return folder
end

--[[
	A launch direction for one chunk.

	Elevation is the angle above horizontal, rolled inside ChunkElevation. That
	single range replaces the old plume/splash split: low angles skim out across
	the ground, high angles go up and come back down, and rolling across the
	whole range every time gives you both from one throw.
]]
local function launchDirection(): Vector3
	local yaw = math.random() * math.pi * 2
	local elevation = math.rad(Shared.rollRange(Config.ChunkElevation))

	local flat = math.cos(elevation)
	return Vector3.new(math.cos(yaw) * flat, math.sin(elevation), math.sin(yaw) * flat)
end

local function destroyChunk(index: number)
	local chunk = live[index]
	chunk.part:Destroy()

	-- Swap-remove. Order does not matter here and table.remove on a few hundred
	-- entries every frame would be the most expensive thing in the loop.
	local last = #live
	live[index] = live[last]
	live[last] = nil
end

--[[
	Throws a burst of chunks out of `position`.

	`groundY` is where they stop existing. Taken from the impact point rather
	than raycast per chunk -- the crater is already snapped to the surface, and
	one shared floor for the whole burst is both cheaper and steadier than a
	few hundred separate answers about where the ground is.
]]
function DebrisChunks.spawn(position: Vector3, color: Color3)
	if not Config.EnableDebrisChunks then
		return
	end

	local parent = getContainer()
	local now = os.clock()

	local budget = math.max(Config.MaxLiveChunks - #live, 0)
	local count = math.min(Config.ChunkCount, budget)

	for _ = 1, count do
		local size = Shared.rollRange(Config.ChunkSize)

		local part = Instance.new("Part")
		part.Name = "DebrisChunk"
		-- Irregular on purpose. Cubes read as voxels; uneven boxes read as rubble.
		part.Size = Vector3.new(size, size * Shared.rollRange(Config.ChunkAspect), size * Shared.rollRange(Config.ChunkAspect))
		part.Color = color
		part.Material = Config.ChunkMaterial
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0)
		part.Parent = parent

		table.insert(live, {
			part = part,
			origin = position,
			velocity = launchDirection() * Shared.rollRange(Config.ChunkSpeed),
			spin = Vector3.new(
				(math.random() - 0.5) * 2 * Config.ChunkSpin,
				(math.random() - 0.5) * 2 * Config.ChunkSpin,
				(math.random() - 0.5) * 2 * Config.ChunkSpin
			),
			born = now,
			lifetime = Shared.rollRange(Config.ChunkLifetime),
			groundY = position.Y,
		})
	end
end

function DebrisChunks.step()
	local count = #live
	if count == 0 then
		return
	end

	local now = os.clock()
	local gravity = ACCEL * Config.ChunkGravity

	-- Backwards, because destroyChunk swaps the last entry into the current slot.
	for index = count, 1, -1 do
		local chunk = live[index]
		local elapsed = now - chunk.born

		if elapsed >= chunk.lifetime then
			destroyChunk(index)
			continue
		end

		local offset = chunk.velocity * elapsed + gravity * (0.5 * elapsed * elapsed)
		local position = chunk.origin + offset

		-- Landed. Removing on contact rather than letting them sink keeps chunks
		-- from ending up buried inside the terrain they came out of.
		if position.Y <= chunk.groundY and elapsed > 0.1 then
			destroyChunk(index)
			continue
		end

		chunk.part.CFrame = CFrame.new(position)
			* CFrame.Angles(chunk.spin.X * elapsed, chunk.spin.Y * elapsed, chunk.spin.Z * elapsed)
	end
end

function DebrisChunks.liveCount(): number
	return #live
end

return DebrisChunks

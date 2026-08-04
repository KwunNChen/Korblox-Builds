--[[
	DustCloud
	The dust a shell throws up: ONE flat image per crater, which grows outward
	and sinks as it settles.

	Not particles, and not a field of spheres either. Both were tried and both
	were worse for the same underlying reason -- an explosion's dust reads as one
	continuous mass, and anything built out of many separate pieces reads as many
	separate pieces. A hundred sprites look thin against open ground; forty balls
	look like forty balls. One big image that opens out and settles is the whole
	effect, and it costs one part.

	THE ANIMATION IS THE POINT. A static decal is a stain. What makes this read as
	dust is that it does two things at once over its life:

	    GROWS   fast at first, then slower, as the cloud pushes outward
	    SINKS   from a few studs up down to the ground, as it settles

	plus a slow rotation, so the mass appears to churn rather than scale.

	It is stepped by hand from the client's single render loop rather than
	tweened, because size, height, spin and transparency all move on different
	curves and four tweens per crater would be four Instances per crater.

	THIS IS THE ONE EFFECT LEFT THAT NEEDS A TEXTURE. Debris is real parts and
	cannot fail; this can, and silently -- a decal id where an image id was
	needed renders nothing at all. See DustDecalTexture in the config.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Shared = require(ArtilleryFolder:WaitForChild("ArtilleryShared"))

local DustCloud = {}

type Cloud = {
	part: BasePart,
	decal: Decal,
	-- Where it sits on the ground, with the surface normal as its local up. The
	-- height offset and the spin are applied to this every frame rather than
	-- baked into it, so neither accumulates.
	placement: CFrame,
	normal: Vector3,
	born: number,
	spin: number,
	startSize: number,
	endSize: number,
}

local live: { Cloud } = {}
local container: Folder?

-- Thin enough to read as flat, thick enough not to z-fight with itself.
local THICKNESS = 0.05

-- Config is frozen, so the total life is worked out once. Growth and sink run
-- across the whole of it; only the fade waits for the hold to pass.
local LIFETIME = math.max(Config.DustDecalHoldTime + Config.DustDecalFadeTime, 0.01)

-- Same camera guard as ShellRender and DebrisChunks: comparing two nils would
-- hand back an orphaned folder forever and draw nothing.
local function getContainer(): Folder
	local camera = workspace.CurrentCamera

	if container and camera and container.Parent == camera then
		return container :: Folder
	end

	if container then
		(container :: Folder):Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "ArtilleryDust"
	folder.Parent = camera
	container = folder
	return folder
end

--[[
	An orthonormal CFrame at `position` with `normal` as its LOCAL UP, so the
	image lies flat against whatever it landed on, slopes included.

	The reference vector swaps to X when the normal is nearly vertical -- which
	is almost always -- because crossing a near-parallel pair gives a near-zero
	vector and Unit throws on it.
]]
local function surfacePlacement(position: Vector3, normal: Vector3): CFrame
	local reference = if math.abs(normal.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = reference:Cross(normal).Unit
	local look = normal:Cross(right).Unit

	return CFrame.fromMatrix(position, right, normal, look)
end

local function destroyCloud(index: number)
	live[index].part:Destroy()

	-- Swap-remove; order does not matter and table.remove every frame would be
	-- the most expensive thing in the loop.
	local last = #live
	live[index] = live[last]
	live[last] = nil
end

--[[
	Lays one cloud at `position`, tinted `color`, lying along `normal`.

	Falls back to SmokeTexture when DustDecalTexture is empty, and draws nothing
	at all when neither is set -- stretching Roblox's default white sparkle
	across ninety studs of ground is worse than no dust.
]]
function DustCloud.spawn(position: Vector3, color: Color3, normal: Vector3)
	if not Config.EnableDustDecal or #live >= Config.MaxLiveDust then
		return
	end

	local texture = Shared.assetId(Config.DustDecalTexture)
	if texture == "" then
		texture = Shared.assetId(Config.SmokeTexture)
	end
	if texture == "" then
		return
	end

	local startSize = Shared.rollRange(Config.DustDecalStartSize)
	local endSize = Shared.rollRange(Config.DustDecalEndSize)

	local part = Instance.new("Part")
	part.Name = "ArtilleryDustCloud"
	part.Size = Vector3.new(startSize, THICKNESS, startSize)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false

	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = texture
	decal.Color3 = color
	decal.Transparency = Config.DustDecalStartTransparency
	decal.Parent = part

	-- A random starting yaw, so twenty craters in one barrage are not twenty
	-- copies of the same image in the same orientation.
	local placement = surfacePlacement(position, normal) * CFrame.Angles(0, math.random() * math.pi * 2, 0)

	part.CFrame = placement + normal * Config.DustDecalStartHeight
	part.Parent = getContainer()

	table.insert(live, {
		part = part,
		decal = decal,
		placement = placement,
		normal = normal,
		born = os.clock(),
		spin = math.rad(Config.DustDecalSpin) * (if math.random() < 0.5 then -1 else 1),
		startSize = startSize,
		endSize = endSize,
	})
end

function DustCloud.step()
	local count = #live
	if count == 0 then
		return
	end

	local now = os.clock()

	-- Backwards, because destroyCloud swaps the last entry into the current slot.
	for index = count, 1, -1 do
		local cloud = live[index]
		local elapsed = now - cloud.born

		if elapsed >= LIFETIME then
			destroyCloud(index)
			continue
		end

		local t = elapsed / LIFETIME

		-- Growth is curved, the sink is not. Dust opens out in the first moment
		-- and then creeps, but it settles at a steady rate -- an eased sink reads
		-- as the image being pulled down rather than as weight coming out of it.
		local size = Shared.lerp(cloud.startSize, cloud.endSize, t ^ Config.DustDecalGrowthCurve)
		local height = Shared.lerp(Config.DustDecalStartHeight, Config.DustDecalEndHeight, t)

		local part = cloud.part
		part.Size = Vector3.new(size, THICKNESS, size)
		part.CFrame = (cloud.placement + cloud.normal * height) * CFrame.Angles(0, cloud.spin * elapsed, 0)

		-- Held fully visible, then faded. The hold is what makes it read as dust
		-- hanging over the crater instead of a flash.
		if elapsed > Config.DustDecalHoldTime then
			local fade = (elapsed - Config.DustDecalHoldTime) / Config.DustDecalFadeTime
			cloud.decal.Transparency = Shared.lerp(Config.DustDecalStartTransparency, 1, fade)
		end
	end
end

function DustCloud.liveCount(): number
	return #live
end

return DustCloud

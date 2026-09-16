--!strict
--[[
	What is in front of the player, and can they get on top of it.

	Three casts, in order, cheapest first, each one able to refuse on its own:

	  1. FORWARD  is there a wall face in reach, and am I running at it?
	  2. TOP      how high is the surface above it?
	  3. CLEAR    is there room for a body up there?

	Every refusal carries a reason string. That is not decoration -- "too high"
	and "no room up there" look identical from inside the game and are fixed by
	different numbers, so the reason is the entire diagnostic when someone says
	"it won't let me climb this".

	The arithmetic is split out into classify(), which is pure and takes only
	numbers, so the band boundaries can be tested without a running game.
]]

--[[
	This lives in shared rather than client because the Studio probe tool needs
	exactly the same answers the game uses. A tool that re-implemented the casts
	would drift from the real ones, and the whole point of the tool is to show
	you what the game is actually seeing.
]]
local Config = require(script.Parent:WaitForChild("ParkourConfig"))
local Shared = require(script.Parent:WaitForChild("ParkourShared"))

local ParkourDetect = {}

ParkourDetect.Result = table.freeze({
	None = "None", -- nothing in front of us worth anything
	Step = "Step", -- low enough that the Humanoid walks over it unaided
	Vault = "Vault",
	Mantle = "Mantle",
	TooHigh = "TooHigh",
})

export type Reading = {
	result: string,
	reason: string?,
	origin: Vector3, -- where the forward probe started, for the probe tool to draw
	direction: Vector3, -- travel direction used
	facePoint: Vector3?,
	topY: number?,
	height: number?, -- top surface above the soles -- the vault's measure
	reach: number?, -- top surface relative to the root -- the mantle's measure
	land: Vector3?, -- where the root ends up if the move is allowed
}

local function fail(origin: Vector3, direction: Vector3, result: string, reason: string): Reading
	return {
		result = result,
		reason = reason,
		origin = origin,
		direction = direction,
	}
end

--[[
	Pure. Height is measured from the soles to the top surface.

	The bands are contiguous on purpose -- a gap between them is a height where
	the player gets no move and no explanation for why not.
]]
function ParkourDetect.classify(height: number): string
	if height < Config.StepHeight then
		return ParkourDetect.Result.Step
	elseif height <= Config.VaultMaxHeight then
		return ParkourDetect.Result.Vault
	elseif height <= Config.MantleMaxHeight then
		return ParkourDetect.Result.Mantle
	end
	return ParkourDetect.Result.TooHigh
end

--[[
	Pure. The mantle's own test, and it asks a different question.

	`reach` is the lip relative to the ROOT, not the soles -- see the config. A
	player at the top of a jump has their feet somewhere useless, but their
	hands are always a known distance from their root.

	`height` is still passed in, only to reject things that are too tall to be
	worth climbing at all no matter how well-placed the lip happens to be.
]]
function ParkourDetect.classifyReach(reach: number, height: number): (string, string?)
	if height > Config.MantleMaxHeight then
		return ParkourDetect.Result.TooHigh,
			string.format("%.1f studs tall -- above MantleMaxHeight", height)
	end

	if reach > Config.MantleGrabHigh then
		return ParkourDetect.Result.TooHigh,
			string.format("the lip is %.1f studs above you -- jump higher or earlier", reach)
	end

	if reach < Config.MantleGrabLow then
		return ParkourDetect.Result.None,
			string.format("you are already %.1f studs above the lip", -reach)
	end

	return ParkourDetect.Result.Mantle, nil
end

--[[
	Is this a surface we are willing to climb, as opposed to merely a surface we
	hit? Three ways a hit can be geometrically fine and still wrong.
]]
local function surfaceIsUsable(instance: BasePart): string?
	if not instance.CanCollide then
		return "surface is non-collidable"
	end

	-- No mantling off a teammate's head.
	local model = instance:FindFirstAncestorWhichIsA("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return "surface is a character"
	end

	--[[
		No mantling onto a moving vehicle. The climb drives the root along a
		path computed once at the start; if the thing underneath it is also
		moving, the two disagree for the whole move and the player ends up
		somewhere neither intended.
	]]
	if not instance.Anchored and instance.AssemblyLinearVelocity.Magnitude > 2 then
		return "surface is moving"
	end

	return nil
end

--[[
	mode is "Vault" or "Mantle", and it changes only where the forward probe
	starts -- see VaultProbeHeight / MantleProbeHeight in the config for why one
	is measured from the soles and the other from the root.
]]
function ParkourDetect.probe(character: Model, humanoid: Humanoid, root: BasePart, mode: string): Reading
	local flat = Shared.travelDirection(root, humanoid)
	local soles = Shared.solesY(root, humanoid)

	local originY = if mode == ParkourDetect.Result.Mantle
		then root.Position.Y + Config.MantleProbeHeight
		else soles + Config.VaultProbeHeight

	local origin = Vector3.new(root.Position.X, originY, root.Position.Z)

	local castParams = Shared.castParams(character)

	-- 1. FORWARD --------------------------------------------------------------

	local face = workspace:Raycast(origin, flat * Config.ProbeDistance, castParams)
	if not face then
		return fail(origin, flat, ParkourDetect.Result.None, "nothing in reach")
	end

	if math.abs(face.Normal.Y) > Config.MaxFaceTilt then
		return fail(origin, flat, ParkourDetect.Result.None, "not a wall face -- it is a slope or a floor")
	end

	-- Are we running at it, or merely alongside it?
	if face.Normal:Dot(flat) > -Config.MinApproachDot then
		return fail(origin, flat, ParkourDetect.Result.None, "approaching too obliquely")
	end

	local unusable = surfaceIsUsable(face.Instance)
	if unusable then
		return fail(origin, flat, ParkourDetect.Result.None, unusable)
	end

	-- 2. TOP ------------------------------------------------------------------

	--[[
		Start above the highest thing we would ever climb and cast down. A MISS
		here is the "too high to bother with" answer, and it is a miss rather
		than a comparison, which is what makes it reliable -- there is simply no
		top surface within reach.
	]]
	local topOrigin = face.Position + flat * Config.TopProbeInset + Vector3.new(0, Config.MantleMaxHeight, 0)
	local topReach = Config.MantleMaxHeight + Config.RootToSoles

	local top = workspace:Raycast(topOrigin, Vector3.new(0, -topReach, 0), castParams)
	if not top then
		return fail(origin, flat, ParkourDetect.Result.TooHigh, "no top surface within reach")
	end

	if top.Normal.Y < Config.MinTopFlatness then
		return fail(origin, flat, ParkourDetect.Result.None, "top is too steep to stand on")
	end

	local height = top.Position.Y - soles
	local reach = top.Position.Y - root.Position.Y

	local result: string
	local reason: string?

	--[[
		The two moves ask different questions of the same geometry, so they get
		different classifiers. The vault asks how tall it is; the mantle asks
		whether the lip is within arm's reach. See MantleGrabLow in the config
		for why measuring a mantle from the soles does not work.
	]]
	if mode == ParkourDetect.Result.Mantle then
		result, reason = ParkourDetect.classifyReach(reach, height)
	else
		result = ParkourDetect.classify(height)
		if result == ParkourDetect.Result.Step then
			reason = string.format("only %.1f studs -- you can walk over that", height)
		elseif result == ParkourDetect.Result.TooHigh then
			reason = string.format("%.1f studs is above MantleMaxHeight", height)
		end
	end

	local reading: Reading = {
		result = result,
		reason = reason,
		origin = origin,
		direction = flat,
		facePoint = face.Position,
		topY = top.Position.Y,
		height = height,
		reach = reach,
	}

	-- Refusals from here on carry the measured height and reach, which fail()
	-- cannot -- so they amend the reading rather than building a new one. One
	-- helper, so all of them still read the same way.
	local function refuse(refusal: string, why: string): Reading
		reading.result = refusal
		reading.reason = why
		return reading
	end

	-- Anything that is not an actionable move stops here, before the clearance
	-- check -- there is no point asking whether you would fit somewhere you are
	-- not going.
	if result ~= ParkourDetect.Result.Vault and result ~= ParkourDetect.Result.Mantle then
		return reading
	end

	-- 3. CLEAR ----------------------------------------------------------------

	local land = Shared.landPoint(face.Position, top.Position.Y, flat)

	-- A body-sized box sitting on the top surface. Catches low ceilings, pipes
	-- over the ledge, a second wall a stud back, and standing in a doorframe.
	local clearCentre = Vector3.new(land.X, top.Position.Y + Config.ClearanceSize.Y / 2 + 0.1, land.Z)

	local blocking = workspace:GetPartBoundsInBox(
		CFrame.new(clearCentre),
		Config.ClearanceSize,
		Shared.overlapParams(character)
	)

	if #blocking > 0 then
		return refuse(ParkourDetect.Result.None, "no room up there -- " .. blocking[1].Name .. " is in the way")
	end

	reading.land = land
	return reading
end

return table.freeze(ParkourDetect)

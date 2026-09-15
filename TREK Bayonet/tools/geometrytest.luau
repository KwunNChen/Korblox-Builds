--[[
	Headless tests for BayonetGeometry.

		lune run tools/geometrytest.luau

	Run this after touching anything in src/shared/BayonetGeometry.luau. It
	builds real Instances in memory -- no Studio, no place file, no playtest.

	It exists because every hit-detection fault in this system was in that
	module and every one of them was found by a person in a playtest wondering
	why a blade through someone's chest did nothing. The last one was

		local centre, half = frame and bladeBox(blade, frame)

	where `x and f()` truncates to a single value, so the box had no size and
	nothing was ever hit. The first test below is that exact case.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance, CFrame, Vector3 = roblox.Instance, roblox.CFrame, roblox.Vector3

-- The module reads nothing but its arguments, so it loads with a bare
-- environment carrying the Roblox datatypes it uses.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local env = {
	CFrame = CFrame,
	Vector3 = Vector3,
	math = math,
	ipairs = ipairs,
	pairs = pairs,
	table = table,
	string = string,
	tostring = tostring,
	type = type,
}
env._G = env

local Geometry = luau.load(
	luau.compile(fs.readFile("src/shared/BayonetGeometry.luau")),
	{ environment = env }
)()

--[[
	A Part with CFrame AND Position set.

	Roblox derives one from the other; lune stores them separately and errors on
	reading a Position that was never assigned. Every fixture below goes through
	here so the module can keep reading part.Position, which is the cheap path
	in the real engine.
]]
local function newPart(size: Vector3, cf: CFrame, name: string?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cf
	part.Position = cf.Position
	if name then
		part.Name = name
	end
	return part
end

local failures = 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		print("  pass  " .. name)
	else
		failures += 1
		print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
	end
end

--[[
	The KR-61's real bayonet, measured from bonecrusher.rbxm: six welded parts
	spanning 0.19 x 0.53 x 1.94 studs, sitting 2.66 studs ahead of the torso.
]]
local function makeBlade(at: CFrame): Instance
	local model = Instance.new("Model")
	model.Name = "Bayonet"

	newPart(Vector3.new(0.19, 0.53, 0.68), at * CFrame.new(0, 0, 0.63), "Guard").Parent = model
	newPart(Vector3.new(0.04, 0.15, 1.19), at * CFrame.new(0, 0, -0.375), "Blade").Parent = model

	return model
end

-- An R6 character, limbs nested one level deeper than usual on purpose: depth
-- is a modelling choice and must not decide whether someone can be stabbed.
local function makeCharacter(at: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Dummy"

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	local nest = Instance.new("Model")
	nest.Name = "Body"
	nest.Parent = model

	newPart(Vector3.new(2, 2, 1), CFrame.new(at), "Torso").Parent = nest
	newPart(Vector3.new(2, 1, 1), CFrame.new(at + Vector3.new(0, 1.5, 0)), "Head").Parent = nest

	return model
end

-- facing -Z, the Roblox convention
local root = newPart(Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), "HumanoidRootPart")

local PAD = Vector3.new(1.25, 2.5, 1.5)

-- Blade held 2.66 studs ahead of the torso.
local function bladeAt(pitchDeg: number): Instance
	return makeBlade(root.CFrame * CFrame.Angles(math.rad(pitchDeg), 0, 0) * CFrame.new(0, 0, -2.66))
end

local function hits(blade: Instance, character: Model): (boolean, number)
	local worldCentre = Geometry.bladeCentre(blade)
	if not worldCentre then
		return false, math.huge
	end

	local frame = Geometry.attackerFrame(root, worldCentre)
	local centre, half = Geometry.bladeBox(blade, frame)
	if not centre or not half then
		return false, math.huge
	end

	local _, gap = Geometry.deepestPart(character, frame, centre, half + PAD)
	return gap <= 0, gap
end

print("\nbladeBox returns both values")
do
	local centre, half = Geometry.bladeBox(bladeAt(0), CFrame.new())
	check("centre is returned", centre ~= nil)
	check("half extents are returned", half ~= nil, "this is the truncation bug")

	-- The guard that actually broke: written the wrong way, `half` vanishes.
	local truncated, alsoTruncated = (true and Geometry.bladeBox(bladeAt(0), CFrame.new()))
	check(
		"`x and bladeBox()` truncates -- never write it that way",
		truncated ~= nil and alsoTruncated == nil,
		"if this fails, Luau changed and the comment in the module is stale"
	)
end

print("\nblade geometry matches the real model")
do
	local _, half = Geometry.bladeBox(bladeAt(0), CFrame.new())
	local size = (half :: Vector3) * 2
	check(
		string.format("blade measures %.2f x %.2f x %.2f", size.X, size.Y, size.Z),
		math.abs(size.Z - 1.94) < 0.05 and size.X < 0.5,
		"expected a sliver about 1.94 studs long"
	)
end

print("\nno geometry is reported, not assumed")
do
	local empty = Instance.new("Model")
	empty.Name = "Bayonet"
	check("a Bayonet with no parts gives nil", Geometry.bladeCentre(empty) == nil)

	local motor = Instance.new("Motor6D")
	motor.Name = "Bayonet"
	check("a Motor6D named Bayonet gives nil", Geometry.bladeCentre(motor) == nil)
end

print("\nstabs that should land")
for _, case in ipairs({
	{ name = "straight ahead, 4 studs", pitch = 0, at = Vector3.new(0, 4, -4) },
	{ name = "mid-thrust, torso pitched 38", pitch = 38, at = Vector3.new(0, 4, -4) },
	{ name = "end of thrust, pitched -8", pitch = -8, at = Vector3.new(0, 4, -4) },
	{ name = "1.5 studs off-centre", pitch = 0, at = Vector3.new(1.5, 4, -4) },
	{ name = "crouched below you", pitch = 0, at = Vector3.new(0, 2.5, -3.5) },
	{ name = "point blank, 2.5 studs", pitch = 0, at = Vector3.new(0, 4, -2.5) },
}) do
	local hit, gap = hits(bladeAt(case.pitch), makeCharacter(case.at))
	check(case.name, hit, string.format("%.2f studs outside the box", gap))
end

print("\nstabs that should not land")
for _, case in ipairs({
	{ name = "4 studs to the side", pitch = 0, at = Vector3.new(4, 4, 0) },
	{ name = "directly behind you", pitch = 0, at = Vector3.new(0, 4, 3) },
	{ name = "8 studs ahead", pitch = 0, at = Vector3.new(0, 4, -8) },
	{ name = "on a roof 8 studs up", pitch = 0, at = Vector3.new(0, 12, -4) },
}) do
	local hit, gap = hits(bladeAt(case.pitch), makeCharacter(case.at))
	check(case.name, not hit, string.format("hit anyway, %.2f", gap))
end

print("\ntarget limbs are found however deeply they are nested")
do
	local character = makeCharacter(Vector3.new(0, 4, -4))
	local part, _ = Geometry.deepestPart(character, CFrame.new(), Vector3.new(0, 4, -4), Vector3.new(3, 3, 3))
	check("found a limb two levels down", part ~= nil and part.Name == "Torso")
end

print("\na held Tool is never the part that gets hit")
do
	local character = makeCharacter(Vector3.new(0, 4, -4))
	local tool = Instance.new("Tool")
	tool.Parent = character

	-- A rifle part sitting closer to the blade than any limb.
	local rifle = newPart(Vector3.new(1, 1, 4), CFrame.new(0, 4, -3), "AnimPart")
	rifle.Parent = tool

	local part, _ = Geometry.deepestPart(character, CFrame.new(), Vector3.new(0, 4, -4), Vector3.new(3, 3, 3))
	check("picked a limb, not the rifle", part ~= nil and part.Name ~= "AnimPart",
		part and ("picked " .. part.Name) or "picked nothing")
end

--[[
	The fast path must never change a verdict.

	deepestFromParts skips the full transform for parts whose bounding sphere
	cannot reach the box. That is an optimisation, so it is checked against an
	exhaustive version that transforms every part unconditionally: same hit or
	miss, and the same limb chosen, everywhere.
]]
print("")
print("the sphere reject never changes the answer")
do
	local function exhaustive(parts, frame, centre, box)
		local inverse = frame:Inverse()
		local bestPart, bestGap = nil, math.huge
		for _, part in ipairs(parts) do
			local rel = inverse * part.CFrame
			local gap = Geometry.separation(centre, box, rel.Position, Geometry.halfExtents(rel, part.Size))
			if gap < bestGap then
				bestGap, bestPart = gap, part
			end
		end
		return bestPart, bestGap
	end

	local mismatches, compared = 0, 0

	for dx = -6, 6 do
		for dz = 1, 12 do
			for _, dy in ipairs({ -3, 0, 3 }) do
				for _, pitch in ipairs({ 38, 0, -20 }) do
					local character = makeCharacter(Vector3.new(dx * 0.8, 4 + dy, -dz * 0.8))
					local blade = bladeAt(pitch)

					local worldCentre = Geometry.bladeCentre(blade)
					local frame = Geometry.attackerFrame(root, worldCentre :: Vector3)
					local centre, half = Geometry.bladeBox(blade, frame)
					local box = (half :: Vector3) + PAD

					local parts, radii = Geometry.collectParts(character, true)
					local fastPart, fastGap = Geometry.deepestFromParts(parts, radii, frame, centre :: Vector3, box)
					local slowPart, slowGap = exhaustive(parts, frame, centre :: Vector3, box)

					compared += 1

					-- The verdict must match, and when it is a hit the limb must too.
					local sameVerdict = (fastGap <= 0) == (slowGap <= 0)
					local samePart = fastGap > 0 or fastPart == slowPart
					-- On a hit the gap must be exact, not the cheap lower bound.
					local exactWhenHit = fastGap > 0 or math.abs(fastGap - slowGap) < 1e-4

					if not (sameVerdict and samePart and exactWhenHit) then
						mismatches += 1
					end
				end
			end
		end
	end

	check(string.format("%d placements agree with an exhaustive test", compared), mismatches == 0,
		mismatches .. " disagreed")
end

--[[
	A limb removed mid-sweep must stop counting.

	The parts array is collected once per stab and reused, so a limb that
	handleGibs destroys between samples is still in it. Testing a destroyed part
	would hit a body that is no longer there.
]]
print("")
print("destroyed limbs drop out of a cached list")
do
	local character = makeCharacter(Vector3.new(0, 4, -4))
	local parts, radii = Geometry.collectParts(character, true)

	local before = Geometry.deepestFromParts(parts, radii, CFrame.new(), Vector3.new(0, 4, -4), Vector3.new(3, 3, 3))
	check("a limb is found while attached", before ~= nil)

	for _, part in ipairs(parts) do
		part:Destroy()
	end

	local after = Geometry.deepestFromParts(parts, radii, CFrame.new(), Vector3.new(0, 4, -4), Vector3.new(3, 3, 3))
	check("no limb is found once destroyed", after == nil)
end

print("")

if failures == 0 then
	print("all geometry tests passed")
else
	print(failures .. " FAILED")
	process.exit(1)
end

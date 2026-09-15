--[[
	Benchmark for BayonetGeometry.

		lune run tools/geometrybench.luau

	Times the work one stab actually does: HitWindow / HitSampleInterval samples,
	each measuring the blade and testing every nearby character's limbs.

	READ THE NUMBERS WITH CARE. Two things they do not tell you:

	  * workspace:GetPartBoundsInBox is an engine call with no equivalent here,
	    so it is absent from these timings entirely. Its cost scales with the
	    volume searched, which the service cut by about thirty-six times by
	    dropping the debug report margin from the query when Debug is off. That
	    is very likely the largest real saving and none of it shows up below.

	  * lune reaches instance properties through a reflection layer that is far
	    slower than the engine's. Every part.Position and part.CFrame read here
	    costs orders of magnitude more than it does in Roblox, which inflates
	    the per-part work and hides the cost of the things that were actually
	    removed -- descendant walks and table allocations.

	So treat this as a RATIO between two implementations on identical work, not
	as a per-stab cost. A change that does not move these numbers may still be
	worth making, and a change that moves them a lot may be measuring lune.
]]

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Instance, CFrame, Vector3 = roblox.Instance, roblox.CFrame, roblox.Vector3

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

-- The KR-61's blade: six welded pieces.
local function makeBlade(at: CFrame): Instance
	local model = Instance.new("Model")
	model.Name = "Bayonet"
	for i = 1, 6 do
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.19, 0.53, 0.4)
		part.CFrame = at * CFrame.new(0, 0, -0.3 * i)
		part.Position = part.CFrame.Position
		part.Parent = model
	end
	return model
end

-- An R6 rig with the accessories and nested extras a real character carries.
local function makeCharacter(at: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Dummy"
	Instance.new("Humanoid").Parent = model

	for _, limb in ipairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "HumanoidRootPart" }) do
		local part = Instance.new("Part")
		part.Name = limb
		part.Size = Vector3.new(1, 2, 1)
		part.CFrame = CFrame.new(at)
		part.Position = at
		part.Parent = model
	end

	-- Hats, and a held rifle whose parts must be skipped.
	for i = 1, 3 do
		local acc = Instance.new("Accessory")
		acc.Name = "Hat" .. i
		acc.Parent = model
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.CFrame = CFrame.new(at + Vector3.new(0, 3, 0))
		handle.Position = at + Vector3.new(0, 3, 0)
		handle.Parent = acc
	end

	local tool = Instance.new("Tool")
	tool.Parent = model
	for i = 1, 8 do
		local part = Instance.new("Part")
		part.Name = "GunPart" .. i
		part.Size = Vector3.new(0.5, 0.5, 2)
		part.CFrame = CFrame.new(at + Vector3.new(1, 0, 0))
		part.Position = at + Vector3.new(1, 0, 0)
		part.Parent = tool
	end

	return model
end

local root = Instance.new("Part")
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(0, 3, 0)
root.Position = root.CFrame.Position

local blade = makeBlade(root.CFrame * CFrame.new(0, 0, -2.66))
local PAD = Vector3.new(1.25, 2.5, 1.5)

-- Six characters in range, which is a busy but ordinary fight.
local characters = {}
for i = 1, 6 do
	table.insert(characters, makeCharacter(Vector3.new(i * 1.5 - 4, 4, -4)))
end

local SAMPLES = 11 -- HitWindow 0.35 / HitSampleInterval 0.03
local STABS = 400

--[[
	THE BASELINE IS WRITTEN OUT IN FULL, on purpose.

	It would be easier to call Geometry.bladeBox and Geometry.deepestPart and
	call that "before" -- but those are the optimised functions now, so that
	measures the caching alone and flatters the result. This is a transcription
	of the code as it stood: descendants walked on every call, a fresh
	Size.Magnitude per part, no destroyed-part check, no sphere reject, and the
	blade measured twice per sample.
]]
local function oldBox(instance, frame)
	local inverse = frame:Inverse()
	local lo, hi = nil, nil

	local function absorb(part)
		local rel = inverse * part.CFrame
		local half = Geometry.halfExtents(rel, part.Size)
		local partLo, partHi = rel.Position - half, rel.Position + half
		lo = lo and Vector3.new(math.min(lo.X, partLo.X), math.min(lo.Y, partLo.Y), math.min(lo.Z, partLo.Z)) or partLo
		hi = hi and Vector3.new(math.max(hi.X, partHi.X), math.max(hi.Y, partHi.Y), math.max(hi.Z, partHi.Z)) or partHi
	end

	if instance:IsA("BasePart") then
		absorb(instance)
	end
	for _, d in ipairs(instance:GetDescendants()) do
		if d:IsA("BasePart") then
			absorb(d)
		end
	end

	if not lo or not hi then
		return nil, nil
	end
	return (lo + hi) * 0.5, (hi - lo) * 0.5
end

local function oldDeepest(character, frame, centre, box)
	local inverse = frame:Inverse()
	local bestPart, bestGap = nil, math.huge

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and not part:FindFirstAncestorWhichIsA("Tool") then
			local rel = inverse * part.CFrame
			local gap = Geometry.separation(centre, box, rel.Position, Geometry.halfExtents(rel, part.Size))
			if gap < bestGap then
				bestGap, bestPart = gap, part
			end
		end
	end

	return bestPart, bestGap
end

local function stabAsShipped(cast)
	for _ = 1, SAMPLES do
		local worldCentre = oldBox(blade, CFrame.new())
		if worldCentre then
			local frame = Geometry.attackerFrame(root, worldCentre)
			local centre, half = oldBox(blade, frame)
			if centre and half then
				local box = half + PAD
				for _, character in ipairs(cast) do
					oldDeepest(character, frame, centre, box)
				end
			end
		end
	end
end

local function time(label: string, fn: (any) -> (), cast)
	-- Warm up, so the first run's compilation does not land in the measurement.
	for _ = 1, 20 do
		fn(cast)
	end

	-- Best of three. A single timing on a desktop picks up whatever else the
	-- machine was doing; the fastest run is the one least polluted by it.
	local best = math.huge
	for _ = 1, 3 do
		local started = os.clock()
		for _ = 1, STABS do
			fn(cast)
		end
		best = math.min(best, os.clock() - started)
	end

	print(string.format("  %-10s %7.3f ms per stab", label, best / STABS * 1000))
	return best / STABS
end

print(string.format("%d samples per stab, %d parts per character", SAMPLES, #characters[1]:GetDescendants()))

--[[
	One stab as the service performs it now: parts collected once, the blade
	measured once per sample in a frame anchored at the attacker's root, and
	each character's limbs walked once for the whole stab.
]]
local function stabOptimised(cast)
	local bladeParts = Geometry.collectParts(blade)
	local limbCache = {}

	for _ = 1, SAMPLES do
		local frame = Geometry.attackerFrame(root, root.Position)
		local centre, half = Geometry.boxFromParts(bladeParts, frame)
		if centre and half then
			local box = half + PAD
			for _, character in ipairs(cast) do
				local limbs = limbCache[character]
				if not limbs then
					local parts, radii = Geometry.collectParts(character, true)
					limbs = { parts = parts, radii = radii }
					limbCache[character] = limbs
				end
				Geometry.deepestFromParts(limbs.parts, limbs.radii, frame, centre, box)
			end
		end
	end
end

--[[
	Two loads, because they are not the same problem.

	TYPICAL is one person in front of you. The hitbox is about 4.5 x 5.5 x 5.6
	studs, so one or two candidates is what a stab actually sees -- the query
	cannot return characters who are not in the box.

	CROWDED is six, which does not physically fit in that box but is what the
	old six-stud report margin used to drag in, and is the shape of the load if
	the box is ever widened.
]]
local typical = { characters[1] }

print("")
print("TYPICAL -- one character in reach")
local beforeTypical = time("before", stabAsShipped, typical)
local afterTypical = time("after", stabOptimised, typical)
print(string.format("  %-10s %.1fx faster, %.2f ms saved per stab",
	"", beforeTypical / afterTypical, (beforeTypical - afterTypical) * 1000))

print("")
print("CROWDED -- six characters in reach")
local beforeCrowd = time("before", stabAsShipped, characters)
local afterCrowd = time("after", stabOptimised, characters)
print(string.format("  %-10s %.1fx faster, %.2f ms saved per stab",
	"", beforeCrowd / afterCrowd, (beforeCrowd - afterCrowd) * 1000))

print("")
print("work done per stab, before -> after (six characters)")
print(string.format("  blade measured             %3d -> %3d", SAMPLES * 2, SAMPLES))
print(string.format("  blade descendants walked   %3d -> %3d", SAMPLES * 2, 1))
print(string.format("  limb descendants walked    %3d -> %3d", SAMPLES * #characters, #characters))
print(string.format("  Size.Magnitude sqrts       %3d -> %3d",
	SAMPLES * #characters * 14, #characters * 14))

return afterTypical

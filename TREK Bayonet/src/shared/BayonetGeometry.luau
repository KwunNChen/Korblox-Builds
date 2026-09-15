--!strict
--[[
	The bayonet's geometry, with no game state in it.

	Split out of BayonetService for one reason: so it can be run outside Roblox.
	Every hit-detection fault in this system so far has been in these few
	functions, and each one cost a Studio playtest to find -- including a
	`local centre, half = frame and bladeBox(...)` that silently truncated to one
	value and made every stab miss. That is a ten-line test to catch and was
	instead found by a player wondering why a blade through someone's chest did
	nothing.

	tools/geometrytest.luau exercises all of it headlessly:

		lune run tools/geometrytest.luau

	Nothing in here reads the DataModel, the config, or a player. Instances go
	in, numbers come out.
]]

local Geometry = {}

--[[
	The half extents of an oriented box, projected onto the axes of the frame it
	is expressed in.

	Standard OBB-to-AABB projection: each axis takes the absolute value of that
	row of the rotation matrix dotted with the half size. Used for the blade and
	for its targets both, so every comparison downstream is like with like and
	nothing depends on which way anything is facing.
]]
function Geometry.halfExtents(cf: CFrame, size: Vector3): Vector3
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local h = size * 0.5

	return Vector3.new(
		math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
		math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
		math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z
	)
end

--[[
	The frame everything is measured in: level, facing where the attacker faces.

	Not the blade's own frame. Model:GetBoundingBox and a part's CFrame are both
	oriented to the blade, which rolls and pitches through the thrust animation,
	so padding measured there means something different at every point in the
	swing. Flattening the attacker's look direction gives three axes that hold
	still: side, up, and forward.
]]
function Geometry.attackerFrame(root: BasePart, at: Vector3): CFrame
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)

	-- Looking straight up or down leaves nothing to flatten. Rare, but it would
	-- produce a zero-length direction and a NaN CFrame.
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end

	return CFrame.lookAt(at, at + flat.Unit)
end

--[[
	Every BasePart under an instance, with each one's bounding-sphere radius.

	Gathered ONCE per stab and reused across all eleven samples. Walking an
	instance's descendants is the single most expensive thing this module does,
	and neither the blade's pieces nor a character's limbs change during the
	third of a second a thrust lasts.

	The radii are cached because they never change either -- a part's Size is
	fixed, so the sqrt behind Size.Magnitude is worth paying once rather than
	once per part per sample.

	`skipTools` drops anything inside a held Tool, which is how a character's
	limbs are collected: handleGibs destroys the part it is given, and that must
	never be someone's rifle.

	RETURNS TWO PARALLEL ARRAYS, parts and radii, indexed together.
]]
function Geometry.collectParts(instance: Instance, skipTools: boolean?): ({ BasePart }, { number })
	local parts: { BasePart } = {}
	local radii: { number } = {}

	local function absorb(part: BasePart)
		if skipTools and part:FindFirstAncestorWhichIsA("Tool") then
			return
		end
		local n = #parts + 1
		parts[n] = part
		radii[n] = part.Size.Magnitude * 0.5
	end

	if instance:IsA("BasePart") then
		absorb(instance)
	end
	for _, d in ipairs(instance:GetDescendants()) do
		if d:IsA("BasePart") then
			absorb(d)
		end
	end

	return parts, radii
end

--[[
	The box around a set of parts, expressed in `frame`.

	RETURNS TWO VALUES, centre and half extents, or nil, nil when there are no
	parts. Both of those matter to callers: a caller that drops the second value
	gets a box with no size and silently stops hitting anything, which is
	exactly the bug this module exists to prevent.
]]
function Geometry.boxFromParts(parts: { BasePart }, frame: CFrame): (Vector3?, Vector3?)
	local inverse = frame:Inverse()
	local lo: Vector3?, hi: Vector3? = nil, nil

	for i = 1, #parts do
		local part = parts[i]
		local rel = inverse * part.CFrame
		local half = Geometry.halfExtents(rel, part.Size)
		local partLo = rel.Position - half
		local partHi = rel.Position + half

		lo = lo and Vector3.new(math.min(lo.X, partLo.X), math.min(lo.Y, partLo.Y), math.min(lo.Z, partLo.Z))
			or partLo
		hi = hi and Vector3.new(math.max(hi.X, partHi.X), math.max(hi.Y, partHi.Y), math.max(hi.Z, partHi.Z))
			or partHi
	end

	if not lo or not hi then
		return nil, nil
	end

	return (lo + hi) * 0.5, (hi - lo) * 0.5
end

-- Convenience wrapper: collect and measure in one call. The service does not
-- use this in its sweep -- it collects once and calls boxFromParts per sample.
function Geometry.bladeBox(blade: Instance, frame: CFrame): (Vector3?, Vector3?)
	local parts = Geometry.collectParts(blade)
	return Geometry.boxFromParts(parts, frame)
end

-- Where the blade is in the world. Frame-independent, so it can be compared
-- across samples to tell whether the thrust actually moved it.
function Geometry.bladeCentre(blade: Instance): Vector3?
	local centre = Geometry.bladeBox(blade, CFrame.new())
	return centre
end

--[[
	How far apart two boxes are, in studs, in a frame they share.

	Zero or less means they overlap, and the more negative the deeper. Positive
	is the gap on the axis furthest from touching -- which is the number worth
	printing on a miss, because it says exactly how much padding the stab was
	short by.
]]
function Geometry.separation(centreA: Vector3, halfA: Vector3, centreB: Vector3, halfB: Vector3): number
	local d = centreA - centreB

	return math.max(
		math.abs(d.X) - (halfA.X + halfB.X),
		math.abs(d.Y) - (halfA.Y + halfB.Y),
		math.abs(d.Z) - (halfA.Z + halfB.Z)
	)
end

--[[
	The part the blade went furthest into, and by how much.

	Deepest rather than first, so a thrust into a crowd damages the limb it
	actually buried itself in rather than whichever part happened to be
	enumerated first.

	Takes the cached arrays from collectParts rather than a character, so the
	descendant walk happens once per stab instead of once per sample.

	TWO CHEAP TESTS GUARD THE EXPENSIVE ONE.

	A part is skipped outright if it has been destroyed mid-sweep, which
	handleGibs does to a limb the instant it is removed -- a cached array would
	otherwise keep testing a limb that is no longer on the body.

	Then a sphere check: if the distance between the part's centre and the box's
	centre exceeds both their bounding radii, they cannot overlap, and the full
	transform is skipped. Most of a character's limbs fail this on any given
	stab, and it costs one point transform instead of a CFrame multiply plus
	nine absolute values.

	For a part rejected that way the returned gap is a LOWER BOUND rather than
	the exact separation. That only ever applies to parts too far away to hit,
	and the exact figure is still computed for anything close enough to matter --
	which is what the miss report quotes.
]]
function Geometry.deepestFromParts(
	parts: { BasePart },
	radii: { number },
	frame: CFrame,
	centre: Vector3,
	box: Vector3
): (BasePart?, number)
	local inverse = frame:Inverse()
	local boxRadius = box.Magnitude
	local bestPart: BasePart? = nil
	local bestGap = math.huge

	for i = 1, #parts do
		local part = parts[i]

		--[[
			The destroyed check comes FIRST, before any property is read.

			A cached array outlives the limbs in it: handleGibs destroys a limb
			the instant it is removed, and a stab landing on a limb that is no
			longer on the body is wrong.

			Hoisting this out of the loop -- checking only the winner, once --
			measured faster and was still wrong twice over: it reads properties
			off a destroyed instance, and a destroyed limb could win the
			comparison and void a legitimate hit on the limb beside it.
		]]
		if part.Parent then
			-- Squared distance, so the reject costs a multiply rather than a
			-- square root. This runs once per part per sample -- roughly a
			-- thousand times a stab in a crowd -- so it must not be the thing
			-- that pays for a sqrt.
			local offset = (inverse * part.Position) - centre
			local reach = radii[i] + boxRadius
			local squared = offset:Dot(offset)

			if squared > reach * reach then
				-- Too far to touch. The bound is kept only if nothing better is
				-- known, so the miss report still has something to say.
				if bestGap == math.huge then
					bestGap = math.sqrt(squared) - reach
					bestPart = bestPart or part
				end
			else
				local rel = inverse * part.CFrame
				local gap = Geometry.separation(centre, box, rel.Position, Geometry.halfExtents(rel, part.Size))
				if gap < bestGap then
					bestGap, bestPart = gap, part
				end
			end
		end
	end

	return bestPart, bestGap
end

-- Convenience wrapper over deepestFromParts that collects the character's parts
-- itself. The service collects once per stab instead and calls the above.
function Geometry.deepestPart(
	character: Model,
	frame: CFrame,
	centre: Vector3,
	box: Vector3
): (BasePart?, number)
	local parts, radii = Geometry.collectParts(character, true)
	return Geometry.deepestFromParts(parts, radii, frame, centre, box)
end

return Geometry

--[[
	SkiGear
	Builds the skis and poles and joins them to the character, and moves them
	between "on your feet" and "stowed on your back".

	BUILT ON THE SERVER on purpose. Gear made here replicates to every client for
	free, so there is no per-client rendering code and no chance of one player
	seeing another with bare feet.

	Every part is Massless, non-collidable and non-queryable. The gear must not
	change how the character falls, must not catch on terrain, and must not show
	up in anyone's raycasts.

	R6. R15 gets a best-effort attach to the feet and hands so a mixed-rig game
	degrades instead of erroring.

	SWAPPING IN YOUR OWN MESH: put an id in Config.SkiMeshId or PoleMeshId and
	that gets used instead of the generated parts. Same joints, same offsets,
	nothing else changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))

local SkiGear = {}

local GEAR_NAME = "SkiGear"

-- Fraction of the ski's length given over to the swept nose.
local TIP_FRACTION = 0.17

-- Roblox puts a cylinder's flat circular faces on its X axis. Every pole part
-- is therefore built with +X running from the grip down to the tip, and one
-- rotation at the joint stands the whole thing upright. Doing it per-part
-- instead would mean every offset below was in a different rotated frame.
local POLE_UPRIGHT = -math.pi / 2

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Motor6D with explicit C0/C1 rather than WeldConstraint, so nothing depends on
-- parts being positioned correctly before they are joined. Parented to Part1
-- (the gear) rather than Part0, so stowing can retarget a joint without having
-- to go and find it somewhere on the character.
local function join(part0: BasePart, part1: BasePart, c0: CFrame, name: string?): Motor6D
	local motor = Instance.new("Motor6D")
	motor.Name = name or (part1.Name .. "Joint")
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = CFrame.identity
	motor.Parent = part1
	return motor
end

local function meshFor(part: BasePart, meshId: string, scale: Vector3, offset: Vector3)
	-- SpecialMesh rather than MeshPart: MeshPart.MeshId cannot be assigned at
	-- runtime in a live game, SpecialMesh.MeshId can.
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = meshId
	mesh.Scale = scale
	mesh.Offset = offset
	mesh.Parent = part
end

local function anglesFromDegrees(degrees: Vector3): CFrame
	return CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

-- ============================================================
-- THE SKIS
-- ============================================================

--[[
	Laid out along local Z, tail at +Z and tip at -Z, because -Z is forward in
	Roblox part space.

	Three body segments rather than one block: wide at the tail, narrow
	underfoot, wide again at the front. That sidecut is most of what stops a ski
	reading as a plank. The waist segment is the root everything else hangs off.
]]
local function buildSki(side: string, sign: number, rig: Model, leg: BasePart): (BasePart, Motor6D)
	local name = side .. "Ski"

	if Config.SkiMeshId ~= "" then
		local body = newPart(name, Vector3.new(Config.SkiWaistWidth, Config.SkiThickness, Config.SkiLength), Config.SkiColor, Config.SkiMaterial)
		meshFor(body, Config.SkiMeshId, Config.SkiMeshScale, Config.SkiMeshOffset)
		body.CFrame = leg.CFrame
		body.Parent = rig

		local attach = join(
			leg,
			body,
			CFrame.new(sign * Config.SkiFootOffset.X, Config.SkiFootOffset.Y, Config.SkiFootOffset.Z)
				* anglesFromDegrees(Config.SkiMeshRotation),
			name .. "Attach"
		)
		return body, attach
	end

	local tipRun = Config.SkiLength * TIP_FRACTION
	local flatLength = Config.SkiLength - tipRun
	local segmentLength = flatLength / 3

	local waist = newPart(name, Vector3.new(Config.SkiWaistWidth, Config.SkiThickness, segmentLength), Config.SkiColor, Config.SkiMaterial)
	waist.CFrame = leg.CFrame
	waist.Parent = rig

	-- Camber: the waist is the root and sits proud, so the tail and front drop
	-- away from it by that much. Set SkiCamber to 0 for a dead flat ski.
	local drop = -Config.SkiCamber

	local tail = newPart(name .. "Tail", Vector3.new(Config.SkiTailWidth, Config.SkiThickness, segmentLength), Config.SkiColor, Config.SkiMaterial)
	tail.CFrame = leg.CFrame
	tail.Parent = rig
	join(waist, tail, CFrame.new(0, drop, segmentLength))

	local front = newPart(name .. "Front", Vector3.new(Config.SkiTipWidth, Config.SkiThickness, segmentLength), Config.SkiColor, Config.SkiMaterial)
	front.CFrame = leg.CFrame
	front.Parent = rig
	join(waist, front, CFrame.new(0, drop, -segmentLength))

	-- The nose: walk forward from the front segment's leading edge, pitching up
	-- a little each step. Deriving the angle from the rise means SkiTipRise
	-- stays a distance you can picture rather than an angle you have to guess.
	local segmentCount = math.max(Config.SkiTipSegments, 1)
	local noseLength = tipRun / segmentCount
	local segmentAngle = (math.atan2(Config.SkiTipRise, tipRun) * 2) / segmentCount

	local cursor = CFrame.new(0, drop, -segmentLength - segmentLength * 0.5)
	for index = 1, segmentCount do
		cursor *= CFrame.Angles(segmentAngle, 0, 0)

		local nose = newPart(
			string.format("%sNose%d", name, index),
			Vector3.new(Config.SkiTipWidth, Config.SkiThickness, noseLength),
			Config.SkiColor,
			Config.SkiMaterial
		)
		nose.CFrame = leg.CFrame
		nose.Parent = rig
		join(waist, nose, cursor * CFrame.new(0, 0, -noseLength * 0.5))

		cursor *= CFrame.new(0, 0, -noseLength)
	end

	-- Toe piece forward (-Z), heel piece back. Both clear of the leg, so they
	-- read as hardware on the ski rather than a block round the ankle.
	for _, piece in { { "Toe", Config.BindingToeSize, -1 }, { "Heel", Config.BindingHeelSize, 1 } } do
		local pieceName, size, direction = piece[1] :: string, piece[2] :: Vector3, piece[3] :: number

		local binding = newPart(name .. "Binding" .. pieceName, size, Config.BindingColor, Enum.Material.SmoothPlastic)
		binding.CFrame = leg.CFrame
		binding.Parent = rig
		join(
			waist,
			binding,
			CFrame.new(0, (Config.SkiThickness + size.Y) * 0.5, direction * Config.BindingSpacing)
		)
	end

	local attach = join(
		leg,
		waist,
		CFrame.new(sign * Config.SkiFootOffset.X, Config.SkiFootOffset.Y, Config.SkiFootOffset.Z),
		name .. "Attach"
	)

	return waist, attach
end

-- ============================================================
-- THE POLES
-- ============================================================

local function poleHandCFrame(sign: number): CFrame
	return CFrame.new(sign * Config.PoleHandOffset.X, Config.PoleHandOffset.Y, Config.PoleHandOffset.Z)
		* CFrame.Angles(0, 0, POLE_UPRIGHT + sign * Config.PoleHandTilt)
end

local function buildPole(side: string, sign: number, rig: Model, arm: BasePart): (BasePart, Motor6D)
	local name = side .. "Pole"

	if Config.PoleMeshId ~= "" then
		local body = newPart(name, Vector3.new(Config.PoleThickness, Config.PoleLength, Config.PoleThickness), Config.PoleColor, Config.PoleMaterial)
		meshFor(body, Config.PoleMeshId, Config.PoleMeshScale, Config.PoleMeshOffset)
		body.CFrame = arm.CFrame
		body.Parent = rig

		local attach = join(
			arm,
			body,
			CFrame.new(sign * Config.PoleHandOffset.X, Config.PoleHandOffset.Y, Config.PoleHandOffset.Z)
				* anglesFromDegrees(Config.PoleMeshRotation),
			name .. "Attach"
		)
		return body, attach
	end

	-- Grip is the root, and +X from here runs down the shaft to the tip.
	local grip = newPart(name, Vector3.new(Config.PoleGripLength, Config.PoleGripThickness, Config.PoleGripThickness), Config.PoleGripColor, Enum.Material.SmoothPlastic)
	grip.Shape = Enum.PartType.Cylinder
	grip.CFrame = arm.CFrame
	grip.Parent = rig

	local shaft = newPart(name .. "Shaft", Vector3.new(Config.PoleLength, Config.PoleThickness, Config.PoleThickness), Config.PoleColor, Config.PoleMaterial)
	shaft.Shape = Enum.PartType.Cylinder
	shaft.CFrame = arm.CFrame
	shaft.Parent = rig
	join(grip, shaft, CFrame.new((Config.PoleGripLength + Config.PoleLength) * 0.5, 0, 0))

	local basket = newPart(name .. "Basket", Vector3.new(Config.PoleBasketThickness, Config.PoleBasketDiameter, Config.PoleBasketDiameter), Config.PoleColor, Enum.Material.SmoothPlastic)
	basket.Shape = Enum.PartType.Cylinder
	basket.CFrame = arm.CFrame
	basket.Parent = rig
	join(grip, basket, CFrame.new(Config.PoleGripLength * 0.5 + Config.PoleLength - Config.PoleBasketHeight, 0, 0))

	local attach = join(arm, grip, poleHandCFrame(sign), name .. "Attach")

	return grip, attach
end

-- ============================================================
-- THE CARRY STRAP
-- ============================================================

-- Everything the strap is made of, so stowing can show and hide it in one loop.
local STRAP_PARTS = {
	"StrapFront",
	"StrapBack",
	"StrapShoulder",
	"LeftSkiCinchFore",
	"LeftSkiCinchAft",
	"RightSkiCinchFore",
	"RightSkiCinchAft",
}

--[[
	A sling over one shoulder: a band down the chest, a band across the back, and
	a short piece joining them over the shoulder itself.

	Joined to the Torso, and hidden rather than moved when you strap in. Hiding
	is the cheap option and the right one -- there is nowhere sensible for a
	sling to go while you are wearing the skis, and you would take it off anyway.
]]
local function buildStrap(rig: Model, torso: BasePart)
	if not Config.EnableStrap then
		return
	end

	local side = if Config.StrapShoulder < 0 then -1 else 1
	local halfHeight = torso.Size.Y * 0.5
	local halfDepth = torso.Size.Z * 0.5

	-- Tilted the opposite way front and back, so the two halves meet over the
	-- same shoulder instead of forming an X around the body.
	local function band(name: string, z: number, tilt: number)
		local part = newPart(
			name,
			Vector3.new(Config.StrapWidth, Config.StrapLength, Config.StrapThickness),
			Config.StrapColor,
			Config.StrapMaterial
		)
		part.CFrame = torso.CFrame
		part.Parent = rig
		join(torso, part, CFrame.new(0, 0, z) * CFrame.Angles(0, 0, tilt))
		return part
	end

	band("StrapFront", -halfDepth - Config.StrapThickness * 0.4, side * Config.StrapTilt)
	band("StrapBack", halfDepth + Config.StrapThickness * 0.4, -side * Config.StrapTilt)

	local shoulder = newPart(
		"StrapShoulder",
		Vector3.new(Config.StrapWidth, Config.StrapThickness, torso.Size.Z + Config.StrapThickness),
		Config.StrapColor,
		Config.StrapMaterial
	)
	shoulder.CFrame = torso.CFrame
	shoulder.Parent = rig
	join(
		torso,
		shoulder,
		CFrame.new(side * (Config.StrapLength * 0.5 * math.sin(Config.StrapTilt)), halfHeight, 0)
	)
end

-- Two bands round each ski, so the pair reads as strapped together rather than
-- floating in formation. Joined to the ski itself, so they follow it whatever
-- carry style is set.
local function buildCinches(name: string, rig: Model, ski: BasePart)
	if not Config.EnableStrap then
		return
	end

	local size = Vector3.new(
		Config.SkiTipWidth + 0.12,
		Config.SkiThickness + 0.14,
		Config.StrapCinchWidth
	)

	for _, entry in { { "Fore", -1 }, { "Aft", 1 } } do
		local band = newPart(name .. "Cinch" .. entry[1], size, Config.StrapColor, Config.StrapMaterial)
		band.CFrame = ski.CFrame
		band.Parent = rig
		join(ski, band, CFrame.new(0, 0, entry[2] * Config.StrapCinchSpacing))
	end
end

local function setStrapVisible(rig: Model, visible: boolean)
	for _, name in STRAP_PARTS do
		local part = rig:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 1
		end
	end
end

-- ============================================================
-- LIMBS
-- ============================================================

local function limbs(character: Model)
	return {
		leftLeg = character:FindFirstChild("Left Leg") or character:FindFirstChild("LeftFoot"),
		rightLeg = character:FindFirstChild("Right Leg") or character:FindFirstChild("RightFoot"),
		leftArm = character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand"),
		rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand"),
		torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"),
	}
end

-- ============================================================
-- BUILD / DESTROY
-- ============================================================

function SkiGear.get(character: Model): Model?
	return character:FindFirstChild(GEAR_NAME) :: Model?
end

function SkiGear.destroy(character: Model)
	local existing = SkiGear.get(character)
	if existing then
		existing:Destroy()
	end
end

function SkiGear.build(character: Model): Model?
	SkiGear.destroy(character)

	local parts = limbs(character)
	if not (parts.leftLeg and parts.rightLeg and parts.leftArm and parts.rightArm and parts.torso) then
		warn("[Ski] " .. character.Name .. " is missing limbs -- gear not built")
		return nil
	end

	local rig = Instance.new("Model")
	rig.Name = GEAR_NAME

	-- Parented before anything is built, so both ends of every Motor6D are
	-- already in the world when the joint is made.
	rig.Parent = character

	buildStrap(rig, parts.torso :: BasePart)

	local leftSki = buildSki("Left", -1, rig, parts.leftLeg :: BasePart)
	local rightSki = buildSki("Right", 1, rig, parts.rightLeg :: BasePart)
	buildCinches("LeftSki", rig, leftSki)
	buildCinches("RightSki", rig, rightSki)

	buildPole("Left", -1, rig, parts.leftArm :: BasePart)
	buildPole("Right", 1, rig, parts.rightArm :: BasePart)

	log("gear built for %s", character.Name)
	return rig
end

-- ============================================================
-- STOWING
-- ============================================================

--[[
	Skis on the back, tips up.

	Reading the rotation right to left: Rx(90) stands the ski on end so its tip
	points up, then Rz(lean) tips it over. Doing those two the other way round
	rotates it about its own length instead, which spins the ski rather than
	leaning it.

	The only real difference between the styles is whether both skis lean the
	SAME way. Mirror the lean and you get an X; share it and you get a pair
	carried together, which is how skis are actually strapped to a pack.

	Separating a pair is done along the torso's Z. That is not arbitrary: after
	Rx(90) the ski's thickness axis points that way regardless of lean, so
	offsetting along it puts the skis base to base -- the direction they'd be
	strapped in -- instead of sliding one along the other's length.
]]
local function skiBackCFrame(sign: number): CFrame
	local style = Config.SkiCarryStyle
	local base = Config.SkiBackOffset

	if style == "Crossed" then
		return CFrame.new(sign * base.X, base.Y, base.Z)
			* CFrame.Angles(0, 0, sign * Config.SkiBackTilt)
			* CFrame.Angles(math.pi / 2, 0, 0)
	end

	if style == "Diagonal" then
		-- Both lean the same way, so they stay a parallel pair. Separated along
		-- Z rather than X: after Rx(90) the ski's thickness axis points that
		-- way, so the two sit base to base the way they'd be strapped together,
		-- instead of one sliding along the other's length.
		return CFrame.new(base.X, base.Y, base.Z + sign * Config.SkiCarrySpread * 0.5)
			* CFrame.Angles(0, 0, Config.SkiCarryAngle)
			* CFrame.Angles(math.pi / 2, 0, 0)
	end

	if style == "Vertical" then
		return CFrame.new(base.X + sign * Config.SkiCarrySpread * 0.5, base.Y, base.Z)
			* CFrame.Angles(math.pi / 2, 0, 0)
	end

	if style ~= "AFrame" then
		warn(string.format("[Ski] SkiCarryStyle %q is not one of AFrame/Diagonal/Vertical/Crossed -- using AFrame", tostring(style)))
	end

	--[[
		The upside-down V.

		Each ski leans in by SkiApexAngle, which swings its tip sideways by
		halfLength * sin(angle). Push the ski out by exactly that much and the
		tip lands back on the spine -- so the tips meet at the top and the tails
		open out below.

		Deriving the offset instead of exposing it is the point. Tilt and offset
		tuned independently is how you end up with an X (offset too small) or a
		gap (too big); tied together it is always a clean apex, and the angle is
		the only thing left to tune.
	]]
	local lean = Config.SkiApexAngle
	local converge = Config.SkiLength * 0.5 * math.sin(lean)

	return CFrame.new(base.X + sign * (converge + Config.SkiApexGap * 0.5), base.Y, base.Z)
		* CFrame.Angles(0, 0, sign * lean)
		* CFrame.Angles(math.pi / 2, 0, 0)
end

local function poleBackCFrame(sign: number): CFrame
	return CFrame.new(sign * Config.PoleBackOffset.X, Config.PoleBackOffset.Y, Config.PoleBackOffset.Z)
		* CFrame.Angles(0, 0, POLE_UPRIGHT + sign * Config.PoleBackTilt)
end

local function skiFootCFrame(sign: number): CFrame
	return CFrame.new(sign * Config.SkiFootOffset.X, Config.SkiFootOffset.Y, Config.SkiFootOffset.Z)
end

local function retarget(rig: Model, rootName: string, part0: BasePart, c0: CFrame)
	local root = rig:FindFirstChild(rootName)
	local attach = root and root:FindFirstChild(rootName .. "Attach")
	if attach and attach:IsA("Motor6D") then
		attach.Part0 = part0
		attach.C0 = c0
	end
end

-- Moves the same joints rather than rebuilding anything, so stowing costs four
-- property writes and never flickers.
function SkiGear.setStowed(character: Model, stowed: boolean)
	local rig = SkiGear.get(character)
	if not rig then
		return
	end

	local parts = limbs(character)
	if not (parts.leftLeg and parts.rightLeg and parts.leftArm and parts.rightArm and parts.torso) then
		return
	end

	local torso = parts.torso :: BasePart

	-- The strap only exists while they're on your back.
	setStrapVisible(rig, stowed)

	if stowed then
		retarget(rig, "LeftSki", torso, skiBackCFrame(-1))
		retarget(rig, "RightSki", torso, skiBackCFrame(1))
		retarget(rig, "LeftPole", torso, poleBackCFrame(-1))
		retarget(rig, "RightPole", torso, poleBackCFrame(1))
	else
		retarget(rig, "LeftSki", parts.leftLeg :: BasePart, skiFootCFrame(-1))
		retarget(rig, "RightSki", parts.rightLeg :: BasePart, skiFootCFrame(1))
		retarget(rig, "LeftPole", parts.leftArm :: BasePart, poleHandCFrame(-1))
		retarget(rig, "RightPole", parts.rightArm :: BasePart, poleHandCFrame(1))
	end

	log("%s gear %s", character.Name, stowed and "stowed" or "deployed")
end

return SkiGear

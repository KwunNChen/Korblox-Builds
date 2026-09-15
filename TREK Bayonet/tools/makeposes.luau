--[[
	Builds two R6 KeyframeSequences for the TREK bayonet:

		BayonetCharge  -- the guard/charge pose, looped
		BayonetThrust  -- the lunge, one shot

	Hierarchy copied from TREK's own animations in RBX_ANIMSAVES:

		KeyframeSequence > Keyframe > HumanoidRootPart > Torso > {Head, arms, legs}

	The thrust is driven from the TORSO, not the arms. TREK Motor6Ds the rifle to
	the torso (chr.Torso.toolAnim.Part1 = tool.AnimPart), so the arms alone would
	wave about while the rifle stayed put. Torso rotation and translation are what
	actually move the blade; the arms sell it.

	Angles are degrees, named, and grouped per pose so they are easy to nudge.
]]

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local Instance, Enum = roblox.Instance, roblox.Enum

local function d(deg: number): number
	return math.rad(deg)
end

-- rx/ry/rz in degrees, optional forward/up offset in studs
local function pose(rx: number, ry: number, rz: number, offset: any?)
	local cf = CFrame.Angles(d(rx), d(ry), d(rz))
	if offset then
		cf = CFrame.new(offset) * cf
	end
	return cf
end

--[[
	GUARD. Hands up on the weapon, and nothing else.

	No lean, no bladed torso, no leg stagger. The earlier version had all three
	and read as a man falling over rather than a man holding a rifle -- on a bare
	R6 dummy a 25 degree torso twist plus splayed legs just looks broken.

	Everything below the shoulders stays at rest. The arms carry the whole pose.
]]
local GUARD = {
	Torso = pose(0, 0, 0),
	Head = pose(0, 0, 0),
	["Right Arm"] = pose(72, 0, 12), -- trailing hand, up and slightly in
	["Left Arm"] = pose(84, 0, -22), -- leading hand, up and across
	["Right Leg"] = pose(0, 0, 0),
	["Left Leg"] = pose(0, 0, 0),
}

-- The same hold, breathing. Small enough to read as alive, not as a sway.
local GUARD_BREATH = {
	Torso = pose(0, 0, 0, Vector3.new(0, -0.04, 0)),
	Head = pose(0, 0, 0),
	["Right Arm"] = pose(75, 0, 12),
	["Left Arm"] = pose(87, 0, -22),
	["Right Leg"] = pose(0, 0, 0),
	["Left Leg"] = pose(0, 0, 0),
}

-- WIND UP. Hands drawn back toward the chest. Torso untouched.
local WINDUP = {
	Torso = pose(0, 0, 0, Vector3.new(0, 0, 0.15)),
	Head = pose(0, 0, 0),
	["Right Arm"] = pose(58, 0, 14),
	["Left Arm"] = pose(70, 0, -26),
	["Right Leg"] = pose(0, 0, 0),
	["Left Leg"] = pose(0, 0, 0),
}

--[[
	THRUST. Both arms punch out. That is the whole move.

	The torso gets a small forward SHOVE and no rotation. This is not styling:
	TREK joints the rifle to the torso (chr.Torso.toolAnim.Part1 = tool.AnimPart),
	so without it the arms would swing through a weapon that never moved. 0.45
	studs is enough to carry the rifle with the hands and small enough that the
	body still reads as still.
]]
local THRUST = {
	Torso = pose(0, 0, 0, Vector3.new(0, 0, -0.45)),
	Head = pose(0, 0, 0),
	["Right Arm"] = pose(96, 0, 4), -- driven out and squared up
	["Left Arm"] = pose(100, 0, -8),
	["Right Leg"] = pose(0, 0, 0),
	["Left Leg"] = pose(0, 0, 0),
}

-- RECOVER. Hands come back to the guard.
local RECOVER = {
	Torso = pose(0, 0, 0, Vector3.new(0, 0, -0.1)),
	Head = pose(0, 0, 0),
	["Right Arm"] = pose(78, 0, 10),
	["Left Arm"] = pose(89, 0, -20),
	["Right Leg"] = pose(0, 0, 0),
	["Left Leg"] = pose(0, 0, 0),
}

--[[
	ONLY the arms. This list is the whole point of the animation.

	A part with a Pose in the sequence has that part OVERRIDDEN for the duration
	-- these clips play at Action priority, which beats the Movement priority of
	Roblox's walk and run. So keyframing a leg, even pinned at rest, freezes the
	foot mid-stride and kills the run animation while the clip plays.

	Head and both legs are therefore absent, not zeroed. A part with no Pose is
	left completely alone and its normal animation shows through underneath.

	Torso stays because it is the parent of the arm poses in the joint tree and
	they cannot be reached without it -- but it is kept as close to rest as
	possible for the same reason.
]]
local LIMBS = { "Left Arm", "Right Arm" }

local function buildKeyframe(time: number, name: string, poses: any): any
	local kf = Instance.new("Keyframe")
	kf.Name = name
	kf.Time = time

	-- The root pose is always identity: moving HumanoidRootPart moves the whole
	-- character through the world, which is the animation sliding the player
	-- around rather than posing them.
	local root = Instance.new("Pose")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new()
	root.Weight = 1
	root.Parent = kf

	local torso = Instance.new("Pose")
	torso.Name = "Torso"
	torso.CFrame = poses.Torso
	torso.Weight = 1
	torso.EasingStyle = Enum.PoseEasingStyle.Cubic
	torso.EasingDirection = Enum.PoseEasingDirection.Out
	torso.Parent = root

	for _, limb in ipairs(LIMBS) do
		local p = Instance.new("Pose")
		p.Name = limb
		p.CFrame = poses[limb]
		p.Weight = 1
		p.EasingStyle = Enum.PoseEasingStyle.Cubic
		p.EasingDirection = Enum.PoseEasingDirection.Out
		p.Parent = torso
	end

	return kf
end

local function buildSequence(name: string, loop: boolean, frames: { any }): any
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = loop
	seq.Priority = Enum.AnimationPriority.Action

	for _, f in ipairs(frames) do
		buildKeyframe(f[1], f[2], f[3]).Parent = seq
	end

	return seq
end

local charge = buildSequence("BayonetCharge", true, {
	{ 0.0, "Guard", GUARD },
	{ 1.1, "Breath", GUARD_BREATH },
	{ 2.2, "GuardEnd", GUARD },
})

local thrust = buildSequence("BayonetThrust", false, {
	{ 0.00, "Guard", GUARD },
	{ 0.12, "WindUp", WINDUP },
	{ 0.28, "Thrust", THRUST },
	{ 0.40, "Hold", THRUST },
	{ 0.62, "Recover", RECOVER },
})

-- One KeyframeSequence per file. A Rojo $path maps a model file to a SINGLE
-- instance, so a two-root .rbxm would not sync cleanly into the project tree.
--
-- Paths are relative to the WORKING DIRECTORY, not to this script, so run it
-- from the package root:  lune run tools/makeposes.luau
--
-- Both formats on purpose. Rojo syncs the binary .rbxm into the place, but the
-- Animation Editor's "Import from file" is happier with XML, so the .rbxmx is
-- the one you feed the editor. Same poses either way.
fs.writeFile("assets/BayonetCharge.rbxm", roblox.serializeModel({ charge }))
fs.writeFile("assets/BayonetThrust.rbxm", roblox.serializeModel({ thrust }))
fs.writeFile("assets/BayonetCharge.rbxmx", roblox.serializeModel({ charge }, true))
fs.writeFile("assets/BayonetThrust.rbxmx", roblox.serializeModel({ thrust }, true))

print("wrote assets/Bayonet{Charge,Thrust}.{rbxm,rbxmx}")
for _, seq in ipairs({ charge, thrust }) do
	print(string.format("%s  (loop=%s)", seq.Name, tostring(seq.Loop)))
	for _, kf in ipairs(seq:GetChildren()) do
		local n = 0
		for _, _ in ipairs(kf:GetDescendants()) do n += 1 end
		print(string.format("   %5.2fs  %-10s  %d poses", kf.Time, kf.Name, n))
	end
end

-- Kill gore for Spearhead. Server only: called once per death with the killing hit part, direction, damage and position.
--   Head:  shotgun pops it or knocks it off (neck stump); anything else leaves a bullet wound where it hit.
--   Limb:  shotgun tears it off with flesh stumps on both ends; anything else (rifles) leaves a bleeding wound, never dismembers.
--   Torso: open wound with guts on the side that was hit; shotgun hits also tear or burst 1-2 limbs.
--   Explosion: 2-4 parts torn off plus a torso wound.
-- Gore pieces: ServerStorage.SPH_Gore.Kit (R6 gore kit from the Creator Store, scripts stripped).
-- Blood: layered splatter decals + normal-mapped streaks (ServerStorage.SPH_Gore.Streaks) + layered particles.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Gore = {}

local assets = game:GetService("ServerStorage"):FindFirstChild("SPH_Gore") -- nil on clients; they never call this
local KIT = assets and assets.Kit
-- Streak textures, drawn as Decals: the SurfaceAppearance boxes they came on flashed as solid red slabs
-- for a frame before their alpha applied. A decal that hasn't loaded draws nothing.
-- Ids copied from ServerStorage.SPH_Gore.Streaks' SurfaceAppearances: game scripts may no longer read
-- SurfaceAppearance.ColorMap (plugin-only), and reading it crashed this module and everything requiring it
local STREAKS = { "rbxassetid://81646923926055", "rbxassetid://127452682916979", "rbxassetid://114518386374542",
	"rbxassetid://72104641594251", "rbxassetid://101377218425579" }
local SPLASH = "rbxassetid://243457340" -- white splash shape, tinted to BLOOD
local BLOOD = Color3.fromRGB(95, 6, 6) -- the one blood colour: decals, streaks and particles all use it
local STREAK_TINT = Color3.new(math.min(BLOOD.R / 0.7, 1), math.min(BLOOD.G / 0.7, 1), math.min(BLOOD.B / 0.7, 1)) -- streak texture is ~70% grey, so this renders as BLOOD
local SPLAT_SOUNDS = {"rbxassetid://255661850", "rbxassetid://3802437696", "rbxassetid://9114519855"}
local BLOOD_LIFETIME = 15 -- seconds blood on the ground/walls stays (last 2 fading out)
local LIMBS = {["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true, LeftHand = true, RightHand = true,
	LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true, LeftFoot = true, RightFoot = true}
local ROOT_LIMBS = {"Left Arm", "Right Arm", "Left Leg", "Right Leg", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg"}
local KIT_NAME = {["Left Arm"] = "LeftArm", ["Right Arm"] = "RightArm", ["Left Leg"] = "LeftLeg", ["Right Leg"] = "RightLeg"} -- R6 only

---------------------------------------------------------------- particles
local function seq(a, b) return NumberSequence.new(a, b) end

-- Fast droplets that stretch along their velocity, lit by the scene (no glow).
local function droplets(parent: Instance, rate: number, speed: number, size: number, duration: number?)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPLASH
	e.Color = ColorSequence.new(BLOOD)
	e.LightInfluence, e.LightEmission = 1, 0
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Size = seq(size, size * 0.6)
	e.Squash = seq(1.2, 0.6)
	e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1)})
	e.Lifetime = NumberRange.new(0.45, 0.85)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(18, 18)
	e.Drag = 1.5
	e.Acceleration = Vector3.new(0, -workspace.Gravity * 0.6, 0)
	e.Rate = rate
	e.Parent = parent
	if duration then
		task.delay(duration, function() e.Enabled = false end)
		Debris:AddItem(e, duration + 1)
	end
	return e
end

-- Short-lived blood mist puff at an impact.
local function mist(parent: Instance)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPLASH
	e.Color = ColorSequence.new(BLOOD)
	e.LightInfluence, e.LightEmission = 1, 0
	e.Size = seq(0.5, 2.4)
	e.Transparency = seq(0.45, 1)
	e.Lifetime = NumberRange.new(0.25, 0.45)
	e.Speed = NumberRange.new(3, 7)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Drag = 8
	e.Rotation = NumberRange.new(-180, 180)
	e.Rate = 0
	e.Parent = parent
	return e
end

local function burst(at: Vector3, dir: Vector3, count: number, speed: number)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.Transparency = true, false, false, false, 1
	a.Size = Vector3.one * 0.2
	a.CFrame = CFrame.lookAt(at, at + dir) * CFrame.Angles(-math.pi / 2, 0, 0) -- Top face points along dir
	a.Parent = workspace
	droplets(a, 0, speed, 0.35):Emit(count)
	mist(a):Emit(math.ceil(count / 6))
	Debris:AddItem(a, 2)
end

local function sound(parent: Instance)
	local s = Instance.new("Sound")
	s.SoundId = SPLAT_SOUNDS[math.random(#SPLAT_SOUNDS)]
	s.RollOffMaxDistance = 120
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end

---------------------------------------------------------------- blood on surfaces
local function fade(p: Instance, target: Instance, prop: string, life: number?)
	life = life or BLOOD_LIFETIME
	task.delay(life - 2, function()
		if p.Parent then TweenService:Create(target, TweenInfo.new(2), {[prop] = 1}):Play() end
	end)
	Debris:AddItem(p, life)
end

local function surfaceCF(at: Vector3, normal: Vector3, yaw: number)
	return CFrame.new(at + normal * 0.02) * CFrame.fromRotationBetweenVectors(Vector3.yAxis, normal) * CFrame.Angles(0, yaw, 0)
end

-- Invisible part carrying a decal on its top face. grow: seconds to spread out to `size` (nil = full size at once).
local function decalAt(cf: CFrame, texture: string, tint: Color3, size: number, grow: number?, life: number?)
	local p = Instance.new("Part")
	p.Name = "BloodDecal" -- TowerRun clears these when a raid ends
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
	p.Size = grow and Vector3.new(0.2, 0.05, 0.2) or Vector3.new(size, 0.05, size)
	p.CFrame = cf
	local d = Instance.new("Decal")
	d.Texture, d.Face, d.Color3 = texture, Enum.NormalId.Top, tint
	d.Parent = p
	p.Parent = workspace
	if grow then
		TweenService:Create(p, TweenInfo.new(grow, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(size, 0.05, size)}):Play()
	end
	fade(p, d, "Transparency", life)
end

local function decal(at: Vector3, normal: Vector3, texture: string, tint: Color3, size: number, grow: number?, life: number?)
	decalAt(surfaceCF(at, normal, math.random() * 6.28), texture, tint, size, grow, life)
end

-- Streak pointing along `along` (projected onto the surface).
local function streak(at: Vector3, normal: Vector3, along: Vector3, size: number, life: number?)
	if #STREAKS == 0 then return end
	local flat = along - normal * along:Dot(normal)
	local base = surfaceCF(at, normal, 0)
	local yaw = flat.Magnitude > 0.01 and math.atan2(-base:VectorToObjectSpace(flat).X, -base:VectorToObjectSpace(flat).Z) or math.random() * 6.28
	decalAt(base * CFrame.Angles(0, yaw + math.pi / 2, 0), STREAKS[math.random(#STREAKS)], STREAK_TINT, size, nil, life)
end

local function castFrom(body: Model, from: Vector3, dir: Vector3, dist: number)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {body}
	return workspace:Raycast(from, dir * dist, params)
end

-- Layered stain: two splashes + wet streaks running away along `dir`, all in BLOOD.
local function stain(at: Vector3, normal: Vector3, dir: Vector3, size: number, grow: number)
	decal(at, normal, SPLASH, BLOOD, size, grow)
	decal(at + (dir - normal * dir:Dot(normal)).Unit * size * 0.15, normal, SPLASH, BLOOD, size * 0.8, grow * 0.7)
	for _ = 1, 2 do
		streak(at + (dir - normal * dir:Dot(normal)).Unit * size * (0.4 + math.random() * 0.3), normal, dir, size * 0.8)
	end
end

---------------------------------------------------------------- gore pieces
-- Weld a kit model's visible pieces onto `anchor`, placed so the kit's Middle sits at `anchorCF`.
-- push: move the insides (everything but the Blood shell) this far out the front, so the body part
-- we keep for its clothing doesn't swallow them.
local function attachKit(kitName: string, anchor: BasePart, anchorCF: CFrame?, push: number?)
	local src = KIT and KIT:FindFirstChild(kitName)
	if not src then return end
	local mid = src.Middle
	anchorCF = anchorCF or anchor.CFrame
	for _, p in src:GetChildren() do
		if p:IsA("BasePart") and p ~= mid then
			local c = p:Clone()
			c.CFrame = anchorCF * mid.CFrame:ToObjectSpace(p.CFrame)
			if push and c.Name ~= "Blood" then c.CFrame += anchorCF.LookVector * push end
			local sa = c.Name == "Blood" and c:FindFirstChildWhichIsA("SurfaceAppearance")
			if sa then sa.Color = anchor.Color end -- the kit's grey "skin" areas take the body part's colour
			if c.Name == "Limb" then c.Color = anchor.Color end -- head kits: a head with the hole cut in, replaces the head
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = anchor, c
			w.Parent = c
			c.Parent = anchor
		end
	end
end

local function pick(prefix: string, n: number) return prefix .. math.random(n) end

-- Cut every joint (Motor6D, Weld, ragdoll BallSocket) holding this part to the body. Returns where it was attached.
local function sever(body: Model, part: BasePart): Vector3
	local joint = part.Position
	for _, j in body:GetDescendants() do
		if j:IsA("JointInstance") and (j.Part0 == part or j.Part1 == part) then
			local other = j.Part0 == part and j.Part1 or j.Part0
			if other and other.Parent ~= part then j:Destroy() end -- keep the part's own invisible hitbox weld
		elseif j:IsA("Constraint") and j.Attachment0 and j.Attachment1
			and (j.Attachment0.Parent == part or j.Attachment1.Parent == part) then
			joint = (j.Attachment0.Parent == part and j.Attachment1 or j.Attachment0).WorldPosition
			j:Destroy()
		end
	end
	return joint
end

local function tearOff(body: Model, root: BasePart, part: BasePart, dir: Vector3, force: number)
	local torso = body:FindFirstChild("Torso")
	local kitName = KIT_NAME[part.Name]
	if kitName and torso then
		attachKit(kitName .. "ChopOff2", torso) -- stump on the body
		attachKit(kitName .. "ChopOff1", part) -- torn end on the limb
	elseif part.Name == "Head" and torso then
		attachKit("HeadChopOff2", torso)
		attachKit("HeadChopOff2", part, part.CFrame * CFrame.new(0, -1.5, 0)) -- same neck flesh, lined up with the bottom of the head
	end
	local joint = sever(body, part)
	part.CanCollide = true
	part.AssemblyLinearVelocity = (dir + Vector3.new(0, 0.6, 0)).Unit * force * (0.8 + math.random() * 0.4)
	part.AssemblyAngularVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))
	burst(joint, dir, 30, 18)
	droplets(part, 18, 3, 0.25, 3) -- torn end drips while it flies
	local stump = Instance.new("Attachment")
	stump.WorldPosition = joint
	stump.Parent = root
	droplets(stump, 35, 7, 0.3, 4)
end

-- Bone sticks out of a shredded limb that stays on the body.
-- Keep a limb's upper part (with its clothing) and cut it off at `cutY` in its own space, so the
-- wound below shows the kit's flesh and bone. Attachments and joints keep their world positions.
local CUT_BELOW = -0.2
local function shorten(part: BasePart, cutY: number)
	local top = part.Size.Y / 2
	local shift = CFrame.new(0, (top + cutY) / 2, 0) -- old space -> new centre
	for _, a in part:GetChildren() do
		if a:IsA("Attachment") then a.CFrame = shift:Inverse() * a.CFrame end
	end
	for _, j in part.Parent:GetDescendants() do
		if j:IsA("JointInstance") then
			if j.Part0 == part then j.C0 = shift:Inverse() * j.C0 end
			if j.Part1 == part then j.C1 = shift:Inverse() * j.C1 end
		end
	end
	local welds = {}
	for _, w in part.Parent:GetDescendants() do
		if w:IsA("WeldConstraint") and w.Enabled and (w.Part0 == part or w.Part1 == part) then
			w.Enabled = false -- so moving the limb doesn't drag what's welded to it
			table.insert(welds, w)
		end
	end
	part.Size = Vector3.new(part.Size.X, top - cutY, part.Size.Z)
	part.CFrame = part.CFrame * shift
	for _, w in welds do w.Enabled = true end
end

-- rifle hit on an arm or leg: blood and a bleeding hole, the limb stays whole
local function limbWound(part: BasePart, at: Vector3, dir: Vector3)
	burst(at, dir, 30, 16)
	local wound = Instance.new("Attachment")
	wound.Parent = part
	wound.WorldPosition = at
	droplets(wound, 20, 3, 0.25, 4)
end

local function burstLimb(part: BasePart, dir: Vector3)
	local kitName = KIT_NAME[part.Name]
	if kitName then
		local cf = part.CFrame
		shorten(part, CUT_BELOW)
		attachKit(kitName .. "BurstDefault1", part, cf)
	end
	burst(part.Position, dir, 30, 16)
	local wound = Instance.new("Attachment")
	wound.Position = Vector3.new(0, -part.Size.Y * 0.3, 0)
	wound.Parent = part
	droplets(wound, 20, 3, 0.25, 4)
end

-- Turn `cf` so its front (-Z) faces the side of `part` that `at` is on.
local function faceToward(part: BasePart, at: Vector3): CFrame
	local l = part.CFrame:PointToObjectSpace(at)
	return part.CFrame * CFrame.Angles(0, math.atan2(-l.X, -l.Z), 0)
end

local function headWound(head: BasePart, at: Vector3, dir: Vector3)
	local h = head.CFrame:PointToObjectSpace(at).Y
	local variant = h > 0.2 and "HeadBurstUpper1" or h < -0.2 and "HeadBurstLower2" or pick("HeadBurstMiddle", 2) -- Middle3 has nothing inside its hole, so you'd see through the head
	attachKit(variant, head, faceToward(head, at))
	head.Transparency = 1 -- the kit's Limb is the head with the hole in it, so the skull inside shows; the face decal stays
	burst(at, -dir, 12, 6) -- back-spatter
	burst(head.Position + dir * head.Size.Z / 2, dir, 40, 22) -- exit
	local w = Instance.new("Attachment")
	w.WorldPosition = at
	w.Parent = head
	droplets(w, 14, 2, 0.2, 5)
end

local function popHead(body: Model, root: BasePart, head: BasePart, dir: Vector3)
	burst(head.Position, dir, 60, 24)
	burst(head.Position, Vector3.yAxis, 25, 12)
	for _, acc in body:GetChildren() do -- hats/hair go with it
		local handle = acc:IsA("Accoutrement") and acc:FindFirstChild("Handle")
		local att = handle and handle:FindFirstChildWhichIsA("Attachment")
		if att and head:FindFirstChild(att.Name) then acc:Destroy() end
	end
	for _, d in head:GetDescendants() do
		if d:IsA("Decal") or d:IsA("BasePart") then d.Transparency = 1 end
	end
	head.Transparency, head.CanCollide, head.CanQuery = 1, false, false -- keep the part: the death camera follows it
	local torso = body:FindFirstChild("Torso")
	if torso then attachKit("HeadChopOff2", torso) end
	local neck = Instance.new("Attachment")
	neck.Position = Vector3.new(0, root.Size.Y / 2, 0)
	neck.Parent = root
	droplets(neck, 45, 9, 0.3, 4).EmissionDirection = Enum.NormalId.Top
end

-- dir given: the bullet went through, so the opposite side gets an exit wound too.
local function torsoWound(torso: BasePart, at: Vector3, dir: Vector3?)
	if torso.Name ~= "Torso" then return end -- kit is R6
	-- the kit is torso-shaped, so only flip front/back: a sideways turn would stick it out of the body
	local back = torso.CFrame:PointToObjectSpace(at).Z > 0
	local flip = torso.CFrame * CFrame.Angles(0, math.pi, 0)
	local function side(cf: CFrame, p: Vector3)
		local l = cf:PointToObjectSpace(p)
		attachKit("TorsoBurstUpper" .. (l.X < 0 and "L" or "R") .. "1", torso, cf, 0.12) -- the kit's lower variants show grey slabs over clothing
	end
	side(back and flip or torso.CFrame, at)
	if dir then side(back and torso.CFrame or flip, at + dir * 1.2) end
	local w = Instance.new("Attachment")
	w.WorldPosition = at
	w.Parent = torso
	droplets(w, 20, 3, 0.25, 4)
end

local function randomLimbs(body: Model, n: number)
	local pool, picked = {}, {}
	for _, name in ROOT_LIMBS do
		if body:FindFirstChild(name) then table.insert(pool, body[name]) end
	end
	for _ = 1, math.min(n, #pool) do table.insert(picked, table.remove(pool, math.random(#pool))) end
	return picked
end

---------------------------------------------------------------- entry point
function Gore.Apply(body: Model, hitName: string?, dir: Vector3?, damage: number?, shotgun: boolean?, hitPos: Vector3?)
	local root = body:FindFirstChild("Torso") or body:FindFirstChild("UpperTorso") or body:FindFirstChild("HumanoidRootPart")
	if not root then return end
	dir = (dir and dir.Magnitude > 0) and dir.Unit or -root.CFrame.LookVector
	damage = damage or 0
	local hit = hitName and body:FindFirstChild(hitName)
	local at = hitPos or (hit and hit.Position - dir * 0.5) or root.Position
	sound(root)

	if hitName == "Explosion" then
		local parts = randomLimbs(body, math.random(2, 4))
		if math.random() < 0.4 and body:FindFirstChild("Head") then table.insert(parts, body.Head) end
		for _, p in parts do tearOff(body, root, p, dir + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5), 45) end
		torsoWound(root, root.Position - dir)
		burst(root.Position, Vector3.yAxis, 70, 25)
	elseif hit and hit.Name == "Head" then
		if not shotgun then
			headWound(hit, at, dir)
		elseif math.random() < 0.5 then
			popHead(body, root, hit, dir)
		else
			tearOff(body, root, hit, dir, 30)
		end
	elseif hit and LIMBS[hit.Name] then
		if shotgun then tearOff(body, root, hit, dir, 35) else limbWound(hit, at, dir) end -- rifles never dismember
	else
		torsoWound(hit or root, at, dir)
		burst(at, dir, 50, 20) -- exit wound
		burst(at, -dir, 12, 6)
		if shotgun then -- rifles never dismember, however hard they hit
			for _, p in randomLimbs(body, math.random(1, 2)) do
				if math.random() < 0.5 then tearOff(body, root, p, dir, 35) else burstLimb(p, dir) end
			end
		end
	end

	-- Wait for the ragdoll to settle, then spatter behind the victim and pool under the body
	task.delay(1.5, function()
		if not root.Parent then return end
		local behind = castFrom(body, at, dir, 14)
		if behind then stain(behind.Position, behind.Normal, dir, 3 + math.random() * 1.5, 0.12) end
		local floor = castFrom(body, root.Position, -Vector3.yAxis, 8)
		if floor then stain(floor.Position, floor.Normal, dir, 4.5 + math.random() * 2, 5) end
	end)
end

-- Downed (ServerScriptService.Medical): the wound keeps bleeding and pools under the body. Returns the
-- emitter's attachment so the caller can remove it on revive.
function Gore.Bleed(character: Model, hitName: string?, hitPos: Vector3?): Attachment?
	local root = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	local part = hitName and character:FindFirstChild(hitName)
	if not (part and part:IsA("BasePart")) then part = root end
	if not part then return nil end
	local a = Instance.new("Attachment")
	if hitPos and (hitPos - part.Position).Magnitude < part.Size.Magnitude then a.WorldPosition = hitPos end
	a.Parent = part
	droplets(a, 10, 2.5, 0.22)
	burst(a.WorldPosition, -part.CFrame.LookVector, 20, 8)
	task.delay(1.5, function()
		if not (a.Parent and root) then return end
		local floor = castFrom(character, root.Position, -Vector3.yAxis, 8)
		if floor then stain(floor.Position, floor.Normal, root.CFrame.LookVector, 3 + math.random(), 8) end
	end)
	return a
end

-- Blood trail (Medical): one drop on the floor under a bleeding body. along = how far it moved since the
-- last call, given when it's being dragged: a brushed smear covering that whole stretch instead of a drop.
local TRAIL_LIFETIME = 40 -- longer than other blood, so the trail can be followed
-- Brushed smear: one chain of flat Beams under the body (beams join seamlessly and follow turns; parts
-- showed every seam, and side-by-side strands crossed on bends). Two layers share the chain: a streaked
-- core over a fainter, wider halo, each with its own jittered width, so the edges are soft and uneven
-- instead of a hard-edged ribbon (a third, widest halo read as an outline). Wide and heavy where the drag starts; narrower and fainter further on.
local SMEAR_TEXTURE = "rbxassetid://119398345796399" -- BloodSmear.png (Spearhead/MedicalAnimations/make_smear.py), group 35065811
local SMEAR_RUNOUT = 60 -- studs dragged until the smear is down to its thin tail
local SMEAR_TAIL = 0.4 -- how heavy the tail stays while the body still bleeds
-- { width scale, how much fainter (0 = as opaque as the core, 1 = invisible), textured, draw order, colour }
local SMEAR_LAYERS = {
	{ 1.35, 0.65, false, 0, Color3.fromRGB(80, 5, 5) },
	{ 1, 0, true, 0.1, Color3.fromRGB(115, 10, 10) }, -- the texture's greys darken it further
}
type Strand = { att: Attachment?, dir: Vector3?, w: { number }, t: { number } }
local smears: { [Model]: { dist: number, dir: Vector3?, pos: Vector3?, strand: Strand } } = setmetatable({}, { __mode = "k" }) :: any
local function fadeBeam(b: Beam, t0: number, t1: number)
	task.delay(TRAIL_LIFETIME - 2, function()
		for k = 1, 10 do
			if not b.Parent then return end
			b.Transparency = NumberSequence.new(t0 + (1 - t0) * k / 10, t1 + (1 - t1) * k / 10)
			task.wait(0.2)
		end
	end)
	Debris:AddItem(b, TRAIL_LIFETIME)
end
-- Lay attachment `a` flat at `p`, its width axis across `dir` (a beam's width runs along its attachments' up axis)
local function orient(a: Attachment, p: Vector3, dir: Vector3, normal: Vector3)
	a.WorldCFrame = CFrame.lookAt(p, p + dir, normal) * CFrame.Angles(0, 0, math.pi / 2)
end
-- Extend the smear to `pt`. width/transparency are this point's; each beam blends from the last point's.
local function grow(s: Strand, pt: Vector3, normal: Vector3, width: number, transparency: number)
	local prev = s.att and s.att.Parent and s.att
	local dir = if prev then pt - prev.WorldPosition else Vector3.zero
	dir -= normal * dir:Dot(normal)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else (s.dir or Vector3.zAxis)
	local a = Instance.new("Attachment")
	a.Parent = workspace.Terrain
	orient(a, pt, dir, normal)
	Debris:AddItem(a, TRAIL_LIFETIME + 0.5) -- the next segment starts here and dies just after
	local w, t = {}, {}
	for i, l in SMEAR_LAYERS do
		w[i] = width * l[1] * (0.85 + math.random() * 0.3)
		t[i] = math.clamp(transparency + l[2] * (1 - transparency), 0, 1)
	end
	if prev then
		-- miter the shared joint: it bisects the turn, so neither segment folds over on a bend
		local bisect = s.dir and s.dir + dir
		if bisect and bisect.Magnitude > 0.2 then orient(prev, prev.WorldPosition, bisect.Unit, normal) end
		for i, l in SMEAR_LAYERS do
			local b = Instance.new("Beam")
			b.Attachment0, b.Attachment1 = prev, a
			b.FaceCamera, b.Segments, b.LightInfluence, b.LightEmission = false, 1, 1, 0
			b.Color, b.ZOffset = ColorSequence.new(l[5]), l[4] -- ZOffset: the layers lie in one plane, so order them
			if l[3] then b.Texture, b.TextureMode, b.TextureSpeed = SMEAR_TEXTURE, Enum.TextureMode.Stretch, 0 end
			b.Width0, b.Width1 = s.w[i] or 0, w[i]
			b.Transparency = NumberSequence.new(s.t[i] or 1, t[i])
			b.Parent = a
			fadeBeam(b, s.t[i] or 1, t[i])
		end
	end
	s.att, s.dir, s.w, s.t = a, dir, w, t
end
local function smear(character: Model, at: Vector3, normal: Vector3, along: Vector3)
	local flat = along - normal * along:Dot(normal)
	if flat.Magnitude < 0.05 then return end
	local st = smears[character]
	if not st then
		st = { dist = 0, strand = { w = {}, t = {} } }
		smears[character] = st
		-- where the drag starts: the body lay here
		decal(at, normal, SPLASH, BLOOD, 4.5 + math.random() * 1.5, 0.4, TRAIL_LIFETIME)
		decal(at - flat.Unit * 0.8, normal, SPLASH, BLOOD, 3 + math.random(), 0.3, TRAIL_LIFETIME)
	end
	local heavy = math.max(SMEAR_TAIL, 1 - st.dist / SMEAR_RUNOUT)
	st.dist += math.min(flat.Magnitude, 2) -- the yank when the body is first grabbed doesn't count
	-- smoothed path and heading: the body swings side to side, and a wide ribbon following every swing folds over itself
	st.dir = if st.dir then (st.dir * 0.6 + flat.Unit * 0.4).Unit else flat.Unit
	st.pos = if st.pos then st.pos:Lerp(at, 0.35) else at
	grow(st.strand, st.pos + normal * 0.04, normal, 1.9 * (0.4 + 0.6 * heavy), math.clamp(0.05 + (1 - heavy) * 0.55, 0, 0.9))
end
function Gore.Drip(character: Model, along: Vector3?)
	local root = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- dragged: the smear's next point is under the body
	local from = if along then root.Position else root.Position + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.8
	local floor = castFrom(character, from, -Vector3.yAxis, 8)
	if not floor or floor.Normal.Y < 0.6
		or floor.Instance:FindFirstAncestorWhichIsA("Model") and floor.Instance:FindFirstAncestorWhichIsA("Model"):FindFirstChildOfClass("Humanoid") then
		return -- nothing below, a wall edge, or the carrier's shoulder
	end
	if along then
		smear(character, floor.Position, floor.Normal, along)
	else
		decal(floor.Position, floor.Normal, SPLASH, BLOOD, 0.5 + math.random() * 0.5, nil, TRAIL_LIFETIME)
	end
end

-- Damage code calls this on the killing hit; the death handler reads it back.
function Gore.Mark(character: Model, hitName: string, dir: Vector3, damage: number, shotgun: boolean?, hitPos: Vector3?)
	character:SetAttribute("GoreHit", hitName)
	character:SetAttribute("GoreDir", dir)
	character:SetAttribute("GoreDamage", damage)
	character:SetAttribute("GoreShotgun", shotgun == true)
	character:SetAttribute("GorePos", hitPos)
end

function Gore.ApplyMarked(character: Model, body: Model?)
	local hitName = character:GetAttribute("GoreHit")
	if not hitName then return end -- not a weapon kill
	-- Died handlers run deferred, after GoreHit is cleared below: KillHit keeps the killing hit for kill credit (TowerRun headshots, kill feed)
	character:SetAttribute("KillHit", hitName)
	character:SetAttribute("GoreHit", nil)
	Gore.Apply(body or character, hitName, character:GetAttribute("GoreDir"), character:GetAttribute("GoreDamage"),
		character:GetAttribute("GoreShotgun"), character:GetAttribute("GorePos"))
end

return Gore

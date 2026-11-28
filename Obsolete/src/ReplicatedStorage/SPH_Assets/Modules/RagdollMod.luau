local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")

-- Every corpse part collides with every other corpse's parts (bodies pile up instead of sinking into each other).
-- Living Bloxians still walk through bodies, as they did when NPC corpses kept the Bloxian group.
local CORPSE_GROUP = "Corpses"
if game:GetService("RunService"):IsServer() then
	if not PhysicsService:IsCollisionGroupRegistered(CORPSE_GROUP) then PhysicsService:RegisterCollisionGroup(CORPSE_GROUP) end
	for _, g in {"Bloxian", "BloxianProne"} do
		if not PhysicsService:IsCollisionGroupRegistered(g) then PhysicsService:RegisterCollisionGroup(g) end
		PhysicsService:CollisionGroupSetCollidable(CORPSE_GROUP, g, false)
	end
end
local BODY_PARTS = {Torso = true, Head = true, ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true, RagdollHitbox = true}
local function corpseGroup(model: Instance)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.CollisionGroup = CORPSE_GROUP
			-- gear and accessories welded to a limb would shove the body's other limbs every frame (spazzing)
			if not BODY_PARTS[p.Name] then p.CanCollide = false end
		end
	end
end

local module = {}

-- R6 joint limits, so the body falls like a person instead of folding like laundry.
-- pivot: joint point in Torso space. axis: centre of the joint's swing cone in Torso space (-Z is the front),
-- tilted forward because limbs bend much further forward than back. cone/twist in degrees.
local R6_JOINTS = {
	Head = {pivot = Vector3.new(0, 1, 0), axis = Vector3.new(0, 1, -0.25), cone = 40, twist = 45},
	["Left Arm"] = {pivot = Vector3.new(-1.5, 0.5, 0), axis = Vector3.new(0, -1, -1), cone = 80, twist = 60},
	["Right Arm"] = {pivot = Vector3.new(1.5, 0.5, 0), axis = Vector3.new(0, -1, -1), cone = 80, twist = 60},
	-- legs fold up to ~100 deg forward (body sinks onto its knees/backside), only ~20 back
	["Left Leg"] = {pivot = Vector3.new(-0.5, -1, 0), axis = Vector3.new(0, -1, -0.84), cone = 60, twist = 25, legs = true},
	["Right Leg"] = {pivot = Vector3.new(0.5, -1, 0), axis = Vector3.new(0, -1, -0.84), cone = 60, twist = 25, legs = true},
}
-- Joint friction: stiff for a moment (muscle tone as the body drops, knees buckle instead of flinging),
-- then relaxes to a little resistance so limbs settle without flopping or jittering.
-- (a limb's weight pulls with ~275, so STIFF slows a fall without holding the limb up)
local STIFF_FRICTION, LOOSE_FRICTION, RELAX_TIME = 150, 25, 1
-- No bounce, high grip: bodies land and stay instead of skidding.
local BODY_PHYSICS = PhysicalProperties.new(0.7, 1, 0, 1, 100)

-- Joint frames whose X axis (the cone's centre) is `axis`. Part0's comes from the Torso-space spec; Part1's
-- position is wherever that pivot sits on the limb right now (so nothing snaps at death), and its rotation
-- is the motor's rest pose (so the cone is centred on a standing body, not on the death animation).
local function limitedSocket(motor: Motor6D, spec)
	local p0, p1 = motor.Part0, motor.Part1
	local ax = spec.axis.Unit
	local cf0 = CFrame.fromMatrix(spec.pivot, ax, ax:Cross(Vector3.xAxis).Unit)
	local rest1 = motor.C1 * motor.C0:Inverse() * cf0 -- Part1 space at the rest pose
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Name, a1.Name = "RagdollJoint", "RagdollJoint"
	a0.CFrame = cf0
	a1.CFrame = CFrame.new(p1.CFrame:PointToObjectSpace(p0.CFrame:PointToWorldSpace(spec.pivot))) * rest1.Rotation
	a0.Parent, a1.Parent = p0, p1
	local b = Instance.new("BallSocketConstraint")
	b.Attachment0, b.Attachment1 = a0, a1
	b.LimitsEnabled, b.UpperAngle = true, spec.cone
	b.TwistLimitsEnabled, b.TwistLowerAngle, b.TwistUpperAngle = true, -spec.twist, spec.twist
	b.Restitution = 0
	b.Parent = p0
	if spec.legs then
		-- legs give way at once: stiff legs are what keep a dead body standing
		b.MaxFrictionTorque = LOOSE_FRICTION
		return
	end
	b.MaxFrictionTorque = STIFF_FRICTION
	TweenService:Create(b, TweenInfo.new(RELAX_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {MaxFrictionTorque = LOOSE_FRICTION}):Play()
end

-- Dead-weight collapse: the body drops where it stands instead of tipping over like a plank.
-- Legs swing forward (knees buckle), everything sinks, and the torso leans along the killing shot
-- (GoreDir, set by Gore.Mark) or randomly forward/back, then gravity finishes it.
local function crumple(parts: {BasePart}, torso: BasePart, shotDir: Vector3?)
	local flat = typeof(shotDir) == "Vector3" and Vector3.new(shotDir.X, 0, shotDir.Z) or Vector3.zero
	local lean = flat.Magnitude > 0.1 and flat.Unit or torso.CFrame.LookVector * (math.random() < 0.5 and -1 or 1)
	local tip = Vector3.yAxis:Cross(lean) * 1.2 -- spin that moves the torso's top along `lean`
	local buckle = torso.CFrame.RightVector * 4 -- +X spin swings feet toward -Z (forward)
	for _, part in parts do
		if part.Name == "HumanoidRootPart" then continue end
		part.AssemblyLinearVelocity = Vector3.new(0, -6, 0) + lean * 1.5
		part.AssemblyAngularVelocity = (part.Name == "Left Leg" or part.Name == "Right Leg") and buckle or tip
	end
end

-- Limb and torso overlap at the joint; letting them collide there makes the body jitter.
local function noCollide(a: BasePart?, b: BasePart?)
	if not (a and b) then return end
	local nc = Instance.new("NoCollisionConstraint")
	nc.Part0, nc.Part1 = a, b
	nc.Parent = a
end

-- A body's own parts (and their RagdollHitboxes) never collide with each other: limbs pressed together
-- jitter the whole body. Other bodies still collide through the Corpses group.
local function noSelfCollide(body: Model)
	local parts = {}
	for _, name in {"Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg"} do
		local p = body:FindFirstChild(name)
		if p then
			table.insert(parts, p)
			local hb = p:FindFirstChild("RagdollHitbox")
			if hb then table.insert(parts, hb) end
		end
	end
	for i = 1, #parts do
		for j = i + 1, #parts do
			-- a hitbox is welded to its own limb, so that pair can't collide anyway
			if parts[j].Parent ~= parts[i] then noCollide(parts[i], parts[j]) end
		end
	end
end

-- Ragdolls an R6 body in place (NPCs: Bloxian HumanoidHandler) with the same limits, friction and grip as player corpses.
-- Call it on death, before the Torso's Motor6Ds are destroyed; it switches them off itself.
module.LimitR6 = function(character: Model)
	local torso = character:FindFirstChild("Torso")
	if not torso then return end
	for _, v in torso:GetChildren() do
		if v:IsA("Motor6D") and v.Part1 and R6_JOINTS[v.Part1.Name] then
			limitedSocket(v, R6_JOINTS[v.Part1.Name])
			v.Enabled = false
		end
	end
	torso.CustomPhysicalProperties = BODY_PHYSICS
	for name in R6_JOINTS do
		local limb = character:FindFirstChild(name)
		if limb then limb.CustomPhysicalProperties = BODY_PHYSICS end
	end
	noSelfCollide(character)
	corpseGroup(character)
	-- a solid HRP (still jointed to the Torso) props the body up, and it tips over stiff like a board
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CanCollide = false end
	local parts = {}
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then table.insert(parts, part) end
	end
	crumple(parts, torso, character:GetAttribute("GoreDir"))
end

module.MakeCorpse = function(character: Model)
	local humanoid:Humanoid = character.Humanoid
	local humanoidRootPart = character.HumanoidRootPart
	local newGroup = Instance.new("Model")
	newGroup.Parent = workspace
	newGroup.Name = character.Name.."_Dead"

	-- Create ragdoll
	for _, v in pairs(character:GetDescendants()) do
		if v:IsA("Motor6D") then
			if not v.Part0 or not v.Part1 then
				continue
			elseif v.Part0.Name == "HumanoidRootPart" or v.Part1.Name == "HumanoidRootPart" then
				v.Enabled = false
			elseif humanoid.RigType == Enum.HumanoidRigType.R6 and R6_JOINTS[v.Part1.Name] and v.Part0.Name == "Torso" then
				limitedSocket(v, R6_JOINTS[v.Part1.Name])
				v:Destroy()
			elseif v.Part0.Parent == character or v.Part1.Parent == character then
				-- shortcut: R15 keeps the original unlimited sockets; give it its own table if R15 is ever used
				local a0,a1 = Instance.new("Attachment"),Instance.new("Attachment")
				a0.CFrame = v.C0
				a1.CFrame = v.C1
				a0.Parent = v.Part0
				a1.Parent = v.Part1

				if humanoid.RigType == Enum.HumanoidRigType.R6 then
					if v.Part1.Name == "Left Leg" then
						a1.Position -= Vector3.new(-0.5,0,0)
						a0.Position -= Vector3.new(-0.5,0,0)
					elseif v.Part1.Name == "Right Leg" then
						a1.Position -= Vector3.new(0.5,0,0)
						a0.Position -= Vector3.new(0.5,0,0)
					end
				end

				local b = Instance.new("BallSocketConstraint")
				b.Attachment0 = a0
				b.Attachment1 = a1
				b.Parent = v.Part0
				--b.LimitsEnabled = true

				v:Destroy()
			end
		end
	end


	local shirt = character:FindFirstChildWhichIsA("Shirt")
	if shirt then shirt.Parent = newGroup end

	local pants = character:FindFirstChildWhichIsA("Pants")
	if pants then pants.Parent = newGroup end

	for _,v:BasePart in pairs(character:GetChildren()) do
		if v:IsA("Part") then
			v.Parent = newGroup
			v:SetNetworkOwner()
			if v.Name ~= "HumanoidRootPart" then
				v.CustomPhysicalProperties = BODY_PHYSICS
				local hitBox = Instance.new("Part")
				hitBox.Name = "RagdollHitbox"
				hitBox.CustomPhysicalProperties = BODY_PHYSICS
				-- near full size so the body rests on the ground instead of sinking half into it
				hitBox.Size = v.Size * 0.95
				hitBox.Transparency = 1
				hitBox.Massless = true
				local weld = Instance.new("Weld")
				weld.Part0 = v
				weld.Part1 = hitBox
				weld.Parent = hitBox
				hitBox.Parent = v
			end
		end
	end


	humanoid.Parent = newGroup
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local fakeHumanoid = Instance.new("Humanoid")
	fakeHumanoid.MaxHealth = 0
	fakeHumanoid.Parent = character

	for _,v in pairs(character:GetChildren()) do
		if v:IsA("Accoutrement") then
			v.Parent = newGroup
			humanoid:AddAccessory(v:Clone())
			v:Destroy()
		elseif v:IsA("Model") then
			v.Parent = newGroup
		end
	end

	for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if state == Enum.HumanoidStateType.None then
			continue
		else
			humanoid:SetStateEnabled(state,false)
		end
	end
	
	local torso = newGroup:FindFirstChild("Torso")
	if torso and humanoid.RigType == Enum.HumanoidRigType.R6 then
		noSelfCollide(newGroup)
	end

	humanoidRootPart.Anchored = true
	humanoidRootPart.CanCollide = false
	humanoidRootPart.CanQuery = false
	humanoidRootPart.CanTouch = false
	corpseGroup(newGroup)

	if torso and humanoid.RigType == Enum.HumanoidRigType.R6 then
		local parts = {}
		for _, part in newGroup:GetChildren() do
			if part:IsA("BasePart") then table.insert(parts, part) end
		end
		crumple(parts, torso, character:GetAttribute("GoreDir"))
	end

	return newGroup
end


return module
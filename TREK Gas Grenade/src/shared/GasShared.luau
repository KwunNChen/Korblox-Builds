--[[
	GasShared
	Turning the imported art into something that can be held and thrown.

	GasGrenades.rbxm arrives as two Models of four loose MeshParts each, every
	one of them anchored, none of them welded, and neither Model carrying a
	PrimaryPart. Unanchor one as it stands and it becomes four grenades falling
	in four directions.

	Rather than ask anyone to remember a Studio checklist, the rig is assembled
	at runtime, every time, from whatever the Model happens to contain. A
	re-import with different part names or an extra greeble still works. Both
	routines are idempotent, so running them twice is a no-op rather than a
	second set of welds.
]]

local GasShared = {}

local WELD_TAG = "GasRigWeld"

--[[
	The part the rest of the model hangs off.

	Chosen by volume rather than by name, because the names are Blender's Korean
	locale defaults (실린더, 큐브) and nothing should depend on them surviving the
	next export.
]]
local function largestPart(model: Model): BasePart?
	local best, bestVolume = nil, -1

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best, bestVolume = descendant, volume
			end
		end
	end

	return best
end

--[[
	Weld `part` to `anchor`, replacing any earlier weld that points somewhere
	else.

	Checking only for the tag's existence is not enough. Re-rigging a model that
	was assembled against a different anchor would find the old weld, skip, and
	leave the part joined to something that is itself joined to nothing -- which
	looks exactly like the rig working right up until it is unanchored.
]]
local function weldTo(anchor: BasePart, part: BasePart)
	local existing = part:FindFirstChild(WELD_TAG)

	if existing and existing:IsA("WeldConstraint") then
		if existing.Part0 == anchor and existing.Part1 == part then
			return
		end
		existing:Destroy()
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = WELD_TAG
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
end

--[[
	Prepare the model that gets thrown.

	One rigid body: a single collidable root with everything else welded to it
	and massless, so the solver treats it as one object with the root's mass
	instead of four bodies arguing with each other.

	CanQuery is off across the board. TREK raycasts constantly, and a grenade
	that answered those queries would block the gas cloud's own line-of-sight
	check from inside the cloud it is producing.
]]
function GasShared.prepareRig(model: Model): BasePart?
	local root = model.PrimaryPart or largestPart(model)
	if not root then
		return nil
	end

	model.PrimaryPart = root

	for _, descendant in ipairs(model:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		descendant.Anchored = false
		descendant.CanQuery = false
		descendant.CanTouch = false

		if descendant == root then
			descendant.CanCollide = true
			descendant.Massless = false
			continue
		end

		descendant.CanCollide = false
		descendant.Massless = true
		weldTo(root, descendant)
	end

	return root
end

--[[
	Prepare the model the player holds: one welded, massless, non-colliding body
	rooted on its largest part.

	Returns that root, which is what attachToHand joins to the hand. Nothing here
	touches the character -- the two steps are separate so a tool can be rigged
	before it is ever equipped.
]]
function GasShared.prepareHeldRig(tool: Tool, modelName: string): BasePart?
	local model = tool:FindFirstChild(modelName)
	if not model or not model:IsA("Model") then
		return nil
	end

	local root = model.PrimaryPart or largestPart(model)
	if not root then
		return nil
	end

	model.PrimaryPart = root

	--[[
		No AnimPart, deliberately, and any left by an older build is removed.

		AnimPart is how TREK hangs a tool off the TORSO: checkForGun sees one and
		calls updateMotor, which points the character's toolAnim Motor6D at it.
		That is right for a rifle, whose animations keyframe the AnimPart track
		to carry it into the hands. The grenade has no idle animation, so the
		same arrangement leaves it parked at a fixed spot beside the chest --
		attached, moving with the body, but never following the arm. It reads as
		floating in mid air.

		Removing it makes checkForGun skip updateMotor entirely, which leaves the
		grenade free to be joined to the hand instead. It also avoids two joints
		fighting over the same part, which is what keeping AnimPart and adding a
		grip would produce.
	]]
	local stale = tool:FindFirstChild("AnimPart") or model:FindFirstChild("AnimPart", true)
	if stale then
		stale:Destroy()
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		descendant.Anchored = false
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false

		if descendant == root then
			descendant.Massless = true
			continue
		end

		descendant.Massless = true
		weldTo(root, descendant)
	end

	return root
end

local GRIP_NAME = "GasGrenadeGrip"

--[[
	The part the grenade is gripped by.

	R6 puts the whole limb in one part and the hand is its lower end; R15 has a
	dedicated RightHand. Both are joined to by the same Motor6D, with different
	offsets, which is why GripOffset is configured per rig type.
]]
local function rightHandOf(character: Model): BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local name = if humanoid.RigType == Enum.HumanoidRigType.R6 then "Right Arm" else "RightHand"
	local part = character:FindFirstChild(name)

	return (part and part:IsA("BasePart")) and part or nil
end

--[[
	Join the grenade to the player's right hand.

	A Motor6D from the hand rather than a WeldConstraint, and from the hand
	rather than the torso. The hand is what actually needs following: it swings
	on every walk cycle and is thrown by the throw animation, and a grenade
	joined to the torso simply does not do either -- which is the whole
	complaint. Motor6D specifically because a joint driven by C0 can be offset
	and re-offset without rebuilding it, and because it is the same class Roblox's
	own RightGrip uses for exactly this job.

	Idempotent: it reuses the joint if one is already there, so re-equipping does
	not stack Motor6Ds on the arm.

	Waits for the hand, because a tool can be equipped before the character has
	finished assembling -- and a single failed check would leave the grenade
	unanchored with nothing holding it, with no error anywhere.
]]
function GasShared.attachToHand(character: Model, root: BasePart, gripOffset: CFrame?, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 5)

	repeat
		local hand = rightHandOf(character)

		if hand then
			local motor = hand:FindFirstChild(GRIP_NAME)

			if not motor or not motor:IsA("Motor6D") then
				if motor then
					motor:Destroy()
				end
				local created = Instance.new("Motor6D")
				created.Name = GRIP_NAME
				created.Parent = hand
				motor = created
			end

			local joint = motor :: Motor6D
			joint.Part0 = hand
			joint.Part1 = root
			joint.C0 = gripOffset or CFrame.new()
			joint.C1 = CFrame.new()

			return true
		end

		task.wait()
	until os.clock() > deadline or not character.Parent

	return false
end

--[[
	Remove the grip joint.

	Worth doing on unequip rather than leaving it pointing at a tool sitting in
	the backpack: a stale Motor6D on the arm is inert but confusing, and it makes
	the next attach look like it succeeded when it only reused a joint aimed at
	the wrong grenade.
]]
function GasShared.detachFromHand(character: Model)
	local hand = rightHandOf(character)
	local motor = hand and hand:FindFirstChild(GRIP_NAME)

	if motor then
		motor:Destroy()
	end
end

--[[
	Which hold offset applies to this character.

	R6 and R15 put the hand in quite different places relative to the torso part
	the joint hangs off, so the two are configured separately.
]]
--[[
	Build the joint transform from the six named numbers.

	Translation first, then rotation, so the grenade spins about its own position
	in the fist. Reversed, it would swing around the wrist on an arm's length of
	radius and the X/Y/Z values would stop meaning what they say.
]]
local function toCFrame(offset): CFrame
	return CFrame.new(offset.X or 0, offset.Y or 0, offset.Z or 0)
		* CFrame.Angles(
			math.rad(offset.Pitch or 0),
			math.rad(offset.Yaw or 0),
			math.rad(offset.Roll or 0)
		)
end

function GasShared.gripOffsetFor(character: Model, config): CFrame
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6

	return toCFrame((isR6 and config.GripOffset.R6) or config.GripOffset.R15)
end

--[[
	Block until TREK has finished installing itself.

	The core Installer relocates half the DataModel on boot and only then sets
	ReplicatedStorage.TREK_INSTALLED. Anything that touches shared.S or
	ServerStorage.TREKDamageModule before that flag flips is reading a tree that
	is still being assembled. This is the same gate BayonetService uses.
]]
function GasShared.waitForTREK()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	repeat
		task.wait()
	until ReplicatedStorage:WaitForChild("TREK_INSTALLED").Value
end

--[[
	The folder TREK parks transient world objects in.

	Worth using for anything the grenade spawns: TREKExplosionModule builds its
	OverlapParams to exclude IgnoreList, so effects parented there are never
	caught by a later explosion's damage sweep.

	Bounded rather than an open WaitForChild. This is called from inside the
	throw handler, and an infinite yield there would not fail loudly -- it would
	hang that one throw forever while the rest of the game carried on.
]]
function GasShared.ignoreList(): Instance
	local folder = workspace:FindFirstChild("IgnoreList") or workspace:WaitForChild("IgnoreList", 5)
	return folder or workspace
end

return table.freeze(GasShared)

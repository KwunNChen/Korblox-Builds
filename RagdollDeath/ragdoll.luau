-- R6 Ragdoll Script, plug into ServerScriptService

local Players = game:GetService("Players")

local RAGDOLL_JOINTS = { "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

local FALL_PUSH_SPEED = 10
local FALL_TOPPLE_SPEED = 2.5

-- Takes the Torso directly rather than re-finding it per joint. ragdoll()
-- looks it up ONCE and hands it to every call instead of doing the same
-- FindFirstChild five times over for the same five joints.
local function findJoint(torso: BasePart, name: string): Motor6D?
	local joint = torso:FindFirstChild(name)
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

local function ragdoll(character: Model)
	local torso = character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		-- R15, or a malformed rig. Nothing below applies without a Torso to
		-- hang the joints on, so stop here instead of failing the same
		-- lookup five more times for nothing.
		return
	end

	for _, name in RAGDOLL_JOINTS do
		local joint = findJoint(torso, name)
		if joint and joint.Part0 and joint.Part1 then
			local a0 = Instance.new("Attachment")
			a0.CFrame = joint.C0
			a0.Parent = joint.Part0

			local a1 = Instance.new("Attachment")
			a1.CFrame = joint.C1
			a1.Parent = joint.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = 75
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Parent = joint.Part0

			joint:Destroy()
		end
	end
end

local function applyFallMomentum(character: Model, humanoid: Humanoid)
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local rootPart = root :: BasePart

	local forward = humanoid.MoveDirection
	if forward.Magnitude < 0.1 then
		forward = rootPart.CFrame.LookVector
	end

	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, -1)
	end
	forward = forward.Unit

	rootPart.AssemblyLinearVelocity += forward * FALL_PUSH_SPEED
	rootPart.AssemblyAngularVelocity += Vector3.yAxis:Cross(forward).Unit * FALL_TOPPLE_SPEED
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end

	humanoid.BreakJointsOnDeath = false

	humanoid.Died:Connect(function()
		humanoid.PlatformStand = true
		applyFallMomentum(character, humanoid)
		ragdoll(character)
	end)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
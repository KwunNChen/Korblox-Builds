--[[
	SkiRagdoll
	Goes limp for a moment after a wipeout, then gets back up.

	R6 is held together by Motor6Ds, which are rigid. Ragdolling means giving
	each one a BallSocketConstraint between the same two attachment points and
	switching the motor off -- the limb then hangs off a joint that can rotate
	instead of one that cannot.

	ON THE SERVER, so everyone sees the crash. The client detects it (only the
	client knows the landing angle) and asks; the server decides and does it.

	IT ONLY TOUCHES R6'S OWN JOINTS. The ski and pole welds are Motor6Ds too, and
	ragdolling those would leave your skis in a heap on the floor beside you. The
	list below is explicit for that reason -- do not make it "every Motor6D in
	the character".
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))

local SkiRagdoll = {}

-- RootJoint is deliberately absent: it holds the torso to the HumanoidRootPart,
-- and freeing it detaches the character from the thing the camera follows.
local RAGDOLL_JOINTS = {
	"Neck",
	"Left Shoulder",
	"Right Shoulder",
	"Left Hip",
	"Right Hip",
}

local LIMBS = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

-- Per character: every instance we created, so recovery is one loop rather than
-- hoping a folder Destroy reaches things parented onto the limbs. Plus the
-- limbs' original CanCollide, because R6's Humanoid leans on the leg parts to
-- work out where the floor is -- guessing a value to restore risks leaving
-- someone unable to walk after they get up.
type Session = {
	created: { Instance },
	collision: { [BasePart]: boolean },
}

local active: { [Model]: Session } = {}

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

--[[
	The wipeout sound, played from the SERVER on purpose.

	A Sound created on a client is only ever heard by that client, so a
	crash played there is silent to everyone watching it happen -- which is the
	one sound where that matters most. Created here it replicates, so it lands
	with the ragdoll everyone can already see.

	Accepts a bare number, an rbxassetid:// url or a full web address, and treats
	the "PUT CRASH SOUND ID HERE" placeholder as unset -- same handling as
	SkiSound, so the two agree about what counts as a filled-in slot.
]]
local function playCrashSound(root: BasePart)
	if not Config.EnableSound then
		return
	end

	local digits = type(Config.CrashSoundId) == "string" and Config.CrashSoundId:match("(%d+)")
	if not digits or #digits < 6 then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "SkiCrashSound"
	sound.SoundId = "rbxassetid://" .. digits
	sound.Volume = Config.OneShotVolume
	sound.RollOffMaxDistance = 160
	sound.Parent = root
	sound:Play()

	Debris:AddItem(sound, 6)
end

local function findJoint(character: Model, name: string): Motor6D?
	local torso = character:FindFirstChild("Torso")
	local joint = torso and torso:FindFirstChild(name)
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

function SkiRagdoll.isActive(character: Model): boolean
	return active[character] ~= nil
end

function SkiRagdoll.stop(character: Model)
	local session = active[character]
	if not session then
		return
	end
	active[character] = nil

	for _, instance in session.created do
		instance:Destroy()
	end

	for _, name in RAGDOLL_JOINTS do
		local joint = findJoint(character, name)
		if joint then
			joint.Enabled = true
		end
	end

	for part, original in session.collision do
		if part.Parent then
			part.CanCollide = original
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.PlatformStand = false
	end

	log("%s back up", character.Name)
end

function SkiRagdoll.start(character: Model, duration: number?)
	if active[character] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	local created = {}
	local collision = {}
	active[character] = { created = created, collision = collision }

	local converted = 0

	for _, name in RAGDOLL_JOINTS do
		local joint = findJoint(character, name)
		if joint and joint.Part0 and joint.Part1 then
			converted += 1
			-- The constraint has to sit exactly where the motor did, or the limb
			-- snaps somewhere new the instant it goes limp.
			local a0 = Instance.new("Attachment")
			a0.Name = "SkiRagdoll_" .. name
			a0.CFrame = joint.C0
			a0.Parent = joint.Part0

			local a1 = Instance.new("Attachment")
			a1.Name = "SkiRagdoll_" .. name
			a1.CFrame = joint.C1
			a1.Parent = joint.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "SkiRagdoll_" .. name
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = 70
			socket.TwistLowerAngle = -50
			socket.TwistUpperAngle = 50
			socket.Parent = joint.Part0

			table.insert(created, a0)
			table.insert(created, a1)
			table.insert(created, socket)

			joint.Enabled = false
		end
	end

	-- Limbs collide while limp, or the character folds through the floor.
	for _, name in LIMBS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			collision[part] = part.CanCollide
			part.CanCollide = true
		end
	end

	-- Zero joints means the rig isn't what this expects -- R15, or something
	-- custom. Say so, because the character will still flop from PlatformStand
	-- alone and "it half works" is the hardest kind of bug to chase later.
	if converted == 0 then
		warn("[Ski] no R6 joints found on " .. character.Name .. " -- falling back to a stiff tumble.")
	end

	humanoid.PlatformStand = true
	playCrashSound(root)

	-- A shove of spin so you tumble rather than going limp and sliding on.
	root.AssemblyLinearVelocity *= Config.CrashSpeedKeep
	root.AssemblyAngularVelocity = Vector3.new(
		(math.random() - 0.5) * 2 * Config.CrashTumble,
		(math.random() - 0.5) * 2 * Config.CrashTumble,
		(math.random() - 0.5) * 2 * Config.CrashTumble
	)

	log("%s wiped out (%d joints limp)", character.Name, converted)

	-- Recovery is wrapped because a character that stays ragdolled is
	-- unrecoverable for that player -- they cannot stand, cannot ski, and have
	-- to reset. An error on the way up must not be able to cause that.
	task.delay(duration or Config.CrashDuration, function()
		if not character.Parent then
			active[character] = nil
			return
		end

		local ok, err = pcall(SkiRagdoll.stop, character)
		if not ok then
			warn("[Ski] recovery failed: " .. tostring(err))
			active[character] = nil

			local stuck = character:FindFirstChildOfClass("Humanoid")
			if stuck and stuck.Health > 0 then
				stuck.PlatformStand = false
			end
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		active[player.Character] = nil
	end
end)

return SkiRagdoll

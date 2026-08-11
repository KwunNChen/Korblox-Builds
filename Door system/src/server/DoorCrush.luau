local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorFolder = ReplicatedStorage:WaitForChild("BlastDoor")
local Config = require(DoorFolder:WaitForChild("DoorConfig"))
local DoorShared = require(DoorFolder:WaitForChild("DoorShared"))

local DoorCrush = {}

local CRUSH_PARAMS = OverlapParams.new()

local killed: { [Model]: boolean } = setmetatable({}, { __mode = "k" })

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[BlastDoor] " .. message, ...))
	end
end

local function spawnMist(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "DoorMistEffect"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local mist = Instance.new("ParticleEmitter")
	mist.Texture = Config.MistTexture
	mist.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Config.MistColorBright),
		ColorSequenceKeypoint.new(1, Config.MistColorDark),
	})
	mist.Size = NumberSequence.new(Config.MistStartSize, Config.MistEndSize)
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Lifetime = NumberRange.new(Config.MistLifetimeMin, Config.MistLifetimeMax)
	mist.Rate = 0
	mist.Speed = NumberRange.new(Config.MistSpeedMin, Config.MistSpeedMax)
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.Acceleration = Vector3.new(0, -Config.MistGravity, 0)
	mist.LightEmission = 0.15
	mist.Parent = attachment

	mist:Emit(Config.MistParticleCount)

	if Config.EnableMistSound and Config.MistSoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = Config.MistSoundId
		sound.Volume = Config.MistSoundVolume
		sound.Parent = anchor
		sound:Play()
	end

	Debris:AddItem(anchor, Config.MistEffectLifetime)
end

function DoorCrush.kill(character: Model, humanoid: Humanoid)
	if killed[character] then
		return
	end
	killed[character] = true

	character:SetAttribute(Config.SuppressRagdollAttribute, true)
	humanoid.BreakJointsOnDeath = false

	local root = character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else character:GetPivot().Position

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
		elseif descendant:IsA("Decal") then
			descendant.Transparency = 1
		end
	end

	spawnMist(position)
	humanoid.Health = 0

	log("%s crushed", character.Name)

	task.delay(Config.CorpseCleanupDelay, function()
		if character.Parent then
			character:Destroy()
		end
	end)
end

function DoorCrush.check(door)
	if not Config.EnableCrushKill then
		return
	end

	local leftPivot = door.left:GetPivot()
	local rightPivot = door.right:GetPivot()

	local gap = (rightPivot.Position - leftPivot.Position):Dot(door.worldAxis)
	if gap > Config.CrushGapThreshold then
		return
	end

	local center = leftPivot.Position:Lerp(rightPivot.Position, 0.5)
	local boxCFrame = CFrame.new(center) * door.closedLeft.Rotation
	local size = DoorShared.crushBoxSize(math.max(gap, Config.CrushZoneMinDepth), Config)

	for _, part in workspace:GetPartBoundsInBox(boxCFrame, size, CRUSH_PARAMS) do
		if part.Name == "HumanoidRootPart" then
			local character = part.Parent
			local humanoid = character and character:IsA("Model") and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				DoorCrush.kill(character :: Model, humanoid)
			end
		end
	end
end

return DoorCrush

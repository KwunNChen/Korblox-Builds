local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DoorFolder = ReplicatedStorage:WaitForChild("BlastDoor")
local Config = require(DoorFolder:WaitForChild("DoorConfig"))
local DoorShared = require(DoorFolder:WaitForChild("DoorShared"))
local DoorCrush = require(script.Parent:WaitForChild("DoorCrush"))

local DoorService = {}

local SENSE_PARAMS = OverlapParams.new()

type Door = {
	model: Model,
	left: PVInstance,
	right: PVInstance,
	closedLeft: CFrame,
	closedRight: CFrame,
	openLeft: CFrame,
	openRight: CFrame,
	worldAxis: Vector3,
	senseCenter: Vector3,
	state: string,
	busy: boolean,
	alive: boolean,
	lastSeen: number,
}

local doors: { [Model]: Door } = {}

-- Forward-declared so scheduleAutoClose (defined first, called later) can
-- close over the real functions instead of a stale global.
local open, close

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[BlastDoor] " .. message, ...))
	end
end

local function playSound(parent: Instance, soundId: string, volume: number)
	if not Config.EnableSound or soundId == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 10)
end

local function tween(door: Door, targetLeft: CFrame, targetRight: CFrame, duration: number, isClosing: boolean)
	local startLeft = door.left:GetPivot()
	local startRight = door.right:GetPivot()
	local startClock = os.clock()

	while true do
		local alpha = if duration <= 0 then 1 else math.clamp((os.clock() - startClock) / duration, 0, 1)
		local eased = TweenService:GetValue(alpha, Config.EasingStyle, Config.EasingDirection)

		door.left:PivotTo(startLeft:Lerp(targetLeft, eased))
		door.right:PivotTo(startRight:Lerp(targetRight, eased))

		if isClosing then
			DoorCrush.check(door)
		end

		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

local function scheduleAutoClose(door: Door)
	if Config.ActivationMethod ~= "Button" or Config.AutoCloseDelay <= 0 then
		return
	end

	task.delay(Config.AutoCloseDelay, function()
		if door.alive and door.state == "Open" then
			close(door)
		end
	end)
end

open = function(door: Door)
	if door.busy or door.state == "Open" or door.state == "Opening" then
		return
	end
	door.busy = true
	door.state = "Opening"
	door.model:SetAttribute("DoorState", door.state)

	playSound(door.left, Config.OpenSoundId, Config.OpenSoundVolume)
	tween(door, door.openLeft, door.openRight, Config.OpenTime, false)

	door.state = "Open"
	door.model:SetAttribute("DoorState", door.state)
	door.busy = false
	log("%s opened", door.model.Name)

	scheduleAutoClose(door)
end

close = function(door: Door)
	if door.busy or door.state == "Closed" or door.state == "Closing" then
		return
	end
	door.busy = true
	door.state = "Closing"
	door.model:SetAttribute("DoorState", door.state)

	playSound(door.left, Config.CloseSoundId, Config.CloseSoundVolume)
	tween(door, door.closedLeft, door.closedRight, Config.CloseTime, true)

	door.state = "Closed"
	door.model:SetAttribute("DoorState", door.state)
	door.busy = false
	log("%s closed", door.model.Name)
end

local function isAnyoneNear(door: Door): boolean
	for _, part in workspace:GetPartBoundsInRadius(door.senseCenter, Config.SenseRadius, SENSE_PARAMS) do
		if part.Name == "HumanoidRootPart" then
			local humanoid = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				return true
			end
		end
	end
	return false
end

local function updateProximity(door: Door)
	if isAnyoneNear(door) then
		door.lastSeen = os.clock()
		if door.state == "Closed" then
			open(door)
		end
	elseif door.state == "Open" and os.clock() - door.lastSeen >= Config.CloseDelay then
		close(door)
	end
end

local function setupButton(door: Door)
	local prompt = door.model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		local anchor = door.model:FindFirstChild(Config.ButtonPartName) or door.left
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorButtonPrompt"
		prompt.ActionText = Config.ButtonActionText
		prompt.ObjectText = Config.ButtonObjectText
		prompt.HoldDuration = Config.ButtonHoldDuration
		prompt.MaxActivationDistance = Config.ButtonMaxDistance
		prompt.RequiresLineOfSight = Config.ButtonRequiresLineOfSight
		prompt.Parent = anchor
		log("%s: no ProximityPrompt found, created a default one on %s", door.model.Name, anchor.Name)
	end

	(prompt :: ProximityPrompt).Triggered:Connect(function()
		if door.state == "Closed" then
			open(door)
		elseif door.state == "Open" then
			close(door)
		end
	end)
end

local function setupActivation(door: Door)
	local method = Config.ActivationMethod

	if method == "Proximity" or method == "Both" then
		door.lastSeen = os.clock()
		task.spawn(function()
			while door.alive do
				task.wait(Config.SenseCheckInterval)
				updateProximity(door)
			end
		end)
	end

	if method == "Button" or method == "Both" then
		setupButton(door)
	end
end

function DoorService.create(model: Model)
	if doors[model] then
		return
	end

	local left = model:FindFirstChild(Config.LeftPartName)
	local right = model:FindFirstChild(Config.RightPartName)
	if not left or not right then
		warn(
			string.format(
				"[BlastDoor] %s is missing %s/%s -- skipped",
				model:GetFullName(),
				Config.LeftPartName,
				Config.RightPartName
			)
		)
		return
	end

	local function isPVInstance(instance: Instance): boolean
		return instance:IsA("Model") or instance:IsA("BasePart")
	end

	if not isPVInstance(left) or not isPVInstance(right) then
		warn(
			string.format(
				"[BlastDoor] %s: %s/%s must be a Part or a Model -- skipped",
				model:GetFullName(),
				Config.LeftPartName,
				Config.RightPartName
			)
		)
		return
	end

	local closedLeft = (left :: PVInstance):GetPivot()
	local closedRight = (right :: PVInstance):GetPivot()

	local localAxis = DoorShared.localAxis(Config.SlideAxis)
	local axisWorld = closedLeft.Rotation:VectorToWorldSpace(localAxis)

	local towardRight = closedRight.Position - closedLeft.Position
	local sign = if towardRight:Dot(axisWorld) >= 0 then 1 else -1
	local worldAxis = axisWorld * sign

	local door: Door = {
		model = model,
		left = left :: PVInstance,
		right = right :: PVInstance,
		closedLeft = closedLeft,
		closedRight = closedRight,
		openLeft = closedLeft - worldAxis * Config.SlideDistance,
		openRight = closedRight + worldAxis * Config.SlideDistance,
		worldAxis = worldAxis,
		senseCenter = closedLeft.Position:Lerp(closedRight.Position, 0.5),
		state = "Closed",
		busy = false,
		alive = true,
		lastSeen = 0,
	}

	doors[model] = door
	model:SetAttribute("DoorState", door.state)
	setupActivation(door)

	log("%s ready (axis %s, %d studs)", model.Name, Config.SlideAxis, Config.SlideDistance)
end

function DoorService.destroy(model: Model)
	local door = doors[model]
	if not door then
		return
	end
	door.alive = false
	doors[model] = nil
end

return DoorService

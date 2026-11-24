--!strict
-- The death screen itself.
--
-- On death: fade to black -> skull close-up -> pull back to his top half ->
-- play the clip -> hold until it ends -> fade the skull out -> ask the server
-- to respawn -> fade the black away once the new character exists.
--
-- Everything is built once at startup and reused for every death: the GUI, the
-- rig, the camera shots, the Sound and every tween. A death only flips the GUI
-- on and plays what is already there. Between deaths the GUI is disabled, so
-- the ViewportFrame costs nothing to render.
--
-- No per-frame Lua anywhere. Waits are event-driven (never task.wait polling),
-- and the idle sway is a looping tween, not a RenderStepped callback.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Folder = ReplicatedStorage:WaitForChild("SkullDeathScreen")
local Config = require(Folder:WaitForChild("DeathScreenConfig")) :: any
local finished = Folder:WaitForChild("Finished") :: RemoteEvent
local template = Folder:WaitForChild(Config.ModelName) :: Model

local player = Players.LocalPlayer

-- Anything that only matters to a live, animated character. The rig here is a
-- still image in a ViewportFrame, so these are dead weight, and the Animate
-- LocalScript would actually run under PlayerGui if it were left in.
-- The Humanoid itself stays: clothing only renders on a rig that has one.
local STRIP = { "BaseScript", "Animator", "Animation", "ValueBase", "BindableFunction", "HumanoidDescription", "JointInstance", "Attachment" }

local function strippable(obj: Instance): boolean
	for _, className in STRIP do
		if obj:IsA(className) then
			return true
		end
	end
	return false
end

local function findPart(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

-- Camera distance that fits `height` studs vertically in frame.
local function distanceFor(height: number): number
	return (height / 2) / math.tan(math.rad(Config.FieldOfView / 2))
end

-- Yields until `signal` fires or `timeout` seconds pass. True if it fired.
-- Event-driven: the thread sleeps instead of waking every frame to check.
local function waitFor(signal: RBXScriptSignal, timeout: number): boolean
	local thread = coroutine.running()
	local settled = false
	local conn: RBXScriptConnection
	local timer: thread

	conn = signal:Once(function()
		if settled then
			return
		end
		settled = true
		task.cancel(timer)
		task.spawn(thread, true)
	end)
	timer = task.delay(timeout, function()
		if settled then
			return
		end
		settled = true
		conn:Disconnect()
		task.spawn(thread, false)
	end)

	return coroutine.yield()
end

local function tween(instance: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, repeats: number?, reverses: boolean?): Tween
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, repeats or 0, reverses or false)
	return TweenService:Create(instance, info, props)
end

------------------------------------------------------------------------------
-- Built once
------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "SkullDeathScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Enabled = false

local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = gui

local viewport = Instance.new("ViewportFrame")
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundTransparency = 1
viewport.ImageTransparency = 1
viewport.Ambient = Config.Ambient
viewport.LightColor = Config.LightColor
viewport.LightDirection = Config.LightDirection
viewport.ZIndex = 2
viewport.Parent = gui

local camera = Instance.new("Camera")
camera.FieldOfView = Config.FieldOfView
camera.Parent = viewport
viewport.CurrentCamera = camera

-- Parented straight to the viewport, no WorldModel: nothing here moves or
-- collides, so there is no physics world to pay for.
local model = template:Clone()
for _, obj in model:GetDescendants() do
	if strippable(obj) then
		obj:Destroy()
	end
end
local humanoid = model:FindFirstChildOfClass("Humanoid")
if humanoid then
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end
model:PivotTo(CFrame.new())
model.Parent = viewport

-- The shots never change, so they are worked out once.
local focus = findPart(model, Config.FocusPartName) or findPart(model, "Head")
assert(focus, `[SkullDeathScreen] {model.Name} has no {Config.FocusPartName} or Head part`)
local torso = findPart(model, "UpperTorso") or findPart(model, "Torso")
local lower = findPart(model, "LowerTorso") or torso

-- Face the way the body faces. The Skull part's own front is whatever
-- orientation it was modelled in, so the torso is the better compass.
local forward = (torso or focus).CFrame.LookVector
local focusPos = focus.Position
local top = focusPos.Y + focus.Size.Y / 2
local bottom = if lower then lower.Position.Y - lower.Size.Y / 2 else focusPos.Y - focus.Size.Y * 3
local center = Vector3.new(focusPos.X, (top + bottom) / 2, focusPos.Z)

local closeShot = CFrame.lookAt(focusPos + forward * distanceFor(focus.Size.Y * Config.CloseUpPadding), focusPos)
local wideShot = CFrame.lookAt(center + forward * distanceFor((top - bottom) * Config.WidePadding), center)
local swayShot = wideShot * CFrame.new(0, Config.SwayHeight, 0) * CFrame.Angles(0, math.rad(Config.SwayAngle), 0)

local sound = Instance.new("Sound")
sound.SoundId = Config.SoundId
sound.Volume = Config.Volume
sound.Parent = gui

local blackIn = tween(black, Config.FadeTime, { BackgroundTransparency = 0 })
local blackOut = tween(black, Config.FadeTime, { BackgroundTransparency = 1 })
local rigIn = tween(viewport, Config.FadeTime, { ImageTransparency = 0 })
local rigOut = tween(viewport, Config.FadeTime, { ImageTransparency = 1 })
local zoom = tween(camera, Config.ZoomTime, { CFrame = wideShot }, Enum.EasingStyle.Quad)
local sway = tween(camera, Config.SwayTime, { CFrame = swayShot }, Enum.EasingStyle.Sine, -1, true)

gui.Parent = player:WaitForChild("PlayerGui")

-- Fetch the clip and the rig's meshes and textures now, so the first death
-- does not wait on the network. Spawned so a slow fetch never delays setup.
task.spawn(ContentProvider.PreloadAsync, ContentProvider, { sound, model })

------------------------------------------------------------------------------
-- Per death
------------------------------------------------------------------------------

local running = false

-- Plays the clip and yields until it ends. Never yields forever: a clip that
-- fails to load holds for FallbackDuration, and a loaded one is capped at its
-- own length in case Ended never fires.
local function playAndWait()
	if not sound.IsLoaded and not waitFor(sound.Loaded, Config.LoadTimeout) then
		warn("[SkullDeathScreen] Audio did not load -- is the id allowed in this place? Holding for FallbackDuration.")
		task.wait(Config.FallbackDuration)
		return
	end

	sound.TimePosition = 0
	sound:Play()
	waitFor(sound.Ended, sound.TimeLength + 1)
end

local function playDeathScreen()
	if running then
		return
	end
	running = true
	local oldCharacter = player.Character

	camera.CFrame = closeShot
	gui.Enabled = true

	blackIn:Play()
	blackIn.Completed:Wait()
	rigIn:Play()
	rigIn.Completed:Wait()
	zoom:Play()
	zoom.Completed:Wait()

	sway:Play()
	playAndWait()
	sway:Cancel()

	-- Respawn happens behind the black, so the new character is never seen
	-- popping in.
	rigOut:Play()
	rigOut.Completed:Wait()
	finished:FireServer()

	if player.Character == oldCharacter then
		waitFor(player.CharacterAdded, 10)
	end

	blackOut:Play()
	blackOut.Completed:Wait()
	gui.Enabled = false
	running = false
end

local function onCharacterAdded(character: Model)
	local charHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	charHumanoid.Died:Once(playDeathScreen)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

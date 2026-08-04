--[[
	ArtilleryShake
	Rattles the camera when a shell lands near you, and washes dust over the
	screen if it lands very near.

	Bound at Camera priority + 1 on purpose. The default camera module writes
	Camera.CFrame every frame at Camera priority, so anything that runs before
	it gets silently overwritten and the shake simply never appears.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))

local ArtilleryShake = {}

local BIND_NAME = "ArtilleryShake"

-- Below this the shake is imperceptible and the noise sampling is wasted work.
local CUTOFF = 0.002

local strength = 0
local dustFrame: Frame?
local lastDustWritten = -1

-- Independent noise streams, or all three axes move together and it reads as a
-- single sway rather than a rattle.
local SEEDS = { 0, 137.3, 291.7 }

local function shakeOffset(clock: number): (Vector3, Vector3)
	local t = clock * Config.ShakeFrequency

	local x = math.noise(t, SEEDS[1], 0)
	local y = math.noise(t, SEEDS[2], 0)
	local z = math.noise(t, SEEDS[3], 0)

	local translation = Vector3.new(x, y, z) * Config.ShakeTranslation * strength
	local rotation = Vector3.new(y, z, x) * math.rad(Config.ShakeRotation) * strength

	return translation, rotation
end

local function applyDust()
	local frame = dustFrame
	if not frame then
		return
	end

	local alpha = strength * Config.ShakeDustStrength

	-- Smoothing never quite reaches zero, so writing every frame would churn the
	-- renderer for changes nobody can see.
	if math.abs(alpha - lastDustWritten) < 0.004 then
		return
	end

	lastDustWritten = alpha
	frame.BackgroundTransparency = 1 - alpha
end

local function step(dt: number)
	if strength <= CUTOFF then
		if strength ~= 0 then
			strength = 0
			applyDust()
		end
		return
	end

	-- Exponential, so it is framerate independent. It never mathematically
	-- reaches zero, which is what CUTOFF above is for.
	strength *= math.exp(-Config.ShakeDecay * dt)

	local camera = workspace.CurrentCamera
	if camera then
		local translation, rotation = shakeOffset(os.clock())
		camera.CFrame = camera.CFrame
			* CFrame.new(translation)
			* CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
	end

	applyDust()
end

-- Strength stacks toward 1 rather than replacing, so a walking barrage builds
-- instead of each shell resetting the last one.
function ArtilleryShake.add(position: Vector3)
	if not Config.EnableCameraShake then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local distance = (camera.CFrame.Position - position).Magnitude
	local amount = 1 - math.clamp(distance / Config.ShakeDistance, 0, 1)
	if amount <= 0 then
		return
	end

	strength = math.min(strength + amount * amount, 1)
end

function ArtilleryShake.init()
	if not Config.EnableCameraShake then
		return
	end

	if Config.ShakeDustStrength > 0 then
		local gui = Instance.new("ScreenGui")
		gui.Name = "ArtilleryDust"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = -10
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

		local frame = Instance.new("Frame")
		frame.Name = "Dust"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Config.ShakeDustColor
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		-- Must stay false or the wash swallows clicks for the whole screen.
		frame.Active = false
		frame.Parent = gui

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.55, 0.85),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		gradient.Parent = frame

		dustFrame = frame
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

return ArtilleryShake

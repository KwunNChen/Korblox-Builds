--[[
	Thunder audio and the storm-dark sky.

	Lightning is environmental only -- it never damages anyone -- and it draws no
	geometry at all. A strike is a flash across the whole sky and a rumble that
	arrives late, both scaled by how far off it happened. Nothing is parented
	into Workspace, because nothing needs to be rendered.

	Distance still matters even with no bolt to look at: two players standing
	apart get different flash strength and a different delay before the thunder
	reaches them.
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))

local Attr = Shared.Attr

local WeatherThunder = {}

-- Sky flash falloff per second. Amplitude lives in WeatherConfig.
local FLASH_DECAY = 3.5

-- Raise to write Lighting less often, lower for finer steps.
local FLASH_EPSILON = 0.004

local FLASH_TINT = Color3.fromRGB(190, 210, 245)

local atmosphere: Atmosphere?
local sky: Sky?
local sunRays: SunRaysEffect?
local rumbleSound: Sound?
local soundPool: { Sound } = {}
local activeSounds = 0

local edgeFrame: Frame?
local edgeGradient: UIGradient?
local edgeStrength = 0
local edgePosition: Vector3?
local lastEdgeWritten = -1

local darkness = 0
local darknessTarget = 0
local sunHide = 0
local sunHideTarget = 0
local flashStrength = 0

local thunderActive = false
local stormIntensity = 0

local lastInfluence = 0
local baseBrightness = 0
local baseExposure = 0
local baseAmbient = Color3.new()
local baseSkyColor = Color3.new()
local baseSunSize = 0
local baseMoonSize = 0
local baseGlare = 0
local baseSunRays = 0

-- Roblox audio is private by default and fails silently, so say so out loud.
local function verifySound(sound: Sound)
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)

		if ok and sound.IsLoaded and sound.TimeLength > 0 then
			return
		end

		warn(
			string.format("[WeatherThunder] Thunder audio failed to load (%s) -- it will be silent.", sound.SoundId)
				.. "\n  Roblox audio is private by default: an id only plays if you uploaded it, or the"
				.. "\n  uploader marked it public. Grabbing an id off a Toolbox MODEL also fails here --"
				.. "\n  you need the audio asset's own id, not the model wrapping it."
		)
	end)
end

local function playPooled(volume: number, pitch: number)
	if activeSounds >= Config.ThunderMaxConcurrentSounds then
		return
	end

	local sound = table.remove(soundPool)
	if not sound then
		return
	end

	sound.Volume = volume
	sound.PlaybackSpeed = pitch

	activeSounds += 1

	local released = false
	local function release()
		if not released then
			released = true
			activeSounds -= 1
			table.insert(soundPool, sound)
		end
	end

	local connection
	connection = sound.Ended:Connect(function()
		connection:Disconnect()
		release()
	end)

	sound:Play()
	task.delay(12, function()
		if not released then
			connection:Disconnect()
			sound:Stop()
			release()
		end
	end)
end

local function playCrack(distance: number)
	local alpha = math.clamp(1 - distance / Config.ThunderAudibleDistance, 0, 1)
	--Distant thunder is a low roll, not a crack.
	playPooled(alpha * alpha, Shared.lerp(0.55, 1.05, alpha))
end

-- Its own instance rather than a pooled one, so a long rumble cannot starve the
-- cracks that follow it.
local function playWarning()
	if rumbleSound then
		(rumbleSound :: Sound):Play()
	end
end

local function strikeAt(position: Vector3)
	local camera = workspace.CurrentCamera
	local viewer = if camera then camera.CFrame.Position else position
	local distance = (viewer - position).Magnitude

	-- Light first, then the roll arrives. This is what makes distance readable
	-- now that there is no bolt to judge it by.
	task.delay(distance / math.max(Config.ThunderSoundSpeed, 1), playCrack, distance)

	local strength = math.clamp(1 - distance / Config.ThunderAudibleDistance, 0, 1)
	flashStrength = math.max(flashStrength, strength)

	-- The brighter strike wins the screen, and its world position is kept rather
	-- than a screen angle so the wash follows the correct edge as you turn.
	if strength >= edgeStrength then
		edgeStrength = strength
		edgePosition = position
	end
end

local function applyEdgeFlash()
	local frame = edgeFrame
	if not frame then
		return
	end

	local alpha = edgeStrength * Config.ThunderScreenFlashStrength

	if math.abs(alpha - lastEdgeWritten) >= FLASH_EPSILON then
		lastEdgeWritten = alpha
		frame.BackgroundTransparency = 1 - alpha
	end

	if alpha <= 0 then
		return
	end

	local camera = workspace.CurrentCamera
	local gradient = edgeGradient
	if not camera or not gradient or not edgePosition then
		return
	end

	-- Gradient runs bright-to-clear from its start, so point it AWAY from the
	-- strike to leave the bright end on the strike's side of the screen.
	local offset = camera.CFrame:PointToObjectSpace(edgePosition :: Vector3)
	gradient.Rotation = math.deg(math.atan2(offset.Y, -offset.X))
end

local function applyLighting()
	local influence = math.max(darkness, flashStrength, sunHide)

	if influence <= 0 then
		-- Re-read the base so a day/night cycle stays authoritative.
		if lastInfluence <= 0 then
			baseBrightness = Lighting.Brightness
			baseExposure = Lighting.ExposureCompensation
			baseAmbient = Lighting.Ambient
			if atmosphere then
				baseSkyColor = (atmosphere :: Atmosphere).Color
				baseGlare = (atmosphere :: Atmosphere).Glare
			end
			if sky then
				baseSunSize = (sky :: Sky).SunAngularSize
				baseMoonSize = (sky :: Sky).MoonAngularSize
			end
			if sunRays then
				baseSunRays = (sunRays :: SunRaysEffect).Intensity
			end
			return
		end
	elseif math.abs(influence - lastInfluence) < FLASH_EPSILON then
		return
	end

	lastInfluence = influence

	Lighting.Brightness = baseBrightness * Shared.lerp(1, Config.ThunderDarkenBrightness, darkness)
		+ flashStrength * Config.ThunderFlashBrightness
	Lighting.ExposureCompensation = baseExposure
		+ darkness * Config.ThunderDarkenExposure
		+ flashStrength * Config.ThunderFlashExposure

	Lighting.Ambient = baseAmbient:Lerp(Config.ThunderAmbientColor, darkness):Lerp(FLASH_TINT, flashStrength * 0.7)

	if atmosphere then
		(atmosphere :: Atmosphere).Color = baseSkyColor:Lerp(Config.ThunderSkyColor, darkness)
	end

	-- Kept separate from darkness: thick cloud blots the sun disc completely
	-- while the scene stays grey-bright, so lightening the storm must not put
	-- the sun back in the sky.
	if Config.ThunderHideSun then
		local clear = 1 - sunHide

		if sky then
			(sky :: Sky).SunAngularSize = baseSunSize * clear;
			(sky :: Sky).MoonAngularSize = baseMoonSize * clear
		end
		if atmosphere then
			(atmosphere :: Atmosphere).Glare = baseGlare * clear
		end
		if sunRays then
			(sunRays :: SunRaysEffect).Intensity = baseSunRays * clear
		end
	end
end

local function refreshDarknessTarget()
	local thunder = if thunderActive then 1 else 0

	darknessTarget = math.max(thunder, math.clamp(stormIntensity * Config.StormDarkenAmount, 0, 1))
	sunHideTarget = math.max(thunder, math.clamp(stormIntensity * Config.StormSunHideAmount, 0, 1))
end

local function step(dt: number)
	local settled = flashStrength <= 0
		and edgeStrength <= 0
		and math.abs(darkness - darknessTarget) < FLASH_EPSILON
		and math.abs(sunHide - sunHideTarget) < FLASH_EPSILON

	if settled and lastInfluence <= 0 and darknessTarget <= 0 and sunHideTarget <= 0 then
		applyLighting()
		return
	end

	darkness = Shared.damp(darkness, darknessTarget, Config.ThunderDarkenSmoothing, dt)
	if darknessTarget <= 0 and darkness < FLASH_EPSILON then
		darkness = 0
	end

	sunHide = Shared.damp(sunHide, sunHideTarget, Config.ThunderDarkenSmoothing, dt)
	if sunHideTarget <= 0 and sunHide < FLASH_EPSILON then
		sunHide = 0
	end

	if flashStrength > 0 then
		flashStrength = math.max(flashStrength - FLASH_DECAY * dt, 0)
	end

	if edgeStrength > 0 then
		edgeStrength = math.max(edgeStrength - FLASH_DECAY * dt, 0)
		if edgeStrength <= 0 then
			edgePosition = nil
		end
	end

	applyLighting()
	applyEdgeFlash()
end

function WeatherThunder.init()
	local strikeEvent = Shared.getStrikeEvent()
	if not strikeEvent then
		warn(
			"[WeatherThunder] ReplicatedStorage.ThunderStrike is missing -- lightning disabled. "
				.. "Move it into ReplicatedStorage alongside Weather and WeatherState (install step 2)."
		)
		return
	end

	local stateHolder = Shared.getStateHolder()

	if Config.EnableThunderScreenFlash then
		local gui = Instance.new("ScreenGui")
		gui.Name = "ThunderFlash"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		--Behind anything the game puts on screen.
		gui.DisplayOrder = -10
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

		local frame = Instance.new("Frame")
		frame.Name = "Edge"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Config.ThunderScreenFlashColor
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		--Must stay false or the wash swallows clicks for the whole screen.
		frame.Active = false
		frame.Parent = gui

		--Bright at the start of the gradient, clear by ThunderScreenFlashSpread.
		--A gradient has no edge to see, which is what the sphere got wrong.
		local spread = math.clamp(Config.ThunderScreenFlashSpread, 0.05, 0.95)
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(spread, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame

		edgeFrame = frame
		edgeGradient = gradient
	end

	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")

	if Config.ThunderHideSun then
		--A place with no Sky uses the default skybox, which cannot be addressed
		--directly. An explicit Sky at defaults looks the same and can be.
		sky = Lighting:FindFirstChildOfClass("Sky")
		if not sky then
			local created = Instance.new("Sky")
			created.Parent = Lighting
			sky = created
		end
	end

	baseBrightness = Lighting.Brightness
	baseExposure = Lighting.ExposureCompensation
	baseAmbient = Lighting.Ambient
	if atmosphere then
		baseSkyColor = (atmosphere :: Atmosphere).Color
		baseGlare = (atmosphere :: Atmosphere).Glare
	end
	if sky then
		baseSunSize = (sky :: Sky).SunAngularSize
		baseMoonSize = (sky :: Sky).MoonAngularSize
	end
	if sunRays then
		baseSunRays = (sunRays :: SunRaysEffect).Intensity
	end

	if Config.ThunderCrackSoundId ~= "" then
		for index = 1, Config.ThunderMaxConcurrentSounds do
			local sound = Instance.new("Sound")
			sound.Name = "ThunderCrack"
			sound.SoundId = Config.ThunderCrackSoundId
			sound.Volume = 0
			sound.Parent = SoundService
			table.insert(soundPool, sound)

			if index == 1 then
				verifySound(sound)
			end
		end

		local rumble = Instance.new("Sound")
		rumble.Name = "ThunderRumble"
		rumble.SoundId = Config.ThunderCrackSoundId
		rumble.Volume = Config.ThunderWarningVolume
		rumble.PlaybackSpeed = Config.ThunderWarningPitch
		rumble.Parent = SoundService
		rumbleSound = rumble
	else
		warn(
			"[WeatherThunder] ThunderCrackSoundId is empty in WeatherConfig -- lightning runs silent. "
				.. "Grab a thunder asset from Toolbox > Audio and paste its id in (see the README)."
		)
	end

	local function refreshWindow()
		local wasActive = thunderActive
		thunderActive = stateHolder:GetAttribute(Attr.ThunderActive) == true
		refreshDarknessTarget()

		if thunderActive and not wasActive then
			playWarning()
		end
	end

	local function refreshIntensity()
		stormIntensity = (stateHolder:GetAttribute(Attr.Intensity) :: number?) or 0
		refreshDarknessTarget()
	end

	stateHolder:GetAttributeChangedSignal(Attr.ThunderActive):Connect(refreshWindow)
	stateHolder:GetAttributeChangedSignal(Attr.Intensity):Connect(refreshIntensity)

	thunderActive = stateHolder:GetAttribute(Attr.ThunderActive) == true
	refreshIntensity()

	strikeEvent.OnClientEvent:Connect(function(position)
		if typeof(position) == "Vector3" then
			strikeAt(position)
		end
	end)

	Lighting.ChildAdded:Connect(function(child)
		if child:IsA("Atmosphere") then
			atmosphere = child
			baseSkyColor = child.Color
			baseGlare = child.Glare
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return WeatherThunder

-- Lightning visuals, thunder audio, and the storm-dark sky.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))

local Attr = Shared.Attr

local WeatherThunder = {}

-- Seconds the bolt stays on screen.
local BOLT_LIFETIME = 0.12

-- Sky flash falloff per second, and how far it lifts brightness and exposure.
local FLASH_DECAY = 3.5
local FLASH_BRIGHTNESS = 2.5
local FLASH_EXPOSURE = 0.55

-- Marker emission at the start and end of the telegraph.
local MARKER_RATE_START = 4
local MARKER_RATE_END = 26

-- Raise to write Lighting less often, lower for finer steps.
local FLASH_EPSILON = 0.004

local BOLT_VISIBLE = NumberSequence.new(0)
local BOLT_HIDDEN = NumberSequence.new(1)
local FLASH_TINT = Color3.fromRGB(190, 210, 245)

type Rig = {
	folder: Folder,
	ground: BasePart,
	sky: BasePart,
	marker: ParticleEmitter,
	light: PointLight,
	bolt: Beam,
}

type Active = {
	rig: Rig,
	startedAt: number,
	strength: number,
	struck: boolean,
}

local container: Folder
local atmosphere: Atmosphere?
local warningSound: Sound?
local soundPool: { Sound } = {}

local pool: { Rig } = {}
local active: { Active } = {}
local activeSounds = 0

local darkness = 0
local darknessTarget = 0
local flashStrength = 0

local lastInfluence = 0
local baseBrightness = 0
local baseExposure = 0
local baseAmbient = Color3.new()
local baseSkyColor = Color3.new()

local function newHiddenPart(name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	-- Must stay false or shelter raycasts would read a strike rig as a roof.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	return part
end

local function buildRig(): Rig
	local folder = Instance.new("Folder")
	folder.Name = "StrikeRig"

	local ground = newHiddenPart("Impact")
	ground.Parent = folder

	local groundAttachment = Instance.new("Attachment")
	groundAttachment.Name = "Impact"
	groundAttachment.Parent = ground

	local marker = Instance.new("ParticleEmitter")
	marker.Name = "Charge"
	marker.Texture = Config.FlakeTexture
	marker.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255), Color3.fromRGB(235, 245, 255))
	marker.Lifetime = NumberRange.new(0.35, 0.6)
	marker.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	marker.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	marker.Speed = NumberRange.new(3, 7)
	marker.EmissionDirection = Enum.NormalId.Top
	marker.SpreadAngle = Vector2.new(18, 18)
	marker.Acceleration = Vector3.new(0, -6, 0)
	marker.LightEmission = 0.8
	marker.Rate = 0
	marker.Enabled = false
	marker.Parent = groundAttachment

	local light = Instance.new("PointLight")
	light.Name = "Flash"
	light.Color = Color3.fromRGB(200, 225, 255)
	light.Range = 55
	light.Brightness = 0
	light.Shadows = false
	light.Enabled = false
	light.Parent = ground

	local sky = newHiddenPart("Cloud")
	sky.Parent = folder

	local skyAttachment = Instance.new("Attachment")
	skyAttachment.Name = "Cloud"
	skyAttachment.Parent = sky

	local bolt = Instance.new("Beam")
	bolt.Name = "Bolt"
	bolt.Attachment0 = skyAttachment
	bolt.Attachment1 = groundAttachment
	bolt.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
	bolt.LightEmission = 1
	bolt.LightInfluence = 0
	bolt.Width0 = 0.6
	bolt.Width1 = 1.6
	bolt.FaceCamera = true
	bolt.Transparency = BOLT_HIDDEN
	bolt.Enabled = false
	bolt.Parent = sky

	folder.Parent = container

	return {
		folder = folder,
		ground = ground,
		sky = sky,
		marker = marker,
		light = light,
		bolt = bolt,
	}
end

local function playCrack(distance: number)
	if activeSounds >= Config.ThunderMaxConcurrentSounds then
		return
	end

	local sound = table.remove(soundPool)
	if not sound then
		return
	end

	local alpha = math.clamp(1 - distance / Config.ThunderAudibleDistance, 0, 1)
	sound.Volume = alpha * alpha
	sound.PlaybackSpeed = Shared.lerp(0.75, 1.05, alpha)

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

local function strikeAt(position: Vector3)
	local camera = workspace.CurrentCamera
	local viewer = if camera then camera.CFrame.Position else position
	local distance = (viewer - position).Magnitude

	task.delay(distance / math.max(Config.ThunderSoundSpeed, 1), playCrack, distance)

	local rig = table.remove(pool)
	if not rig then
		return
	end

	rig.ground.Position = position
	rig.sky.Position = position + Vector3.new(0, Config.ThunderCloudHeight, 0)
	rig.marker.Rate = MARKER_RATE_START
	rig.marker.Enabled = true

	table.insert(active, {
		rig = rig,
		startedAt = os.clock(),
		strength = math.clamp(1 - distance / Config.ThunderAudibleDistance, 0, 1),
		struck = false,
	})
end

local function applyLighting()
	local influence = math.max(darkness, flashStrength)

	if influence <= 0 then
		-- Re-read the base so a day/night cycle stays authoritative.
		if lastInfluence <= 0 then
			baseBrightness = Lighting.Brightness
			baseExposure = Lighting.ExposureCompensation
			baseAmbient = Lighting.Ambient
			if atmosphere then
				baseSkyColor = (atmosphere :: Atmosphere).Color
			end
			return
		end
	elseif math.abs(influence - lastInfluence) < FLASH_EPSILON then
		return
	end

	lastInfluence = influence

	Lighting.Brightness = baseBrightness * Shared.lerp(1, Config.ThunderDarkenBrightness, darkness)
		+ flashStrength * FLASH_BRIGHTNESS
	Lighting.ExposureCompensation = baseExposure
		+ darkness * Config.ThunderDarkenExposure
		+ flashStrength * FLASH_EXPOSURE

	Lighting.Ambient = baseAmbient:Lerp(Config.ThunderAmbientColor, darkness):Lerp(FLASH_TINT, flashStrength * 0.7)

	if atmosphere then
		(atmosphere :: Atmosphere).Color = baseSkyColor:Lerp(Config.ThunderSkyColor, darkness)
	end
end

local function step(dt: number)
	local settled = #active == 0 and flashStrength <= 0 and math.abs(darkness - darknessTarget) < FLASH_EPSILON

	if settled and lastInfluence <= 0 and darknessTarget <= 0 then
		applyLighting()
		return
	end

	local now = os.clock()
	local telegraph = Config.ThunderTelegraph

	for index = #active, 1, -1 do
		local entry = active[index]
		local rig = entry.rig
		local elapsed = now - entry.startedAt

		if elapsed < telegraph then
			local alpha = elapsed / telegraph
			rig.marker.Rate = Shared.lerp(MARKER_RATE_START, MARKER_RATE_END, alpha * alpha)
		elseif not entry.struck then
			entry.struck = true

			rig.marker.Enabled = false
			rig.marker.Rate = 0
			rig.bolt.Transparency = BOLT_VISIBLE
			rig.bolt.Enabled = true
			rig.light.Brightness = 6
			rig.light.Enabled = true

			flashStrength = math.max(flashStrength, entry.strength)
		elseif elapsed >= telegraph + BOLT_LIFETIME then
			rig.bolt.Enabled = false
			rig.bolt.Transparency = BOLT_HIDDEN
			rig.light.Enabled = false
			rig.light.Brightness = 0

			table.insert(pool, rig)
			table.remove(active, index)
		end
	end

	darkness = Shared.damp(darkness, darknessTarget, Config.ThunderDarkenSmoothing, dt)
	if darknessTarget <= 0 and darkness < FLASH_EPSILON then
		darkness = 0
	end

	if flashStrength > 0 then
		flashStrength = math.max(flashStrength - FLASH_DECAY * dt, 0)
	end

	applyLighting()
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

	container = Instance.new("Folder")
	container.Name = "ThunderVisuals"
	container.Parent = workspace.CurrentCamera or workspace

	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

	baseBrightness = Lighting.Brightness
	baseExposure = Lighting.ExposureCompensation
	baseAmbient = Lighting.Ambient
	if atmosphere then
		baseSkyColor = (atmosphere :: Atmosphere).Color
	end

	for _ = 1, Config.ThunderVisualPool do
		table.insert(pool, buildRig())
	end

	if Config.ThunderCrackSoundId ~= "" then
		for _ = 1, Config.ThunderMaxConcurrentSounds do
			local sound = Instance.new("Sound")
			sound.Name = "ThunderCrack"
			sound.SoundId = Config.ThunderCrackSoundId
			sound.Volume = 0
			sound.Parent = SoundService
			table.insert(soundPool, sound)
		end
	end

	if Config.ThunderWarningSoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = "ThunderWarning"
		sound.SoundId = Config.ThunderWarningSoundId
		sound.Volume = 0.7
		sound.Parent = SoundService
		warningSound = sound
	end

	if Config.ThunderCrackSoundId == "" and Config.ThunderWarningSoundId == "" then
		warn(
			"[WeatherThunder] No thunder sound ids set in WeatherConfig -- lightning runs silent. "
				.. "Grab thunder assets from Toolbox > Audio and paste their ids into "
				.. "ThunderWarningSoundId and ThunderCrackSoundId (see the README)."
		)
	end

	local function refreshWindow()
		local isActive = stateHolder:GetAttribute(Attr.ThunderActive) == true
		darknessTarget = if isActive then 1 else 0

		if isActive and warningSound then
			(warningSound :: Sound):Play()
		end
	end

	stateHolder:GetAttributeChangedSignal(Attr.ThunderActive):Connect(refreshWindow)
	darknessTarget = if stateHolder:GetAttribute(Attr.ThunderActive) == true then 1 else 0

	strikeEvent.OnClientEvent:Connect(function(position)
		if typeof(position) == "Vector3" then
			strikeAt(position)
		end
	end)

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			container.Parent = camera
		end
	end)

	Lighting.ChildAdded:Connect(function(child)
		if child:IsA("Atmosphere") then
			atmosphere = child
			baseSkyColor = child.Color
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return WeatherThunder

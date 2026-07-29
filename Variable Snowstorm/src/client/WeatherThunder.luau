--[[
	Lightning visuals, thunder audio, and the storm-dark sky.

	Lightning is environmental only -- it never damages anyone, so there is no
	telegraph and nothing to dodge. A strike is a bolt, a lit patch of cloud, a
	flash across the whole sky, and a rumble that arrives late.

	Strikes land past StormFogEnd on purpose, so fog reduces most of them to a
	flash on the horizon and only the nearest show an actual bolt.

	Visual rigs are pooled and capped. When the pool is empty the oldest is
	recycled, so a busy window has a hard ceiling instead of a frame hitch.
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))

local Attr = Shared.Attr

local WeatherThunder = {}

-- Seconds the bolt and the lit cloud stay on screen.
local BOLT_LIFETIME = 0.12
local GLOW_LIFETIME = 0.45

-- Sky flash falloff per second. Amplitude lives in WeatherConfig.
local FLASH_DECAY = 3.5

-- Raise to write Lighting less often, lower for finer steps.
local FLASH_EPSILON = 0.004

-- Impact light. Kept dim on purpose: the sky flash is the event, not a flare
-- on the ground.
local IMPACT_BRIGHTNESS = 2.5
local IMPACT_RANGE = 35
local IMPACT_COLOR = Color3.fromRGB(200, 225, 255)

-- Cloud glow transparency at its brightest. Lower is brighter.
local GLOW_STRIKE = 0.35

local BOLT_VISIBLE = NumberSequence.new(0)
local BOLT_HIDDEN = NumberSequence.new(1)
local FLASH_TINT = Color3.fromRGB(190, 210, 245)

type Rig = {
	folder: Folder,
	ground: BasePart,
	sky: BasePart,
	glow: BasePart,
	light: PointLight,
	bolt: Beam,
}

type Active = {
	rig: Rig,
	startedAt: number,
	boltDone: boolean,
}

local container: Folder
local atmosphere: Atmosphere?
local sky: Sky?
local sunRays: SunRaysEffect?
local rumbleSound: Sound?
local soundPool: { Sound } = {}

local pool: { Rig } = {}
local active: { Active } = {}
local activeSounds = 0

local darkness = 0
local darknessTarget = 0
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

local function newHiddenPart(name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
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

	local light = Instance.new("PointLight")
	light.Name = "Flash"
	light.Color = IMPACT_COLOR
	light.Range = IMPACT_RANGE
	light.Brightness = 0
	light.Shadows = false
	light.Enabled = false
	light.Parent = ground

	local skyPart = newHiddenPart("Cloud")
	skyPart.Parent = folder

	local skyAttachment = Instance.new("Attachment")
	skyAttachment.Name = "Cloud"
	skyAttachment.Parent = skyPart

	local bolt = Instance.new("Beam")
	bolt.Name = "Bolt"
	bolt.Attachment0 = skyAttachment
	bolt.Attachment1 = groundAttachment
	bolt.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
	bolt.LightEmission = 1
	bolt.LightInfluence = 0
	bolt.Width0 = Config.ThunderBoltWidth * 0.6
	bolt.Width1 = Config.ThunderBoltWidth
	bolt.FaceCamera = true
	bolt.Transparency = BOLT_HIDDEN
	bolt.Enabled = false
	bolt.Parent = skyPart

	--The lit patch of cloud the bolt drops out of. Sits below the bolt's origin
	--so it stays inside fog range, and the fog is what smears it from a sphere
	--into something cloud-shaped.
	local glow = Instance.new("Part")
	glow.Name = "CloudGlow"
	glow.Shape = Enum.PartType.Ball
	glow.Material = Enum.Material.Neon
	glow.Color = Config.ThunderCloudGlowColor
	glow.Size = Vector3.one * Config.ThunderCloudGlowSize
	glow.Transparency = 1
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.CastShadow = false
	glow.Locked = true
	glow.Parent = folder

	folder.Parent = container

	return {
		folder = folder,
		ground = ground,
		sky = skyPart,
		glow = glow,
		light = light,
		bolt = bolt,
	}
end

local function resetRig(rig: Rig)
	rig.bolt.Enabled = false
	rig.bolt.Transparency = BOLT_HIDDEN
	rig.light.Enabled = false
	rig.light.Brightness = 0
	rig.glow.Transparency = 1
end

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

local function acquireRig(): Rig?
	local rig = table.remove(pool)
	if rig then
		return rig
	end

	local oldest, oldestAt = nil, math.huge
	for index, entry in active do
		if entry.startedAt < oldestAt then
			oldest, oldestAt = index, entry.startedAt
		end
	end

	if not oldest then
		return nil
	end

	local entry = table.remove(active, oldest)
	resetRig(entry.rig)
	return entry.rig
end

local function strikeAt(position: Vector3)
	local camera = workspace.CurrentCamera
	local viewer = if camera then camera.CFrame.Position else position
	local distance = (viewer - position).Magnitude

	-- Light first, then the roll arrives. This is the whole point of
	-- ThunderSoundSpeed and is what makes distance readable.
	task.delay(distance / math.max(Config.ThunderSoundSpeed, 1), playCrack, distance)

	local rig = acquireRig()
	if not rig then
		return
	end

	rig.ground.Position = position
	rig.sky.Position = position + Vector3.new(0, Config.ThunderCloudHeight, 0)
	rig.glow.Position = position + Vector3.new(0, Config.ThunderCloudGlowHeight, 0)

	rig.bolt.Transparency = BOLT_VISIBLE
	rig.bolt.Enabled = true
	rig.glow.Transparency = GLOW_STRIKE
	rig.light.Brightness = IMPACT_BRIGHTNESS
	rig.light.Enabled = true

	flashStrength = math.max(flashStrength, math.clamp(1 - distance / Config.ThunderAudibleDistance, 0, 1))

	table.insert(active, {
		rig = rig,
		startedAt = os.clock(),
		boltDone = false,
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

	-- Dimming Brightness alone leaves a bright sun disc hanging in a black sky,
	-- so the disc, its glare and its god rays all go with it.
	if Config.ThunderHideSun then
		local clear = 1 - darkness

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

-- A thunderstorm darkens fully; a blizzard darkens on its own by intensity, so
-- Peak snow blots the sun even with no lightning running.
local function refreshDarknessTarget()
	local fromStorm = stormIntensity * Config.StormDarkenAmount
	darknessTarget = math.max(if thunderActive then 1 else 0, math.clamp(fromStorm, 0, 1))
end

local function step(dt: number)
	local settled = #active == 0 and flashStrength <= 0 and math.abs(darkness - darknessTarget) < FLASH_EPSILON

	if settled and lastInfluence <= 0 and darknessTarget <= 0 then
		applyLighting()
		return
	end

	local now = os.clock()

	for index = #active, 1, -1 do
		local entry = active[index]
		local rig = entry.rig
		local elapsed = now - entry.startedAt

		if not entry.boltDone and elapsed >= BOLT_LIFETIME then
			entry.boltDone = true
			rig.bolt.Enabled = false
			rig.bolt.Transparency = BOLT_HIDDEN
			rig.light.Enabled = false
			rig.light.Brightness = 0
		end

		if elapsed >= GLOW_LIFETIME then
			resetRig(rig)
			table.insert(pool, rig)
			table.remove(active, index)
		else
			--The cloud keeps glowing a beat after the bolt has gone.
			rig.glow.Transparency = Shared.lerp(GLOW_STRIKE, 1, elapsed / GLOW_LIFETIME)
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

	for _ = 1, Config.ThunderVisualPool do
		table.insert(pool, buildRig())
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
			baseGlare = child.Glare
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return WeatherThunder

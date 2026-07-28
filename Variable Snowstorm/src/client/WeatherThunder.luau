-- Lightning visuals, thunder audio, and the storm-dark sky.

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

-- Seconds the bolt stays on screen.
local BOLT_LIFETIME = 0.08

-- Sky flash falloff per second. Amplitude lives in WeatherConfig.
local FLASH_DECAY = 3.5

-- Impact light. Kept dim on purpose: a bright one lights the ground like a
-- flare and reads as a strike beside you rather than a flash overhead.
local IMPACT_BRIGHTNESS = 2.5
local IMPACT_RANGE = 35
local IMPACT_COLOR = Color3.fromRGB(200, 225, 255)

-- Marker emission at the start and end of the telegraph. Live spark count is
-- Rate * average Lifetime, and that lifetime is very short, so these look
-- higher than they are: roughly 9 and 60 live. Lower the end value first if
-- Peak framerate suffers.
local MARKER_RATE_START = 80
local MARKER_RATE_END = 540

-- Ground glow radius while charging.
local MARKER_LIGHT_RANGE = 16

-- Half-height of the spark volume. It is lifted by this much so the whole box
-- sits above the surface instead of half the sparks spawning underground.
local GROUND_LIFT = 0.3

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
local rumbleSound: Sound?
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
	--Sized off the kill radius so the crackling patch is exactly the ground
	--that kills you, and cannot drift out of sync when that value is retuned.
	local field = Config.ThunderKillRadius * Config.ThunderMarkerSpread * 2
	ground.Size = Vector3.new(field, GROUND_LIFT * 2, field)
	ground.Parent = folder

	local groundAttachment = Instance.new("Attachment")
	groundAttachment.Name = "Impact"
	groundAttachment.Parent = ground

	--Parented to the part rather than the attachment so it can emit from the
	--part's volume instead of a single point.
	local marker = Instance.new("ParticleEmitter")
	marker.Name = "Charge"
	marker.Texture = Config.ThunderMarkerTexture
	marker.Color = ColorSequence.new(Config.ThunderMarkerColor)
	marker.Lifetime = NumberRange.new(0.06, 0.16)
	marker.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.ThunderMarkerSize),
		NumberSequenceKeypoint.new(1, Config.ThunderMarkerSize),
	})
	--Holds solid then snaps out. A linear fade reads as a dying ember.
	marker.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	marker.Speed = NumberRange.new(0, 2)
	marker.SpreadAngle = Vector2.new(0, 0)
	marker.Acceleration = Vector3.zero
	marker.Rotation = NumberRange.new(0, 360)
	marker.RotSpeed = NumberRange.new(-250, 250)
	marker.Shape = Enum.ParticleEmitterShape.Box
	marker.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	marker.LockedToPart = true
	marker.LightEmission = 1
	marker.LightInfluence = 0
	marker.Rate = 0
	marker.Enabled = false
	marker.Parent = ground

	local light = Instance.new("PointLight")
	light.Name = "Flash"
	light.Color = IMPACT_COLOR
	light.Range = IMPACT_RANGE
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
	bolt.Width0 = Config.ThunderBoltWidth * 0.6
	bolt.Width1 = Config.ThunderBoltWidth
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
				.. "\n  To confirm: drop a Sound into Workspace, paste the id in, and press the play"
				.. "\n  arrow next to SoundId in Properties. If it is silent there, it is the asset."
		)
	end)
end

-- Same silent-failure trap as the audio: a bad image id renders nothing and
-- says nothing, which is indistinguishable from the marker being too subtle.
local function verifyTexture(texture: string)
	if texture == "" or texture:sub(1, 10) == "rbxasset://" then
		return
	end

	task.spawn(function()
		local probe = Instance.new("Decal")
		probe.Texture = texture

		pcall(function()
			ContentProvider:PreloadAsync({ probe })
		end)

		local ok, fetchStatus = pcall(function()
			return ContentProvider:GetAssetFetchStatus(texture)
		end)

		probe:Destroy()

		if not ok or fetchStatus ~= Enum.AssetFetchStatus.Failure then
			return
		end

		warn(
			string.format("[WeatherThunder] Marker texture failed to load (%s).", texture)
				.. "\n  Toolbox images are private unless the uploader made them public, and a"
				.. "\n  MODEL id will not work here -- you need an Image or Decal asset id."
				.. "\n  To check one: put a Decal on a part, paste the id into its Texture, and"
				.. "\n  see whether it appears in the viewport."
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
	playPooled(alpha * alpha, Shared.lerp(0.75, 1.05, alpha))
end

-- Its own instance rather than a pooled one, so a long rumble cannot starve the
-- cracks that follow it.
local function playWarning()
	if rumbleSound then
		(rumbleSound :: Sound):Play()
	end
end

local function resetRig(rig: Rig)
	rig.marker.Enabled = false
	rig.marker.Rate = 0
	rig.bolt.Enabled = false
	rig.bolt.Transparency = BOLT_HIDDEN
	rig.light.Enabled = false
	rig.light.Brightness = 0
end

-- A strike with no marker cannot be dodged, so an exhausted pool steals from a
-- strike that has already landed, or failing that the one furthest from
-- landing. Never the one about to hit -- that is the warning that matters most.
local function acquireRig(): Rig?
	local rig = table.remove(pool)
	if rig then
		return rig
	end

	local victim, newest = nil, -math.huge
	for index, entry in active do
		if entry.struck then
			victim = index
			break
		end
		if entry.startedAt > newest then
			victim, newest = index, entry.startedAt
		end
	end

	if not victim then
		return nil
	end

	local entry = table.remove(active, victim)
	resetRig(entry.rig)
	return entry.rig
end

local function strikeAt(position: Vector3)
	local camera = workspace.CurrentCamera
	local viewer = if camera then camera.CFrame.Position else position
	local distance = (viewer - position).Magnitude

	-- Offset by the telegraph so the lag is measured from the bolt, not from the
	-- marker appearing. Without it the crack lands before the flash.
	local soundLag = Config.ThunderTelegraph + distance / math.max(Config.ThunderSoundSpeed, 1)
	task.delay(soundLag, playCrack, distance)

	local rig = acquireRig()
	if not rig then
		return
	end

	rig.ground.Position = position + Vector3.new(0, GROUND_LIFT, 0)
	rig.sky.Position = position + Vector3.new(0, Config.ThunderCloudHeight, 0)
	rig.marker.Rate = MARKER_RATE_START
	rig.marker.Enabled = true

	--Same light does both jobs: a dim blue charge now, a white flash on impact.
	rig.light.Color = Config.ThunderMarkerColor
	rig.light.Range = MARKER_LIGHT_RANGE
	rig.light.Brightness = 0
	rig.light.Enabled = Config.ThunderMarkerLight > 0

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
		+ flashStrength * Config.ThunderFlashBrightness
	Lighting.ExposureCompensation = baseExposure
		+ darkness * Config.ThunderDarkenExposure
		+ flashStrength * Config.ThunderFlashExposure

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
			local charge = (elapsed / telegraph) ^ 2
			rig.marker.Rate = Shared.lerp(MARKER_RATE_START, MARKER_RATE_END, charge)
			rig.light.Brightness = Config.ThunderMarkerLight * charge
		elseif not entry.struck then
			entry.struck = true

			rig.marker.Enabled = false
			rig.marker.Rate = 0
			rig.bolt.Transparency = BOLT_VISIBLE
			rig.bolt.Enabled = true
			rig.light.Color = IMPACT_COLOR
			rig.light.Range = IMPACT_RANGE
			rig.light.Brightness = IMPACT_BRIGHTNESS
			rig.light.Enabled = true

			flashStrength = math.max(flashStrength, entry.strength)
		elseif elapsed >= telegraph + BOLT_LIFETIME then
			resetRig(rig)
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

	verifyTexture(Config.ThunderMarkerTexture)

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
		local isActive = stateHolder:GetAttribute(Attr.ThunderActive) == true
		darknessTarget = if isActive then 1 else 0

		if isActive then
			playWarning()
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

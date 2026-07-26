-- Snow rendering, roof detection, and local lighting for this player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local WeatherFolder = ReplicatedStorage:WaitForChild("Weather")
local Config = require(WeatherFolder:WaitForChild("WeatherConfig"))
local Shared = require(WeatherFolder:WaitForChild("WeatherShared"))
local WeatherAudio = require(script.Parent:WaitForChild("WeatherAudio"))

local Attr = Shared.Attr
local player = Players.LocalPlayer

-- Raise these to write engine properties less often, lower for finer steps.
local LIGHTING_EPSILON = 0.002
local RATE_EPSILON = 0.5
local ACCEL_EPSILON = 0.5

local camera = workspace.CurrentCamera
while not camera do
	task.wait()
	camera = workspace.CurrentCamera
end

local stateHolder = Shared.getStateHolder()

local function readNumber(name: string): number
	return (stateHolder:GetAttribute(name) :: number?) or 0
end

local stormIntensity = readNumber(Attr.Intensity)
local stormWind = Vector3.new(readNumber(Attr.WindX), 0, readNumber(Attr.WindZ))

local function refreshWind()
	stormWind = Vector3.new(readNumber(Attr.WindX), 0, readNumber(Attr.WindZ))
end

stateHolder:GetAttributeChangedSignal(Attr.Intensity):Connect(function()
	stormIntensity = readNumber(Attr.Intensity)
end)
stateHolder:GetAttributeChangedSignal(Attr.WindX):Connect(refreshWind)
stateHolder:GetAttributeChangedSignal(Attr.WindZ):Connect(refreshWind)

local averageLifetime = (Config.FlakeLifetime.Min + Config.FlakeLifetime.Max) / 2
local MAX_RATE = Config.ParticleBudget / averageLifetime

local rig = Instance.new("Part")
rig.Name = "SnowRig"
rig.Size = Config.RigSize
rig.Transparency = 1
rig.Anchored = true
rig.CanCollide = false
rig.CanQuery = false
rig.CanTouch = false
rig.CastShadow = false
rig.Locked = true
rig.TopSurface = Enum.SurfaceType.Smooth
rig.BottomSurface = Enum.SurfaceType.Smooth
rig.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, Config.RigHeightOffset, 0))
rig.Parent = camera

local emitter = Instance.new("ParticleEmitter")
emitter.Name = "Snow"
emitter.Texture = Config.FlakeTexture
emitter.Color = Config.FlakeColor
emitter.Lifetime = Config.FlakeLifetime
emitter.Speed = Config.FlakeSpeed
emitter.Rate = 0
emitter.Enabled = false
emitter.EmissionDirection = Enum.NormalId.Bottom
emitter.SpreadAngle = Vector2.new(25, 25)
emitter.Rotation = NumberRange.new(0, 360)
emitter.RotSpeed = NumberRange.new(-40, 40)
emitter.LightEmission = 0.2
emitter.LightInfluence = 1
emitter.ZOffset = 0
emitter.Shape = Enum.ParticleEmitterShape.Box
emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
emitter.LockedToPart = false
emitter.Drag = Config.FlakeDrag

-- Flake fade curve: birth -> visible -> death.
emitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.12, 0.2),
	NumberSequenceKeypoint.new(0.82, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})

emitter.Parent = rig

pcall(function()
	emitter.WindAffectsDrag = true
end)

local shelterParams = Shared.newShelterParams({ rig })
local character: Model? = nil

local function bindCharacter(newCharacter: Model)
	character = newCharacter
	shelterParams.FilterDescendantsInstances = { newCharacter, rig }
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

-- Measured from the character, not the camera, so backing the camera through a
-- wall does not start snow indoors.
local function measureShelter(): number
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = if root then (root :: BasePart).Position else camera.CFrame.Position
	return Shared.sampleShelter(origin, shelterParams)
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere and Config.EnableLightingEffects then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

-- Maps with fog off sit at FogEnd 100000; clamped so the storm's fog is visible.
local baseFogEnd = math.min(Lighting.FogEnd, 5000)
local baseFogColor = Lighting.FogColor
local baseOutdoorAmbient = Lighting.OutdoorAmbient
local baseDensity = if atmosphere then atmosphere.Density else 0
local baseHaze = if atmosphere then atmosphere.Haze else 0

local lastLightingAlpha = 0

local function applyLighting(alpha: number)
	if math.abs(alpha - lastLightingAlpha) < LIGHTING_EPSILON then
		return
	end
	lastLightingAlpha = alpha

	Lighting.FogEnd = Shared.lerp(baseFogEnd, Config.StormFogEnd, alpha)
	Lighting.FogColor = baseFogColor:Lerp(Config.StormFogColor, alpha)
	Lighting.OutdoorAmbient = baseOutdoorAmbient:Lerp(Config.StormOutdoorAmbient, alpha)

	if atmosphere then
		atmosphere.Density = Shared.lerp(baseDensity, Config.StormAtmosphereDensity, alpha)
		atmosphere.Haze = Shared.lerp(baseHaze, Config.StormAtmosphereHaze, alpha)
	end
end

WeatherAudio.init()

local shelter = 0
local shelterTarget = 0
local lightingAlpha = 0
local checkAccumulator = 0
local lastBucket = -1
local lastRate = -1
local lastAccel = Vector3.zero
local lastCameraPos = camera.CFrame.Position
local smoothedVelocity = Vector3.zero
local wasActive = false

local function applyBucketedLook(intensity: number)
	local size = Shared.lerp(Config.FlakeSizeCalm, Config.FlakeSizePeak, intensity)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.8),
		NumberSequenceKeypoint.new(1, size),
	})
	emitter.Squash = NumberSequence.new(Shared.lerp(Config.SquashAtCalm, Config.SquashAtPeak, intensity))
end

local function positionRig(wind: Vector3)
	local lookahead = smoothedVelocity * Config.LookaheadTime
	if lookahead.Magnitude > Config.LookaheadMaxDistance then
		lookahead = lookahead.Unit * Config.LookaheadMaxDistance
	end

	-- Offsets the volume upwind so flakes blow into view.
	local windBias = -wind * 0.3
	if windBias.Magnitude > 40 then
		windBias = windBias.Unit * 40
	end

	rig.CFrame = CFrame.new(
		camera.CFrame.Position + Vector3.new(0, Config.RigHeightOffset, 0) + lookahead + windBias
	)
end

RunService:BindToRenderStep("SnowRig", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local intensity = stormIntensity
	local wind = stormWind

	if Config.EnableLightingEffects then
		lightingAlpha = Shared.damp(lightingAlpha, intensity, Config.LightingSmoothing, dt)
		applyLighting(lightingAlpha)
	end

	WeatherAudio.update(intensity, shelter, wind.Magnitude, dt)

	if intensity <= 0 and shelter <= 0.001 and not emitter.Enabled then
		lastCameraPos = camera.CFrame.Position
		smoothedVelocity = Vector3.zero
		return
	end

	if intensity > 0 then
		if not wasActive then
			wasActive = true
			checkAccumulator = 0
			shelterTarget = measureShelter()
			shelter = shelterTarget
		else
			checkAccumulator += dt
			if checkAccumulator >= Config.ShelterCheckInterval then
				checkAccumulator = 0
				shelterTarget = measureShelter()
			end
		end
	else
		wasActive = false
		shelterTarget = 0
	end

	shelter = Shared.damp(shelter, shelterTarget, Config.ShelterSmoothing, dt)

	local cameraPos = camera.CFrame.Position
	if dt > 0 then
		smoothedVelocity = smoothedVelocity:Lerp((cameraPos - lastCameraPos) / dt, 0.15)
	end
	lastCameraPos = cameraPos

	positionRig(wind)

	local rate = MAX_RATE * intensity * (1 - shelter)
	if math.abs(rate - lastRate) > RATE_EPSILON then
		lastRate = rate
		emitter.Rate = rate
	end

	local enabled = rate > 0.5
	if emitter.Enabled ~= enabled then
		emitter.Enabled = enabled
	end

	local accel = Vector3.new(wind.X, -Config.FlakeGravity, wind.Z)
	if (accel - lastAccel).Magnitude > ACCEL_EPSILON then
		lastAccel = accel
		emitter.Acceleration = accel
	end

	local bucket = math.floor(intensity * Config.IntensityBuckets + 0.5)
	if bucket ~= lastBucket then
		lastBucket = bucket
		applyBucketedLook(intensity)
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local newCamera = workspace.CurrentCamera
	if newCamera then
		camera = newCamera
		rig.Parent = newCamera
	end
end)

-- Fires only from setOverride(intensity, true); skips the ramp-up for testing.
stateHolder:GetAttributeChangedSignal(Attr.InstantCue):Connect(function()
	task.defer(function()
		local intensity = stormIntensity
		if intensity <= 0 then
			return
		end

		local wind = stormWind

		if Config.EnableLightingEffects then
			lightingAlpha = intensity
			applyLighting(lightingAlpha)
		end

		shelterTarget = measureShelter()
		shelter = shelterTarget
		wasActive = true

		WeatherAudio.snap(intensity, shelter, wind.Magnitude)

		local exposure = 1 - shelter
		if exposure <= 0.01 then
			return
		end

		lastBucket = math.floor(intensity * Config.IntensityBuckets + 0.5)
		applyBucketedLook(intensity)
		positionRig(wind)

		emitter.Enabled = true
		emitter:Emit(math.floor(Config.ParticleBudget * intensity * exposure))
	end)
end)

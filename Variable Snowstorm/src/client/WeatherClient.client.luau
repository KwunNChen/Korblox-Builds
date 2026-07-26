--[[
	WeatherClient  (per-player rendering)

	Reads the four replicated numbers the server publishes and turns them into
	an actual snowstorm for THIS player, at THIS player's position.

	Two things make this cheap:

	1. The particle rig is parented to workspace.CurrentCamera. Instances under
	   the Camera are rendered locally but never replicate to anyone, and get
	   cleaned up automatically. One emitter exists per client, not per player
	   per client.

	2. Roof detection is a handful of raycasts fired five times a second by each
	   client for itself -- not N raycasts per second on the server for everyone.
	   The result is smoothed, so a slow check still fades smoothly.
]]

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

local camera = workspace.CurrentCamera
while not camera do
	task.wait()
	camera = workspace.CurrentCamera
end

local stateHolder = Shared.getStateHolder()

-- Live particle count is roughly Rate * average Lifetime, so we solve for the
-- Rate that lands on the configured budget instead of guessing at a number.
local averageLifetime = (Config.FlakeLifetime.Min + Config.FlakeLifetime.Max) / 2
local MAX_RATE = Config.ParticleBudget / averageLifetime

-- ============================================================
-- Particle rig
-- ============================================================

local rig = Instance.new("Part")
rig.Name = "SnowRig"
rig.Size = Config.RigSize
rig.Transparency = 1
rig.Anchored = true
rig.CanCollide = false
rig.CanQuery = false -- keeps it out of everyone's raycasts, including our own
rig.CanTouch = false
rig.CastShadow = false
rig.Locked = true
rig.TopSurface = Enum.SurfaceType.Smooth
rig.BottomSurface = Enum.SurfaceType.Smooth
-- Start it on the camera rather than at the default (0,0,0). The render loop
-- early-outs while no storm is active and never touches CFrame, so without this
-- a burst fired before the first storm would spawn at world origin.
rig.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, Config.RigHeightOffset, 0))
rig.Parent = camera -- never replicates

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
emitter.LightInfluence = 1 -- flakes pick up the scene's lighting
emitter.ZOffset = 0

-- Fill the whole box volume so snow is already mid-air when a storm starts,
-- rather than taking a few seconds to fall down into view.
emitter.Shape = Enum.ParticleEmitterShape.Box
emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume

-- Critical: without this, flakes would be welded to the rig and teleport along
-- with the camera instead of falling through the world.
emitter.LockedToPart = false

-- Drag turns Acceleration into a velocity target: a particle settles at roughly
-- (acceleration / drag). With the default config that is ~14 studs/s downward
-- in calm air, which is why gravity here is much lower than real gravity.
emitter.Drag = Config.FlakeDrag

emitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.12, 0.2),
	NumberSequenceKeypoint.new(0.82, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})

emitter.Parent = rig

-- Snow follows workspace.GlobalWind when this is on and Drag > 0. It is a newer
-- property and flagged deprecated in the API dump, so it is set defensively --
-- the storm's real horizontal motion comes from Acceleration below, and this is
-- only a bonus layer of turbulence.
pcall(function()
	emitter.WindAffectsDrag = true
end)

-- ============================================================
-- Shelter detection
-- ============================================================

local shelterParams = Shared.newShelterParams({ rig })
local character: Model? = nil

local function bindCharacter(newCharacter: Model)
	character = newCharacter
	-- Rebuild the filter so our own body never counts as a roof.
	shelterParams.FilterDescendantsInstances = { newCharacter, rig }
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

--[[
	Shelter is measured from the CHARACTER, not the camera.

	In third person the camera often floats outside the building you are standing
	in. Using the character matches what the player believes -- "am I indoors?" --
	and avoids snow pouring through the ceiling every time you back the camera
	into a wall.
]]
local function measureShelter(): number
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = if root then (root :: BasePart).Position else camera.CFrame.Position
	return Shared.sampleShelter(origin, shelterParams)
end

-- ============================================================
-- Lighting  (applied locally -- these changes never leave this client)
-- ============================================================

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere and Config.EnableLightingEffects then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

-- A map with fog disabled has FogEnd at 100000. Lerping from that would mean no
-- visible fog until intensity was nearly maxed, so we clamp the starting point
-- to something the eye can actually read a change from.
local baseFogEnd = math.min(Lighting.FogEnd, 5000)
local baseFogColor = Lighting.FogColor
local baseOutdoorAmbient = Lighting.OutdoorAmbient
local baseDensity = if atmosphere then atmosphere.Density else 0
local baseHaze = if atmosphere then atmosphere.Haze else 0

local function applyLighting(alpha: number)
	Lighting.FogEnd = Shared.lerp(baseFogEnd, Config.StormFogEnd, alpha)
	Lighting.FogColor = baseFogColor:Lerp(Config.StormFogColor, alpha)
	Lighting.OutdoorAmbient = baseOutdoorAmbient:Lerp(Config.StormOutdoorAmbient, alpha)

	if atmosphere then
		atmosphere.Density = Shared.lerp(baseDensity, Config.StormAtmosphereDensity, alpha)
		atmosphere.Haze = Shared.lerp(baseHaze, Config.StormAtmosphereHaze, alpha)
	end
end

-- ============================================================
-- Main loop
-- ============================================================

WeatherAudio.init()

local shelter = 0 -- smoothed, 0 = open sky, 1 = fully covered
local shelterTarget = 0
local lightingAlpha = 0
local checkAccumulator = 0
local lastBucket = -1
local lastCameraPos = camera.CFrame.Position
local smoothedVelocity = Vector3.zero
local wasActive = false

--[[
	NumberSequence assignments allocate a new object every time, so rebuilding
	them every frame would generate steady garbage for no visual gain. Instead we
	quantise intensity into buckets and only rebuild when the bucket changes.
]]
local function applyBucketedLook(intensity: number)
	local size = Shared.lerp(Config.FlakeSizeCalm, Config.FlakeSizePeak, intensity)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.8),
		NumberSequenceKeypoint.new(1, size),
	})

	-- Flakes stretch into streaks as the storm picks up.
	emitter.Squash = NumberSequence.new(Shared.lerp(Config.SquashAtCalm, Config.SquashAtPeak, intensity))
end

--[[
	Parks the emission volume around the camera.

	Extracted rather than inlined in the render loop because the instant-override
	handler also has to position the rig before it bursts -- otherwise the burst
	spawns wherever the rig was last left.
]]
local function positionRig(wind: Vector3)
	local lookahead = smoothedVelocity * Config.LookaheadTime
	if lookahead.Magnitude > Config.LookaheadMaxDistance then
		lookahead = lookahead.Unit * Config.LookaheadMaxDistance
	end

	-- Offset the volume upwind so flakes blow into view rather than away from it.
	local windBias = -wind * 0.3
	if windBias.Magnitude > 40 then
		windBias = windBias.Unit * 40
	end

	rig.CFrame = CFrame.new(
		camera.CFrame.Position + Vector3.new(0, Config.RigHeightOffset, 0) + lookahead + windBias
	)
end

--[[
	Bound just after the camera updates rather than on RenderStepped.

	RenderStepped fires *before* the default camera moves, so reading the camera
	there gives last frame's position and the rig visibly trails behind on fast
	turns. Camera priority + 1 means we always position the volume against the
	camera transform that is about to be rendered.
]]
RunService:BindToRenderStep("SnowRig", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local intensity = (stateHolder:GetAttribute(Attr.Intensity) :: number?) or 0
	local windX = (stateHolder:GetAttribute(Attr.WindX) :: number?) or 0
	local windZ = (stateHolder:GetAttribute(Attr.WindZ) :: number?) or 0
	local wind = Vector3.new(windX, 0, windZ)

	-- Lighting keeps easing even at zero intensity so a storm ending still fades
	-- out smoothly instead of snapping back to clear skies.
	if Config.EnableLightingEffects then
		lightingAlpha = Shared.damp(lightingAlpha, intensity, Config.LightingSmoothing, dt)
		applyLighting(lightingAlpha)
	end

	-- Audio updates before the idle early-out for the same reason as lighting:
	-- otherwise the wind would freeze at whatever volume it held when the storm
	-- ended instead of fading out. `shelter` here is last frame's value, which is
	-- imperceptible at these smoothing rates.
	WeatherAudio.update(intensity, shelter, wind.Magnitude, dt)

	-- Fully idle: no storm and nothing left to fade. Skip every raycast and every
	-- property write until the weather actually changes.
	if intensity <= 0 and shelter <= 0.001 and not emitter.Enabled then
		-- Keep camera tracking current even while idle. Otherwise the first frame
		-- of the next storm measures movement against a position from minutes ago
		-- and computes an enormous bogus velocity.
		lastCameraPos = camera.CFrame.Position
		smoothedVelocity = Vector3.zero
		return
	end

	-- ---- Shelter, on a throttle ----
	if intensity > 0 then
		if not wasActive then
			-- The storm just started. Measure immediately and snap rather than
			-- easing up from zero, or a player standing indoors would see a brief
			-- burst of snow through the ceiling before the smoothing catches up.
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
		-- No storm: stop raycasting entirely and let shelter unwind to zero so
		-- the loop can reach its idle early-out above.
		wasActive = false
		shelterTarget = 0
	end

	shelter = Shared.damp(shelter, shelterTarget, Config.ShelterSmoothing, dt)

	-- ---- Position the emission volume ----
	local cameraPos = camera.CFrame.Position

	if dt > 0 then
		local velocity = (cameraPos - lastCameraPos) / dt
		-- Smooth the velocity or the volume jitters on every small camera nudge.
		smoothedVelocity = smoothedVelocity:Lerp(velocity, 0.15)
	end
	lastCameraPos = cameraPos

	positionRig(wind)

	-- ---- Cheap per-frame properties ----
	local exposure = 1 - shelter
	local rate = MAX_RATE * intensity * exposure

	emitter.Rate = rate
	emitter.Enabled = rate > 0.5
	emitter.Acceleration = Vector3.new(wind.X, -Config.FlakeGravity, wind.Z)

	-- ---- Expensive properties, only when the look meaningfully changed ----
	local bucket = math.floor(intensity * Config.IntensityBuckets + 0.5)
	if bucket ~= lastBucket then
		lastBucket = bucket
		applyBucketedLook(intensity)
	end
end)

-- Studio's camera can be swapped out (and some games replace it deliberately).
-- Reparent so the rig never ends up orphaned under a destroyed camera.
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local newCamera = workspace.CurrentCamera
	if newCamera then
		camera = newCamera
		rig.Parent = newCamera
	end
end)

--[[
	Fires only when WeatherService.setOverride(intensity, true) is used from the
	command bar. Skips the lighting ease and the particle lifetime ramp-up so a
	test override reads as instant instead of taking several seconds to visually
	catch up. Production storms never touch this path.
]]
stateHolder:GetAttributeChangedSignal(Attr.InstantCue):Connect(function()
	-- Attribute ordering within a replication batch is not guaranteed. Deferring
	-- a step lets Intensity land before we read it -- otherwise, if InstantCue
	-- arrives first, we read a stale 0 and bail without doing anything.
	task.defer(function()
		local intensity = (stateHolder:GetAttribute(Attr.Intensity) :: number?) or 0
		if intensity <= 0 then
			return
		end

		local wind = Vector3.new(
			(stateHolder:GetAttribute(Attr.WindX) :: number?) or 0,
			0,
			(stateHolder:GetAttribute(Attr.WindZ) :: number?) or 0
		)

		if Config.EnableLightingEffects then
			lightingAlpha = intensity
			applyLighting(lightingAlpha)
		end

		-- Measure shelter before bursting so a test override fired indoors is
		-- scaled down instead of flashing a lungful of snow through the ceiling.
		shelterTarget = measureShelter()
		shelter = shelterTarget
		wasActive = true

		WeatherAudio.snap(intensity, shelter, wind.Magnitude)

		local exposure = 1 - shelter
		if exposure <= 0.01 then
			return
		end

		-- Match flake sizing to the new intensity first, or the burst spawns
		-- using whatever look the calm bucket last applied.
		lastBucket = math.floor(intensity * Config.IntensityBuckets + 0.5)
		applyBucketedLook(intensity)

		-- The rig is only repositioned inside the render loop, which early-outs
		-- while idle. Park it on the camera now or the whole burst lands
		-- wherever the rig was last left.
		positionRig(wind)

		-- Roblox's own docs pair Emit() with Enabled = false, but that behaviour
		-- isn't spelled out anywhere, so don't depend on it. The render loop
		-- recomputes Enabled from Rate on the very next frame regardless.
		emitter.Enabled = true
		emitter:Emit(math.floor(Config.ParticleBudget * intensity * exposure))
	end)
end)

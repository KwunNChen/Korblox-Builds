--[[
	ShellRender
	Draws the shells and their impacts. Client only, and it decides nothing --
	the server has already chosen where every one of these lands.

	Everything built here is parented into a folder under workspace.CurrentCamera.
	Nothing under the Camera replicates, which is what lets twenty shells cost
	one render loop instead of twenty replicated physics assemblies. It is the
	same trick Variable Snowstorm uses for its particle rig.

	The bright arc is a Trail with LightEmission at 1, not a light source. That
	makes it read as glowing against a dark or foggy sky for free -- twenty
	actual PointLights would not survive contact with a framerate.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Shared = require(ArtilleryFolder:WaitForChild("ArtilleryShared"))
local ArtilleryAudio = require(script.Parent:WaitForChild("ArtilleryAudio"))
local ArtilleryShake = require(script.Parent:WaitForChild("ArtilleryShake"))
local DebrisChunks = require(script.Parent:WaitForChild("DebrisChunks"))
local DustCloud = require(script.Parent:WaitForChild("DustCloud"))

local ShellRender = {}

type Shell = {
	launch: Vector3,
	impact: Vector3,
	velocity: Vector3,
	flightTime: number,
	impactTime: number,
	part: BasePart?,
	whistle: Sound?,
	whistleStarted: boolean,
}

local active: { Shell } = {}
local container: Folder?

-- Counts shells that actually have a part, not entries in `active` -- culled
-- ones stay in the list so their impact still bursts and booms, and charging
-- them against the render budget would let a distant barrage stop a nearby one
-- from drawing.
local rendered = 0

local FADE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Artillery/client] " .. message, ...))
	end
end

-- The camera is replaced on respawn in some games, taking the folder with it.
-- The camera check is explicit rather than folded into the parent comparison:
-- with no camera, `container.Parent == camera` compares nil to nil and passes,
-- which would hand back an orphaned folder forever and draw nothing.
local function getContainer(): Folder
	local camera = workspace.CurrentCamera

	if container and camera and container.Parent == camera then
		return container :: Folder
	end

	if container then
		(container :: Folder):Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "ArtilleryEffects"
	folder.Parent = camera
	container = folder
	return folder
end

local function cameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

-- ============================================================
-- THE SHELL
-- ============================================================

local function buildShellPart(): BasePart
	local part = Instance.new("Part")
	part.Name = "ArtilleryShell"
	part.Size = Config.ShellSize
	part.Color = Config.ShellColor
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false

	-- Trail width is the distance between its two attachments, so they are
	-- placed across the shell rather than along it.
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, Config.TrailWidth * 0.5, 0)
	a0.Parent = part

	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -Config.TrailWidth * 0.5, 0)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = Config.TrailLifetime
	trail.Color = Config.TrailColor
	trail.LightEmission = Config.TrailLightEmission
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.MinLength = 0
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})

	if Config.TrailTexture ~= "" then
		trail.Texture = Config.TrailTexture
		trail.TextureLength = Config.TrailTextureLength
		trail.TextureMode = Enum.TextureMode.Stretch
	end

	trail.Parent = part

	if Config.EnableShellSmoke then
		local smokeAt = Instance.new("Attachment")
		smokeAt.Parent = part

		local smoke = Instance.new("ParticleEmitter")
		smoke.Color = ColorSequence.new(Color3.fromRGB(120, 110, 100), Color3.fromRGB(60, 55, 50))
		smoke.Size = NumberSequence.new(1.2, 7)
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Lifetime = NumberRange.new(0.8, 1.6)
		smoke.Rate = Config.ShellSmokeRate
		smoke.Speed = NumberRange.new(0, 2)
		smoke.LightEmission = 0.1
		smoke.Parent = smokeAt
	end

	return part
end

-- ============================================================
-- THE IMPACT
-- ============================================================

-- Reused; the local character is swapped in per cast so standing on the crater
-- does not colour the debris with your own torso.
local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Exclude
surfaceParams.IgnoreWater = false

--[[
	What the shell landed on -- colour AND facing.

	Colour is what the debris and dust are tinted with, so snow throws white and
	mud throws brown without anything being authored per map. The normal is what
	lets the ground dust decal lie flat against a slope instead of floating at a
	fixed world-up angle and clipping into the hillside.

	Terrain has no Color of its own, so its material is looked up instead. That
	call is wrapped: the material set it accepts is not the same as the set a
	raycast can report, and a miss there should cost a fallback colour rather
	than an error on every impact.

	Falling back to Vector3.yAxis for the normal (flat, facing up) when the
	surface match is off or the cast finds nothing is the same as this system's
	old behaviour before a normal was tracked at all -- it only gets worse than
	that on genuinely sloped, untracked ground.
]]
local function readSurface(position: Vector3): (Color3, Vector3)
	if not Config.DebrisMatchSurface then
		return Config.DebrisFallbackColor, Vector3.yAxis
	end

	local character = Players.LocalPlayer.Character
	surfaceParams.FilterDescendantsInstances = if character then { character } else {}

	local result = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -24, 0), surfaceParams)
	if not result then
		return Config.DebrisFallbackColor, Vector3.yAxis
	end

	local normal = if result.Normal.Magnitude > 0.001 then result.Normal.Unit else Vector3.yAxis

	if result.Instance == workspace.Terrain then
		local ok, color = pcall(function()
			return workspace.Terrain:GetMaterialColor(result.Material)
		end)
		return (if ok and color then color else Config.DebrisFallbackColor), normal
	end

	return result.Instance.Color, normal
end

local function buildImpact(position: Vector3)
	if (cameraPosition() - position).Magnitude > Config.ImpactEffectDistance then
		return
	end

	local parent = getContainer()

	-- ============ [STAGE 1] DUST -- fires immediately ============
	--
	-- No glowing ball. Just a brief light, and one dust cloud that grows and
	-- sinks over the crater -- spawned below, once the surface under the shell
	-- has been read.

	if Config.EnableImpactLight then
		local lightHost = Instance.new("Part")
		lightHost.Name = "ArtilleryImpactLight"
		lightHost.Size = Vector3.one
		lightHost.CFrame = CFrame.new(position)
		-- Invisible on purpose: this exists only to carry the PointLight. The
		-- part itself is what used to be the ball.
		lightHost.Transparency = 1
		lightHost.Anchored = true
		lightHost.CanCollide = false
		lightHost.CanQuery = false
		lightHost.CanTouch = false
		lightHost.CastShadow = false
		lightHost.Parent = parent

		local light = Instance.new("PointLight")
		light.Brightness = Config.ImpactLightBrightness
		light.Range = Config.ImpactLightRange
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Parent = lightHost

		TweenService:Create(light, FADE_INFO, { Brightness = 0 }):Play()
		Debris:AddItem(lightHost, 0.4)
	end

	local burst = Instance.new("Part")
	burst.Name = "ArtilleryBurst"
	burst.Size = Vector3.one
	burst.CFrame = CFrame.new(position)
	burst.Transparency = 1
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.Parent = parent

	local at = Instance.new("Attachment")
	at.Parent = burst

	local surface, groundNormal = readSurface(position)
	local smokeTexture = Shared.assetId(Config.SmokeTexture)

	-- The dust: one image, grown and sunk against the surface normal so it
	-- lies flat on a slope. DustCloud owns its own lifetime and cleanup, so
	-- nothing about it is tracked here.
	DustCloud.spawn(position, surface:Lerp(Color3.new(0, 0, 0), Config.DustDecalDarken), groundNormal)

	-- ============ [STAGE 2] DEBRIS -- thrown at ImpactDebrisDelay ============
	--
	-- Real parts, not particles. See DebrisChunks for why.

	-- Darkened after the surface tint. Thrown earth is shadowed and reads nearly
	-- as a silhouette; taking snow's colour raw throws bright white specks, which
	-- is most of what makes an impact look like glitter instead of dirt.
	local debrisColor = surface:Lerp(Color3.new(0, 0, 0), Config.DebrisDarken)

	-- ============ [STAGE 3] SMOKE -- emitted at ImpactSmokeDelay ============

	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Config.ImpactSmokeColor)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.ImpactSmokeSize.Min * 0.3),
		NumberSequenceKeypoint.new(1, Config.ImpactSmokeSize.Max),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = Config.ImpactSmokeLifetime
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(18, 45)
	smoke.SpreadAngle = Vector2.new(50, 50)
	smoke.Acceleration = Vector3.new(0, Config.ImpactSmokeRise, 0)
	smoke.LightEmission = 0.05
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-24, 24)

	if smokeTexture ~= "" then
		smoke.Texture = smokeTexture
	end

	smoke.Parent = at

	--[[
		Fire the three stages in order rather than all on one frame.

		Everything bursting simultaneously is what makes an explosion read as a
		flat pop: the dust wave, the ground coming up and the cloud settling are
		one event visually, so the eye gets no sense of anything happening TO the
		ground. A few hundredths of a second between them is enough.

		The guards matter. These delays outlive the host if the effect is culled
		or the camera is swapped, and emitting from a destroyed emitter is a
		silent no-op that would otherwise hide the mistake.
	]]
	task.delay(Config.ImpactDebrisDelay, function()
		DebrisChunks.spawn(position, debrisColor)
	end)

	task.delay(Config.ImpactSmokeDelay, function()
		if burst.Parent then
			smoke:Emit(Config.ImpactSmokeCount)
		end
	end)

	-- Nothing outlives the emitters. A shell throws the ground up and leaves no
	-- mark of any kind behind it.
	Debris:AddItem(burst, Config.ImpactEffectLifetime)
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

local function detonate(shell: Shell)
	if shell.part then
		(shell.part :: BasePart):Destroy()
		rendered -= 1
	end

	buildImpact(shell.impact)
	ArtilleryAudio.impact(shell.impact)
	ArtilleryShake.add(shell.impact)
end

function ShellRender.add(launch: Vector3, impact: Vector3, flightTime: number, impactTime: number)
	local shell: Shell = {
		launch = launch,
		impact = impact,
		velocity = Shared.solveVelocity(launch, impact, flightTime),
		flightTime = flightTime,
		impactTime = impactTime,
		part = nil,
		whistle = nil,
		whistleStarted = false,
	}

	-- Over budget or over the horizon: the record still exists, so the impact
	-- still bursts, booms and shakes. Only the arc is skipped.
	local visible = rendered < Config.MaxRenderedShells
		and (cameraPosition() - impact).Magnitude <= Config.ShellRenderDistance

	if visible then
		local part = buildShellPart()
		part.CFrame = CFrame.new(launch)
		part.Parent = getContainer()
		shell.part = part
		rendered += 1

		local whistle = ArtilleryAudio.newWhistle()
		if whistle then
			whistle.Parent = part
			shell.whistle = whistle
		end
	end

	table.insert(active, shell)
end

local function updateShell(shell: Shell, elapsed: number)
	local part = shell.part
	if not part then
		return
	end

	local position = Shared.positionAt(shell.launch, shell.velocity, elapsed)

	-- Direction is taken from a step further along the same curve rather than
	-- from the launch velocity, so the shell tips over as it falls instead of
	-- flying nose-up all the way down.
	local ahead = Shared.positionAt(shell.launch, shell.velocity, elapsed + 0.05)
	local direction = ahead - position

	if direction.Magnitude > 0.001 then
		part.CFrame = CFrame.lookAt(position, ahead)
	else
		part.CFrame = CFrame.new(position)
	end

	local whistle = shell.whistle
	if whistle then
		local progress = elapsed / shell.flightTime
		local audible = (progress - Config.WhistleAudibleFrom) / math.max(1 - Config.WhistleAudibleFrom, 0.001)

		if audible > 0 then
			if not shell.whistleStarted then
				shell.whistleStarted = true
				whistle:Play()
			end
			whistle.Volume = math.clamp(audible, 0, 1) * Config.WhistleVolume
			whistle.PlaybackSpeed = Shared.lerp(Config.WhistlePitchStart, Config.WhistlePitchEnd, progress)
		end
	end
end

function ShellRender.step(now: number)
	for index = #active, 1, -1 do
		local shell = active[index]
		local elapsed = shell.flightTime - (shell.impactTime - now)

		if elapsed >= shell.flightTime then
			table.remove(active, index)
			detonate(shell)
		elseif elapsed >= 0 then
			updateShell(shell, elapsed)
		end
	end
end

function ShellRender.init()
	getContainer()
	log("ready")
end

return ShellRender

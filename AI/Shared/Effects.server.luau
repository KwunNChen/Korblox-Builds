--[[
	Runs on each client (RunContext Client): draws this vehicle's blasts: the
	main gun's muzzle and shell impacts, and the vehicle blowing up when it is
	destroyed, in the same style as the Random Arty barrages. No explosion ball
	and nothing left on the ground:

	    0.00s   a brief light, and one dust image that opens out and settles,
	            tinted to whatever the shell hit
	    0.04s   real debris chunks thrown out, the same colour, darkened
	    0.22s   a smoke puff that drifts and fades
	    plus camera shake falling off with distance, and the impact sound.

	The server deals the damage and sends "muzzle", "impact" or "wreck" through
	the vehicle's VehicleFx remote; this is only what players see. The same
	script is in every vehicle package.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--Impacts further than this from the camera are not drawn.
local EFFECT_DISTANCE = 900

--Impact sound (the artillery's near impact) and how far it carries.
local IMPACT_SOUND = "rbxassetid://73652976704676"
local IMPACT_VOLUME = 2
local IMPACT_SOUND_DISTANCE = 1500

--Light at the impact: brightness and range.
local LIGHT_BRIGHTNESS = 5
local LIGHT_RANGE = 50

--Dust image: texture, starting and final width (studs), the height it starts
--above the ground, seconds held before fading and seconds to fade, how much it
--is darkened from the ground colour, and spin (degrees/s).
local DUST_TEXTURE = "rbxassetid://4449493080"
local DUST_START_SIZE = NumberRange.new(10, 14)
local DUST_END_SIZE = NumberRange.new(36, 52)
local DUST_START_HEIGHT = 3
local DUST_HOLD_TIME = 1.1
local DUST_FADE_TIME = 2.2
local DUST_DARKEN = 0.2
local DUST_SPIN = 4

--Debris chunks: how many, their size range (studs), throw speed (studs/s),
--angle above the ground (degrees), lifetime (s), gravity, and how much darker
--than the ground they are.
local CHUNK_COUNT = 16
local CHUNK_SIZE = NumberRange.new(0.4, 2)
local CHUNK_SPEED = NumberRange.new(20, 140)
local CHUNK_ELEVATION = NumberRange.new(8, 80)
local CHUNK_LIFETIME = NumberRange.new(1, 2.2)
local CHUNK_GRAVITY = 95
local CHUNK_DARKEN = 0.55

--Smoke puff: texture, count, size range, lifetime and colour.
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SMOKE_COUNT = 12
local SMOKE_SIZE = NumberRange.new(45, 75)
local SMOKE_LIFETIME = NumberRange.new(4, 7)
local SMOKE_COLOR = Color3.fromRGB(74, 68, 62)

--Camera shake at the impact (studs and degrees), the distance it falls off to
--nothing, and how fast it dies away.
local SHAKE_TRANSLATION = 1.6
local SHAKE_ROTATION = 1.2
local SHAKE_DISTANCE = 300
local SHAKE_DECAY = 3.5
local SHAKE_FREQUENCY = 28

--How much bigger than a shell impact the blast is when the vehicle is destroyed.
local WRECK_SCALE = 1.7

--Muzzle blast: smoke count and size.
local MUZZLE_SMOKE_COUNT = 14
local MUZZLE_SMOKE_SIZE = NumberRange.new(6, 16)

local FALLBACK_COLOR = Color3.fromRGB(92, 76, 58)

local vehicle = script.Parent
local vehicleFx = vehicle:WaitForChild("VehicleFx")

local function roll(range)
	return range.Min + math.random()*(range.Max - range.Min)
end

local function container()
	local camera = workspace.CurrentCamera
	local folder = camera and camera:FindFirstChild("AbramsEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "AbramsEffects"
		folder.Parent = camera
	end
	return folder
end

local function host(position)
	local part = Instance.new("Part")
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = container()
	return part
end

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Exclude

--What the shell landed on: its colour (terrain by material) and which way it faces.
local function readSurface(position)
	local list = {vehicle}
	if Players.LocalPlayer.Character then
		table.insert(list,Players.LocalPlayer.Character)
	end
	surfaceParams.FilterDescendantsInstances = list
	local result = workspace:Raycast(position + Vector3.new(0,6,0),Vector3.new(0,-24,0),surfaceParams)
	if not result then
		return FALLBACK_COLOR,Vector3.yAxis
	end
	local normal = result.Normal.Magnitude > 0.001 and result.Normal.Unit or Vector3.yAxis
	if result.Instance == workspace.Terrain then
		local ok,color = pcall(function()
			return workspace.Terrain:GetMaterialColor(result.Material)
		end)
		return ok and color or FALLBACK_COLOR,normal
	end
	return result.Instance.Color,normal
end

local function smokePuff(parent,count,size,lifetime,speed,spread)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(SMOKE_COLOR)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0,size.Min*0.3),
		NumberSequenceKeypoint.new(1,size.Max),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,0.25),
		NumberSequenceKeypoint.new(1,1),
	})
	smoke.Lifetime = lifetime
	smoke.Rate = 0
	smoke.Speed = speed
	smoke.SpreadAngle = spread
	smoke.Acceleration = Vector3.new(0,1,0)
	smoke.LightEmission = 0.05
	smoke.Rotation = NumberRange.new(0,360)
	smoke.RotSpeed = NumberRange.new(-24,24)
	smoke.Parent = parent
	smoke:Emit(count)
end

local function flash(position,brightness,range)
	local lightHost = host(position)
	local light = Instance.new("PointLight")
	light.Brightness = brightness
	light.Range = range
	light.Color = Color3.fromRGB(255,190,120)
	light.Parent = lightHost
	TweenService:Create(light,TweenInfo.new(0.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Brightness = 0}):Play()
	Debris:AddItem(lightHost,0.4)
end

---------------------------------------------------------------- dust and debris

local clouds = {}
local chunks = {}

local function spawnDust(position,color,normal,scale)
	local reference = math.abs(normal.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	local right = reference:Cross(normal).Unit
	local placement = CFrame.fromMatrix(position,right,normal,normal:Cross(right).Unit) * CFrame.Angles(0,math.random()*math.pi*2,0)
	local startSize,endSize = roll(DUST_START_SIZE)*scale,roll(DUST_END_SIZE)*scale

	local part = host(position)
	part.Size = Vector3.new(startSize,0.05,startSize)
	part.CFrame = placement + normal*DUST_START_HEIGHT
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = DUST_TEXTURE
	decal.Color3 = color
	decal.Transparency = 0.1
	decal.Parent = part

	table.insert(clouds,{part = part,decal = decal,placement = placement,normal = normal,born = os.clock(),
		spin = math.rad(DUST_SPIN)*(math.random() < 0.5 and -1 or 1),startSize = startSize,endSize = endSize})
end

local function spawnChunks(position,color,scale)
	local now = os.clock()
	for _ = 1,math.floor(CHUNK_COUNT*scale) do
		local size = roll(CHUNK_SIZE)
		local part = host(position)
		part.Transparency = 0
		part.Size = Vector3.new(size,size*(0.45 + math.random()),size*(0.45 + math.random()))
		part.Color = color
		part.Material = Enum.Material.Slate
		part.CFrame = CFrame.new(position) * CFrame.Angles(math.random()*6.28,math.random()*6.28,0)

		local yaw = math.random()*math.pi*2
		local elevation = math.rad(roll(CHUNK_ELEVATION))
		local direction = Vector3.new(math.cos(yaw)*math.cos(elevation),math.sin(elevation),math.sin(yaw)*math.cos(elevation))
		table.insert(chunks,{part = part,origin = position,velocity = direction*roll(CHUNK_SPEED)*math.sqrt(scale),
			spin = Vector3.new(math.random() - 0.5,math.random() - 0.5,math.random() - 0.5)*28,born = now,lifetime = roll(CHUNK_LIFETIME)})
	end
end

local function stepDust(now)
	local lifetime = DUST_HOLD_TIME + DUST_FADE_TIME
	for index = #clouds,1,-1 do
		local cloud = clouds[index]
		local elapsed = now - cloud.born
		if elapsed >= lifetime then
			cloud.part:Destroy()
			clouds[index] = clouds[#clouds]
			clouds[#clouds] = nil
		else
			local t = elapsed/lifetime
			local size = cloud.startSize + (cloud.endSize - cloud.startSize)*t^0.5
			local height = DUST_START_HEIGHT + (0.08 - DUST_START_HEIGHT)*t
			cloud.part.Size = Vector3.new(size,0.05,size)
			cloud.part.CFrame = (cloud.placement + cloud.normal*height) * CFrame.Angles(0,cloud.spin*elapsed,0)
			if elapsed > DUST_HOLD_TIME then
				cloud.decal.Transparency = 0.1 + 0.9*((elapsed - DUST_HOLD_TIME)/DUST_FADE_TIME)
			end
		end
	end
end

local function stepChunks(now)
	local gravity = Vector3.new(0,-CHUNK_GRAVITY,0)
	for index = #chunks,1,-1 do
		local chunk = chunks[index]
		local elapsed = now - chunk.born
		local position = chunk.origin + chunk.velocity*elapsed + gravity*(0.5*elapsed*elapsed)
		if elapsed >= chunk.lifetime or (position.Y <= chunk.origin.Y and elapsed > 0.1) then
			chunk.part:Destroy()
			chunks[index] = chunks[#chunks]
			chunks[#chunks] = nil
		else
			chunk.part.CFrame = CFrame.new(position) * CFrame.Angles(chunk.spin.X*elapsed,chunk.spin.Y*elapsed,chunk.spin.Z*elapsed)
		end
	end
end

---------------------------------------------------------------- camera shake

local shake = 0

local function addShake(position,scale)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local amount = 1 - math.clamp((camera.CFrame.Position - position).Magnitude/(SHAKE_DISTANCE*scale),0,1)
	shake = math.min(shake + amount*amount*scale,1)
end

local bindName = "AbramsShake"..tostring(math.random(1,1e9))
RunService:BindToRenderStep(bindName,Enum.RenderPriority.Camera.Value + 1,function(dt)
	if shake <= 0.002 then
		shake = 0
		return
	end
	shake *= math.exp(-SHAKE_DECAY*dt)
	local camera = workspace.CurrentCamera
	if camera then
		local t = os.clock()*SHAKE_FREQUENCY
		local x,y,z = math.noise(t,0,0),math.noise(t,137.3,0),math.noise(t,291.7,0)
		local rotation = math.rad(SHAKE_ROTATION)*shake
		camera.CFrame = camera.CFrame * CFrame.new(Vector3.new(x,y,z)*SHAKE_TRANSLATION*shake) * CFrame.Angles(y*rotation,z*rotation,x*rotation)
	end
end)

---------------------------------------------------------------- events

local function impact(position,scale)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > EFFECT_DISTANCE then return end

	flash(position,LIGHT_BRIGHTNESS*scale,LIGHT_RANGE*scale)
	local surface,normal = readSurface(position)
	spawnDust(position,surface:Lerp(Color3.new(),DUST_DARKEN),normal,scale)
	addShake(position,scale)

	local burst = host(position)
	local sound = Instance.new("Sound")
	sound.SoundId = IMPACT_SOUND
	sound.Volume = IMPACT_VOLUME*math.min(scale,1.5)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = IMPACT_SOUND_DISTANCE
	sound.Parent = burst
	sound:Play()

	local attachment = Instance.new("Attachment")
	attachment.Parent = burst
	task.delay(0.04,function()
		spawnChunks(position,surface:Lerp(Color3.new(),CHUNK_DARKEN),scale)
	end)
	task.delay(0.22,function()
		if burst.Parent then
			local size = NumberRange.new(SMOKE_SIZE.Min*scale,SMOKE_SIZE.Max*scale)
			smokePuff(attachment,math.floor(SMOKE_COUNT*scale),size,SMOKE_LIFETIME,NumberRange.new(18,45),Vector2.new(50,50))
		end
	end)
	Debris:AddItem(burst,10)
end

local function muzzle(cframe)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - cframe.Position).Magnitude > EFFECT_DISTANCE then return end

	flash(cframe.Position,4,30)
	addShake(cframe.Position,1)
	local burst = host(cframe.Position)
	burst.CFrame = cframe * CFrame.Angles(-math.pi/2,0,0)
	local attachment = Instance.new("Attachment")
	attachment.Parent = burst
	smokePuff(attachment,MUZZLE_SMOKE_COUNT,MUZZLE_SMOKE_SIZE,NumberRange.new(1.5,3),NumberRange.new(10,30),Vector2.new(25,25))
	Debris:AddItem(burst,4)
end

vehicleFx.OnClientEvent:Connect(function(kind,where)
	if kind == "impact" and typeof(where) == "Vector3" then
		impact(where,1)
	elseif kind == "wreck" and typeof(where) == "Vector3" then
		impact(where,WRECK_SCALE)
	elseif kind == "muzzle" and typeof(where) == "CFrame" then
		muzzle(where)
	end
end)

local stepper = RunService.RenderStepped:Connect(function()
	if #clouds == 0 and #chunks == 0 then return end
	local now = os.clock()
	stepDust(now)
	stepChunks(now)
end)

local function cleanUp()
	stepper:Disconnect()
	RunService:UnbindFromRenderStep(bindName)
	for _,cloud in ipairs(clouds) do cloud.part:Destroy() end
	for _,chunk in ipairs(chunks) do chunk.part:Destroy() end
	table.clear(clouds)
	table.clear(chunks)
end
vehicle.Destroying:Connect(cleanUp)
vehicle.AncestryChanged:Connect(function()
	if not vehicle:IsDescendantOf(workspace) then
		cleanUp()
	end
end)

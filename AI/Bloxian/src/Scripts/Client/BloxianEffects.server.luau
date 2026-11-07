--[[
	Runs on each client (RunContext Client): draws the Bloxians' tracers, spent
	casings and the bits of ground a round kicks up. The server only works out
	where rounds go and what they hit, and tells every client about each round
	through the Remote inside this script.

	It ships disabled inside every soldier. The first soldier to load copies it
	into ReplicatedStorage, switched on, so there is one copy per server.
]]

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local remote = script:WaitForChild("Remote")

--Rounds fired further than this from the camera are not drawn.
local TRACER_DISTANCE = 1200

--Casings and kicked-up chunks further than this from the camera are not drawn,
--and at most this many casings lie around at once.
local DEBRIS_DISTANCE = 200
local MAX_CASES = 60

--Seconds a casing and a chunk last.
local CASE_LIFETIME = 2
local CHUNK_LIFETIME = 1

local folder = Instance.new("Folder")
folder.Name = "BloxianEffects"
folder.Parent = workspace

local function cameraPosition()
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

local function newTracer()
	local bullet = Instance.new("Part")
	bullet.Size = Vector3.new(0.1,0.1,0.3)
	bullet.Material = Enum.Material.SmoothPlastic
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CanQuery = false
	bullet.CanTouch = false
	bullet.CastShadow = false
	bullet.Name = "Bullet"

	local s = Instance.new("Sound")
	s.Name = "Whiz"
	s.Volume = 0.7
	s.PlaybackSpeed = 7
	s.Looped = true
	s.SoundId = "rbxasset://sounds/Rocket whoosh 01.wav"
	s.Parent = bullet

	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-0.1,-0.1,0)
	a1.Parent = bullet

	local a2 = Instance.new("Attachment")
	a2.Position = Vector3.new(0.1,0.1,0)
	a2.Parent = bullet

	local t = Instance.new("Trail")
	t.Enabled = false
	t.Attachment0 = a1
	t.Attachment1 = a2
	t.WidthScale = NumberSequence.new(1,0)
	t.Lifetime = 0.1
	t.MinLength = 1
	t.FaceCamera = true
	t.Parent = bullet
	return bullet
end

local pool = {}

local function release(bullet)
	bullet.Transparency = 1
	bullet.Whiz:Stop()
	bullet.Trail.Enabled = false
	task.delay(0.2,function()
		bullet.Parent = nil
		pool[#pool+1] = bullet
	end)
end

local function chunks(result)
	if (result.Position - cameraPosition()).Magnitude > DEBRIS_DISTANCE then return end
	local hit = result.Instance
	if hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid") then return end
	for _ = 1,math.random(2,3) do
		local chunk = Instance.new("Part")
		chunk.Color = hit.Color
		chunk.Material = hit.Material
		local size = math.random(5)/20
		chunk.Size = Vector3.new(size,size,size)
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CFrame = CFrame.new(result.Position)
		chunk.AssemblyLinearVelocity = Vector3.new(math.random(-20,20),math.random(10,20),math.random(-20,20))
		chunk.Parent = folder
		Debris:AddItem(chunk,CHUNK_LIFETIME)
	end
end

local flying = {}
local connection

local function step(dt)
	dt = math.min(dt,0.1)
	for i = #flying,1,-1 do
		local flight = flying[i]
		local bullet = flight.part
		local cframe = bullet.CFrame
		local stepLength = flight.speed*dt
		local result = workspace:Raycast(cframe.Position,cframe.LookVector*stepLength,flight.params)
		if result then
			table.remove(flying,i)
			bullet.CFrame = CFrame.new(result.Position)
			release(bullet)
			chunks(result)
		else
			flight.travelled += stepLength
			if flight.travelled > flight.range then
				table.remove(flying,i)
				release(bullet)
			else
				bullet.CFrame = cframe + cframe.LookVector*stepLength
			end
		end
	end
	if #flying == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function tracer(origin,speed,range,color,ignore)
	local camera = cameraPosition()
	local far = origin.Position + origin.LookVector*range
	if (origin.Position - camera).Magnitude > TRACER_DISTANCE and (far - camera).Magnitude > TRACER_DISTANCE then
		return
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = ignore and {folder,ignore} or {folder}

	local bullet = table.remove(pool) or newTracer()
	bullet.Color = color
	bullet.Trail.Color = ColorSequence.new(color)
	bullet.Transparency = 0
	bullet.CFrame = origin
	bullet.Parent = folder
	bullet.Trail.Enabled = true
	bullet.Whiz:Play()

	flying[#flying+1] = {part = bullet, speed = speed, range = range, travelled = 0, params = params}
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
end

local cases = {}

local function casing(at)
	if (at.Position - cameraPosition()).Magnitude > DEBRIS_DISTANCE then return end
	if #cases >= MAX_CASES then
		local oldest = table.remove(cases,1)
		oldest:Destroy()
	end

	local case = Instance.new("Part")
	case.Size = Vector3.new(0.1,0.1,0.4)
	case.Material = Enum.Material.Metal
	case.CanCollide = false
	case.CanQuery = false
	case.CanTouch = false
	case.BrickColor = BrickColor.new("New Yeller")
	local mesh = Instance.new("FileMesh")
	mesh.MeshId = "rbxassetid://5435476321"
	mesh.TextureId = "rbxassetid://5435476346"
	mesh.Scale = Vector3.new(0.1,0.1,0.1)
	mesh.Parent = case

	case.CFrame = at
	case.Parent = folder
	case.AssemblyLinearVelocity = at.RightVector*-20*Vector3.new(1,-3,1)
	cases[#cases+1] = case
	task.delay(0.05,function()
		if case.Parent then case.CanCollide = true end
	end)
	task.delay(CASE_LIFETIME,function()
		local index = table.find(cases,case)
		if index then table.remove(cases,index) end
		case:Destroy()
	end)
end

--A shot from at, heard from where it was fired, only past close studs.
local function echo(at,soundId,volume,range,close)
	if (at - cameraPosition()).Magnitude < close then return end
	local spot = Instance.new("Attachment")
	spot.Position = at
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = close
	sound.RollOffMaxDistance = range
	sound.Parent = spot
	spot.Parent = workspace.Terrain
	sound:Play()
	Debris:AddItem(spot,6)
end

remote.OnClientEvent:Connect(function(origin,speed,range,color,ignore,caseAt)
	if origin == "echo" then
		echo(speed,range,color,ignore,caseAt)
		return
	end
	tracer(origin,speed,range,color,ignore)
	if caseAt then
		casing(caseAt)
	end
end)

local clone = script.Parent:Clone()
--Respawns go back where the vehicle was placed, not straight into Workspace.
local homeParent = script.Parent.Parent

--The model ships without a PrimaryPart, which silently broke the ownership fix
--below and anything else that reads it.
if not script.Parent.PrimaryPart then
	script.Parent.PrimaryPart = script.Parent.Body.Body
end

--Who simulates the vehicle's physics. A player driving gets it, for responsive
--controls. Otherwise the server keeps it: an NPC-driven car simulated by a
--nearby player's client stutters. The wheels are separate assemblies, so every
--part is checked, not just the body.
local function claimPhysics()
	local seat = script.Parent:FindFirstChild("VehicleSeat")
	local driver = seat and seat.Occupant and game:GetService("Players"):GetPlayerFromCharacter(seat.Occupant.Parent)
	for _,part in ipairs(script.Parent:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored and part:CanSetNetworkOwnership() then
			if driver then
				if part:GetNetworkOwner() ~= driver then
					part:SetNetworkOwner(driver)
				end
			elseif part:GetNetworkOwnershipAuto() or part:GetNetworkOwner() ~= nil then
				part:SetNetworkOwner(nil)
			end
		end
	end
end
pcall(claimPhysics)

local collectionService = game:GetService("CollectionService")

--Bloxian soldiers look for vehicles with this tag to crew.
collectionService:AddTag(script.Parent,"BloxianVehicle")

local deadTexture = "rbxassetid://9784107342"

--Sounds: the turret's machine gun (played once per round by the crew) and the
--engine loop, which plays while someone is driving and rises in pitch with the
--throttle up to ENGINE_MAX_PITCH.
local MG_SOUND = "rbxassetid://80013099941453"
local ENGINE_SOUND = "rbxassetid://126994453153159"
local MG_VOLUME = 0.8
local ENGINE_VOLUME = 1
local ENGINE_MAX_PITCH = 1.4

--Destroyed: how hard it is thrown up (studs/s), how far it drifts sideways
--(studs/s) and how fast it rolls over (radians/s).
local LAUNCH_SPEED = 45
local LAUNCH_DRIFT = 12
local LAUNCH_SPIN = 5

local car = script.Parent
local seat = script.Parent.VehicleSeat
local body = car.Body.Body
local turret = script.Parent.Turret
local top = turret.Top
local barrel = turret.Barrel
local base = turret.Base
local platform = car.Chassis.Platform
local mySettings = script.Parent.Settings
local maxInactive = mySettings.MaxInactive
local respawnTime = mySettings.RespawnDelay.Value
local windshield = script.Parent.Windshield

local dead = false
local occupant = nil
local home = body.Position

local maxSteerAngle = 40
local steer = 0
local throttle = 0
local pitch = 1

local frontDoor = body.FrontDoor
local sideDoor = body.SideDoor

local shootSound = barrel:FindFirstChild("Shoot")
if shootSound then
	shootSound.SoundId = MG_SOUND
	shootSound.Volume = MG_VOLUME
end
local engineSound = Instance.new("Sound")
engineSound.Name = "EngineLoop"
engineSound.SoundId = ENGINE_SOUND
engineSound.Volume = ENGINE_VOLUME
engineSound.Looped = true
engineSound.RollOffMode = Enum.RollOffMode.InverseTapered
engineSound.RollOffMaxDistance = 250
engineSound.Parent = body

--Tells the Effects script on each client where to draw the blast when it is destroyed.
local kit = require(script.Parent:WaitForChild("VehicleKit"))

local vehicleFx = Instance.new("RemoteEvent")
vehicleFx.Name = "VehicleFx"
vehicleFx.Parent = car

for _,crewSeat in ipairs(car:GetDescendants()) do
	if crewSeat:IsA("Seat") or crewSeat:IsA("VehicleSeat") then
		local inside = nil
		crewSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local leaving = inside
			inside = crewSeat.Occupant
			if inside then
				kit.protect(inside)
			end
			if leaving and leaving ~= inside then
				--Moving seats (the gunner taking the wheel) is not leaving.
				task.delay(0.1,function()
					if not (leaving.SeatPart and leaving.SeatPart:IsDescendantOf(car)) then
						kit.unprotect(leaving)
					end
				end)
			end
		end)
	end
end
local headlights = script.Parent.Body.HeadLights
local taillights = script.Parent.Body.TailLights

local aFL = car.Chassis.Platform.AttachmentFL
local aFR = car.Chassis.Platform.AttachmentFR

local cylFR = car.Chassis.Platform.CylindricalFR
local cylFL = car.Chassis.Platform.CylindricalFL
local cylBR = car.Chassis.Platform.CylindricalBR
local cylBL = car.Chassis.Platform.CylindricalBL

local whFR = script.Parent.Body.WheelFR.PhysicalWheel
local whFL = script.Parent.Body.WheelFL.PhysicalWheel
local whBR = script.Parent.Body.WheelBR.PhysicalWheel
local whBL = script.Parent.Body.WheelBL.PhysicalWheel
local wheels = {whBL,whFL,whBR,whFR}

function verifyWheels()
	--Ensure wheels exist - ie they haven't fallen out of the workspace
	for i,obj in ipairs(script.Parent.Body:GetChildren()) do
		if string.match(obj.Name,"Wheel*") then
			if #obj:GetChildren() < 2 then
				return false
			end
		end
	end
	
	-- Don't check wheel orientation if we are upsidedown
	if math.abs(body.Orientation.Z) > 80 then
		return true
	end
	
	
	--Ensure no weird wheel glitches
	--for _,wheel in ipairs(wheels) do
	--	--Cushion of 1 just to be safe
	--	if wheel.Position.Y > platform["Attachment"..string.sub(wheel.Parent.Name,-2)].WorldPosition.Y then
	--		warn("Snapping wheel into place",wheel)
	--		wheel.CFrame = wheel.CFrame * CFrame.new(0,-10,0)
	--	end
	--end
	return true
end

function accelerate(throttleGoal)
	local throttle = throttle + (throttleGoal - throttle) * 0.01 * seat.TurnSpeed
	local torque = seat.Torque
	local speed = seat.MaxSpeed * throttle
	cylFR.MotorMaxTorque = torque
	cylBR.MotorMaxTorque = torque
	cylFL.MotorMaxTorque = torque
	cylBL.MotorMaxTorque = torque
	cylFL.AngularVelocity = speed
	cylFR.AngularVelocity = -speed
	cylBL.AngularVelocity = speed
	cylBR.AngularVelocity = -speed
end

function turn(dir)
	local steerGoal = -dir * maxSteerAngle
	steer = steer + (steerGoal - steer) * 0.01 * seat.TurnSpeed
	aFL.Orientation = Vector3.new(0,steer,-90)
	aFR.Orientation = Vector3.new(0,steer,-90)
end

function startEngine()
	occupant = seat.Occupant
	--body.Start1:Play()
	if not dead then
		engineSound:Play()
	end
	headlights.Material = Enum.Material.Neon
	taillights.Material = Enum.Material.Neon
	taillights.BrickColor = BrickColor.new("Really red")
	
	--Change engine pitch from throttle
	coroutine.wrap(function()
		while seat.Occupant do
			local throttleInput = car:GetAttribute("AIThrottle") or seat.ThrottleFloat
			local pitchGoal = 1 + math.abs(throttleInput)*(ENGINE_MAX_PITCH - 1)
			pitch = pitch + (pitchGoal - pitch) * 0.01 * 2
			engineSound.PlaybackSpeed = pitch
			task.wait()
		end
	end)()
	
	while seat.Occupant do
		--An NPC driver sets AIThrottle / AISteer: a seated NPC gives the seat no input of its own.
		local steerInput = car:GetAttribute("AISteer") or seat.SteerFloat
		local throttleInput = car:GetAttribute("AIThrottle") or seat.ThrottleFloat
		turn(steerInput)
		accelerate(throttleInput)
		if throttleInput < 0 then
			taillights.BrickColor = BrickColor.new("Institutional white")
		else
			taillights.BrickColor = BrickColor.new("Really red")
		end
		task.wait()
	end
	--body.Start2:Play()
	accelerate(0)
end

function stopEngine()
	car:SetAttribute("AIThrottle",nil)
	car:SetAttribute("AISteer",nil)
	if not body.Parent then return end --Fell out of workspace or something
	headlights.Material = Enum.Material.SmoothPlastic
	taillights.Material = Enum.Material.SmoothPlastic
	taillights.BrickColor = BrickColor.new("Maroon")
	engineSound:Stop()
	if not occupant then return end
	ejectOccupant(occupant,true)
	occupant = nil
	pitch = 1
	if math.abs(body.Orientation.Z) > 85 then
		respawn()
	end
end

--Find a place to teleport the occupant on exit that isn't blocked.
function getExitPos(occupant)
	
	local dist = (body.Position - frontDoor.WorldPosition).Magnitude
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {script.Parent,occupant.Parent}
	
	local origin = body.Position
	local dir = (frontDoor.WorldPosition-body.Position).Unit*dist
	local result = workspace:Raycast(origin,dir,params)
	if not result then
		return frontDoor.WorldCFrame
	end
	
	dir = (sideDoor.WorldPosition - body.Position).Unit*dist
	result = workspace:Raycast(origin,dir,params)
	if not result then
		return sideDoor.WorldCFrame
	end
	
	return body.CFrame + Vector3.new(0,5,0)
	
end

function ejectOccupant(occupant,instant)
	if not instant then
		task.wait(0.5)
		while occupant.Sit do
			occupant.Jump = true
			game:GetService("RunService").Heartbeat:Wait()
		end
	else
		game:GetService("RunService").Heartbeat:Wait()
	end
	--A driver who died at the wheel can be missing his root part by now.
	if not occupant.RootPart then return end
	occupant.RootPart.CFrame = getExitPos(occupant)
end

--Ensure only police use the car, force out other NPCs.
--[[
function checkOccupant(occupant)
	if collectionService:HasTag(occupant.Parent,"Police") then
		return true
	else
		ejectOccupant(occupant)
		return false
	end
end--]] -- Don't think I need this since you can't get in automatically anymore

function init()
	if seat.Occupant then
		startEngine()
	else
		stopEngine()
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(init)

function respawn()
	for _,part in ipairs(script.Parent:GetDescendants()) do
		if part:IsA("BasePart") then
			game:GetService("TweenService"):Create(part,TweenInfo.new(1),{Transparency = 1}):Play()
		end
	end
	task.wait(1)
	--One from the Vehicle Spawner is just removed, not put back.
	if not script.Parent:GetAttribute("NoRespawn") then
		clone.Parent = homeParent or workspace
	end
	script.Parent:Destroy()
end

--Running someone over. RAM_MIN_SPEED is how fast (studs/s) the car has to be
--going toward him to hurt; it then does RAM_BASE_DAMAGE plus RAM_DAMAGE per
--stud/s above that. RAM_REACH is how far past the body's sides a hit counts.
--RAM_COOLDOWN keeps one hit from counting several times.
local RAM_MIN_SPEED = 12
local RAM_REACH = 1.5
local RAM_BASE_DAMAGE = 20
local RAM_DAMAGE = 4
local RAM_COOLDOWN = 0.75

local players = game:GetService("Players")
local debris = game:GetService("Debris")
local lastRammed = setmetatable({},{__mode = "k"})

local sides = require(script.Parent:WaitForChild("Sides"))
local sideOf,sparesPlayer = sides.sideOf,sides.sparesPlayer

local function ram(driver,victim)
	local victimModel = victim.Parent
	if victim.Health <= 0 or victimModel:IsDescendantOf(car) then return end
	if victim.SeatPart and victim.SeatPart:IsDescendantOf(car) then return end
	local victimRoot = victim.RootPart
	if not victimRoot then return end
	local now = os.clock()
	if now - (lastRammed[victim] or 0) < RAM_COOLDOWN then return end

	--Never his own side, and an NPC driver spares the players it would not shoot.
	local driverModel = driver.Parent
	local driverSide = sideOf(driverModel)
	if driverSide and driverSide == sideOf(victimModel) then return end
	local driverPlayer = players:GetPlayerFromCharacter(driverModel)
	local victimPlayer = players:GetPlayerFromCharacter(victimModel)
	if not driverPlayer and victimPlayer and sparesPlayer(driverModel,driverSide,victimPlayer) then return end

	local offset = victimRoot.Position - body.Position
	offset = Vector3.new(offset.X,0,offset.Z)
	if offset.Magnitude < 0.1 then return end
	--The car's own speed toward him, so running away from it does not save him.
	local closing = body.AssemblyLinearVelocity:Dot(offset.Unit)
	if closing < RAM_MIN_SPEED then return end
	lastRammed[victim] = now

	--Kill credit for a player driver, the way Roblox weapons tag it.
	if driverPlayer then
		local creator = Instance.new("ObjectValue")
		creator.Name = "creator"
		creator.Value = driverPlayer
		creator.Parent = victim
		debris:AddItem(creator,2)
	end
	victim:TakeDamage(RAM_BASE_DAMAGE + (closing - RAM_MIN_SPEED)*RAM_DAMAGE)
	--An NPC driver watches this to know he got one.
	if victim.Health <= 0 then
		car:SetAttribute("Roadkills",(car:GetAttribute("Roadkills") or 0) + 1)
	end
end

--Checked every frame rather than on Touched: Touched fires once when the car
--starts pushing someone, before it has the speed to hurt him.
local ramParams = OverlapParams.new()
ramParams.FilterType = Enum.RaycastFilterType.Exclude
ramParams.FilterDescendantsInstances = {car}
local ramPadding = Vector3.new(RAM_REACH*2,0,RAM_REACH*2)
game:GetService("RunService").Heartbeat:Connect(function()
	local driver = seat.Occupant
	if dead or not driver or not body.Parent then return end
	if body.AssemblyLinearVelocity.Magnitude < RAM_MIN_SPEED then return end
	local seen = {}
	for _,part in ipairs(workspace:GetPartBoundsInBox(body.CFrame,body.Size + ramPadding,ramParams)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local victim = model and model:FindFirstChildOfClass("Humanoid")
		if victim and not seen[victim] then
			seen[victim] = true
			ram(driver,victim)
		end
	end
end)

stopEngine()

--Inactive Respawn
local inactiveTimer = script.Parent.Settings.MaxInactive.Value
local timeTagged = 0
while true do
	--Ensure we still exist in the workspace, ie havent fallen out of the map
	if not body.Parent then
		pcall(respawn)
	elseif not verifyWheels() then
		if not seat.Occupant then
			pcall(respawn)
		end
	end
	
	local driver = script.Parent:GetAttribute("Driver")
	local gunner = script.Parent:GetAttribute("Gunner")
	if body.AssemblyLinearVelocity.Magnitude < 3 and not driver and not gunner and (body.Position-home).Magnitude > 20 then
		inactiveTimer = inactiveTimer - 1
		if inactiveTimer <= 0 then
			respawn()
			break
		end
	else
		inactiveTimer = maxInactive.Value
	end
	
	pcall(claimPhysics)

	--Ensure we aren't tagged for too long
	if collectionService:HasTag(script.Parent,"Occupied") then
		timeTagged = timeTagged + 1
		if timeTagged > 10 then
			collectionService:RemoveTag(script.Parent,"Occupied")
		end
	else
		timeTagged = 0
	end
	
	if script.Parent.Humanoid.Health <= 0 and not dead then
		dead = true
		engineSound:Stop()
		script.Parent.Body.Body.Engine.Smoke.Enabled = true
		script.Parent.Body.Body.Engine.Pop:Play()
		body.TextureID = deadTexture
		top.TextureID = deadTexture
		base.TextureID = deadTexture
		barrel.TextureID = deadTexture
		top.TopToBaseHinge:Destroy()
		top.CanCollide = true
		barrel.CanCollide = true
		
		body.Explosion:Play()

		--Nobody inside lives through it, and the bodies come out of their seats.
		for _,part in ipairs(car:GetDescendants()) do
			if (part:IsA("Seat") or part:IsA("VehicleSeat")) and part.Occupant then
				kit.unprotect(part.Occupant)
				part.Occupant.Health = 0
				local weld = part:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
			end
		end

		--Drawn by Effects on each client. Not an Explosion, which would crater terrain.
		vehicleFx:FireAllClients("wreck",body.Position)

		--Thrown up and over.
		pcall(claimPhysics)
		local drift = Vector3.new(math.random() - 0.5,0,math.random() - 0.5)*2*LAUNCH_DRIFT
		body.AssemblyLinearVelocity += Vector3.new(0,LAUNCH_SPEED,0) + drift
		body.AssemblyAngularVelocity += body.CFrame.LookVector*(math.random() < 0.5 and -LAUNCH_SPIN or LAUNCH_SPIN)

		local fire = Instance.new("Fire")
		fire.Size = 9
		fire.Heat = 18
		fire.Parent = body
		local smoke = Instance.new("Smoke")
		smoke.Size = 8
		smoke.RiseVelocity = 9
		smoke.Opacity = 0.6
		smoke.Color = Color3.fromRGB(35,35,35)
		smoke.Parent = body

		windshield.Material = Enum.Material.CorrodedMetal
		
		for i,v in ipairs(platform:GetChildren()) do
			if v:IsA("CylindricalConstraint") or v:IsA("SpringConstraint") then
				v.Enabled = false
			end
		end
		
		for i,v in ipairs(script.Parent.Body:GetDescendants()) do
			if v:IsA("CylindricalConstraint") then
				v.Enabled = false
			end
		end
		
		task.wait(respawnTime)
		respawn()
		break
	end
	
	
	task.wait(1)
end
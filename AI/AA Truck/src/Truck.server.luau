--[[
	Anti-air truck (a BM-21 Grad carrying surface-to-air rockets) that Bloxians
	crew and players can drive.

	The model is static meshes, so this rigs it when the server starts: the body
	is welded to Hull, and the launcher (TurretRing, Trunnion) is fixed to it,
	tubes pointing up over the cab; each wheel hangs on a motor the Wheels
	script spins on each client. The hull is moved by script through rigid
	constraints, the same way as the Abrams.

	Driving: the AIThrottle / AISteer attributes (a Bloxian driver), or the
	VehicleSeat's own input (a player driver). It turns like a truck: only while
	rolling.
	Launcher: it never turns. Whenever someone sits at it (Seat), it fires homing
	rockets at the nearest enemy aircraft in sight and in range (a Phantom, an
	AC-130 or an Apache); they leave the way the tubes point and steer round
	onto it. It never fires at anything on the ground. The
	aircraft get MissileInbound like any missile, and throw flares at them.
	Support: the Bloxian driver keeps with his infantry instead of charging the
	enemy.
]]

local clone = script.Parent:Clone()
--Respawns go back where the truck was placed, not straight into Workspace.
local homeParent = script.Parent.Parent

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local debris = game:GetService("Debris")
local collectionService = game:GetService("CollectionService")

--Driving: top speed forward and in reverse (studs/s), how fast it gets there
--(studs/s gained each second), turn rate at full lock (degrees/s), and the
--speed below which it turns less (a truck cannot turn standing still).
local MAX_SPEED = 20
local MAX_REVERSE = 8
local ACCELERATION = 8
local TURN_RATE = 40
local TURN_FULL_SPEED = 8

--Bumps lower than this (studs) are driven over; anything taller stops it.
local STEP_HEIGHT = 1.5

--How quickly the hull settles onto the slope under it. Higher is snappier.
local SETTLE = 8

--Targets: how far it reaches and the closest it fires (studs), how often it
--looks again (seconds), and the most of its rockets in the air at one target.
local AA_RANGE = 2500
local AA_MIN_RANGE = 80
local SCAN_INTERVAL = 0.25
local MAX_INBOUND = 2

--Firing: rockets in the tubes (a Grad has 40), rockets per salvo and the gap
--between them, seconds between salvos, and seconds to reload once they are
--all gone.
local ROCKETS = 40
local SALVO = 2
local SALVO_GAP = 0.3
local SALVO_INTERVAL = 4
local RELOAD_TIME = 30

--Rockets: speed (studs/s), turn (degrees/s: enough to come round onto an
--aircraft behind the truck), seconds flying straight out of the tubes before
--they steer, how close counts as a hit, seconds before one that
--misses bursts on its own, and damage to a plane's AirHealth (a Phantom has
--200, an AC-130 600) and to a helicopter (an Apache has 1500).
local ROCKET_SPEED = 450
local ROCKET_TURN = 160
local ROCKET_BOOST = 0.3
local ROCKET_HIT = 25
local ROCKET_LIFE = 9
local ROCKET_PLANE_DAMAGE = 187.5
local ROCKET_HELI_DAMAGE = 1200

--Flares, the same ones the Phantom's missiles meet, are the shared AirDefense module.

--How big a rocket's burst is next to a shell's impact (Random Arty's ArtilleryBlast).
local ROCKET_BLAST_SCALE = 0.6

--Sounds: each rocket's launch (the Javelin's) and the engine loop (pitched with
--speed while someone drives).
local LAUNCH_SOUND = "rbxassetid://112204190873336"
local ENGINE_SOUND = "rbxassetid://17485939810"
local LAUNCH_VOLUME = 2
local ENGINE_VOLUME = 1
local ENGINE_PITCH = {1.1, 1.5}

--Crushing. CRUSH_MIN_SPEED is how fast (studs/s) the truck has to be going
--toward someone to hurt him; it then does CRUSH_BASE_DAMAGE plus CRUSH_DAMAGE
--per stud/s above that. CRUSH_COOLDOWN keeps one hit from counting several times.
local CRUSH_MIN_SPEED = 6
local CRUSH_BASE_DAMAGE = 30
local CRUSH_DAMAGE = 6
local CRUSH_COOLDOWN = 0.75

--Going up: the blast's radius, damage at its centre and edge, and damage to
--other vehicles in it.
local WRECK_RADIUS = 25
local WRECK_DAMAGE = 120
local WRECK_EDGE_DAMAGE = 20
local WRECK_VEHICLE_DAMAGE = 200

local sides = require(script.Parent:WaitForChild("Sides"))
local airDefense = require(script.Parent:WaitForChild("AirDefense"))
local kit = require(script.Parent:WaitForChild("VehicleKit"))
local FRIENDLY = sides.FRIENDLY
local JET_TAG = sides.JET_TAG
local GUNSHIP_TAG = sides.GUNSHIP_TAG
local AIR_TAGS = sides.AIR_TAGS

local truck = script.Parent
local mesh = truck.Mesh
local hull = truck.Hull
local turretRing = truck.TurretRing
local trunnion = truck.Trunnion
local driverSeat = truck.VehicleSeat
local gunnerSeat = truck.Seat
local humanoid = truck.Humanoid
local mySettings = truck.Settings
local launchPoint = trunnion.Launch

---------------------------------------------------------------- rigging

local function weldTo(base,part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
	part.Anchored = false
	part.Massless = true
end

local turretModel = mesh.Turret
local launcherModel = turretModel.Launcher

--Each wheel's hub hangs on a motor the Wheels script spins on each client.
for _,wheel in ipairs(mesh.Wheels:GetChildren()) do
	local hub = wheel:FindFirstChild("Hub")
	if hub then
		local motor = Instance.new("Motor6D")
		motor.Name = "WheelMotor"
		motor.Part0 = hull
		motor.Part1 = hub
		motor.C0 = hull.CFrame:ToObjectSpace(hub.CFrame)
		motor.Parent = hub
		hub.Anchored = false
		hub.Massless = true
		for _,part in ipairs(wheel:GetChildren()) do
			if part:IsA("BasePart") and part ~= hub then
				weldTo(hub,part)
				part.CanCollide = false
			end
		end
	end
end

for _,part in ipairs(mesh:GetDescendants()) do
	if part:IsA("BasePart") and part.Anchored and part.Name ~= "Hub" then
		if part:IsDescendantOf(launcherModel) then
			weldTo(trunnion,part)
		elseif part:IsDescendantOf(turretModel) then
			weldTo(turretRing,part)
		elseif not part:IsDescendantOf(mesh.Wheels) then
			weldTo(hull,part)
		end
	end
end
weldTo(hull,driverSeat)
weldTo(hull,gunnerSeat)

--The launcher is fixed to the truck; this weld only lets go when it is blown off.
weldTo(turretRing,trunnion)
local launcherMount = Instance.new("WeldConstraint")
launcherMount.Name = "LauncherMount"
launcherMount.Part0 = hull
launcherMount.Part1 = turretRing
launcherMount.Parent = turretRing
turretRing.Anchored = false
turretRing.Massless = true

--The hull is held by rigid constraints the script moves every frame, so it
--stays physics-simulated (smooth for players watching) without wheels.
local anchor = Instance.new("Attachment")
anchor.Name = "DriveAnchor"
anchor.Parent = hull
local alignPosition = Instance.new("AlignPosition")
alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
alignPosition.Attachment0 = anchor
alignPosition.RigidityEnabled = true
alignPosition.Position = hull.Position
alignPosition.Parent = hull
local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.Attachment0 = anchor
alignOrientation.RigidityEnabled = true
alignOrientation.CFrame = hull.CFrame.Rotation
alignOrientation.Parent = hull

hull.Massless = false
hull.Anchored = false
truck.PrimaryPart = hull

humanoid.BreakJointsOnDeath = false
humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
humanoid.MaxHealth = mySettings.Health.Value
humanoid.Health = humanoid.MaxHealth

local function newSound(name,id,volume,parent,maxDistance)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = parent
	return sound
end

local launchSound = newSound("Launch",LAUNCH_SOUND,LAUNCH_VOLUME,trunnion,1200)
local engineSound = newSound("Engine",ENGINE_SOUND,ENGINE_VOLUME,hull,300)
engineSound.Looped = true

--Tells the Effects script on each client where to draw a launch flash or a blast.
local vehicleFx = Instance.new("RemoteEvent")
vehicleFx.Name = "VehicleFx"
vehicleFx.Parent = truck

truck:SetAttribute("Speed",0)
truck:SetAttribute("Rolling",0)
truck:SetAttribute("Rockets",ROCKETS)
collectionService:AddTag(truck,"BloxianVehicle")
--The Wheels script on each client waits for this before looking for the wheel motors.
truck:SetAttribute("Rigged",true)

--The server simulates the truck. A VehicleSeat hands its driver ownership on
--its own, so this is taken back whenever someone gets in, and every second.
local function claimPhysics()
	if hull:CanSetNetworkOwnership() and hull:GetNetworkOwner() ~= nil then
		hull:SetNetworkOwner(nil)
	end
end
pcall(claimPhysics)
driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
	pcall(claimPhysics)
end)

---------------------------------------------------------------- getting in and out

--How close a player has to be to a door for its prompt, and how long to hold it.
local PROMPT_DISTANCE = 12
local PROMPT_HOLD = 0.25

local seats = {
	{seat = driverSeat, door = hull.FrontDoor, action = "Drive"},
	{seat = gunnerSeat, door = hull.SideDoor, action = "Run the launcher"},
}

--Both seats sit inside the cab, where nobody can walk up to them. Players get
--in through a prompt at each door, and anyone leaving is put down outside it.
for _,entry in ipairs(seats) do
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = entry.action
	prompt.ObjectText = "AA Truck"
	prompt.HoldDuration = PROMPT_HOLD
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = entry.door

	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local human = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid.Health <= 0 or not human or human.Health <= 0 or human.SeatPart or entry.seat.Occupant then return end
		entry.seat:Sit(human)
	end)

	local inside = nil
	entry.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		prompt.Enabled = entry.seat.Occupant == nil
		local leaving = inside
		inside = entry.seat.Occupant
		if inside then
			kit.protect(inside)
		end
		if not leaving or leaving == inside then return end
		--Moving seats (the gunner taking the wheel) is not leaving.
		task.delay(0.1,function()
			if leaving.SeatPart and leaving.SeatPart:IsDescendantOf(truck) then return end
			kit.unprotect(leaving)
			local root = leaving.RootPart
			if leaving.SeatPart or not root or not root.Parent then return end
			local door = entry.door.WorldPosition
			local outward = Vector3.new(door.X - hull.Position.X,0,door.Z - hull.Position.Z)
			outward = outward.Magnitude > 0.1 and outward.Unit or Vector3.zero
			root.CFrame = CFrame.new(door + outward*2 + Vector3.new(0,3,0))
		end)
	end)
end

---------------------------------------------------------------- sides

--The side the launcher fights for: whoever sits at it. A Bloxian's blank team
--is Hostile; a player is on his Roblox team, else Friendly.
local function gunnerSide()
	local occupant = gunnerSeat.Occupant
	local gunner = occupant and occupant.Health > 0 and occupant.Parent
	if not gunner then return nil end
	local player = players:GetPlayerFromCharacter(gunner)
	if player then
		return not player.Neutral and player.Team and player.Team.Name or FRIENDLY
	end
	return sides.npcSide(gunner)
end

local airKind = sides.airKind
local enemyAircraft = sides.enemyAircraft
local hurtAircraft = airDefense.hurtAircraft

---------------------------------------------------------------- rockets

local plainPart,addTrail = airDefense.plainPart,airDefense.addTrail

--One rocket off the rails at target, steering for it once clear. The target
--knows it is coming (MissileInbound) and may throw flares, which can pull it off.
local function launchRocket(target)
	local launch = launchPoint.WorldCFrame
	local spread = launch.RightVector*(math.random() - 0.5)*3 + launch.UpVector*(math.random() - 0.5)*2
	local rocket = plainPart("AARocket",Vector3.new(0.6,0.6,4),Color3.fromRGB(205,210,200),Enum.Material.Metal)
	rocket.CFrame = CFrame.lookAt(launch.Position + spread,launch.Position + spread + launch.LookVector)
	addTrail(rocket,Color3.fromRGB(230,230,225),1.4,0.7)
	local flame = Instance.new("PointLight")
	flame.Color = Color3.fromRGB(255,170,80)
	flame.Range = 12
	flame.Brightness = 3
	flame.Parent = rocket
	rocket.Parent = workspace
	debris:AddItem(rocket,ROCKET_LIFE + 1)

	local bang = launchSound:Clone()
	bang.Parent = trunnion
	bang:Play()
	debris:AddItem(bang,6)
	vehicleFx:FireAllClients("muzzle",CFrame.lookAt(rocket.Position,rocket.Position + launch.LookVector))

	target:SetAttribute("MissileInbound",(target:GetAttribute("MissileInbound") or 0) + 1)
	--The count above only comes back down from this script: past this, readers ignore it.
	target:SetAttribute("MissileInboundUntil",math.max(target:GetAttribute("MissileInboundUntil") or 0,workspace:GetServerTimeNow() + ROCKET_LIFE + 1))
	target:SetAttribute("ThreatAt",launch.Position)
	airDefense.velocityOf(target)
	local chasing = nil --a chaff cloud it was pulled onto
	local flareChecked = false
	local forward = launch.LookVector
	local born = os.clock()

	local connection
	local function finish()
		connection:Disconnect()
		rocket:Destroy()
		if target.Parent then
			target:SetAttribute("MissileInbound",math.max((target:GetAttribute("MissileInbound") or 1) - 1,0))
		end
	end
	connection = runService.Heartbeat:Connect(function(dt)
		local age = os.clock() - born
		local goal = nil
		if chasing then
			goal = chasing.Parent and chasing.Position
		elseif target.Parent and target.PrimaryPart and not target:GetAttribute("ShotDown") then
			goal = target.PrimaryPart.Position
		end
		if goal and age > ROCKET_BOOST then
			local toGoal = goal - rocket.Position
			if not chasing and not flareChecked and toGoal.Magnitude < airDefense.FLARE_RANGE then
				flareChecked = true
				chasing = airDefense.decoy(target,rocket.Position,"radar")
			end
			--Through the flares: it goes off on one instead of the aircraft.
			if airDefense.touchedFlare(target,rocket.Position,"radar") then
				kit.blastFx(rocket.Position,ROCKET_BLAST_SCALE)
				finish()
				return
			end
			if toGoal.Magnitude < ROCKET_HIT then
				if not chasing then
					hurtAircraft(target,ROCKET_PLANE_DAMAGE,ROCKET_HELI_DAMAGE)
				end
				kit.blastFx(rocket.Position,ROCKET_BLAST_SCALE)
				finish()
				return
			end
			local angle = math.acos(math.clamp(forward:Dot(toGoal.Unit),-1,1))
			local turn = math.min(math.rad(ROCKET_TURN)*dt,angle)
			local axis = forward:Cross(toGoal.Unit)
			if angle > 1e-3 and axis.Magnitude > 1e-4 then
				forward = CFrame.fromAxisAngle(axis.Unit,turn):VectorToWorldSpace(forward)
			end
		end
		local position = rocket.Position + forward*ROCKET_SPEED*dt
		rocket.CFrame = CFrame.lookAt(position,position + forward)
		if age > ROCKET_LIFE then
			kit.blastFx(position,ROCKET_BLAST_SCALE)
			finish()
		end
	end)
end

---------------------------------------------------------------- the launcher

local dead = false
local target = nil
local rocketsLeft = ROCKETS
local nextSalvo = 0
local reloading = false

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude

local function crew()
	local list = {truck}
	for _,seat in ipairs({driverSeat,gunnerSeat}) do
		if seat.Occupant then
			list[#list+1] = seat.Occupant.Parent
		end
	end
	return list
end

--In range, and nothing solid between the tubes and it.
local function canEngage(craft)
	local from = launchPoint.WorldPosition
	local offset = craft.PrimaryPart.Position - from
	local dist = offset.Magnitude
	if dist > AA_RANGE or dist < AA_MIN_RANGE then return false end
	sightParams.FilterDescendantsInstances = crew()
	local result = workspace:Raycast(from,offset,sightParams)
	return result == nil or result.Instance:IsDescendantOf(craft)
end

--The nearest enemy aircraft the launcher can engage, or nil.
local function findAircraft(side)
	local best,bestDist = nil,math.huge
	for _,tag in ipairs(AIR_TAGS) do
		for _,craft in ipairs(collectionService:GetTagged(tag)) do
			if enemyAircraft(craft,side) and canEngage(craft) then
				local dist = (craft.PrimaryPart.Position - hull.Position).Magnitude
				if dist < bestDist then
					best,bestDist = craft,dist
				end
			end
		end
	end
	return best
end

local function salvo(craft)
	for shot = 1,math.min(SALVO,rocketsLeft) do
		if dead or not craft.Parent then break end
		rocketsLeft -= 1
		truck:SetAttribute("Rockets",rocketsLeft)
		launchRocket(craft)
		if shot < SALVO then
			task.wait(SALVO_GAP)
		end
	end
	if rocketsLeft <= 0 and not reloading then
		reloading = true
		truck:SetAttribute("Reloading",true)
		task.delay(RELOAD_TIME,function()
			reloading = false
			rocketsLeft = ROCKETS
			if truck.Parent and not dead then
				truck:SetAttribute("Rockets",rocketsLeft)
				truck:SetAttribute("Reloading",nil)
			end
		end)
	end
end

--What the spawner's tracker shows.
local function setStatus(text)
	if truck:GetAttribute("Status") ~= text then
		truck:SetAttribute("Status",text)
	end
end

task.spawn(function()
	while truck.Parent and not dead do
		local side = gunnerSide()
		if not side then
			setStatus("No gunner")
		elseif reloading then
			setStatus("Reloading")
		elseif target then
			setStatus("Engaging "..(airKind(target) == JET_TAG and "F-4" or airKind(target) == GUNSHIP_TAG and "AC-130" or "Apache"))
		else
			setStatus("Scanning")
		end
		if not side then
			target = nil
		elseif not (target and enemyAircraft(target,side) and canEngage(target)) then
			target = findAircraft(side)
		end
		if target then
			truck:SetAttribute("AATarget",target.Name)
			local inbound = workspace:GetServerTimeNow() < (target:GetAttribute("MissileInboundUntil") or 0)
				and target:GetAttribute("MissileInbound") or 0
			if rocketsLeft > 0 and os.clock() >= nextSalvo and inbound < MAX_INBOUND then
				nextSalvo = os.clock() + SALVO_INTERVAL
				task.spawn(salvo,target)
			end
		else
			truck:SetAttribute("AATarget",nil)
		end
		task.wait(SCAN_INTERVAL)
	end
end)

---------------------------------------------------------------- driving

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.FilterDescendantsInstances = {truck}

--People do not hold the truck up or stop it: a cast that hits one ignores him and tries again.
local function cast(fn)
	for _ = 1,4 do
		local result = fn()
		if not result then return nil end
		local person = kit.personOf(truck,result.Instance)
		if not person then return result end
		castParams:AddToFilter(person.Parent)
	end
	return nil
end

local function refreshFilter()
	castParams.FilterDescendantsInstances = crew()
end

local function flat(v)
	return Vector3.new(v.X,0,v.Z)
end

local rideHeight = hull.Size.Y/2 + 0.2
local halfWidth = hull.Size.X/2 - 1
local halfLength = hull.Size.Z/2 - 2

local function groundUnder(point,bottom)
	local result = cast(function()
		return workspace:Raycast(Vector3.new(point.X,bottom + STEP_HEIGHT + 1,point.Z),Vector3.new(0,-(STEP_HEIGHT + 31),0),castParams)
	end)
	return result and result.Position
end

local function blocked(cf,move)
	local boxSize = Vector3.new(hull.Size.X - 1,hull.Size.Y - STEP_HEIGHT,hull.Size.Z - 1)
	local boxCFrame = cf * CFrame.new(0,STEP_HEIGHT/2,0)
	local direction = move + move.Unit*0.5
	return cast(function()
		return workspace:Blockcast(boxCFrame,boxSize,direction,castParams)
	end) ~= nil
end

local speed = 0
local fallSpeed = 0
local position = hull.Position
local up = hull.CFrame.UpVector
local heading = flat(hull.CFrame.LookVector).Unit
local velocity = Vector3.zero
local lastCrushed = setmetatable({},{__mode = "k"})
local crushParams = OverlapParams.new()
crushParams.FilterType = Enum.RaycastFilterType.Exclude
crushParams.FilterDescendantsInstances = {truck}

local function drive(dt)
	local throttle,steer = 0,0
	if not dead and driverSeat.Occupant then
		throttle = truck:GetAttribute("AIThrottle") or driverSeat.ThrottleFloat
		steer = truck:GetAttribute("AISteer") or driverSeat.SteerFloat
	end
	local goalSpeed = throttle >= 0 and throttle*MAX_SPEED or throttle*MAX_REVERSE
	speed += math.clamp(goalSpeed - speed,-ACCELERATION*dt,ACCELERATION*dt)

	--Wheels steer: it turns with its speed, and the other way backing up.
	local rolling = math.clamp(speed/TURN_FULL_SPEED,-1,1)
	heading = CFrame.fromAxisAngle(Vector3.yAxis,-steer*rolling*math.rad(TURN_RATE)*dt) * heading
	local move = heading*speed*dt
	local tilted = CFrame.fromMatrix(position,heading:Cross(up).Unit,up)
	if move.Magnitude > 0.01 and blocked(tilted,move) then
		speed = 0
		move = Vector3.zero
	end
	local newPosition = position + move

	--Settle onto the ground under the four corners.
	local bottom = position.Y - rideHeight
	local corners = {}
	for _,offset in ipairs({Vector3.new(-halfWidth,0,-halfLength),Vector3.new(halfWidth,0,-halfLength),Vector3.new(-halfWidth,0,halfLength),Vector3.new(halfWidth,0,halfLength)}) do
		corners[#corners+1] = groundUnder(CFrame.lookAt(newPosition,newPosition + heading) * offset,bottom) or false
	end
	local fl,fr,bl,br = corners[1],corners[2],corners[3],corners[4]
	if fl and fr and bl and br then
		local front,back = (fl + fr)/2,(bl + br)/2
		local left,right = (fl + bl)/2,(fr + br)/2
		local groundUp = (right - left):Cross(front - back).Unit
		local groundY = (fl.Y + fr.Y + bl.Y + br.Y)/4 + rideHeight
		if newPosition.Y > groundY + 0.3 then
			fallSpeed += workspace.Gravity*dt
			newPosition = Vector3.new(newPosition.X,math.max(newPosition.Y - fallSpeed*dt,groundY),newPosition.Z)
		else
			fallSpeed = 0
			newPosition = Vector3.new(newPosition.X,newPosition.Y + (groundY - newPosition.Y)*math.min(1,SETTLE*dt*2),newPosition.Z)
		end
		up = up:Lerp(groundUp,math.min(1,SETTLE*dt)).Unit
	else
		--Off an edge: drop.
		fallSpeed += workspace.Gravity*dt
		newPosition -= Vector3.new(0,fallSpeed*dt,0)
	end

	velocity = (newPosition - position)/dt
	position = newPosition
	local right = heading:Cross(up).Unit
	alignPosition.Position = position
	alignOrientation.CFrame = CFrame.fromMatrix(Vector3.zero,right,up)

	local moving = flat(velocity).Magnitude
	if math.abs(moving - (truck:GetAttribute("Speed") or 0)) > 0.5 then
		truck:SetAttribute("Speed",moving)
	end
	local signed = moving*math.sign(speed)
	if math.abs(signed - (truck:GetAttribute("Rolling") or 0)) > 0.5 then
		truck:SetAttribute("Rolling",signed)
	end

	local engineOn = not dead and driverSeat.Occupant ~= nil
	if engineOn and not engineSound.IsPlaying then
		engineSound:Play()
	elseif not engineOn and engineSound.IsPlaying then
		engineSound:Stop()
	end
	if engineOn then
		local enginePitch = ENGINE_PITCH[1] + (ENGINE_PITCH[2] - ENGINE_PITCH[1])*math.min(moving/MAX_SPEED,1)
		if math.abs(engineSound.PlaybackSpeed - enginePitch) > 0.02 then
			engineSound.PlaybackSpeed = enginePitch
		end
	end
end

local function crush()
	local driver = driverSeat.Occupant
	if not driver or flat(velocity).Magnitude < CRUSH_MIN_SPEED then return end
	local now = os.clock()
	local seen = {}
	for _,part in ipairs(workspace:GetPartBoundsInBox(hull.CFrame,hull.Size + Vector3.new(2,0,2),crushParams)) do
		local victim = kit.personOf(truck,part)
		if victim and not seen[victim] then
			seen[victim] = true
			local offset = flat(victim.RootPart.Position - hull.Position)
			local closing = offset.Magnitude > 0.1 and velocity:Dot(offset.Unit) or 0
			if closing >= CRUSH_MIN_SPEED and now - (lastCrushed[victim] or 0) > CRUSH_COOLDOWN and kit.canHurt(truck,driver.Parent,victim) then
				lastCrushed[victim] = now
				kit.hurt(truck,driver.Parent,victim,CRUSH_BASE_DAMAGE + (closing - CRUSH_MIN_SPEED)*CRUSH_DAMAGE,"Roadkills")
			end
		end
	end
end

---------------------------------------------------------------- dying

local function respawn()
	--One from the Vehicle Spawner is just removed, not put back.
	if not truck:GetAttribute("NoRespawn") then
		clone.Parent = homeParent or workspace
	end
	truck:Destroy()
end

--Its own blast going up hurts everyone near it, and any vehicle.
local function wreckBlast(at)
	local damaged = {}
	for _,part in ipairs(workspace:GetPartBoundsInRadius(at,WRECK_RADIUS)) do
		local victim = kit.personOf(truck,part)
		if victim and not damaged[victim] then
			damaged[victim] = true
			if kit.canHurt(truck,nil,victim) then
				local share = math.clamp((victim.RootPart.Position - at).Magnitude/WRECK_RADIUS,0,1)
				kit.hurt(truck,nil,victim,WRECK_DAMAGE + (WRECK_EDGE_DAMAGE - WRECK_DAMAGE)*share)
			end
		end
		local car = not victim and kit.vehicleOf(truck,part)
		if car and not damaged[car] then
			damaged[car] = true
			local carHuman = car:FindFirstChildOfClass("Humanoid")
			if carHuman and carHuman.Health > 0 then
				carHuman:TakeDamage(WRECK_VEHICLE_DAMAGE)
			end
		end
	end
	vehicleFx:FireAllClients("wreck",at)
end

--Destroyed: how hard the launcher is thrown off (studs/s up, studs/s sideways,
--spin), the colour the wreck is charred to, when the rockets left in the tubes
--cook off after the first blast (seconds), and how long the wreck takes to fade
--out at the end.
local LAUNCHER_TOSS_SPEED = 55
local LAUNCHER_TOSS_DRIFT = 25
local LAUNCHER_TOSS_SPIN = 5
local WRECK_COLOR = Color3.fromRGB(60,55,50)
local COOK_OFF_TIMES = {0.8, 1.6, 2.5, 3.6}
local FADE_TIME = 1

local function burn(part,size)
	local fire = Instance.new("Fire")
	fire.Size = size
	fire.Heat = 20
	fire.Parent = part
	local smoke = Instance.new("Smoke")
	smoke.Size = size
	smoke.RiseVelocity = 10
	smoke.Opacity = 0.6
	smoke.Color = Color3.fromRGB(35,35,35)
	smoke.Parent = part
end

local function tossLauncher()
	launcherMount:Destroy()
	turretRing.Massless = false
	runService.Heartbeat:Wait()
	if not turretRing.Parent then return end
	pcall(turretRing.SetNetworkOwner,turretRing,nil)
	local drift = Vector3.new(math.random() - 0.5,0,math.random() - 0.5)*2*LAUNCHER_TOSS_DRIFT
	turretRing.AssemblyLinearVelocity = Vector3.new(0,LAUNCHER_TOSS_SPEED,0) + drift
	turretRing.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5,math.random() - 0.5,math.random() - 0.5)*2*LAUNCHER_TOSS_SPIN
end

local function char()
	for _,part in ipairs(mesh:GetDescendants()) do
		if part:IsA("SurfaceAppearance") then
			pcall(function()
				part.Color = WRECK_COLOR
			end)
		elseif part:IsA("BasePart") and part.Transparency < 1 then
			part.Color = WRECK_COLOR
			if part:IsA("MeshPart") then
				pcall(function()
					part.TextureID = ""
				end)
			end
		end
	end
end

local function fadeOut()
	local info = TweenInfo.new(FADE_TIME)
	for _,part in ipairs(truck:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			game:GetService("TweenService"):Create(part,info,{Transparency = 1}):Play()
		end
	end
	task.wait(FADE_TIME)
end

local function destroyed()
	if dead then return end
	dead = true
	truck:SetAttribute("Wrecked",true)
	truck:SetAttribute("AATarget",nil)

	--Nobody inside lives through it.
	for _,seat in ipairs({driverSeat,gunnerSeat}) do
		if seat.Occupant then
			kit.unprotect(seat.Occupant)
			seat.Occupant.Health = 0
		end
	end

	wreckBlast(hull.Position)
	char()
	burn(hull,14)
	task.spawn(tossLauncher)

	--The bodies come out of their seats a moment later.
	task.delay(0.1,function()
		for _,seat in ipairs({driverSeat,gunnerSeat}) do
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
		end
	end)

	if rocketsLeft > 0 then
		for _,delay in ipairs(COOK_OFF_TIMES) do
			task.delay(delay,function()
				if hull.Parent then
					vehicleFx:FireAllClients("impact",hull.Position + Vector3.new(math.random(-6,6),4,math.random(-12,12)))
				end
			end)
		end
	end

	task.wait(mySettings.RespawnDelay.Value)
	fadeOut()
	respawn()
end

--Watched on health, not Died: a Humanoid with no body has no state machine to
--die with, so Died never fires for it.
humanoid.HealthChanged:Connect(function(health)
	if health <= 0 then
		destroyed()
	end
end)
humanoid.Died:Connect(destroyed)

---------------------------------------------------------------- loop

runService.Heartbeat:Connect(function(dt)
	if not hull.Parent then return end
	drive(dt)
	if not dead then
		crush()
	end
	if position.Y < workspace.FallenPartsDestroyHeight + 20 and not dead then
		dead = true
		respawn()
	end
end)

while truck.Parent do
	pcall(claimPhysics)
	refreshFilter()
	task.wait(1)
end

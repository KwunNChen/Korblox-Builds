--[[
	M1 Abrams that Bloxians crew and players can drive.

	The model is a static mesh, so this rigs it when the server starts: hull
	meshes are welded to Hull, the turret to TurretRing (which traverses) and the
	gun to Trunnion (which elevates). The hull is moved by script through rigid
	constraints rather than by wheels: it follows the ground, stops at walls and
	crushes anyone it drives into.

	Driving: the AIThrottle / AISteer attributes (a Bloxian driver), or the
	VehicleSeat's own input (a player driver).
	Turret: follows the AimPoint attribute.
	Main gun: FireMain:Fire(shooter) sends a high-explosive shell down the barrel
	when loaded (MainGunReady attribute).
	Riders: RiderSeat seats on the turret roof, for infantry to ride on.
	Smoke: the launchers fire on their own when a missile is coming (the
	MissileInbound attribute, from ThreatAt) or a heavy round hits. Each cloud is
	a part tagged SmokeScreen with a Radius attribute, which soldiers, gunners
	and missiles cannot see through. SmokeAt is when the last salvo went up.
]]

local clone = script.Parent:Clone()
--Respawns go back where the tank was placed, not straight into Workspace.
local homeParent = script.Parent.Parent

local runService = game:GetService("RunService")
local debris = game:GetService("Debris")
local collectionService = game:GetService("CollectionService")
local kit = require(script.Parent:WaitForChild("VehicleKit"))

--Driving: top speed forward and in reverse (studs/s), how fast it gets there
--(studs/s gained each second) and turn rate (degrees/s).
local MAX_SPEED = 28
local MAX_REVERSE = 12
local ACCELERATION = 14
local TURN_RATE = 45

--Bumps lower than this (studs) are driven over; anything taller stops it.
local STEP_HEIGHT = 2

--The barrel's hitbox: how thick it is (studs). It reaches from the breech
--(Trunnion) to the muzzle, and the turret will not swing it, nor the tank drive
--it, into anything solid.
local BARREL_THICKNESS = 1.2

--How quickly the hull settles onto the slope under it. Higher is snappier.
local SETTLE = 8

--Turret traverse and gun elevation speeds (degrees/s), and how far the gun
--dips and lifts (degrees).
local TRAVERSE_SPEED = 50
local ELEVATE_SPEED = 25
local MIN_ELEVATION = -8
local MAX_ELEVATION = 20

--Main gun: seconds to reload, shell speed (studs/s) and range, blast radius,
--and damage at the centre and at the edge of the blast.
local RELOAD_TIME = 6
local SHELL_SPEED = 500
local SHELL_RANGE = 800
local BLAST_RADIUS = 30
local BLAST_DAMAGE = 150
local BLAST_EDGE_DAMAGE = 25

--Against vehicles: damage from a direct hit, and the share of it a vehicle only
--caught in the blast takes. An Abrams has 3000 health, a Warthog 400.
local SHELL_VEHICLE_DAMAGE = 750
local SHELL_VEHICLE_SPLASH = 0.25

--Sounds: main gun, machine gun (one per round), and the engine loop. The engine
--plays while someone is driving, pitched up as the tank speeds up.
local MAIN_GUN_SOUND = "rbxassetid://138839154527248"
local MG_SOUND = "rbxassetid://80013099941453"
local ENGINE_SOUND = "rbxassetid://17485939810"
local MAIN_GUN_VOLUME = 2
local MG_VOLUME = 0.8
local ENGINE_VOLUME = 1.2
local ENGINE_PITCH = {0.85, 1.2}

--Crushing. CRUSH_MIN_SPEED is how fast (studs/s) the tank has to be going toward
--someone to hurt him; it then does CRUSH_BASE_DAMAGE plus CRUSH_DAMAGE per stud/s
--above that. CRUSH_COOLDOWN keeps one hit from counting several times.
local CRUSH_MIN_SPEED = 5
local CRUSH_BASE_DAMAGE = 40
local CRUSH_DAMAGE = 8
local CRUSH_COOLDOWN = 0.75

--Infantry riding on the turret roof: each seat's place in studs from the turret
--ring (sideways, back) and which way its rider faces (1 right, -1 left), and the
--roof height above the ring used when the roof cannot be found under a seat.
local RIDER_SPOTS = {
	{Vector2.new(-4,5.5),-1},
	{Vector2.new(4,5.5),1},
	{Vector2.new(-4,10),-1},
	{Vector2.new(4,10),1},
}
local RIDER_ROOF = 5.75

--Smoke launchers: salvos carried, grenades per salvo, how far out they burst
--(studs) across SMOKE_ARC degrees toward the threat, each cloud's radius
--(studs) and how long it hangs (seconds), the least time between salvos, and
--the damage from one hit that also sets them off.
local SMOKE_SALVOS = 2
local SMOKE_GRENADES = 6
local SMOKE_DISTANCE = 20
local SMOKE_ARC = 120
local SMOKE_RADIUS = 14
local SMOKE_TIME = 25
local SMOKE_COOLDOWN = 6
local SMOKE_HIT = 500
local SMOKE_SOUND = "rbxasset://sounds/Launching rocket.wav"

local tank = script.Parent
local mesh = tank.Mesh
local hull = tank.Hull
local turretRing = tank.TurretRing
local trunnion = tank.Trunnion
local driverSeat = tank.VehicleSeat
local gunnerSeat = tank.Seat
local humanoid = tank.Humanoid
local mySettings = tank.Settings
local mainGun = trunnion.MainGun

---------------------------------------------------------------- rigging

local function weldTo(base,part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
	part.Anchored = false
	part.Massless = true
end

local function joint(part0,part1)
	local motor = Instance.new("Motor6D")
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	motor.Parent = part0
	part1.Anchored = false
	return motor
end

local turretModel = mesh.Turret
local cannonModel = turretModel.Cannon
local roadWheels = {mesh.Wheels["Wheels L"],mesh.Wheels["Wheels R"]}

--Road wheels hang on motors so the Tracks script can spin them on each client.
local function isRoadWheel(part)
	return part:IsDescendantOf(roadWheels[1]) or part:IsDescendantOf(roadWheels[2])
end

for _,part in ipairs(mesh:GetDescendants()) do
	if part:IsA("BasePart") then
		if isRoadWheel(part) then
			local motor = Instance.new("Motor6D")
			motor.Name = "WheelMotor"
			motor.Part0 = hull
			motor.Part1 = part
			motor.C0 = hull.CFrame:ToObjectSpace(part.CFrame)
			motor.Parent = part
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
		elseif part:IsDescendantOf(cannonModel) then
			weldTo(trunnion,part)
		elseif part:IsDescendantOf(turretModel) then
			weldTo(turretRing,part)
		else
			weldTo(hull,part)
			--The tracks reach the ground; the hull rides just above it.
			if part:IsDescendantOf(mesh.Wheels) then
				part.CanCollide = false
			end
		end
	end
end
weldTo(hull,driverSeat)
weldTo(turretRing,gunnerSeat)

--Rider seats sit on the roof found under each spot, turning with the turret.
local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Include
roofParams.FilterDescendantsInstances = {turretModel}
local riderSeats = {}
for _,spot in ipairs(RIDER_SPOTS) do
	local offset,side = spot[1],spot[2]
	local above = turretRing.CFrame * Vector3.new(offset.X,RIDER_ROOF + 10,offset.Y)
	local hit = workspace:Raycast(above,-turretRing.CFrame.UpVector*20,roofParams)
	local roof = hit and turretRing.CFrame:PointToObjectSpace(hit.Position).Y or RIDER_ROOF
	local seat = Instance.new("Seat")
	seat.Name = "RiderSeat"
	seat.Size = Vector3.new(2,0.2,2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CastShadow = false
	seat.CFrame = turretRing.CFrame * CFrame.new(offset.X,roof + 0.1,offset.Y) * CFrame.Angles(0,-side*math.pi/2,0)
	seat.Parent = tank
	weldTo(turretRing,seat)
	riderSeats[#riderSeats+1] = seat
end

local traverseMotor = joint(hull,turretRing)
local elevateMotor = joint(turretRing,trunnion)
local traverseBase = traverseMotor.C0
local elevateBase = elevateMotor.C0

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
tank.PrimaryPart = hull

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

--The crew's machine-gun bursts play the "Shoot" sound next to the Tip they fire from.
local mainGunSound = newSound("MainGunFire",MAIN_GUN_SOUND,MAIN_GUN_VOLUME,trunnion,900)
newSound("Shoot",MG_SOUND,MG_VOLUME,trunnion,400)
local engineSound = newSound("Engine",ENGINE_SOUND,ENGINE_VOLUME,hull,300)
engineSound.Looped = true

--Tells the Effects script on each client where to draw a muzzle blast or an impact.
local vehicleFx = Instance.new("RemoteEvent")
vehicleFx.Name = "VehicleFx"
vehicleFx.Parent = tank

local fireMain = Instance.new("BindableEvent")
fireMain.Name = "FireMain"
fireMain.Parent = tank

tank:SetAttribute("MainGunReady",true)
tank:SetAttribute("ShellSpeed",SHELL_SPEED)
tank:SetAttribute("Speed",0)
collectionService:AddTag(tank,"BloxianVehicle")
--The Tracks script on each client waits for this before looking for the wheel motors.
tank:SetAttribute("Rigged",true)

--The server simulates the tank. A VehicleSeat hands its driver ownership on
--its own, so this is taken back whenever someone gets in, and every second.
local function claimPhysics()
	if hull:CanSetNetworkOwnership() and hull:GetNetworkOwner() ~= nil then
		hull:SetNetworkOwner(nil)
	end
end
pcall(claimPhysics)
for _,seat in ipairs({driverSeat,table.unpack(riderSeats)}) do
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		pcall(claimPhysics)
	end)
end

---------------------------------------------------------------- getting in and out

--How close a player has to be to a door for its prompt, and how long to hold it.
local PROMPT_DISTANCE = 12
local PROMPT_HOLD = 0.25

local seats = {
	{seat = driverSeat, door = hull.FrontDoor, action = "Drive"},
	{seat = gunnerSeat, door = hull.SideDoor, action = "Gunner's hatch"},
}

--Both seats sit inside the hull's collision, where nobody can walk up to them,
--and someone leaving would pop out inside the tank. Players get in through a
--prompt at each door, and anyone leaving is put down outside that door.
for _,entry in ipairs(seats) do
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = entry.action
	prompt.ObjectText = "Abrams"
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
			if leaving.SeatPart and leaving.SeatPart:IsDescendantOf(tank) then return end
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

--Players climb on at the back for a free rider seat, and jump to get off.
local rearDeck = Instance.new("Attachment")
rearDeck.Name = "RearDeck"
rearDeck.Position = Vector3.new(0,-2,hull.Size.Z/2 + 1)
rearDeck.Parent = hull
local ridePrompt = Instance.new("ProximityPrompt")
ridePrompt.ActionText = "Ride"
ridePrompt.ObjectText = "Abrams"
ridePrompt.HoldDuration = PROMPT_HOLD
ridePrompt.MaxActivationDistance = PROMPT_DISTANCE
ridePrompt.RequiresLineOfSight = false
ridePrompt.Parent = rearDeck
ridePrompt.Triggered:Connect(function(player)
	local character = player.Character
	local human = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid.Health <= 0 or not human or human.Health <= 0 or human.SeatPart then return end
	for _,seat in ipairs(riderSeats) do
		if not seat.Occupant and not seat:GetAttribute("Claim") then
			seat:Sit(human)
			return
		end
	end
end)

---------------------------------------------------------------- who gets hurt


---------------------------------------------------------------- main gun

local dead = false
local loaded = true

local function crew()
	local list = {tank}
	for _,seat in ipairs({driverSeat,gunnerSeat,table.unpack(riderSeats)}) do
		if seat.Occupant then
			list[#list+1] = seat.Occupant.Parent
		end
	end
	return list
end

--Damage is a plain radius check rather than an Explosion, which would also blow
--a crater in terrain. What players see is drawn by Effects on each client.
local function explode(position,attacker,kind,hitPart)
	local damaged = {}
	local direct = hitPart and kit.vehicleOf(tank,hitPart)
	for _,part in ipairs(workspace:GetPartBoundsInRadius(position,BLAST_RADIUS)) do
		local victim = kit.personOf(tank,part)
		if victim and not damaged[victim] then
			damaged[victim] = true
			if kit.canHurt(tank,attacker,victim) then
				local distance = (victim.RootPart.Position - position).Magnitude
				local share = math.clamp(distance/BLAST_RADIUS,0,1)
				kit.hurt(tank,attacker,victim,BLAST_DAMAGE + (BLAST_EDGE_DAMAGE - BLAST_DAMAGE)*share,"GunKills")
			end
		end

		local car = not victim and kit.vehicleOf(tank,part)
		if car and not damaged[car] then
			damaged[car] = true
			if kit.canHurtVehicle(tank,attacker,car) then
				local human = car:FindFirstChildOfClass("Humanoid")
				human:TakeDamage(SHELL_VEHICLE_DAMAGE*(car == direct and 1 or SHELL_VEHICLE_SPLASH))
				if human.Health <= 0 then
					tank:SetAttribute("GunKills",(tank:GetAttribute("GunKills") or 0) + 1)
				end
			end
		end
	end
	vehicleFx:FireAllClients(kind or "impact",position)
end

local function fireShell(attacker)
	if dead or not loaded then return end
	loaded = false
	tank:SetAttribute("MainGunReady",false)
	task.delay(RELOAD_TIME,function()
		loaded = true
		if tank.Parent and not dead then
			tank:SetAttribute("MainGunReady",true)
		end
	end)

	local muzzle = mainGun.WorldCFrame
	vehicleFx:FireAllClients("muzzle",muzzle)

	local bang = mainGunSound:Clone()
	bang.Parent = trunnion
	bang:Play()
	debris:AddItem(bang,6)

	local shell = Instance.new("Part")
	shell.Size = Vector3.new(0.4,0.4,3)
	shell.Material = Enum.Material.Neon
	shell.Color = Color3.fromRGB(255,190,90)
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.CFrame = muzzle
	shell.Parent = workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = crew()
	--A barrel up against a wall bursts the shell on the wall, not out past it.
	local breech = trunnion.Position
	local inBarrel = workspace:Raycast(breech,muzzle.Position - breech,params)
	if inBarrel then
		shell:Destroy()
		explode(inBarrel.Position,attacker,nil,inBarrel.Instance)
		return
	end
	local travelled = 0
	local connection
	connection = runService.Heartbeat:Connect(function(dt)
		local cf = shell.CFrame
		local step = SHELL_SPEED*dt
		local result = workspace:Raycast(cf.Position,cf.LookVector*step,params)
		if result or travelled + step > SHELL_RANGE then
			connection:Disconnect()
			shell:Destroy()
			explode(result and result.Position or cf.Position + cf.LookVector*step,attacker,nil,result and result.Instance)
			return
		end
		travelled += step
		shell.CFrame = cf + cf.LookVector*step
	end)
end
fireMain.Event:Connect(fireShell)

---------------------------------------------------------------- driving

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.FilterDescendantsInstances = {tank}

--People do not hold the tank up or stop it: a cast that hits one ignores him and tries again.
local function cast(fn)
	for _ = 1,4 do
		local result = fn()
		if not result then return nil end
		local person = kit.personOf(tank,result.Instance)
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

--Where the trunnion would be with the hull at hullCFrame and the turret at
--atYaw / atPitch.
local function trunnionAt(hullCFrame,atYaw,atPitch)
	return hullCFrame * traverseBase * CFrame.Angles(0,atYaw,0) * elevateBase * CFrame.Angles(atPitch,0,0)
end

--Whether the barrel, with the trunnion at trunnionCFrame, would be in anything
--solid: rays down its middle and along its sides, breech to muzzle. People do
--not count, nor anything that does not collide.
local barrelParams = RaycastParams.new()
barrelParams.FilterType = Enum.RaycastFilterType.Exclude
barrelParams.RespectCanCollide = true
local muzzleOffset = mainGun.Position
local barrelEdges = {Vector3.zero}
for _,side in ipairs({Vector3.xAxis,-Vector3.xAxis,Vector3.yAxis,-Vector3.yAxis}) do
	barrelEdges[#barrelEdges+1] = side*BARREL_THICKNESS/2
end
local function barrelBlocked(trunnionCFrame)
	for _,edge in ipairs(barrelEdges) do
		local from = trunnionCFrame * edge
		local direction = trunnionCFrame:VectorToWorldSpace(muzzleOffset)
		for _ = 1,4 do
			local result = workspace:Raycast(from,direction,barrelParams)
			if not result then break end
			local person = kit.personOf(tank,result.Instance)
			if not person then return true end
			barrelParams:AddToFilter(person.Parent)
		end
	end
	return false
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
local yaw,pitch = 0,0
local position = hull.Position
local up = hull.CFrame.UpVector
local heading = flat(hull.CFrame.LookVector).Unit
local velocity = Vector3.zero
local lastCrushed = setmetatable({},{__mode = "k"})
local crushParams = OverlapParams.new()
crushParams.FilterType = Enum.RaycastFilterType.Exclude
crushParams.FilterDescendantsInstances = {tank}

local function approachAngle(current,goal,step)
	local diff = (goal - current + math.pi) % (2*math.pi) - math.pi
	return current + math.clamp(diff,-step,step)
end

local function drive(dt)
	local throttle,steer = 0,0
	if not dead and driverSeat.Occupant then
		throttle = tank:GetAttribute("AIThrottle") or driverSeat.ThrottleFloat
		steer = tank:GetAttribute("AISteer") or driverSeat.SteerFloat
	end
	local target = throttle >= 0 and throttle*MAX_SPEED or throttle*MAX_REVERSE
	speed += math.clamp(target - speed,-ACCELERATION*dt,ACCELERATION*dt)

	local oldHeading = heading
	heading = CFrame.fromAxisAngle(Vector3.yAxis,-steer*math.rad(TURN_RATE)*dt) * heading
	local move = heading*speed*dt
	local tilted = CFrame.fromMatrix(position,heading:Cross(up).Unit,up)
	if move.Magnitude > 0.01 and blocked(tilted,move) then
		speed = 0
		move = Vector3.zero
	end
	--The barrel reaches out past the hull: driving or turning it into a wall stops the tank too.
	if (move.Magnitude > 0.01 or steer ~= 0) and barrelBlocked(trunnionAt(CFrame.fromMatrix(position + move,heading:Cross(up).Unit,up),yaw,pitch))
		and not barrelBlocked(trunnionAt(CFrame.fromMatrix(position,oldHeading:Cross(up).Unit,up),yaw,pitch)) then
		speed = 0
		move = Vector3.zero
		heading = oldHeading
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
	if math.abs(moving - (tank:GetAttribute("Speed") or 0)) > 0.5 then
		tank:SetAttribute("Speed",moving)
	end

	local engineOn = not dead and driverSeat.Occupant ~= nil
	if engineOn and not engineSound.IsPlaying then
		engineSound:Play()
	elseif not engineOn and engineSound.IsPlaying then
		engineSound:Stop()
	end
	if engineOn then
		local pitch = ENGINE_PITCH[1] + (ENGINE_PITCH[2] - ENGINE_PITCH[1])*math.min(moving/MAX_SPEED,1)
		if math.abs(engineSound.PlaybackSpeed - pitch) > 0.02 then
			engineSound.PlaybackSpeed = pitch
		end
	end
end

local function crush()
	local driver = driverSeat.Occupant
	if not driver or flat(velocity).Magnitude < CRUSH_MIN_SPEED then return end
	local now = os.clock()
	local seen = {}
	for _,part in ipairs(workspace:GetPartBoundsInBox(hull.CFrame,hull.Size + Vector3.new(2,0,2),crushParams)) do
		local victim = kit.personOf(tank,part)
		if victim and not seen[victim] then
			seen[victim] = true
			local offset = flat(victim.RootPart.Position - hull.Position)
			local closing = offset.Magnitude > 0.1 and velocity:Dot(offset.Unit) or 0
			if closing >= CRUSH_MIN_SPEED and now - (lastCrushed[victim] or 0) > CRUSH_COOLDOWN and kit.canHurt(tank,driver.Parent,victim) then
				lastCrushed[victim] = now
				kit.hurt(tank,driver.Parent,victim,CRUSH_BASE_DAMAGE + (closing - CRUSH_MIN_SPEED)*CRUSH_DAMAGE,"Roadkills")
			end
		end
	end
end

local function aim(dt)
	--Once destroyed the turret has been blown off; nothing turns it.
	if dead then return end
	local aimPoint = tank:GetAttribute("AimPoint")
	local wantYaw,wantPitch = 0,0
	if typeof(aimPoint) == "Vector3" then
		local ringCFrame = hull.CFrame * traverseBase
		local toTarget = ringCFrame:PointToObjectSpace(aimPoint)
		wantYaw = math.atan2(-toTarget.X,-toTarget.Z)
		local gunCFrame = ringCFrame * CFrame.Angles(0,yaw,0) * elevateBase
		local fromGun = gunCFrame:PointToObjectSpace(aimPoint)
		wantPitch = math.atan2(fromGun.Y,math.sqrt(fromGun.X^2 + fromGun.Z^2))
	end
	wantPitch = math.clamp(wantPitch,math.rad(MIN_ELEVATION),math.rad(MAX_ELEVATION))

	local newYaw = approachAngle(yaw,wantYaw,math.rad(TRAVERSE_SPEED)*dt)
	local newPitch = pitch + math.clamp(wantPitch - pitch,-math.rad(ELEVATE_SPEED)*dt,math.rad(ELEVATE_SPEED)*dt)
	--The barrel stops against a wall instead of swinging through it.
	if (newYaw ~= yaw or newPitch ~= pitch) and barrelBlocked(trunnionAt(hull.CFrame,newYaw,newPitch))
		and not barrelBlocked(trunnionAt(hull.CFrame,yaw,pitch)) then
		return
	end
	if newYaw ~= yaw then
		yaw = newYaw
		traverseMotor.C0 = traverseBase * CFrame.Angles(0,yaw,0)
	end
	if newPitch ~= pitch then
		pitch = newPitch
		elevateMotor.C0 = elevateBase * CFrame.Angles(pitch,0,0)
	end
end

---------------------------------------------------------------- smoke

local smokeLeft = SMOKE_SALVOS
local lastSmoke = -math.huge
tank:SetAttribute("Smoke",smokeLeft)

local function smokeCloud(at)
	local cloud = Instance.new("Part")
	cloud.Name = "SmokeScreen"
	cloud.Shape = Enum.PartType.Ball
	cloud.Size = Vector3.one*SMOKE_RADIUS
	cloud.Transparency = 1
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.CastShadow = false
	cloud.CFrame = CFrame.new(at)
	cloud:SetAttribute("Radius",SMOKE_RADIUS)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(205,205,200))
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,SMOKE_RADIUS*0.8),NumberSequenceKeypoint.new(1,SMOKE_RADIUS*1.6)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.15,0.1),NumberSequenceKeypoint.new(0.7,0.25),NumberSequenceKeypoint.new(1,1)})
	emitter.Lifetime = NumberRange.new(5,8)
	emitter.Rate = 4
	emitter.Speed = NumberRange.new(1,4)
	emitter.SpreadAngle = Vector2.new(180,180)
	emitter.Rotation = NumberRange.new(0,360)
	emitter.RotSpeed = NumberRange.new(-15,15)
	emitter.Acceleration = Vector3.new(0,0.5,0)
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = cloud
	cloud.Parent = workspace
	collectionService:AddTag(cloud,"SmokeScreen")
	emitter:Emit(10)
	--Debris, as the delay dies with this script if the tank goes first.
	debris:AddItem(cloud,SMOKE_TIME + 9)
	task.delay(SMOKE_TIME,function()
		collectionService:RemoveTag(cloud,"SmokeScreen")
		emitter.Enabled = false
	end)
end

--One grenade lobbed from the turret to burst over the ground at to.
local function throwSmoke(from,to)
	local ground = workspace:Raycast(to + Vector3.new(0,30,0),Vector3.new(0,-80,0),castParams)
	local landing = ground and ground.Position or to
	local grenade = Instance.new("Part")
	grenade.Name = "SmokeGrenade"
	grenade.Size = Vector3.new(0.5,0.5,0.9)
	grenade.Color = Color3.fromRGB(60,64,50)
	grenade.Anchored = true
	grenade.CanCollide = false
	grenade.CanQuery = false
	grenade.CanTouch = false
	grenade.CFrame = CFrame.new(from)
	grenade.Parent = workspace
	debris:AddItem(grenade,2)
	local flight,elapsed = 0.6,0
	while elapsed < flight and grenade.Parent do
		elapsed += runService.Heartbeat:Wait()
		local t = math.min(elapsed/flight,1)
		grenade.CFrame = CFrame.new(from:Lerp(landing,t) + Vector3.new(0,math.sin(t*math.pi)*6,0))
	end
	grenade:Destroy()
	smokeCloud(landing + Vector3.new(0,SMOKE_RADIUS*0.5,0))
end

--A salvo toward a threat at towards (or the way the turret faces), if the crew is
--aboard to fire it and there is one left.
local function popSmoke(towards)
	if dead or smokeLeft <= 0 or os.clock() - lastSmoke < SMOKE_COOLDOWN then return end
	if not driverSeat.Occupant and not gunnerSeat.Occupant then return end
	smokeLeft -= 1
	lastSmoke = os.clock()
	tank:SetAttribute("Smoke",smokeLeft)
	tank:SetAttribute("SmokeAt",workspace:GetServerTimeNow())

	local facing = typeof(towards) == "Vector3" and flat(towards - hull.Position) or flat(turretRing.CFrame.LookVector)
	facing = facing.Magnitude > 0.1 and facing.Unit or flat(hull.CFrame.LookVector).Unit
	local from = turretRing.Position + Vector3.new(0,5,0)
	local pop = newSound("SmokePop",SMOKE_SOUND,1,turretRing,300)
	pop.PlaybackSpeed = 1.6
	pop:Play()
	debris:AddItem(pop,4)
	for i = 1,SMOKE_GRENADES do
		local angle = math.rad(-SMOKE_ARC/2 + SMOKE_ARC*(i - 1)/math.max(SMOKE_GRENADES - 1,1))
		local direction = CFrame.fromAxisAngle(Vector3.yAxis,angle):VectorToWorldSpace(facing)
		task.spawn(throwSmoke,from,hull.Position + direction*SMOKE_DISTANCE)
	end
end

tank:GetAttributeChangedSignal("MissileInbound"):Connect(function()
	if (tank:GetAttribute("MissileInbound") or 0) > 0 then
		popSmoke(tank:GetAttribute("ThreatAt"))
	end
end)

local lastHealth = humanoid.Health
humanoid.HealthChanged:Connect(function(health)
	if lastHealth - health >= SMOKE_HIT and health > 0 then
		popSmoke(nil)
	end
	lastHealth = health
end)

---------------------------------------------------------------- dying

local function respawn()
	--One from the Vehicle Spawner is just removed, not put back.
	if not tank:GetAttribute("NoRespawn") then
		clone.Parent = homeParent or workspace
	end
	tank:Destroy()
end

--Destroyed: how hard the turret is thrown off (studs/s up, studs/s sideways,
--spin), the colour the wreck is charred to, when the ammunition left inside
--cooks off after the first blast (seconds), and how long the wreck takes to fade
--out at the end.
local TURRET_TOSS_SPEED = 70
local TURRET_TOSS_DRIFT = 30
local TURRET_TOSS_SPIN = 6
local WRECK_COLOR = Color3.fromRGB(60,55,50)
local COOK_OFF_TIMES = {1.3, 2.8}
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

--The turret is thrown clear of the hull, spinning, the way a tank's ammunition
--going up does it.
local function tossTurret()
	traverseMotor:Destroy()
	turretRing.Massless = false
	runService.Heartbeat:Wait()
	if not turretRing.Parent then return end
	pcall(turretRing.SetNetworkOwner,turretRing,nil)
	local drift = Vector3.new(math.random() - 0.5,0,math.random() - 0.5)*2*TURRET_TOSS_DRIFT
	turretRing.AssemblyLinearVelocity = Vector3.new(0,TURRET_TOSS_SPEED,0) + drift
	turretRing.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5,math.random() - 0.5,math.random() - 0.5)*2*TURRET_TOSS_SPIN
end

local function char()
	for _,part in ipairs(mesh:GetDescendants()) do
		if part:IsA("SurfaceAppearance") then
			pcall(function()
				part.Color = WRECK_COLOR
			end)
		elseif part:IsA("BasePart") then
			part.Color = WRECK_COLOR
		end
	end
end

local function fadeOut()
	--The tread links are on each client; Tracks fades those.
	tank:SetAttribute("Fading",true)
	local info = TweenInfo.new(FADE_TIME)
	for _,part in ipairs(tank:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			game:GetService("TweenService"):Create(part,info,{Transparency = 1}):Play()
		end
	end
	task.wait(FADE_TIME)
end

local function destroyed()
	if dead then return end
	dead = true
	tank:SetAttribute("Wrecked",true)
	tank:SetAttribute("MainGunReady",false)
	tank:SetAttribute("AimPoint",nil)

	--Nobody inside lives through it.
	for _,seat in ipairs({driverSeat,gunnerSeat}) do
		if seat.Occupant then
			kit.unprotect(seat.Occupant)
			seat.Occupant.Health = 0
		end
	end
	--Riders are thrown off, into the blast.
	for _,seat in ipairs(riderSeats) do
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	runService.Heartbeat:Wait()

	explode(hull.Position,nil,"wreck")
	char()
	burn(hull,14)
	task.spawn(tossTurret)

	--The bodies come out of their seats a moment later.
	task.delay(0.1,function()
		for _,seat in ipairs({driverSeat,gunnerSeat}) do
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
		end
	end)

	for _,delay in ipairs(COOK_OFF_TIMES) do
		task.delay(delay,function()
			if hull.Parent then
				vehicleFx:FireAllClients("impact",hull.Position + Vector3.new(0,3,0))
			end
		end)
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
	aim(dt)
	if position.Y < workspace.FallenPartsDestroyHeight + 20 and not dead then
		dead = true
		respawn()
	end
end)

while tank.Parent do
	pcall(claimPhysics)
	refreshFilter()
	barrelParams.FilterDescendantsInstances = crew()
	task.wait(1)
end

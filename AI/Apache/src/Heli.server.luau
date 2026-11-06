--[[
	AH-64 Apache that Bloxians crew and players can fly: a pilot (VehicleSeat)
	and a gunner (Seat) in the cockpit, no AI of its own.

	The body is moved by script through rigid constraints, like the Abrams: it
	holds Settings.Height above the ground, climbs over whatever is ahead, and
	hovers in place with nobody flying it.

	Flying: the AIThrottle / AISteer attributes (a Bloxian pilot), or the
	VehicleSeat's own input (a player pilot).
	M230 chin gun: follows the AimPoint attribute.
	Hellfires: FireMain:Fire(shooter) launches the next missile off the rails
	when loaded (MainGunReady attribute); it steers onto AimPoint.

	At BAIL_HEALTH the crew jump out on parachutes and it goes down without them.
]]

local clone = script.Parent:Clone()
--Respawns go back where the Apache was placed, not straight into Workspace.
local homeParent = script.Parent.Parent

local players = game:GetService("Players")
local teams = game:GetService("Teams")
local runService = game:GetService("RunService")
local debris = game:GetService("Debris")
local collectionService = game:GetService("CollectionService")
local serverStorage = game:GetService("ServerStorage")
local tweenService = game:GetService("TweenService")

--Flying: top speed forward and backward (studs/s), how fast it gets there
--(studs/s gained each second), turn rate (degrees/s) and climb rate (studs/s).
local MAX_SPEED = 60
local MAX_REVERSE = 20
local ACCELERATION = 25
local TURN_RATE = 60
local CLIMB_RATE = 25

--How far ahead (studs, at full speed) it looks for higher ground to climb over.
local LOOK_AHEAD = {30,60,90}

--Nose-down tilt at full speed and bank in a full turn (degrees), and how quickly
--it leans into them.
local MAX_PITCH = 14
local MAX_BANK = 22
local TILT_RATE = 3

--M230 traverse and elevation speeds (degrees/s), and how far it swings to each
--side and dips and lifts (degrees).
local TRAVERSE_SPEED = 120
local ELEVATE_SPEED = 90
local MAX_TRAVERSE = 100
local MIN_ELEVATION = -60
local MAX_ELEVATION = 10

--Hellfires: seconds between launches, speed (studs/s), range, how hard it steers
--onto the aim point (degrees/s) and seconds before a fired rail is loaded again.
local RELOAD_TIME = 3
local MISSILE_SPEED = 220
local MISSILE_RANGE = 900
local MISSILE_TURN = 90
local REARM_TIME = 20

--Blast radius, damage at the centre and at the edge, and against vehicles: a
--direct hit, and the share of it one only caught in the blast takes.
local BLAST_RADIUS = 14
local BLAST_DAMAGE = 200
local BLAST_EDGE_DAMAGE = 40
local MISSILE_VEHICLE_DAMAGE = 1000
local MISSILE_VEHICLE_SPLASH = 0.25

--Engine volume.
local ENGINE_VOLUME = 1
--How fast each rotor turns against the main rotor (the Rotors script spins them).
local TAIL_ROTOR_RATE = 4

--Health share at or below which the crew bail out.
local BAIL_HEALTH = 0.3
--Anyone leaving higher than this above the ground (studs) gets a parachute.
local CHUTE_ABOVE = 12
--Thrown out sideways and up (studs/s), the canopy opening after CHUTE_DELAY
--seconds. Under it he sinks at FALL_SPEED and drifts outward at DRIFT_SPEED.
local EJECT_SPEED = 30
local EJECT_UP = 12
local CHUTE_DELAY = 0.6
local FALL_SPEED = 14
local DRIFT_SPEED = 4
local CHUTE_SIZE = Vector3.new(14,5,14)
local CHUTE_HEIGHT = 10
local CHUTE_COLOR = Color3.fromRGB(96,104,72)
local CHUTE_FADE = 1.5

--Placed in the world (not from the Vehicle Spawner) with Settings.AutoCrew on,
--it brings its own pilot and gunner: Bloxians cloned from ServerStorage, in the
--Pilot uniform with the FN FAL (the Rifle profile).
local SOLDIER_NAME = "BLOXIAN"
local CREW_UNIT = "Pilot"
local CREW_WEAPON = "Rifle"
local CREW_DELAY = 0.5

--Engulfed: how many of its parts burn and the biggest fire on one (studs; 30
--is Roblox's limit), and how much bigger than a shell's impact the blast is
--when it hits the ground (Random Arty's ArtilleryBlast).
local ENGULF_PARTS = 30
local ENGULF_MAX_FIRE = 25
local CRASH_SCALE = 4

--Going down: spin (radians/s), the colour the wreck is charred to, how long
--the wreck lies there at most (seconds; Settings.RespawnDelay if shorter), and
--how long it takes to fade out at the end.
local CRASH_SPIN = 2.5
local CRASH_TIMEOUT = 10
local WRECK_COLOR = Color3.fromRGB(60,55,50)
local WRECK_TIME = 12
local FADE_TIME = 3

local heli = script.Parent
local body = heli.Body
local gun = heli.M230
local pilotSeat = heli.VehicleSeat
local gunnerSeat = heli.Seat
local humanoid = heli.Humanoid
local mySettings = heli.Settings
local rotors = {heli["Main Propeller"],heli["Rear Propeller"]}
local rotorHinges = {body.FrontBladeHinge,body.BackBladeHinge}

---------------------------------------------------------------- rigging

local function weldTo(base,part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
end

--Everything rides on Body: the rails and pods already have their joints, the
--mount and seats get welds, the M230 a motor that aims it.
for _,part in ipairs(heli:GetDescendants()) do
	if part:IsA("BasePart") and part ~= body then
		part.Anchored = false
		part.Massless = true
	end
end
weldTo(body,heli.M230Mount)
weldTo(body,pilotSeat)
weldTo(body,gunnerSeat)
for _,rotor in ipairs(rotors) do
	rotor.CanCollide = false
end

local function flat(v)
	return Vector3.new(v.X,0,v.Z)
end

--Which way the nose points in Body's own space (the chin gun is under it).
local noseLocal = flat(body.CFrame:PointToObjectSpace(gun.Position)).Unit
local noseFrame = CFrame.lookAt(Vector3.zero,noseLocal,Vector3.yAxis)

local gunPivot = body.CFrame:PointToObjectSpace(gun.Position)
local gunFix = noseFrame:Inverse() * body.CFrame:ToObjectSpace(gun.CFrame).Rotation
local gunMotor = Instance.new("Motor6D")
gunMotor.Name = "GunMotor"
gunMotor.Part0 = body
gunMotor.Part1 = gun
gunMotor.C0 = body.CFrame:ToObjectSpace(gun.CFrame)
gunMotor.Parent = body

local anchor = Instance.new("Attachment")
anchor.Name = "FlyAnchor"
anchor.Parent = body
local alignPosition = Instance.new("AlignPosition")
alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
alignPosition.Attachment0 = anchor
alignPosition.RigidityEnabled = true
alignPosition.Position = body.Position
alignPosition.Parent = body
local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.Attachment0 = anchor
alignOrientation.RigidityEnabled = true
alignOrientation.CFrame = body.CFrame.Rotation
alignOrientation.Parent = body

body.Massless = false
body.Anchored = false
heli.PrimaryPart = body

humanoid.BreakJointsOnDeath = false
humanoid.RequiresNeck = false
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
humanoid.MaxHealth = mySettings.Health.Value
humanoid.Health = humanoid.MaxHealth

--The rotors hang on motors that the Rotors script spins on each client.
for _,hinge in ipairs(rotorHinges) do
	local onBody = hinge.Attachment0.Parent == body and hinge.Attachment0 or hinge.Attachment1
	local onRotor = onBody == hinge.Attachment0 and hinge.Attachment1 or hinge.Attachment0
	local rotor = onRotor.Parent
	local motor = Instance.new("Motor6D")
	motor.Name = "RotorMotor"
	motor.Part0 = body
	motor.Part1 = rotor
	motor.C0 = onBody.CFrame
	motor.C1 = onRotor.CFrame
	motor:SetAttribute("Rate",rotor == rotors[2] and TAIL_ROTOR_RATE or 1)
	motor.Parent = rotor
	hinge:Destroy()
end
local engineSound = body.Sound
engineSound.Looped = true
engineSound.Volume = ENGINE_VOLUME
engineSound:Play()

--Tells the Effects script on each client where to draw a launch or an impact.
local vehicleFx = Instance.new("RemoteEvent")
vehicleFx.Name = "VehicleFx"
vehicleFx.Parent = heli

local fireMain = Instance.new("BindableEvent")
fireMain.Name = "FireMain"
fireMain.Parent = heli

heli:SetAttribute("MainGunReady",true)
heli:SetAttribute("ShellSpeed",MISSILE_SPEED)
heli:SetAttribute("Speed",0)
collectionService:AddTag(heli,"BloxianVehicle")
--Javelin teams lock on to aircraft by this tag.
collectionService:AddTag(heli,"BloxianAircraft")

--The server simulates the Apache. A VehicleSeat hands its driver ownership on
--its own, so this is taken back whenever someone gets in, and every second.
local function claimPhysics()
	if body:CanSetNetworkOwnership() and body:GetNetworkOwner() ~= nil then
		body:SetNetworkOwner(nil)
	end
end
pcall(claimPhysics)
pilotSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
	pcall(claimPhysics)
end)

---------------------------------------------------------------- who gets hurt

--A player's team name, or the Team value an NPC carries. nil for no side.
local function sideOf(model)
	local player = players:GetPlayerFromCharacter(model)
	if player then
		return not player.Neutral and player.Team and player.Team.Name or nil
	end
	local settings = model:FindFirstChild("Settings")
	local tag = model:FindFirstChild("Team") or (settings and settings:FindFirstChild("Team"))
	if tag and tag.Value ~= "" then
		return tag.Value
	end
	return nil
end

--Whether an NPC leaves this player alone: Hostile never does, one on a Roblox
--team's name fights other teams, and any other follows its AttackPlayers.
local function sparesPlayer(npcModel,npcSide,player)
	if npcSide == "Hostile" then return false end
	local robloxTeam = npcSide and teams:FindFirstChild(npcSide)
	if robloxTeam and robloxTeam:IsA("Team") and player.Team and not player.Neutral then return false end
	local settings = npcModel:FindFirstChild("Settings")
	local attackPlayers = settings and settings:FindFirstChild("AttackPlayers")
	return attackPlayers ~= nil and not attackPlayers.Value
end

--Never the crew or the attacker's own side, and an NPC spares the players it
--would not shoot.
local function canHurt(attacker,victim)
	local victimModel = victim.Parent
	if not victimModel or victim.Health <= 0 or victimModel:IsDescendantOf(heli) then return false end
	if victim.SeatPart and victim.SeatPart:IsDescendantOf(heli) then return false end
	if not attacker then return true end
	if attacker == victimModel then return false end
	local attackerSide = sideOf(attacker)
	if attackerSide and attackerSide == sideOf(victimModel) then return false end
	local victimPlayer = players:GetPlayerFromCharacter(victimModel)
	if not players:GetPlayerFromCharacter(attacker) and victimPlayer and sparesPlayer(attacker,attackerSide,victimPlayer) then
		return false
	end
	return true
end

local function hurt(attacker,victim,damage)
	--Kill credit for a player, the way Roblox weapons tag it.
	local player = attacker and players:GetPlayerFromCharacter(attacker)
	if player then
		local creator = Instance.new("ObjectValue")
		creator.Name = "creator"
		creator.Value = player
		creator.Parent = victim
		debris:AddItem(creator,2)
	end
	victim:TakeDamage(damage)
	--A Bloxian crew watches this to know they got one.
	if victim.Health <= 0 then
		heli:SetAttribute("GunKills",(heli:GetAttribute("GunKills") or 0) + 1)
	end
end

--A live character (not a vehicle that happens to have a Humanoid).
local function personOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	local victim = model and model:FindFirstChildOfClass("Humanoid")
	if victim and victim.RootPart and not model:IsDescendantOf(heli) then
		return victim
	end
	return nil
end

local function crew()
	local list = {heli}
	for _,seat in ipairs({pilotSeat,gunnerSeat}) do
		if seat.Occupant then
			list[#list+1] = seat.Occupant.Parent
		end
	end
	return list
end

--The vehicle (tagged BloxianVehicle or MarineVehicle) a part belongs to, other than this one.
local function vehicleOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model ~= heli and (model:HasTag("BloxianVehicle") or model:HasTag("MarineVehicle")) then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--A vehicle on the other side from the attacker: crewed by an enemy of his and no
--friend, or kept to another team. The wreck going up (no attacker) hurts any.
local function canHurtVehicle(attacker,car)
	local human = car:FindFirstChildOfClass("Humanoid")
	if not human or human.Health <= 0 then return false end
	if not attacker then return true end
	local enemyAboard = false
	for _,name in ipairs({"VehicleSeat","Seat"}) do
		local seat = car:FindFirstChild(name)
		local occupant = seat and seat.Occupant
		if occupant and occupant.Health > 0 then
			if not canHurt(attacker,occupant) then
				return false
			end
			enemyAboard = true
		end
	end
	if enemyAboard then return true end
	local settings = car:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	local side = sideOf(attacker)
	return team ~= nil and team.Value ~= "" and side ~= nil and team.Value ~= side
end

--Damage is a plain radius check rather than an Explosion, which would also blow
--a crater in terrain. What players see is drawn by Effects on each client.
local function explode(position,attacker,kind,hitPart)
	local damaged = {}
	local direct = hitPart and vehicleOf(hitPart)
	for _,part in ipairs(workspace:GetPartBoundsInRadius(position,BLAST_RADIUS)) do
		local victim = personOf(part)
		if victim and not damaged[victim] then
			damaged[victim] = true
			if canHurt(attacker,victim) then
				local distance = (victim.RootPart.Position - position).Magnitude
				local share = math.clamp(distance/BLAST_RADIUS,0,1)
				hurt(attacker,victim,BLAST_DAMAGE + (BLAST_EDGE_DAMAGE - BLAST_DAMAGE)*share)
			end
		end

		local car = not victim and vehicleOf(part)
		if car and not damaged[car] then
			damaged[car] = true
			if canHurtVehicle(attacker,car) then
				local human = car:FindFirstChildOfClass("Humanoid")
				human:TakeDamage(MISSILE_VEHICLE_DAMAGE*(car == direct and 1 or MISSILE_VEHICLE_SPLASH))
				if human.Health <= 0 then
					heli:SetAttribute("GunKills",(heli:GetAttribute("GunKills") or 0) + 1)
				end
			end
		end
	end
	vehicleFx:FireAllClients(kind or "impact",position)
end

---------------------------------------------------------------- hellfires

local dead = false
local loaded = true
local rails = {}
for index = 1,8 do
	local rail = heli:FindFirstChild("Hellfire"..index)
	if rail then
		table.insert(rails,rail)
	end
end
local nextRail = 1

local function playAt(sound,position)
	if not sound then return end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local copy = sound:Clone()
	copy.Parent = holder
	copy:Play()
	debris:AddItem(holder,math.max(copy.TimeLength,3))
end

local function fireMissile(attacker)
	if dead or not loaded then return end
	local rail
	for step = 0,#rails - 1 do
		local candidate = rails[(nextRail + step - 1) % #rails + 1]
		if candidate.Transparency < 1 then
			rail = candidate
			nextRail = (nextRail + step) % #rails + 1
			break
		end
	end
	if not rail then return end

	loaded = false
	heli:SetAttribute("MainGunReady",false)
	task.delay(RELOAD_TIME,function()
		loaded = true
		if heli.Parent and not dead then
			heli:SetAttribute("MainGunReady",true)
		end
	end)
	rail.Transparency = 1
	task.delay(REARM_TIME,function()
		if rail.Parent and not dead then
			rail.Transparency = 0
		end
	end)

	local aimPoint = heli:GetAttribute("AimPoint")
	if typeof(aimPoint) ~= "Vector3" then
		aimPoint = rail.Position + body.CFrame:VectorToWorldSpace(noseLocal)*100
	end
	local missile = rail:Clone()
	for _,child in ipairs(missile:GetChildren()) do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	missile.Name = "Hellfire"
	missile.Transparency = 0
	missile.Anchored = true
	missile.CanCollide = false
	missile.CanQuery = false
	missile.CanTouch = false
	missile.CFrame = CFrame.lookAt(rail.Position,aimPoint)
	missile.Parent = workspace
	local trail = missile:FindFirstChild("Back") and missile.Back:FindFirstChild("Trail")
	if trail then
		trail.Enabled = true
	end
	if missile:FindFirstChild("Whiz") then
		missile.Whiz:Play()
	end
	vehicleFx:FireAllClients("muzzle",CFrame.lookAt(rail.Position,rail.Position - (aimPoint - rail.Position)))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = crew()
	local travelled = 0
	local connection
	connection = runService.Heartbeat:Connect(function(dt)
		local cf = missile.CFrame
		--Steers onto wherever the gunner is aiming now.
		local goal = heli.Parent and heli:GetAttribute("AimPoint")
		if typeof(goal) == "Vector3" then
			local want = (goal - cf.Position).Unit
			local angle = math.acos(math.clamp(cf.LookVector:Dot(want),-1,1))
			local turn = math.rad(MISSILE_TURN)*dt
			if angle > 0.001 then
				cf = CFrame.lookAt(cf.Position,cf.Position + cf.LookVector:Lerp(want,math.min(1,turn/angle)))
			end
		end
		local step = MISSILE_SPEED*dt
		local result = workspace:Raycast(cf.Position,cf.LookVector*step,params)
		if result or travelled + step > MISSILE_RANGE then
			connection:Disconnect()
			local at = result and result.Position or cf.Position + cf.LookVector*step
			playAt(missile:FindFirstChild("Explosion"),at)
			missile:Destroy()
			explode(at,attacker,nil,result and result.Instance)
			return
		end
		travelled += step
		missile.CFrame = cf + cf.LookVector*step
	end)
	debris:AddItem(missile,MISSILE_RANGE/MISSILE_SPEED + 2)
end
fireMain.Event:Connect(fireMissile)

---------------------------------------------------------------- flying

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.FilterDescendantsInstances = {heli}

--People do not hold it up: a cast that hits one ignores him and tries again.
local function cast(fn)
	for _ = 1,4 do
		local result = fn()
		if not result then return nil end
		local person = personOf(result.Instance)
		if not person then return result end
		castParams:AddToFilter(person.Parent)
	end
	return nil
end

local function refreshFilter()
	castParams.FilterDescendantsInstances = crew()
end

local function groundY(point)
	local result = cast(function()
		return workspace:Raycast(point,Vector3.new(0,-1000,0),castParams)
	end)
	return result and result.Position.Y
end

local function blocked(cf,move)
	local direction = move + move.Unit*2
	return cast(function()
		return workspace:Blockcast(cf,body.Size*Vector3.new(0.8,0.6,0.8),direction,castParams)
	end) ~= nil
end

local speed = 0
local position = body.Position
local heading = flat(body.CFrame:VectorToWorldSpace(noseLocal)).Unit
local tiltPitch,tiltBank = 0,0
local hoverHeight = mySettings.Height.Value

local function approachAngle(current,goal,step)
	local diff = (goal - current + math.pi) % (2*math.pi) - math.pi
	return current + math.clamp(diff,-step,step)
end

local function fly(dt)
	local throttle,steer = 0,0
	if pilotSeat.Occupant then
		throttle = heli:GetAttribute("AIThrottle") or pilotSeat.ThrottleFloat
		steer = heli:GetAttribute("AISteer") or pilotSeat.SteerFloat
	end
	local target = throttle >= 0 and throttle*MAX_SPEED or throttle*MAX_REVERSE
	speed += math.clamp(target - speed,-ACCELERATION*dt,ACCELERATION*dt)

	heading = CFrame.fromAxisAngle(Vector3.yAxis,-steer*math.rad(TURN_RATE)*dt) * heading
	local move = heading*speed*dt
	local wall = false
	if move.Magnitude > 0.01 and blocked(CFrame.lookAt(position,position + heading),move) then
		speed = 0
		move = Vector3.zero
		wall = true
	end

	--Hold the hover height over the highest ground under it and just ahead.
	local highest = groundY(position)
	local reach = math.abs(speed)/MAX_SPEED
	for _,distance in ipairs(LOOK_AHEAD) do
		local ahead = groundY(position + heading*math.sign(speed)*distance*reach)
		if ahead and (not highest or ahead > highest) then
			highest = ahead
		end
	end
	local wantY = highest and highest + hoverHeight or position.Y
	if wall then
		wantY = position.Y + CLIMB_RATE
	end
	local climb = math.clamp(wantY - position.Y,-CLIMB_RATE*dt,CLIMB_RATE*dt)
	position += move + Vector3.new(0,climb,0)

	local wantPitch = -speed/MAX_SPEED*MAX_PITCH
	local wantBank = steer*MAX_BANK
	tiltPitch += (wantPitch - tiltPitch)*math.min(1,TILT_RATE*dt)
	tiltBank += (wantBank - tiltBank)*math.min(1,TILT_RATE*dt)
	local flight = CFrame.lookAt(Vector3.zero,heading) * CFrame.Angles(math.rad(tiltPitch),0,-math.rad(tiltBank))
	alignPosition.Position = position
	alignOrientation.CFrame = flight * noseFrame:Inverse()

	local moving = math.abs(speed)
	if math.abs(moving - (heli:GetAttribute("Speed") or 0)) > 0.5 then
		heli:SetAttribute("Speed",moving)
	end
end

local aimYaw,aimPitch = 0,0
local function aim(dt)
	local aimPoint = heli:GetAttribute("AimPoint")
	local wantYaw,wantPitch = 0,0
	if typeof(aimPoint) == "Vector3" then
		local offset = noseFrame:VectorToObjectSpace(body.CFrame:PointToObjectSpace(aimPoint) - gunPivot)
		wantYaw = math.atan2(-offset.X,-offset.Z)
		wantPitch = math.atan2(offset.Y,math.sqrt(offset.X^2 + offset.Z^2))
	end
	wantYaw = math.clamp(wantYaw,-math.rad(MAX_TRAVERSE),math.rad(MAX_TRAVERSE))
	wantPitch = math.clamp(wantPitch,math.rad(MIN_ELEVATION),math.rad(MAX_ELEVATION))
	local newYaw = approachAngle(aimYaw,wantYaw,math.rad(TRAVERSE_SPEED)*dt)
	local newPitch = aimPitch + math.clamp(wantPitch - aimPitch,-math.rad(ELEVATE_SPEED)*dt,math.rad(ELEVATE_SPEED)*dt)
	if newYaw ~= aimYaw or newPitch ~= aimPitch then
		aimYaw,aimPitch = newYaw,newPitch
		gunMotor.C0 = CFrame.new(gunPivot) * noseFrame * CFrame.Angles(0,aimYaw,0) * CFrame.Angles(aimPitch,0,0) * gunFix
	end
end

---------------------------------------------------------------- crew

--The crew are not hurt while inside: nothing gets to them until they get out or
--it goes down with them. A hidden ForceField stops anything that uses
--TakeDamage, damage that sets Health directly is undone, and the InVehicle
--attribute tells the Random Arty barrages to pass them over.
local protected = {}

local function protect(human)
	local character = human.Parent
	if protected[human] or not character then return end
	local shield = Instance.new("ForceField")
	shield.Name = "VehicleArmor"
	shield.Visible = false
	shield.Parent = character
	character:SetAttribute("InVehicle",true)
	local kept = human.Health
	local guard = human.HealthChanged:Connect(function(health)
		if health >= kept then
			kept = health
		elseif health > 0 then
			human.Health = kept
		end
	end)
	protected[human] = {shield = shield,guard = guard}
end

local function unprotect(human)
	local entry = protected[human]
	if not entry then return end
	protected[human] = nil
	entry.guard:Disconnect()
	entry.shield:Destroy()
	if human.Parent then
		human.Parent:SetAttribute("InVehicle",nil)
	end
end

local function parachute(character,outward)
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	local human = character:FindFirstChildOfClass("Humanoid")
	if not root or not torso or not human or human.Health <= 0 then return end

	local canopy = Instance.new("Part")
	canopy.Name = "Parachute"
	canopy.Size = CHUTE_SIZE
	canopy.Color = CHUTE_COLOR
	canopy.Material = Enum.Material.Fabric
	canopy.CanCollide = false
	canopy.CanQuery = false
	canopy.CanTouch = false
	canopy.Massless = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = canopy
	canopy.CFrame = torso.CFrame * CFrame.new(0,CHUTE_HEIGHT,0)
	local weld = Instance.new("Weld")
	weld.Part0 = torso
	weld.Part1 = canopy
	weld.C0 = CFrame.new(0,CHUTE_HEIGHT,0)
	weld.Parent = canopy

	local harness = Instance.new("Attachment")
	harness.Name = "Harness"
	harness.Position = Vector3.new(0,1,0)
	harness.Parent = torso
	for _,corner in ipairs({Vector3.new(1,0,1),Vector3.new(-1,0,1),Vector3.new(1,0,-1),Vector3.new(-1,0,-1)}) do
		local rim = Instance.new("Attachment")
		rim.Position = Vector3.new(corner.X*CHUTE_SIZE.X*0.4,-CHUTE_SIZE.Y*0.2,corner.Z*CHUTE_SIZE.Z*0.4)
		rim.Parent = canopy
		local line = Instance.new("RopeConstraint")
		line.Attachment0 = harness
		line.Attachment1 = rim
		line.Length = CHUTE_HEIGHT + 2
		line.Visible = true
		line.Thickness = 0.05
		line.Color = BrickColor.new("Light stone grey")
		line.Parent = canopy
	end
	canopy.Parent = character

	local drag = Instance.new("LinearVelocity")
	drag.Name = "ParachuteDrag"
	drag.Attachment0 = harness
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.VectorVelocity = outward*DRIFT_SPEED - Vector3.new(0,FALL_SPEED,0)
	drag.MaxForce = root.AssemblyMass*workspace.Gravity*3
	drag.Parent = root

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {character,heli}
	local falling = 0
	while character.Parent and human.Health > 0 and falling < 60 do
		if human.FloorMaterial ~= Enum.Material.Air or workspace:Raycast(root.Position,Vector3.new(0,-3.5,0),params) then
			break
		end
		falling += task.wait()
	end

	drag:Destroy()
	harness:Destroy()
	canopy.Anchored = true
	weld:Destroy()
	tweenService:Create(canopy,TweenInfo.new(CHUTE_FADE),{Transparency = 1}):Play()
	debris:AddItem(canopy,CHUTE_FADE)
end

local function heightAboveGround()
	local below = groundY(body.Position)
	return below and body.Position.Y - below or math.huge
end

--How close a player has to be to a door for its prompt, and how long to hold it.
local PROMPT_DISTANCE = 12
local PROMPT_HOLD = 0.25

local seats = {
	{seat = pilotSeat, door = body.LeftDoor, action = "Fly"},
	{seat = gunnerSeat, door = body.RightDoor, action = "Gunner"},
}

local bailed = {}

--Getting in on the ground is through a prompt at each door. Anyone leaving is
--put down outside that door, and in the air he goes out on a parachute.
for _,entry in ipairs(seats) do
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = entry.action
	prompt.ObjectText = "Apache"
	prompt.HoldDuration = PROMPT_HOLD
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = entry.door

	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local human = character and character:FindFirstChildOfClass("Humanoid")
		if dead or not human or human.Health <= 0 or human.SeatPart or entry.seat.Occupant then return end
		entry.seat:Sit(human)
	end)

	local inside = nil
	entry.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		prompt.Enabled = entry.seat.Occupant == nil
		local leaving = inside
		inside = entry.seat.Occupant
		if inside then
			protect(inside)
		end
		if not leaving or leaving == inside then return end
		--Moving seats (the gunner taking the controls) is not leaving.
		task.delay(0.1,function()
			if leaving.SeatPart and leaving.SeatPart:IsDescendantOf(heli) then return end
			unprotect(leaving)
			local root = leaving.RootPart
			if leaving.SeatPart or not root or not root.Parent or (dead and not bailed[leaving]) then return end
			local door = entry.door.WorldPosition
			local outward = flat(door - body.Position)
			outward = outward.Magnitude > 0.1 and outward.Unit or Vector3.xAxis
			root.CFrame = CFrame.lookAt(door + outward*3,door + outward*4)
			if bailed[leaving] or heightAboveGround() > CHUTE_ABOVE then
				root.AssemblyLinearVelocity = body.AssemblyLinearVelocity + outward*EJECT_SPEED + Vector3.new(0,EJECT_UP,0)
				task.wait(CHUTE_DELAY)
				parachute(leaving.Parent,outward)
			end
		end)
	end)
end

--Both jump: out of the seats, and the seat handler above throws them clear.
local function bail()
	for _,seat in ipairs({pilotSeat,gunnerSeat}) do
		local occupant = seat.Occupant
		if occupant and occupant.Health > 0 then
			bailed[occupant] = true
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			occupant.Sit = false
		end
	end
end

local function setValue(settings,name,className,value)
	local holder = settings:FindFirstChild(name)
	if not holder then
		holder = Instance.new(className)
		holder.Name = name
		holder.Parent = settings
	end
	holder.Value = value
end

local function autoCrew()
	local autoValue = mySettings:FindFirstChild("AutoCrew")
	if heli:GetAttribute("SpawnedBy") or not autoValue or not autoValue.Value then return end
	local template = serverStorage:FindFirstChild(SOLDIER_NAME)
	if not template then return end

	local team = mySettings.Team.Value ~= "" and mySettings.Team.Value or "Hostile"
	local below = groundY(body.Position) or body.Position.Y
	for index,role in ipairs({"Driver","Gunner"}) do
		if dead or not heli.Parent then return end
		local soldier = template:Clone()
		local settings = soldier:FindFirstChild("Settings")
		if settings then
			setValue(settings,"Team","StringValue",team)
			setValue(settings,"AttackPlayers","BoolValue",team == "Hostile")
			setValue(settings,"Weapon","StringValue",CREW_WEAPON)
			setValue(settings,"Unit","StringValue",CREW_UNIT)
			setValue(settings,"Role","StringValue","Rifleman")
			setValue(settings,"Respawn","BoolValue",false)
			setValue(settings,"Vehicle","ObjectValue",heli)
			setValue(settings,"VehicleRole","StringValue",role)
		end
		soldier:SetAttribute("VehicleCrew",true)
		--On the ground under it; his own script seats him.
		local at = Vector3.new(body.Position.X + index*3,below + 3,body.Position.Z)
		soldier:PivotTo(CFrame.new(at))
		soldier.Parent = workspace
		task.wait(0.1)
	end
end
task.delay(CREW_DELAY,autoCrew)

---------------------------------------------------------------- dying

local function respawn()
	--One from the Vehicle Spawner is just removed, not put back.
	if not heli:GetAttribute("NoRespawn") then
		clone.Parent = homeParent or workspace
	end
	heli:Destroy()
end

--Sets the whole airframe alight: a fire on each visible part (the biggest
--ENGULF_PARTS of them, sized to the part) and black smoke off the largest.
local function engulf(model)
	local parts = {}
	for _,part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 and not part:FindFirstChild("EngulfFire") then
			parts[#parts+1] = part
		end
	end
	table.sort(parts,function(a,b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	for index = 1,math.min(#parts,ENGULF_PARTS) do
		local part = parts[index]
		local fire = Instance.new("Fire")
		fire.Name = "EngulfFire"
		fire.Size = math.clamp(math.max(part.Size.X,part.Size.Y,part.Size.Z)*0.4,4,ENGULF_MAX_FIRE)
		fire.Heat = 20
		fire.Color = Color3.fromRGB(255,120,30)
		fire.SecondaryColor = Color3.fromRGB(255,220,80)
		fire.Parent = part
		if index <= 3 then
			local smoke = Instance.new("Smoke")
			smoke.Size = ENGULF_MAX_FIRE
			smoke.RiseVelocity = 12
			smoke.Opacity = 0.7
			smoke.Color = Color3.fromRGB(30,30,30)
			smoke.Parent = part
		end
	end
end

local function char()
	for _,part in ipairs(heli:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.Color = WRECK_COLOR
		end
	end
end

local function fadeOut()
	local info = TweenInfo.new(FADE_TIME)
	for _,part in ipairs(heli:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			tweenService:Create(part,info,{Transparency = 1}):Play()
		end
	end
	task.wait(FADE_TIME)
end

--Spins down out of control, then blows up on the ground.
local function destroyed()
	if dead then return end
	dead = true
	heli:SetAttribute("Wrecked",true)
	heli:SetAttribute("MainGunReady",false)
	heli:SetAttribute("AimPoint",nil)

	--Whoever did not get out goes down with it.
	for _,seat in ipairs({pilotSeat,gunnerSeat}) do
		local occupant = seat.Occupant
		if occupant and not bailed[occupant] then
			unprotect(occupant)
			occupant.Health = 0
		end
	end
	task.delay(0.1,function()
		for _,seat in ipairs({pilotSeat,gunnerSeat}) do
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
		end
	end)

	engulf(heli)
	alignPosition.Enabled = false
	alignOrientation.Enabled = false
	pcall(claimPhysics)
	body.AssemblyAngularVelocity = Vector3.new(0,CRASH_SPIN,0)

	local falling = 0
	while heli.Parent and falling < CRASH_TIMEOUT and heightAboveGround() > body.Size.Y/2 + 2 do
		falling += task.wait()
	end
	if not heli.Parent then return end

	explode(body.Position,nil,"wreck")
	local artilleryBlast = serverStorage:FindFirstChild("ArtilleryBlast")
	if artilleryBlast then
		artilleryBlast:Fire(body.Position,CRASH_SCALE)
	end
	engineSound:Stop()
	char()

	local delay = mySettings.RespawnDelay.Value
	task.wait(math.min(WRECK_TIME,delay))
	fadeOut()
	--A placed one comes back after the full RespawnDelay; a spawned one is just gone.
	if not heli:GetAttribute("NoRespawn") then
		task.wait(math.max(delay - WRECK_TIME - FADE_TIME,0))
	end
	respawn()
end

--Watched on health, not Died: a Humanoid with no body has no state machine to
--die with, so Died never fires for it. Badly hit, the crew get out first.
humanoid.HealthChanged:Connect(function(health)
	if not dead and health <= humanoid.MaxHealth*BAIL_HEALTH and (pilotSeat.Occupant or gunnerSeat.Occupant) then
		bail()
		humanoid.Health = 0
	end
	if humanoid.Health <= 0 then
		task.spawn(destroyed)
	end
end)
humanoid.Died:Connect(destroyed)

---------------------------------------------------------------- loop

runService.Heartbeat:Connect(function(dt)
	if not body.Parent or dead then return end
	fly(dt)
	aim(dt)
	if position.Y < workspace.FallenPartsDestroyHeight + 20 then
		dead = true
		respawn()
	end
end)

while heli.Parent do
	pcall(claimPhysics)
	refreshFilter()
	task.wait(1)
end

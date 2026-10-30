--[[
	Crewing a vehicle (the Warthog, the Abrams, or anything built the same way).

	A vehicle is anything tagged "BloxianVehicle" (or "MarineVehicle") with a
	VehicleSeat (driver), a Seat (gunner) and an attachment called Tip where the
	turret's machine-gun rounds come out. The turret follows Body.Body.Aimer when
	there is one (the Warthog), otherwise the vehicle's AimPoint attribute (the
	Abrams). A vehicle with a FireMain event and a MainGun attachment also has a
	main gun. Its Settings.Team, if set, limits it to soldiers of that team.
	Optional attributes on the vehicle: EngageDistance, HalfWidth, AgentRadius
	(bigger vehicles), Speed (one not moved by physics).

	When a soldier has an enemy far enough away to be worth driving to and a
	free seat is close, he claims it (the vehicle's Driver / Gunner attribute),
	walks over and gets in.
		Driver  closes on the enemy, then circles him at ENGAGE_DISTANCE so the
		        gunner always has an angle. Backs out when stuck.
		Gunner  swings the turret onto the enemy, leading him, and fires bursts
		        whenever the barrel is on target with a clear line.
	The crew gets out when there has been no enemy for a while. They never bail:
	damaged or not, they fight it out and go up with the vehicle.
]]

local vehicle = {}

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local movement = require(modules.MovementModule)
local actions = require(modules.ActionsModule)
local combat = require(modules.CombatModule)
local tactics = require(modules.TacticsModule)
local chatter = require(modules.ChatterModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart
local mySettings = marine.Settings
local teamValue = mySettings.Team
local useVehiclesValue = mySettings:FindFirstChild("UseVehicles")

--Vehicles are found by tag. MarineVehicle is the tag the Warthog shipped with.
local TAGS = {"BloxianVehicle","MarineVehicle"}

--How far a soldier will walk to a free vehicle, and the closest an enemy can be
--for it to be worth getting in (closer than this he just fights on foot).
local MOUNT_RANGE = 80
local MOUNT_MIN_ENEMY_DISTANCE = 35

--A seat claimed but not sat in for this many seconds is given up.
local CLAIM_TIMEOUT = 15

--Get in when within this many studs of the seat, this close to its door, or
--this close to any side of the vehicle's body.
local BOARD_DISTANCE = 7
local DOOR_REACH = 3
local BODY_REACH = 3

--A driver whose crewmate is still on his way to the gun waits this many seconds for him.
local CREW_WAIT = 8

--How far out from the door attachment he stands to get in, clear of the body.
local DOOR_STANDOFF = 2

--Seconds with no enemy before the crew climbs out, and the vehicle health share
--below which nobody gets into it (a crew already aboard stays put).
local DISMOUNT_IDLE = 20
local BAIL_HEALTH = 0.25

--Driving: the range he circles the enemy at, and how far ahead on the circle he
--steers for. Further than ENGAGE_DISTANCE + APPROACH_SLACK he drives straight in.
local ENGAGE_DISTANCE = 45
local APPROACH_SLACK = 15
local ORBIT_LEAD = 25

--Running people over: within RAM_DISTANCE of an enemy on foot he may go for him
--instead of circling. With no gunner aboard he always does; otherwise he decides
--every RAM_DECIDE seconds with RAM_CHANCE odds. After a pass he keeps going for
--PASS_TIME seconds before turning back for another.
local RAM_DISTANCE = 60
local RAM_CHANCE = 0.5
local RAM_DECIDE = 6
local PASS_TIME = 1.5

--Seconds the driver's seat sits empty (driver dead or out) before the gunner
--climbs over and takes the wheel.
local TAKE_WHEEL_DELAY = 3

--Degrees off course for full steering lock, and above which he slows for the turn.
local STEER_FULL_ANGLE = 35
local SLOW_TURN_ANGLE = 60
local TURN_THROTTLE = 0.6

--Stuck: barely moving for this long with the throttle open, so back out for REVERSE_TIME.
local STUCK_SPEED = 2
local STUCK_TIME = 2
local REVERSE_TIME = 1.5

--Path round obstacles: waypoints count as reached this close, and the path is
--worked out again this often.
local PATH_REACH = 8
local PATH_REFRESH = 2

--Turret: damage per round, seconds between rounds, rounds per burst and the pause
--after, spread in degrees, bullet speed and range, and how close (degrees) the
--barrel has to be on target before firing.
local TURRET_DAMAGE = {8, 14}
local TURRET_INTERVAL = 0.08
local TURRET_BURST = 12
local TURRET_COOLDOWN = 0.8
local TURRET_SPREAD = 1.5
local TURRET_SPEED = 600
local TURRET_RANGE = 220
local AIM_TOLERANCE = 12
local TURRET_TRACER = Color3.fromRGB(255,40,30)

--Barrel spin speed while firing.
local BARREL_SPIN = 30

--Main gun: how close (degrees) it has to be on target, and the closest and
--furthest he fires it at.
local MAIN_GUN_TOLERANCE = 3
local MAIN_GUN_MIN_RANGE = 20
local MAIN_GUN_MAX_RANGE = 400

--Enemy vehicles: how far a crew looks for one (crewed by an enemy, in sight of
--the gun), and how often they look again. A vehicle in sight comes before men
--on foot.
local VEHICLE_SIGHT_RANGE = 350
local VEHICLE_RECHECK = 0.5

local myId = tostring(math.random(1,1e9))
marine:SetAttribute("BloxianId",myId)

local role = nil --nil, "Driver" or "Gunner"
local ride = nil
local claimedAt = 0
local lastEnemyAt = 0

--A soldier spawned as a vehicle's crew (the Vehicle Spawner sets Settings.Vehicle
--and Settings.VehicleRole) takes that seat at once and stays in it, enemy or not,
--until he is thrown out or the vehicle is wrecked.
local assignedVehicle = mySettings:FindFirstChild("Vehicle")
local assignedRole = mySettings:FindFirstChild("VehicleRole")
local stayIn = false

local function flat(v)
	return Vector3.new(v.X,0,v.Z)
end

--The vehicle's main body part: what it is measured from.
local function bodyOf(car)
	return car.PrimaryPart or (car:FindFirstChild("Body") and car.Body:FindFirstChild("Body"))
end

--Named parts deep inside a vehicle, looked up once.
local found = setmetatable({},{__mode = "k"})
local function partOf(car,name)
	local cache = found[car]
	if not cache then
		cache = {}
		found[car] = cache
	end
	local hit = cache[name]
	if hit == nil or (hit and not hit:IsDescendantOf(car)) then
		hit = car:FindFirstChild(name,true) or false
		cache[name] = hit
	end
	return hit or nil
end

local function carSpeed(car)
	local speed = car:GetAttribute("Speed")
	if speed then return speed end
	local body = bodyOf(car)
	return body and body.AssemblyLinearVelocity.Magnitude or 0
end

local function stopBarrel(car)
	local tip = partOf(car,"Tip")
	local motor = tip and tip.Parent:FindFirstChild("BarrelMotor")
	if motor then
		motor.AngularVelocity = 0
	end
end

local function seatFor(car,which)
	return which == "Driver" and car:FindFirstChild("VehicleSeat") or car:FindFirstChild("Seat")
end

--Where to stand to get in. The seats sit inside the body's collision, so walking
--to the seat itself has no path: he goes to the door on that side instead
--(FrontDoor for the driver, SideDoor for the gunner), a little out from the car.
--How far he is from the side of the vehicle's body (0 when right up against it).
local function distanceToBody(car)
	local body = bodyOf(car)
	if not body then return math.huge end
	local offset = body.CFrame:PointToObjectSpace(myRoot.Position)
	local half = body.Size/2
	return Vector2.new(math.max(math.abs(offset.X) - half.X,0),math.max(math.abs(offset.Z) - half.Z,0)).Magnitude
end

local function boardingPoint(car,which,seat)
	local body = bodyOf(car)
	local door = body and body:FindFirstChild(which == "Driver" and "FrontDoor" or "SideDoor")
	if not door then
		return seat.Position
	end

	local point = door.WorldPosition
	local outward = Vector3.new(point.X - body.Position.X,0,point.Z - body.Position.Z)
	if outward.Magnitude > 0.1 then
		point += outward.Unit*DOOR_STANDOFF
	end
	return point
end

local function carHealth(car)
	local human = car:FindFirstChildOfClass("Humanoid")
	if not human then return 1 end
	return human.Health/human.MaxHealth
end

local function usable(car)
	if not car.Parent or carHealth(car) <= BAIL_HEALTH then return false end
	local carTeam = car:FindFirstChild("Settings") and car.Settings:FindFirstChild("Team")
	return not carTeam or carTeam.Value == "" or carTeam.Value == teamValue.Value
end

--The Warthog ships with Driver / Gunner set to false, which the original kit
--used for "free". Only a soldier's id counts as a claim.
local function claimed(car,which)
	local claim = car:GetAttribute(which)
	return claim ~= nil and claim ~= false
end

local function seatFree(car,which)
	local seat = seatFor(car,which)
	return seat ~= nil and seat.Occupant == nil and not claimed(car,which)
end

--The vehicle's script reads AIThrottle / AISteer when they are set: a seated NPC
--sends the seat no input, so ThrottleFloat alone is not reliable.
local function setControls(car,throttle,steer)
	car:SetAttribute("AIThrottle",throttle)
	car:SetAttribute("AISteer",steer)
	local seat = car:FindFirstChild("VehicleSeat")
	if seat then
		seat.ThrottleFloat = throttle or 0
		seat.SteerFloat = steer or 0
	end
end

local function release()
	if ride and ride:GetAttribute(role) == myId then
		ride:SetAttribute(role,false)
	end
	if role == "Gunner" and ride then
		stopBarrel(ride)
		ride:SetAttribute("AimPoint",nil)
	end
	if role == "Driver" and ride then
		setControls(ride,nil,nil)
	end
	role = nil
	ride = nil
	stayIn = false
	status:set("mounted",nil)
end

local function getOut(reason)
	log("vehicle","getting out: "..reason)
	release()
	if myHuman.Sit then
		myHuman.Sit = false
		myHuman.Jump = true
	end
end

--A corpse left welded in a seat would block it for as long as the body lies there.
myHuman.Died:Connect(function()
	if ride and role then
		local seat = seatFor(ride,role)
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	release()
end)
marine.Destroying:Connect(release)

--Squadmates leave a soldier who is in a vehicle out of their squad.
local radioEntry = _G.BloxianRadio and _G.BloxianRadio[marine]
if radioEntry then
	radioEntry.isMounted = function()
		return status:get("mounted") ~= nil
	end
end

local function currentEnemy()
	local target = status:get("currentTarget")
	if target and target.Parent then
		return target
	end
	return nil
end

--A free seat close by, driver first. nil and the reason when there is none.
local function findSeat()
	local best,bestRole,bestDist = nil,nil,MOUNT_RANGE
	local seen,count = {},0
	for _,tag in ipairs(TAGS) do
		for _,car in ipairs(CollectionService:GetTagged(tag)) do
			if not seen[car] then
				seen[car] = true
				count += 1
			end
		end
	end

	local nearestDist,nearestWhy = math.huge,nil
	for car in pairs(seen) do
		local body = bodyOf(car)
		local dist = body and (body.Position - myRoot.Position).Magnitude or math.huge
		local why
		if not car:IsDescendantOf(workspace) then
			why = "not in Workspace"
		elseif not usable(car) then
			why = carHealth(car) <= BAIL_HEALTH and "too damaged" or "set to another team"
		else
			local which = seatFree(car,"Driver") and "Driver" or (seatFree(car,"Gunner") and "Gunner")
			if not which then
				why = "both seats taken"
			else
				local seatDist = (seatFor(car,which).Position - myRoot.Position).Magnitude
				if seatDist < bestDist then
					best,bestRole,bestDist = car,which,seatDist
				else
					why = string.format("%d studs away, over MOUNT_RANGE %d",math.floor(seatDist),MOUNT_RANGE)
				end
			end
		end
		if why and dist < nearestDist then
			nearestDist,nearestWhy = dist,why
		end
	end

	if best then
		return best,bestRole
	end
	if count == 0 then
		return nil,nil,"no vehicle tagged BloxianVehicle or MarineVehicle in the game"
	end
	return nil,nil,string.format("%d vehicle(s); nearest is %s",count,nearestWhy or "unusable")
end

local function wantsToMount(enemy)
	if useVehiclesValue and not useVehiclesValue.Value then return false end
	if not enemy or myHuman.Health/myHuman.MaxHealth < 0.3 then return false end
	return (enemy.Position - myRoot.Position).Magnitude >= MOUNT_MIN_ENEMY_DISTANCE
end

---------------------------------------------------------------- driving

--One path object per vehicle width.
local carPaths = {}
local function pathFor(car)
	local radius = car:GetAttribute("AgentRadius") or 5
	carPaths[radius] = carPaths[radius] or PathfindingService:CreatePath({AgentRadius = radius, AgentHeight = 6, AgentCanJump = false, WaypointSpacing = 8})
	return carPaths[radius]
end
local pathWaypoints,pathIndex,pathAt,pathGoal = nil,1,-math.huge,nil
local ramming,ramDecidedAt,passUntil = false,-math.huge,0
local waitingSince = nil
local stuckSince,reverseUntil,reverseSteer = nil,0,0
local orbitDirection = math.random(2) == 1 and 1 or -1

local function clearRun(car,from,to)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {car,marine}
	local offset = flat(to - from)
	local length = math.min(offset.Magnitude,40)
	if length < 1 then return true end
	local dir = offset.Unit
	local side = dir:Cross(Vector3.yAxis)*(car:GetAttribute("HalfWidth") or 3)
	for _,lane in ipairs({Vector3.zero,side,-side}) do
		if workspace:Raycast(from + lane + Vector3.new(0,1,0),dir*length,params) then
			return false
		end
	end
	return true
end

--Where to steer: straight at goal if the way is clear, else the next point of a
--path round whatever is in the way.
local function steerPoint(car,seat,goal)
	if clearRun(car,seat.Position,goal) then
		pathWaypoints = nil
		return goal
	end

	local now = os.clock()
	if not pathWaypoints or now - pathAt > PATH_REFRESH or (pathGoal and (goal - pathGoal).Magnitude > 15) then
		pathAt = now
		pathGoal = goal
		local carPath = pathFor(car)
		local ok = pcall(carPath.ComputeAsync,carPath,seat.Position,goal)
		pathWaypoints = ok and carPath.Status == Enum.PathStatus.Success and carPath:GetWaypoints() or nil
		pathIndex = 2
	end

	if pathWaypoints then
		while pathWaypoints[pathIndex] and flat(pathWaypoints[pathIndex].Position - seat.Position).Magnitude < PATH_REACH do
			pathIndex += 1
		end
		local waypoint = pathWaypoints[pathIndex]
		if waypoint then
			return waypoint.Position
		end
	end
	return goal
end

local function drive(car,enemy)
	local seat = car.VehicleSeat
	if not enemy then
		setControls(car,0,0)
		return
	end

	local fromEnemy = flat(seat.Position - enemy.Position)
	local dist = fromEnemy.Magnitude
	local clock = os.clock()

	--Decide whether to run him over. Someone sitting in a vehicle is not worth ramming.
	local gunSeat = car:FindFirstChild("Seat")
	local hasGunner = gunSeat and gunSeat.Occupant ~= nil

	--A crewmate on his way to the gun: hold still so he can catch up, for a while.
	if gunSeat and not hasGunner and claimed(car,"Gunner") then
		waitingSince = waitingSince or clock
		if clock - waitingSince < CREW_WAIT then
			setControls(car,0,0)
			return
		end
	else
		waitingSince = nil
	end
	local enemyHuman = enemy.Parent and enemy.Parent:FindFirstChildOfClass("Humanoid")
	local onFoot = enemyHuman and enemyHuman.RootPart and not enemyHuman.Sit
	if clock - ramDecidedAt > RAM_DECIDE then
		ramDecidedAt = clock
		local wasRamming = ramming
		ramming = onFoot and (not hasGunner or math.random() < RAM_CHANCE)
		if ramming and not wasRamming then
			log("vehicle","going to run him over")
		end
	end

	--Just went past him: keep going a moment, then swing round for another pass.
	local forwardNow = flat(seat.CFrame.LookVector)
	if ramming and dist < 12 and forwardNow.Magnitude > 0.01 and forwardNow.Unit:Dot(-fromEnemy.Unit) < 0 then
		passUntil = clock + PASS_TIME
	end

	local engageDistance = car:GetAttribute("EngageDistance") or ENGAGE_DISTANCE
	local goal
	if clock < passUntil then
		goal = seat.Position + forwardNow.Unit*30
	elseif ramming and onFoot and dist < RAM_DISTANCE then
		--Aim where he is going to be.
		local lead = math.clamp(dist/30,0,1)
		goal = enemy.Position + flat(enemy.AssemblyLinearVelocity)*lead
	elseif dist > engageDistance + APPROACH_SLACK or dist < 1 then
		--Close in, then circle him so the gunner keeps an angle and the car keeps moving.
		goal = enemy.Position
	else
		local radial = fromEnemy.Unit
		local tangent = radial:Cross(Vector3.yAxis)*orbitDirection
		goal = enemy.Position + radial*engageDistance + tangent*ORBIT_LEAD
	end

	local point = steerPoint(car,seat,goal)
	local forward = flat(seat.CFrame.LookVector)
	local toPoint = flat(point - seat.Position)
	if forward.Magnitude < 0.01 or toPoint.Magnitude < 0.5 then return end
	forward,toPoint = forward.Unit,toPoint.Unit

	--Signed angle, positive when the point is to his right.
	local angle = math.deg(math.acos(math.clamp(forward:Dot(toPoint),-1,1)))
	if forward:Cross(toPoint).Y > 0 then
		angle = -angle
	end

	local now = os.clock()
	local steer = math.clamp(angle/STEER_FULL_ANGLE,-1,1)
	local throttle = math.abs(angle) > SLOW_TURN_ANGLE and TURN_THROTTLE or 1

	--Stuck against something: back out with the wheel turned the other way.
	local speed = carSpeed(car)
	if now < reverseUntil then
		setControls(car,-1,reverseSteer)
		return
	end
	if speed < STUCK_SPEED then
		stuckSince = stuckSince or now
		if now - stuckSince > STUCK_TIME then
			log("vehicle","stuck, backing out")
			reverseUntil = now + REVERSE_TIME
			reverseSteer = -steer
			stuckSince = nil
			pathWaypoints = nil
			orbitDirection = -orbitDirection
		end
	else
		stuckSince = nil
	end

	setControls(car,throttle,steer)
end

---------------------------------------------------------------- gunning

local firing = false
local lastBurstEnd = 0
local flashIndex = 0

local function turretParams(car)
	local params = RaycastParams.new()
	local exclude = {car,marine}
	for _,seatName in ipairs({"VehicleSeat","Seat"}) do
		local seat = car:FindFirstChild(seatName)
		if seat and seat.Occupant then
			exclude[#exclude+1] = seat.Occupant.Parent
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

--What a round has to hit to count: the target's vehicle when it is one or he is
--sitting in one (a crew is mostly hidden inside), otherwise his body.
local function targetModel(target)
	local car = core.vehicleOf(target)
	if car then
		return car
	end
	local human = target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
	local seatCar = human and human.SeatPart and core.vehicleOf(human.SeatPart)
	return seatCar or target.Parent
end

local function lineToEnemy(car,from,enemy)
	local offset = enemy.Position - from
	local result = workspace:Raycast(from,offset.Unit*(offset.Magnitude + 3),turretParams(car))
	return result ~= nil and result.Instance:IsDescendantOf(targetModel(enemy))
end

local vehicleTarget,vehicleCheckedAt = nil,-math.huge

--The nearest vehicle crewed by an enemy that the gun can see, or nil. Its body
--part is the target.
local function enemyVehicle(car)
	local now = os.clock()
	if now - vehicleCheckedAt < VEHICLE_RECHECK then
		return vehicleTarget and vehicleTarget.Parent and vehicleTarget or nil
	end
	vehicleCheckedAt = now
	vehicleTarget = nil

	local tip = partOf(car,"Tip")
	local from = tip and tip.WorldPosition or myRoot.Position
	local params = turretParams(car)
	local best = math.max(VEHICLE_SIGHT_RANGE,car:GetAttribute("SpotRange") or 0)
	local seen = {}
	for _,tag in ipairs(TAGS) do
		for _,other in ipairs(CollectionService:GetTagged(tag)) do
			if not seen[other] and other ~= car and other:IsDescendantOf(workspace) and carHealth(other) > 0 and core.isEnemyVehicle(other) then
				seen[other] = true
				local body = bodyOf(other)
				local dist = body and (body.Position - from).Magnitude
				if dist and dist < best then
					local result = workspace:Raycast(from,(body.Position - from).Unit*(dist + 3),params)
					if result and result.Instance:IsDescendantOf(other) then
						best,vehicleTarget = dist,body
					end
				end
			end
		end
	end
	return vehicleTarget
end

local function burst(car,enemy)
	firing = true
	local tip = partOf(car,"Tip")
	local barrel = tip.Parent
	local motor = barrel:FindFirstChild("BarrelMotor")
	local flashGui = tip:FindFirstChild("FlashBG")
	local light = tip:FindFirstChild("PointLight")
	local shoot = barrel:FindFirstChild("Shoot")
	local shot = {damage = TURRET_DAMAGE, speed = TURRET_SPEED, range = TURRET_RANGE, color = TURRET_TRACER, params = turretParams(car)}

	if motor then motor.AngularVelocity = BARREL_SPIN end
	--Only a man is passed on to the squad as a contact; a vehicle is the crew's business.
	if not core.vehicleOf(enemy) then
		chatter.shareContact(enemy)
	end

	for _ = 1,TURRET_BURST do
		if role ~= "Gunner" or not enemy.Parent or myHuman.Health <= 0 or not tip.Parent then break end
		--Rounds go at where he will be while the barrel is roughly on him.
		local muzzle = tip.WorldCFrame
		local aimAt = core.leadPoint(enemy,muzzle.Position,TURRET_SPEED)
		if muzzle.LookVector:Dot((aimAt - muzzle.Position).Unit) > math.cos(math.rad(AIM_TOLERANCE)) then
			muzzle = CFrame.lookAt(muzzle.Position,aimAt)
		end
		combat.fireFrom(muzzle,TURRET_SPREAD,shot)

		--A copy per round, so each shot rings out instead of cutting off the last.
		if shoot then
			local round = shoot:Clone()
			round.Parent = barrel
			round:Play()
			Debris:AddItem(round,3)
		end
		if tip:FindFirstChild("Flash") then tip.Flash:Emit(1) end
		if flashGui then
			flashIndex = flashIndex % 3 + 1
			local flash = flashGui:FindFirstChild("Flash"..flashIndex)
			if flash then
				flash.Visible = true
				task.delay(TURRET_INTERVAL*0.8,function() flash.Visible = false end)
			end
		end
		if light then
			light.Enabled = true
			task.delay(TURRET_INTERVAL*0.8,function() light.Enabled = false end)
		end
		task.wait(TURRET_INTERVAL)
	end

	if motor then motor.AngularVelocity = 0 end
	lastBurstEnd = os.clock()
	firing = false
end

--The main gun: fired when it is on him, loaded, and he is far enough off for the blast.
local function mainGun(car,enemy)
	local fire = car:FindFirstChild("FireMain")
	local muzzle = partOf(car,"MainGun")
	if not fire or not muzzle or not car:GetAttribute("MainGunReady") then return end
	local from = muzzle.WorldPosition
	local dist = (enemy.Position - from).Magnitude
	if dist < MAIN_GUN_MIN_RANGE or dist > MAIN_GUN_MAX_RANGE then return end
	local aimPoint = core.leadPoint(enemy,from,car:GetAttribute("ShellSpeed") or 500)
	local onTarget = muzzle.WorldCFrame.LookVector:Dot((aimPoint - from).Unit) > math.cos(math.rad(MAIN_GUN_TOLERANCE))
	if onTarget and lineToEnemy(car,from,enemy) then
		log("vehicle","main gun")
		fire:Fire(marine)
	end
end

local function gun(car,enemy)
	local body = bodyOf(car)
	local aimer = body and body:FindFirstChild("Aimer")
	local tip = partOf(car,"Tip")
	if not tip or not enemy then return end

	--Lead a moving enemy by the bullet's flight time.
	local tipPos = tip.WorldPosition
	local aimPoint = core.leadPoint(enemy,tipPos,TURRET_SPEED)
	if aimer then
		aimer.WorldCFrame = CFrame.lookAt(aimer.WorldPosition,aimPoint)
	else
		car:SetAttribute("AimPoint",aimPoint)
	end
	--Tracks anything he can see, but holds fire beyond the vehicle's FireRange.
	local fireRange = car:GetAttribute("FireRange")
	if fireRange and (enemy.Position - tipPos).Magnitude > fireRange then return end
	mainGun(car,enemy)

	if firing or os.clock() - lastBurstEnd < TURRET_COOLDOWN then return end
	if (enemy.Position - tipPos).Magnitude > TURRET_RANGE then return end

	local onTarget = tip.WorldCFrame.LookVector:Dot((aimPoint - tipPos).Unit) > math.cos(math.rad(AIM_TOLERANCE))
	if onTarget and lineToEnemy(car,tipPos,enemy) then
		task.spawn(burst,car,enemy)
	end
end

---------------------------------------------------------------- the soldier's side

local driverGoneSince = nil
local switchedAt = -math.huge
local seenRoadkills = nil
local seenGunKills = nil

--The gunner climbs over into the empty driver's seat.
local function takeWheel()
	local gunSeat = ride:FindFirstChild("Seat")
	local driverSeat = ride:FindFirstChild("VehicleSeat")
	if not gunSeat or not driverSeat then return end

	local weld = gunSeat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	stopBarrel(ride)
	ride:SetAttribute("AimPoint",nil)
	if ride:GetAttribute("Gunner") == myId then
		ride:SetAttribute("Gunner",false)
	end

	ride:SetAttribute("Driver",myId)
	role = "Driver"
	status:set("mounted","Driver")
	switchedAt = os.clock()
	driverGoneSince = nil
	seenRoadkills = nil
	driverSeat:Sit(myHuman)
	log("vehicle","driver's down, taking the wheel")
	chatter.callout("mountDriver",nil,0.8)
end

--Runs the vehicle for this tick. True while he is in, or on his way to, a vehicle.
function vehicle.update()
	local enemy = currentEnemy()
	local now = os.clock()
	if enemy then
		lastEnemyAt = now
	end

	--In a vehicle.
	if ride and status:get("mounted") then
		local seat = seatFor(ride,role)
		--Moving seats takes a moment to register.
		local settling = now - switchedAt < 1
		if not ride.Parent or not seat or (seat.Occupant ~= myHuman and not settling) then
			log("vehicle","thrown out")
			release()
			return false
		end
		--An enemy vehicle in sight comes first, then whoever he was fighting.
		local foe = enemyVehicle(ride) or enemy
		if foe then
			lastEnemyAt = now
		end
		if not stayIn and now - lastEnemyAt > DISMOUNT_IDLE then
			getOut("no enemy for a while")
			return false
		end

		if role == "Gunner" then
			--Nobody driving: after a moment the gunner moves over and drives.
			if seatFree(ride,"Driver") then
				driverGoneSince = driverGoneSince or now
				if now - driverGoneSince > TAKE_WHEEL_DELAY then
					takeWheel()
					return true
				end
			else
				driverGoneSince = nil
			end
		end

		if role == "Driver" then
			--The vehicle counts the people it runs over.
			local roadkills = ride:GetAttribute("Roadkills") or 0
			if seenRoadkills and roadkills > seenRoadkills then
				log("vehicle","ran him over")
				chatter.kill()
			end
			seenRoadkills = roadkills
			drive(ride,foe)
		else
			local gunKills = ride:GetAttribute("GunKills") or 0
			if seenGunKills and gunKills > seenGunKills then
				log("vehicle","main gun got one")
				chatter.kill()
			end
			seenGunKills = gunKills
			gun(ride,foe)
		end
		return true
	end

	--Heading for a claimed seat.
	if ride then
		local seat = seatFor(ride,role)

		--Sit() can take a moment to register: he is in once Occupant is him.
		if seat and seat.Occupant == myHuman then
			status:set("mounted",role)
			log("vehicle","in the "..role:lower().."'s seat")
			return true
		end

		local taken = seat and seat.Occupant ~= nil
		if not seat or taken or not usable(ride) or (not enemy and not stayIn) or now - claimedAt > CLAIM_TIMEOUT then
			log("vehicle","gave up on the seat")
			release()
			return false
		end

		local door = boardingPoint(ride,role,seat)
		if (seat.Position - myRoot.Position).Magnitude <= BOARD_DISTANCE
			or Vector3.new(door.X - myRoot.Position.X,0,door.Z - myRoot.Position.Z).Magnitude <= DOOR_REACH
			or distanceToBody(ride) <= BODY_REACH then
			movement.stop()
			actions.yieldWeapons()
			seat:Sit(myHuman)
		else
			movement.navigate(door)
		end
		return true
	end

	--Spawned as crew: straight into the assigned seat, once.
	if assignedVehicle then
		local car = assignedVehicle.Value
		local which = assignedRole and assignedRole.Value
		assignedVehicle = nil
		if car and car.Parent and (which == "Driver" or which == "Gunner") and seatFree(car,which) then
			ride,role,claimedAt = car,which,now
			stayIn = true
			seenRoadkills = nil
			seenGunKills = nil
			driverGoneSince = nil
			car:SetAttribute(which,myId)
			seatFor(car,which):Sit(myHuman)
			log("vehicle","spawned as the "..which:lower())
			return true
		end
	end

	--On foot: worth getting in?
	if wantsToMount(enemy) then
		local car,which,why = findSeat()
		if not car then
			log("vehicle","wants a vehicle, none usable: "..tostring(why),5)
		end
		if car then
			ride,role,claimedAt = car,which,now
			seenRoadkills = nil
			seenGunKills = nil
			driverGoneSince = nil
			car:SetAttribute(which,myId)
			--Whatever he was doing on foot is over: give up his cover spot, and a
			--stalking guerrilla gets his voice back for the crew calls.
			tactics.release()
			status:set("stealth",false)
			log("vehicle","claimed the "..which:lower().."'s seat")
			chatter.callout(which == "Driver" and "mountDriver" or "mountGunner",nil,0.7)
			return true
		end
	end
	return false
end

function vehicle.mounted()
	return status:get("mounted") ~= nil
end

return vehicle

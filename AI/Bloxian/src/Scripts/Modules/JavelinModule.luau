--[[
	The AT team's Javelin.

	The Rocketeer carries a launcher slung on his back and his carbine for
	everything else. When an enemy-crewed vehicle is in sight and in range, he
	slings the carbine, shoulders the launcher, locks on, and fires a missile
	that climbs and dives onto the vehicle from above (top attack), following it
	as it moves. One hit wrecks a Warthog; two wreck an Abrams. Enemy aircraft
	(tagged BloxianAircraft, like the Apache) are fair game too: one hit.

	In a team on its own, with nothing in sight he hunts; a team a squad brought
	stays with that squad instead (SpecialTeamModule). Every other soldier who sees an enemy
	vehicle calls it out ("Armor! Get AT on it!") and reports it to his side;
	the Rocketeer takes the nearest fresh report within HUNT_RANGE, says he is
	moving, and walks toward it until he can see it. With nothing reported he
	patrols around where he was put down. He stands still while reloading.

	A launcher is good for one shot: he drops the empty one and it despawns.
	A fresh one is on his back once he has reloaded: quickly with his Loader
	beside him, slowly alone.

	The launcher is the model ServerStorage.BloxianJavelin (the FGM-148 shipped
	in assets/Javelin.rbxm); without it, one built from parts stands in.
]]

local javelin = {}

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local actions = require(modules.ActionsModule)
local log = require(modules.Troubleshoot).log
local specialTeam = require(modules.SpecialTeamModule)
local chatter = require(modules.ChatterModule)
local movement = require(modules.MovementModule)

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local myHuman = marine.Humanoid
local myTorso = marine.Torso
local unitValue = marine.Settings:FindFirstChild("Unit")
local unit = unitValue and unitValue.Value or "Infantry"

--The launcher model in ServerStorage, and where it is held, in the space of
--its biggest part (the tube, which runs along -X to the muzzle): the middle of the
--tube, which rests on his shoulder, turned so the sight is on top.
local MODEL_NAME = "BloxianJavelin"
local MODEL_HOLD = CFrame.new(0.03,0.49,0)*CFrame.Angles(0,math.pi/2,0)*CFrame.Angles(0,0,math.pi)

--How far ahead of the hold point the muzzle is, and how far behind it the rear end.
local MUZZLE = 2.8
local REAR = 2.35

--The launch sound.
local LAUNCH_SOUND = "rbxassetid://112204190873336"

--Seconds a dropped launcher lies on the ground before it despawns.
local DROP_DESPAWN = 20

--Missile damage to a vehicle it hits (armour does not count). A Warthog has 400
--health and an Abrams 3000, so 1600 is one Warthog or half an Abrams. Vehicles
--only caught in the blast take SPLASH of it.
local VEHICLE_DAMAGE = 1600
local SPLASH = 0.25

--Missile damage to an aircraft it hits. The Apache has 1500 health.
local AIRCRAFT_DAMAGE = 1600

--Blast on people: dead within KILL_RADIUS, up to WOUND of max health out to BLAST_RADIUS.
local BLAST_RADIUS = 14
local KILL_RADIUS = 4
local WOUND = 0.9

--Closest and furthest he fires at, and how far he spots vehicles (it raises his
--and his Loader's DetectionRange to this).
local MIN_RANGE = 25
local MAX_RANGE = 500

--Seconds shouldered before the missile is away (the lock), and seconds to reload
--with the Loader within LOADER_RANGE, or alone.
local LOCK_TIME = 1.5
local RELOAD_WITH_LOADER = 15
local RELOAD_ALONE = 30
local LOADER_RANGE = 12

--Missile speed in studs per second, and how high the top-attack climb goes:
--CLIMB of the distance, between MIN_CLIMB and MAX_CLIMB studs.
--How far off he hears of an enemy vehicle and goes after it.
local HUNT_RANGE = 1000

--Soldiers look for enemy vehicles to report this often; a report goes stale
--after REPORT_MEMORY seconds without anyone seeing it, and one vehicle is
--called out again at most every CALL_AGAIN seconds.
local REPORT_INTERVAL = 1.5
local REPORT_MEMORY = 45
local CALL_AGAIN = 40

--With nothing to hunt he patrols: legs out to this far from where he was put
--down, a pause between legs, and a leg he cannot finish in time is dropped.
local PATROL_RADIUS = 150
local PATROL_PAUSE_MIN = 3
local PATROL_PAUSE_MAX = 6
local PATROL_LEG_TIME = 30

local MISSILE_SPEED = 140
local CLIMB = 0.35
local MIN_CLIMB = 25
local MAX_CLIMB = 120

--Where the launcher sits against his torso: slung muzzle-up across his back,
--and on his left shoulder (the sight, on top and to the tube's right, comes to
--his eye) tilted up a little.
local CARRY = CFrame.new(0,0.2,1.05)*CFrame.Angles(0,0,math.rad(-30))*CFrame.Angles(math.rad(90),0,0)
local SHOULDER = CFrame.new(-0.7,1.3,0.3)*CFrame.Angles(math.rad(6),0,0)

--Seconds to bring the launcher up to the shoulder, to let go of it, and the kick on launch.
local RAISE_TIME = 0.45
local LET_GO_TIME = 0.3
local RECOIL = CFrame.new(0,0.12,0.4)*CFrame.Angles(math.rad(7),0,0)
local RECOIL_TIME = 0.25

--His arms on the launcher, against his torso: from the shoulder end to the hand.
--The right hand reaches across to the sight's side, the left holds the tube up from below.
local RIGHT_HOLD = {Vector3.new(1.4,0.9,-0.3),Vector3.new(0.4,1.7,-1.2)}
local LEFT_HOLD = {Vector3.new(-1.5,0.7,-0.2),Vector3.new(-0.7,0.95,-1.9)}

local OLIVE = Color3.fromRGB(93,98,72)
local DARK = Color3.fromRGB(45,48,38)
local BLACK = Color3.fromRGB(25,25,25)
local CYLINDER = CFrame.Angles(0,math.pi/2,0)

local function makePart(name,size,cframe,color,shape,parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Shape = shape or Enum.PartType.Block
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function weldAll(root,model)
	for _,part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
end

--A launcher built from parts around root, the middle of the tube (-Z is the
--muzzle end), with the sight on top and to its right like the model's.
local function builtLauncher(model,root)
	local at = root.CFrame
	local length = MUZZLE + REAR
	makePart("Tube",Vector3.new(length,0.55,0.55),at*CFrame.new(0,0,(REAR - MUZZLE)/2)*CYLINDER,OLIVE,Enum.PartType.Cylinder,model)
	makePart("FrontCap",Vector3.new(0.3,0.66,0.66),at*CFrame.new(0,0,-MUZZLE)*CYLINDER,DARK,Enum.PartType.Cylinder,model)
	makePart("RearCap",Vector3.new(0.4,0.7,0.7),at*CFrame.new(0,0,REAR)*CYLINDER,DARK,Enum.PartType.Cylinder,model)
	makePart("Sight",Vector3.new(0.6,0.8,1.2),at*CFrame.new(0.55,0.3,-1.5),DARK,nil,model)
	makePart("Eyepiece",Vector3.new(0.25,0.22,0.2),at*CFrame.new(0.55,0.2,-0.85),BLACK,nil,model)
	makePart("Handle",Vector3.new(0.2,0.5,0.3),at*CFrame.new(0.42,1.0,-2.1),BLACK,nil,model)
end

--The shipped model's parts laid along root, stripped of anything but looks.
local function fitModel(template,model,root)
	local copy = template:Clone()
	local tube,biggest = nil,0
	for _,item in ipairs(copy:GetDescendants()) do
		if item:IsA("LuaSourceContainer") or item:IsA("JointInstance") or item:IsA("WeldConstraint")
			or item:IsA("Constraint") or item:IsA("Sound") or item:IsA("Camera") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			local volume = item.Size.X*item.Size.Y*item.Size.Z
			if volume > biggest then
				tube,biggest = item,volume
			end
		end
	end
	if not tube then
		copy:Destroy()
		return false
	end

	local move = root.CFrame*(tube.CFrame*MODEL_HOLD):Inverse()
	for _,part in ipairs(copy:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = move*part.CFrame
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.Parent = model
		end
	end
	copy:Destroy()
	return true
end

--A launcher on his back, welded to his torso at CARRY. Returns the weld that moves it,
--its root (the rear of the tube) and the model.
local function fitLauncher()
	local model = Instance.new("Model")
	model.Name = "Javelin"
	local root = makePart("JavelinRoot",Vector3.new(0.2,0.2,0.2),myTorso.CFrame*CARRY,OLIVE,nil,model)
	root.Transparency = 1

	local template = ServerStorage:FindFirstChild(MODEL_NAME)
	if not (template and fitModel(template,model,root)) then
		builtLauncher(model,root)
	end
	weldAll(root,model)

	local weld = Instance.new("Weld")
	weld.Part0 = myTorso
	weld.Part1 = root
	weld.C0 = CARRY
	weld.Parent = root
	model.Parent = marine
	return weld,root,model
end

--Lets the empty launcher fall from his shoulder; it despawns a while later.
local function dropLauncher(weld,model)
	weld:Destroy()
	for _,part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = false
			part.CanCollide = part.Transparency < 1
		end
	end
	model.Parent = workspace
	local root = model.PrimaryPart or model:FindFirstChild("JavelinRoot")
	if root then
		root.AssemblyLinearVelocity = myRoot.CFrame.RightVector*-4 + Vector3.new(0,3,0)
	end
	Debris:AddItem(model,DROP_DESPAWN)
end

-- Missile -------------------------------------------------------------------

local AIRCRAFT_TAG = "BloxianAircraft"

--The aircraft (a model tagged BloxianAircraft) a part belongs to, if any.
local function aircraftOf(instance)
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if model:HasTag(AIRCRAFT_TAG) then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--A vehicle or an aircraft.
local function craftOf(instance)
	return core.vehicleOf(instance) or aircraftOf(instance)
end

--Missile damage to a vehicle or aircraft; never to one on his side.
local function damageCraft(craft,share)
	if craft:HasTag(AIRCRAFT_TAG) then
		local human = craft:FindFirstChildOfClass("Humanoid")
		local ally = if craft:HasTag("BloxianVehicle") then core.isAllyVehicle(craft) else core.isAlly(craft)
		if human and human.Health > 0 and not craft:GetAttribute("Wrecked") and not ally then
			human:TakeDamage(AIRCRAFT_DAMAGE*share)
		end
	else
		core.damageVehicle(craft,VEHICLE_DAMAGE*share,true)
	end
end

local function explode(position,hitCar)
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = BLAST_RADIUS
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.ExplosionType = Enum.ExplosionType.NoCraters
	blast.Parent = workspace

	if hitCar then
		damageCraft(hitCar,1)
	end

	local closest = {}
	local splashed = {}
	for _,part in ipairs(workspace:GetPartBoundsInRadius(position,BLAST_RADIUS)) do
		local car = craftOf(part)
		if car then
			if car ~= hitCar and not splashed[car] then
				splashed[car] = true
				damageCraft(car,SPLASH)
			end
		else
			local human = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
			if human then
				local distance = (part.Position - position).Magnitude
				if not closest[human] or distance < closest[human] then
					closest[human] = distance
				end
			end
		end
	end
	for human,distance in pairs(closest) do
		if distance <= KILL_RADIUS then
			core.applyDamage(human,human.MaxHealth)
		else
			core.applyDamage(human,human.MaxHealth*WOUND*math.clamp(1 - distance/BLAST_RADIUS,0,1))
		end
	end
end

--Lets a vehicle know a missile is on its way (MissileInbound, from ThreatAt) so
--its crew can pop smoke. Aircraft have flares of their own.
local function warnCar(car,change)
	if not car or not car.Parent or car:HasTag(AIRCRAFT_TAG) then return end
	car:SetAttribute("MissileInbound",math.max((car:GetAttribute("MissileInbound") or 0) + change,0))
	if change > 0 then
		car:SetAttribute("ThreatAt",myRoot.Position)
	end
end

--Climbs from start and dives onto aimPart from above, following it as it moves
--while its seeker can see it (not through smoke).
local function flyMissile(start,aimPart,car)
	warnCar(car,1)
	local missile = makePart("JavelinMissile",Vector3.new(1.4,0.3,0.3),CFrame.new(start),OLIVE,Enum.PartType.Cylinder,workspace)
	missile.Anchored = true
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0.7,0.12,0)
	tail.Parent = missile
	local tail2 = Instance.new("Attachment")
	tail2.Position = Vector3.new(0.7,-0.12,0)
	tail2.Parent = missile
	local trail = Instance.new("Trail")
	trail.Attachment0 = tail
	trail.Attachment1 = tail2
	trail.Lifetime = 1.5
	trail.Color = ColorSequence.new(Color3.fromRGB(220,220,215))
	trail.Transparency = NumberSequence.new(0.2,1)
	trail.WidthScale = NumberSequence.new(1,6)
	trail.Parent = missile
	local flame = Instance.new("PointLight")
	flame.Color = Color3.fromRGB(255,170,80)
	flame.Range = 8
	flame.Parent = missile

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {marine,missile}

	local goal = aimPart.Position
	local previous = start
	local travelled = 0
	local born = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if aimPart.Parent and not core.smokeBetween(previous,aimPart.Position) then
			goal = aimPart.Position
		end
		local span = (goal - start).Magnitude
		local climb = math.clamp(span*CLIMB,MIN_CLIMB,MAX_CLIMB)
		local apex = (start + goal)/2 + Vector3.new(0,climb,0)
		travelled += MISSILE_SPEED*dt
		local t = math.min(travelled/(span*1.25 + climb),1)
		local position = (1 - t)^2*start + 2*(1 - t)*t*apex + t^2*goal

		local hit = workspace:Raycast(previous,position - previous,params)
		local done = hit ~= nil or t >= 1 or os.clock() - born > 12
		if done then
			connection:Disconnect()
			missile:Destroy()
			warnCar(car,-1)
			local at = hit and hit.Position or position
			--Striking the crew (they sit inside) or landing on the vehicle counts as hitting it.
			local direct = hit and craftOf(hit.Instance)
			if not direct and car and aimPart.Parent and (at - aimPart.Position).Magnitude < 10 then
				direct = car
			end
			explode(at,direct)
			return
		end
		if (position - previous).Magnitude > 0.01 then
			missile.CFrame = CFrame.lookAt(position,position + (position - previous))*CYLINDER
		end
		previous = position
	end)
end

-- Rocketeer -----------------------------------------------------------------

local VEHICLE_TAGS = {"BloxianVehicle","MarineVehicle","BloxianAircraft"}

local function aimPartOf(car)
	return car:FindFirstChild("HumanoidRootPart") or car.PrimaryPart or (car:FindFirstChild("Body") and car.Body:FindFirstChild("Body")) or car:FindFirstChildWhichIsA("BasePart",true)
end

--An aircraft on the other side, still flying. One with seats (the Apache) is
--judged by its crew, like any vehicle.
local function isEnemyAircraft(craft)
	if craft:GetAttribute("Wrecked") then return false end
	if craft:HasTag("BloxianVehicle") then
		return core.isEnemyVehicle(craft)
	end
	return not core.isAlly(craft)
end

local function hostile(car)
	local human = car:FindFirstChildOfClass("Humanoid")
	if not car:IsDescendantOf(workspace) or not human or human.Health <= 0 then
		return false
	end
	return if car:HasTag(AIRCRAFT_TAG) then isEnemyAircraft(car) else core.isEnemyVehicle(car)
end

--The nearest enemy-crewed vehicle within range (default MAX_RANGE) and in
--sight (unless anywhere is true), and the part to aim at. Armor comes first:
--an enemy aircraft only when there is no vehicle on the ground to hit.
local function findVehicle(range,anywhere)
	local found = {ground = {dist = range or MAX_RANGE},air = {dist = range or MAX_RANGE}}
	for _,tag in ipairs(VEHICLE_TAGS) do
		for _,car in ipairs(CollectionService:GetTagged(tag)) do
			local human = car:FindFirstChildOfClass("Humanoid")
			local part = car:IsDescendantOf(workspace) and human and human.Health > 0 and aimPartOf(car)
			local flying = car:HasTag(AIRCRAFT_TAG)
			local enemy = part and (if flying then isEnemyAircraft(car) else core.isEnemyVehicle(car))
			local slot = flying and found.air or found.ground
			if enemy then
				local dist = (part.Position - myRoot.Position).Magnitude
				if dist >= MIN_RANGE and dist < slot.dist and (anywhere or core.checkSight(part)) then
					slot.car,slot.part,slot.dist = car,part,dist
				end
			end
		end
	end
	local pick = found.ground.car and found.ground or found.air
	return pick.car,pick.part
end

-- Pose ----------------------------------------------------------------------

local rShoulder = myTorso:FindFirstChild("Right Shoulder")
local lShoulder = myTorso:FindFirstChild("Left Shoulder")
local rArm = marine:FindFirstChild("Right Arm")
local lArm = marine:FindFirstChild("Left Arm")

local REST_RIGHT = CFrame.new(1.5,0,0)
local REST_LEFT = CFrame.new(-1.5,0,0)

--An arm lying from one torso-space point (shoulder end) to another (hand).
local function armPose(points)
	local from,to = points[1],points[2]
	local center = (from + to)/2
	return CFrame.lookAt(center,center + (to - from))*CFrame.Angles(math.rad(90),0,0)
end
local HOLD_RIGHT = armPose(RIGHT_HOLD)
local HOLD_LEFT = armPose(LEFT_HOLD)

--Eases alpha 0 to 1 over duration seconds, calling apply each frame.
local function sweep(duration,apply)
	local start = os.clock()
	while true do
		local alpha = math.min((os.clock() - start)/duration,1)
		apply(alpha*alpha*(3 - 2*alpha))
		if alpha >= 1 or myHuman.Health <= 0 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

--Takes his arms off their shoulder motors and onto welds this module moves.
local function gripArms()
	local welds = {}
	for _,info in ipairs({{rShoulder,rArm,REST_RIGHT},{lShoulder,lArm,REST_LEFT}}) do
		local motor,arm,rest = info[1],info[2],info[3]
		if motor and arm then
			motor.Part1 = nil
			local weld = Instance.new("Weld")
			weld.Name = "JavelinGrip"
			weld.Part0 = myTorso
			weld.Part1 = arm
			weld.C0 = rest
			weld.Parent = myTorso
			welds[#welds+1] = weld
		end
	end
	return welds
end

--Dying mid-shot lets the arms go limp with the rest of him.
myHuman.Died:Connect(function()
	for _,weld in ipairs(myTorso:GetChildren()) do
		if weld.Name == "JavelinGrip" then
			weld:Destroy()
		end
	end
end)

local function releaseArms(welds)
	for _,weld in ipairs(welds) do
		weld:Destroy()
	end
	if myHuman.Health > 0 then
		if rShoulder and rArm then rShoulder.Part1 = rArm end
		if lShoulder and lArm then lShoulder.Part1 = lArm end
	end
end

--Launcher and arms together, from carry (0) to shouldered (1).
local function pose(launcherWeld,armWelds,alpha,shoulder)
	launcherWeld.C0 = CARRY:Lerp(shoulder or SHOULDER,alpha)
	if armWelds[1] then armWelds[1].C0 = REST_RIGHT:Lerp(HOLD_RIGHT,alpha) end
	if armWelds[2] then armWelds[2].C0 = REST_LEFT:Lerp(HOLD_LEFT,alpha) end
end

local function backblast(root)
	local at = Instance.new("Attachment")
	at.Position = Vector3.new(0,0,REAR + 0.2)
	at.Parent = root
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(200,200,195))
	smoke.Size = NumberSequence.new(1,4)
	smoke.Transparency = NumberSequence.new(0.3,1)
	smoke.Lifetime = NumberRange.new(0.8,1.4)
	smoke.Speed = NumberRange.new(8,14)
	smoke.SpreadAngle = Vector2.new(20,20)
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Rate = 0
	smoke.Parent = at
	smoke:Emit(25)
	Debris:AddItem(at,2)
end

local function face(position)
	local flat = Vector3.new(position.X,myRoot.Position.Y,position.Z)
	if (flat - myRoot.Position).Magnitude > 0.1 then
		myRoot.CFrame = CFrame.lookAt(myRoot.Position,flat)
	end
end

-- Hunting -------------------------------------------------------------------

local random = Random.new()
local armed = false
local home = nil
local patrolGoal = nil
local legEnd = 0
local pauseUntil = 0
local picking = false


local function flatDistance(point)
	local offset = point - myRoot.Position
	return Vector3.new(offset.X,0,offset.Z).Magnitude
end

--Where he walks now (see specialTeam.hunt), or nil to stand.
-- Reports -------------------------------------------------------------------

--reports[vehicle][team] = {seen = when last seen, called = when last called out}
_G.BloxianArmorReports = _G.BloxianArmorReports or setmetatable({},{__mode = "k"})
local reports = _G.BloxianArmorReports
local teamValue = marine.Settings.Team
local reportRange = marine.Settings:FindFirstChild("DetectionRange")

--Whether a Rocketeer on his side is alive within HUNT_RANGE of position.
local function atTeamNear(position)
	for model,entry in pairs(_G.BloxianRadio or {}) do
		if model:GetAttribute("Unit") == "Rocketeer" and entry.team.Value == teamValue.Value
			and entry.root.Parent and entry.human.Health > 0
			and (entry.root.Position - position).Magnitude <= HUNT_RANGE then
			return true
		end
	end
	return false
end

--Looks for an enemy vehicle in sight; reports it and, now and then, calls it out.
local function reportArmor()
	local car,part = findVehicle(reportRange and reportRange.Value or MAX_RANGE)
	if not car then return end

	local byTeam = reports[car]
	if not byTeam then
		byTeam = {}
		reports[car] = byTeam
	end
	local now = os.clock()
	local report = byTeam[teamValue.Value]
	if not report then
		report = {called = -math.huge}
		byTeam[teamValue.Value] = report
	end
	report.seen = now
	if now - report.called >= CALL_AGAIN then
		report.called = now
		log("attack","reporting armor: "..car.Name)
		chatter.armor(part,atTeamNear(part.Position))
	end
end

--The nearest vehicle his side has reported lately, within HUNT_RANGE, and its aim part.
local function reportedVehicle()
	local best,bestPart,bestDist = nil,nil,HUNT_RANGE
	local now = os.clock()
	for car,byTeam in pairs(reports) do
		local report = byTeam[teamValue.Value]
		if report and now - report.seen <= REPORT_MEMORY and hostile(car) then
			local part = aimPartOf(car)
			local dist = part and (part.Position - myRoot.Position).Magnitude
			if dist and dist < bestDist then
				best,bestPart,bestDist = car,part,dist
			end
		end
	end
	return best,bestPart
end

local hunting = nil

local function hunt(hasTarget)
	home = home or myRoot.Position
	if not armed or hasTarget or findVehicle() then
		return nil
	end

	local car,part = reportedVehicle()
	if car ~= hunting then
		hunting = car
		if car then
			log("attack","AT team hunting "..car.Name)
			chatter.callout("atMoving")
		end
	end
	if car then
		patrolGoal = nil
		if flatDistance(part.Position) < MIN_RANGE*2 then
			return nil
		end
		--Toward a spot on the ground short of it, never right under it.
		local toward = Vector3.new(part.Position.X - myRoot.Position.X,0,part.Position.Z - myRoot.Position.Z).Unit
		local short = part.Position - toward*MIN_RANGE*1.5
		local hit,result = core.raycast(Vector3.new(short.X,math.max(short.Y,myRoot.Position.Y) + 40,short.Z),Vector3.new(0,-200,0))
		if hit and not result.Instance:IsDescendantOf(car) then
			return result.Position + Vector3.new(0,3,0)
		end
		return Vector3.new(short.X,myRoot.Position.Y,short.Z)
	end

	local now = os.clock()
	if now < pauseUntil then
		return nil
	end
	if patrolGoal and (flatDistance(patrolGoal) < 4 or now > legEnd) then
		patrolGoal = nil
		pauseUntil = now + random:NextNumber(PATROL_PAUSE_MIN,PATROL_PAUSE_MAX)
		return nil
	end
	if not patrolGoal and not picking then
		picking = true
		task.spawn(function()
			local spot = movement.patrolPoint(home,PATROL_RADIUS)
			picking = false
			if spot then
				patrolGoal = spot
				legEnd = os.clock() + PATROL_LEG_TIME
				log("brain","AT team patrolling")
			else
				pauseUntil = os.clock() + PATROL_PAUSE_MIN
			end
		end)
	end
	return patrolGoal
end

local function runRocketeer()
	local weld,root,model = fitLauncher()
	armed = weld ~= nil

	while myHuman.Health > 0 and marine.Parent do
		local car,part = nil,nil
		if weld and not status:get("reloading") then
			car,part = findVehicle()
		end
		if car then
			log("attack","Javelin: locking on to "..car.Name)
			status:set("launching",true)
			actions.yieldM4()
			local armWelds = gripArms()
			sweep(RAISE_TIME,function(alpha)
				pose(weld,armWelds,alpha)
				face(part.Position)
			end)

			local locked = true
			local lockEnd = os.clock() + LOCK_TIME
			warnCar(car,1)
			while os.clock() < lockEnd do
				local stillEnemy = if car:HasTag(AIRCRAFT_TAG) then isEnemyAircraft(car) else core.isEnemyVehicle(car)
				if myHuman.Health <= 0 or not part.Parent or not stillEnemy or core.smokeBetween(myRoot.Position,part.Position) then
					locked = false
					break
				end
				face(part.Position)
				task.wait(0.1)
			end

			if locked and myHuman.Health > 0 then
				log("attack","Javelin: missile away")
				chatter.callout("javelinOut")
				--The M4's shot is copied for its volume and how far it carries.
				local gunshot = marine.M4:FindFirstChild("Fire")
				if gunshot then
					local launch = gunshot:Clone()
					launch.SoundId = LAUNCH_SOUND
					launch.PlaybackSpeed = 1
					launch.Parent = root
					launch:Play()
					Debris:AddItem(launch,8)
				end
				flyMissile(root.CFrame*Vector3.new(0,0,-MUZZLE - 0.5),part,car)
				backblast(root)
				sweep(RECOIL_TIME,function(alpha)
					weld.C0 = SHOULDER*RECOIL:Lerp(CFrame.identity,alpha)
				end)
				task.wait(0.3)

				--Spent: it drops, and his hands come back down.
				dropLauncher(weld,model)
				--The lock is handed to the missile, which clears it when it lands.
				warnCar(car,-1)
				weld,root,model = nil,nil,nil
				armed = false
				sweep(LET_GO_TIME,function(alpha)
					if armWelds[1] then armWelds[1].C0 = HOLD_RIGHT:Lerp(REST_RIGHT,alpha) end
					if armWelds[2] then armWelds[2].C0 = HOLD_LEFT:Lerp(REST_LEFT,alpha) end
				end)

				local loader = specialTeam.partner("Loader")
				local nearby = loader and (loader.root.Position - myRoot.Position).Magnitude <= LOADER_RANGE
				local reload = nearby and RELOAD_WITH_LOADER or RELOAD_ALONE
				log("attack","Javelin: reloading ("..reload.." s)")
				task.delay(reload,function()
					if myHuman.Health > 0 and marine.Parent then
						weld,root,model = fitLauncher()
						armed = weld ~= nil
					end
				end)
			else
				warnCar(car,-1)
				sweep(RAISE_TIME,function(alpha)
					pose(weld,armWelds,1 - alpha)
				end)
			end

			releaseArms(armWelds)
			status:set("launching",false)
		end
		task.wait(0.25)
	end
	status:set("launching",false)
end

if unit == "Rocketeer" or unit == "Loader" then
	local detection = marine.Settings:FindFirstChild("DetectionRange")
	if detection and detection.Value < MAX_RANGE then
		detection.Value = MAX_RANGE
	end
end

if unit ~= "Rocketeer" and unit ~= "Loader" then
	task.spawn(function()
		while myHuman.Health > 0 and marine.Parent do
			task.wait(REPORT_INTERVAL)
			reportArmor()
		end
	end)
end

if unit == "Rocketeer" then
	specialTeam.hunt = hunt
	--Waits for the respawn copy to be taken first, or it would carry the launcher too.
	task.spawn(function()
		local waited = 0
		while not marine:GetAttribute("BloxianCloned") and waited < 5 do
			waited += task.wait()
		end
		runRocketeer()
	end)
end

return javelin

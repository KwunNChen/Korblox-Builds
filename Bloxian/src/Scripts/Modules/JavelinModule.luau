--[[
	The AT team's Javelin.

	The Rocketeer carries a launcher slung on his back and his carbine for
	everything else. When an enemy-crewed vehicle is in sight and in range, he
	slings the carbine, shoulders the launcher, locks on, and fires a missile
	that climbs and dives onto the vehicle from above (top attack), following it
	as it moves. One hit wrecks a Warthog; two wreck an Abrams.

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
local LAUNCH_SOUND = "rbxassetid://139048208305901"

--Seconds a dropped launcher lies on the ground before it despawns.
local DROP_DESPAWN = 20

--Missile damage to a vehicle it hits (armour does not count). A Warthog has 400
--health and an Abrams 3000, so 1600 is one Warthog or half an Abrams. Vehicles
--only caught in the blast take SPLASH of it.
local VEHICLE_DAMAGE = 1600
local SPLASH = 0.25

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

local function explode(position,hitCar)
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = BLAST_RADIUS
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.ExplosionType = Enum.ExplosionType.NoCraters
	blast.Parent = workspace

	if hitCar then
		core.damageVehicle(hitCar,VEHICLE_DAMAGE,true)
	end

	local closest = {}
	local splashed = {}
	for _,part in ipairs(workspace:GetPartBoundsInRadius(position,BLAST_RADIUS)) do
		local car = core.vehicleOf(part)
		if car then
			if car ~= hitCar and not splashed[car] then
				splashed[car] = true
				core.damageVehicle(car,VEHICLE_DAMAGE*SPLASH,true)
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

--Climbs from start and dives onto aimPart from above, following it as it moves.
local function flyMissile(start,aimPart,car)
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
		if aimPart.Parent then
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
			local at = hit and hit.Position or position
			--Striking the crew (they sit inside) or landing on the mark counts as hitting the vehicle.
			local direct = hit and core.vehicleOf(hit.Instance)
			if not direct and car and (at - goal).Magnitude < 10 then
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

local VEHICLE_TAGS = {"BloxianVehicle","MarineVehicle"}

local function aimPartOf(car)
	return car.PrimaryPart or (car:FindFirstChild("Body") and car.Body:FindFirstChild("Body")) or car:FindFirstChildWhichIsA("BasePart",true)
end

--The nearest enemy-crewed vehicle he can see within range, and the part to aim at.
local function findVehicle()
	local best,bestPart,bestDist = nil,nil,MAX_RANGE
	for _,tag in ipairs(VEHICLE_TAGS) do
		for _,car in ipairs(CollectionService:GetTagged(tag)) do
			local human = car:FindFirstChildOfClass("Humanoid")
			local part = car:IsDescendantOf(workspace) and human and human.Health > 0 and aimPartOf(car)
			if part and core.isEnemyVehicle(car) then
				local dist = (part.Position - myRoot.Position).Magnitude
				if dist >= MIN_RANGE and dist < bestDist and core.checkSight(part) then
					best,bestPart,bestDist = car,part,dist
				end
			end
		end
	end
	return best,bestPart
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

local function runRocketeer()
	local weld,root,model = fitLauncher()

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
			while os.clock() < lockEnd do
				if myHuman.Health <= 0 or not part.Parent or not core.isEnemyVehicle(car) then
					locked = false
					break
				end
				face(part.Position)
				task.wait(0.1)
			end

			if locked and myHuman.Health > 0 then
				log("attack","Javelin: missile away")
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
				weld,root,model = nil,nil,nil
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
					end
				end)
			else
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

if unit == "Rocketeer" then
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

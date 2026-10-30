--Pilot and gunner: Bloxian figures sitting in the cockpit, which bail out as
--real Bloxians when the Apache is shot up and fight on where they land. Needs
--ServerStorage.BLOXIAN; without it the Apache flies with an empty cockpit.

local crew = {}

local myModel = script.Parent.Parent
local body = myModel.Body
local mySettings = myModel.Settings

local serverStorage = game:GetService("ServerStorage")
local insertService = game:GetService("InsertService")
local collectionService = game:GetService("CollectionService")
local debrisService = game:GetService("Debris")

--The soldier the crew are cloned from, in ServerStorage.
local SOLDIER_NAME = "BLOXIAN"

--Attachments on Body where each sits (move them in Studio to fit the cockpit),
--and the side he jumps out of (1 right, -1 left).
local SEATS = {
	{attachment = "PilotSeat", side = 1},
	{attachment = "GunnerSeat", side = -1},
}

--Health share at or below which they bail out. The Apache goes down without them.
crew.BAIL_HEALTH = 0.3

--Aviator helmet, USAF flight suit shirt and pants. The ones on the ground get the
--same from the "Pilot" rule in the Bloxian's UniformModule.
local HELMET = 88312962939182
local SHIRT = 126970663663675
local PANTS = 124011055669062
--What they carry on the ground (a WeaponProfiles name; Rifle is the FN FAL).
local WEAPON = "Rifle"

local BODY = {"HumanoidRootPart","Torso","Head","Left Arm","Right Arm","Left Leg","Right Leg"}

--Thrown out sideways and up (studs/s), the canopy opening after CHUTE_DELAY
--seconds. Under it he sinks at FALL_SPEED and drifts outward at DRIFT_SPEED.
local EJECT_SPEED = 30
local EJECT_UP = 12
local CHUTE_DELAY = 0.6
local FALL_SPEED = 14
local DRIFT_SPEED = 4
--How far out from the fuselage centre (studs) he comes out.
local EJECT_OFFSET = 11

local CHUTE_SIZE = Vector3.new(14,5,14)
local CHUTE_HEIGHT = 10
local CHUTE_COLOR = Color3.fromRGB(96,104,72)
--Seconds the canopy takes to fade once he is down.
local CHUTE_FADE = 1.5

local figures = {}

_G.BloxianAccessoryCache = _G.BloxianAccessoryCache or {}
_G.BloxianAccessoryLoading = _G.BloxianAccessoryLoading or {}
local cache = _G.BloxianAccessoryCache
local loading = _G.BloxianAccessoryLoading

--Same download cache as the Bloxian's UniformModule.
local function catalogItem(id,className)
	if cache[id] then
		return cache[id]
	end
	while loading[id] do
		task.wait(0.1)
	end
	if cache[id] then
		return cache[id]
	end
	loading[id] = true
	local ok,model = pcall(insertService.LoadAsset,insertService,id)
	if ok and model then
		local item = model:FindFirstChildWhichIsA(className,true)
		if item then
			item.Parent = nil
			cache[id] = item
		end
		model:Destroy()
	end
	if not cache[id] then
		warn("[Apache] could not load "..className.." "..id)
	end
	loading[id] = nil
	return cache[id]
end

local function dress(figure)
	for _,item in ipairs({{SHIRT,"Shirt"},{PANTS,"Pants"}}) do
		local template = catalogItem(item[1],item[2])
		if template and figure.Parent then
			local old = figure:FindFirstChildOfClass(item[2])
			if old then
				old:Destroy()
			end
			template:Clone().Parent = figure
		end
	end
	local helmet = catalogItem(HELMET,"Accessory")
	local human = figure:FindFirstChildOfClass("Humanoid")
	if helmet and human and figure.Parent then
		human:AddAccessory(helmet:Clone())
		for _,part in ipairs(figure:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Massless = true
			end
		end
	end
end

local function bend(torso,jointName,degrees)
	local joint = torso:FindFirstChild(jointName)
	if joint then
		joint.C0 = joint.C0 * CFrame.Angles(0,0,math.rad(degrees))
	end
end

--A still, seated copy of the soldier: no scripts, no gun, not hittable.
local function makeFigure(template,seat)
	local figure = template:Clone()
	figure.Name = "Crew"
	for _,child in ipairs(figure:GetChildren()) do
		local keep = (child:IsA("BasePart") and table.find(BODY,child.Name))
			or child:IsA("Humanoid") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("BodyColors") or child:IsA("CharacterMesh")
		if not keep then
			child:Destroy()
		end
	end
	for _,part in ipairs(figure:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		elseif part:IsA("Constraint") or part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
	end
	local human = figure:FindFirstChildOfClass("Humanoid")
	if human then
		human.EvaluateStateMachine = false
		human.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local torso = figure:FindFirstChild("Torso")
	if torso then
		bend(torso,"Right Hip",90)
		bend(torso,"Left Hip",-90)
		bend(torso,"Right Shoulder",50)
		bend(torso,"Left Shoulder",-50)
	end

	local root = figure.HumanoidRootPart
	figure.PrimaryPart = root
	figure:PivotTo(body.CFrame * seat.CFrame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = root
	weld.Parent = root
	figure.Parent = myModel
	task.spawn(dress,figure)
	return figure
end

function crew.board()
	local template = serverStorage:FindFirstChild(SOLDIER_NAME)
	if not template then return end
	for _,spot in ipairs(SEATS) do
		local seat = body:FindFirstChild(spot.attachment)
		if seat then
			table.insert(figures,{figure = makeFigure(template,seat),side = spot.side})
		end
	end
end

function crew.aboard()
	return #figures > 0
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

local function chute(soldier,outward)
	local root = soldier:FindFirstChild("HumanoidRootPart")
	local torso = soldier:FindFirstChild("Torso")
	local human = soldier:FindFirstChildOfClass("Humanoid")
	if not root or not torso or not human then return end

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
	canopy.Parent = soldier

	local drag = Instance.new("LinearVelocity")
	drag.Name = "ParachuteDrag"
	drag.Attachment0 = harness
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.VectorVelocity = outward*DRIFT_SPEED - Vector3.new(0,FALL_SPEED,0)
	drag.MaxForce = root.AssemblyMass*workspace.Gravity*3
	drag.Parent = root

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {soldier,myModel}
	local falling = 0
	while soldier.Parent and human.Health > 0 and falling < 60 do
		if human.FloorMaterial ~= Enum.Material.Air or workspace:Raycast(root.Position,Vector3.new(0,-3.5,0),params) then
			break
		end
		falling += task.wait()
	end

	drag:Destroy()
	harness:Destroy()
	canopy.Anchored = true
	weld:Destroy()
	game:GetService("TweenService"):Create(canopy,TweenInfo.new(CHUTE_FADE),{Transparency = 1}):Play()
	debrisService:AddItem(canopy,CHUTE_FADE)
end

local function bailOne(template,entry)
	local figure = entry.figure
	local seat = figure.Parent and figure:FindFirstChild("HumanoidRootPart")
	local seatCFrame = seat and seat.CFrame or body.CFrame
	figure:Destroy()

	local outward = body.CFrame.RightVector*entry.side
	local soldier = template:Clone()
	local settings = soldier:FindFirstChild("Settings")
	if settings then
		setValue(settings,"Team","StringValue",mySettings.Team.Value)
		setValue(settings,"AttackPlayers","BoolValue",mySettings.AttackPlayers.Value)
		setValue(settings,"Weapon","StringValue",WEAPON)
		setValue(settings,"Unit","StringValue","Pilot")
		setValue(settings,"Role","StringValue","Rifleman")
		setValue(settings,"Respawn","BoolValue",false)
	end
	local spawnedBy = myModel:GetAttribute("SpawnedBy")
	if spawnedBy then
		soldier:SetAttribute("SpawnedBy",spawnedBy)
		soldier:SetAttribute("VehicleCrew",true)
		collectionService:AddTag(soldier,"BloxianSpawned")
	end

	local at = seatCFrame.Position + outward*EJECT_OFFSET
	soldier:PivotTo(CFrame.lookAt(at,at + outward))
	soldier.Parent = workspace

	local root = soldier:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = body.AssemblyLinearVelocity + outward*EJECT_SPEED + Vector3.new(0,EJECT_UP,0)
	end
	task.wait(CHUTE_DELAY)
	chute(soldier,outward)
end

--Both jump; the figures are swapped for live soldiers on parachutes.
function crew.bail()
	local template = serverStorage:FindFirstChild(SOLDIER_NAME)
	local leaving = figures
	figures = {}
	for _,entry in ipairs(leaving) do
		if template then
			task.spawn(bailOne,template,entry)
		else
			entry.figure:Destroy()
		end
	end
end

return crew

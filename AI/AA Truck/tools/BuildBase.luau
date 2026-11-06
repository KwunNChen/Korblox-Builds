-- Builds AA Truck/src/Base.rbxm from the downloaded BM-21 model: meshes only, plus the rig parts.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local source = roblox.deserializeModel(fs.readFile(process.args[1]))[1]
local out = process.args[2]

local KEEP_CHILDREN = {SurfaceAppearance = true, Decal = true, Texture = true, SpecialMesh = true}
local FORWARD = Vector3.new(0,0,1) -- the cab end of the truck

local function copyPart(part, parent, name)
	local copy = part:Clone()
	for _,child in copy:GetChildren() do
		if not KEEP_CHILDREN[child.ClassName] then
			child:Destroy()
		end
	end
	copy.Anchored = true
	if name then copy.Name = name end
	copy.Parent = parent
	return copy
end

local function rigPart(name, size, cframe, parent, class)
	local part = Instance.new(class or "Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

-- Built from the axes: Lune's CFrame.lookAt faces the other way to Roblox's.
local function facing(position, direction)
	local look = (direction or FORWARD).Unit
	local right = look:Cross(Vector3.new(0,1,0)).Unit
	local up = right:Cross(look).Unit
	return CFrame.fromMatrix(position, right, up)
end

local model = Instance.new("Model")
model.Name = "AA Truck"

local mesh = Instance.new("Model")
mesh.Name = "Mesh"
mesh.Parent = model

local body = Instance.new("Model")
body.Name = "Body"
body.Parent = mesh
for _,part in source.Body:GetChildren() do
	if part:IsA("BasePart") and part.Transparency < 1 then
		copyPart(part, body)
	end
end

-- Wheels: each hub is the old invisible wheel ball, with its tyre and rim meshes.
local wheels = Instance.new("Model")
wheels.Name = "Wheels"
wheels.Parent = mesh
local index = 0
for _,wheel in source.Wheels:GetChildren() do
	if wheel:IsA("BasePart") then
		index += 1
		local holder = Instance.new("Model")
		holder.Name = "Wheel"..index
		holder.Parent = wheels
		local hub = rigPart("Hub", Vector3.new(1,1,1), CFrame.new(wheel.CFrame.Position), holder)
		hub:SetAttribute("Radius", wheel.Size.Y/2)
		for _,part in wheel.Parts:GetChildren() do
			if part:IsA("BasePart") then
				local copy = copyPart(part, holder)
				copy.CanCollide = false
			end
		end
	end
end

local kit = source.Misc["Comp's Tank Kit V1.5 [FE CAPABLE]"].BEREG
local turret = Instance.new("Model")
turret.Name = "Turret"
turret.Parent = mesh
for _,part in kit.Weapon.Turret:GetChildren() do
	if part:IsA("BasePart") and part.Transparency < 1 then
		copyPart(part, turret)
	end
end
local launcher = Instance.new("Model")
launcher.Name = "Launcher"
launcher.Parent = turret
for _,part in kit.Weapon.Gun:GetChildren() do
	if part:IsA("BasePart") and part.Transparency < 1 then
		copyPart(part, launcher).CanCollide = false
	end
end

-- The hull: an invisible box round the body and wheels, its front at the cab.
local hullCenter = Vector3.new(75.43, 4.9, -193.08)
local hullSize = Vector3.new(11.8, 9.4, 38.8)
local hull = rigPart("Hull", hullSize, facing(hullCenter), model)

local function attach(name, worldPosition, parent)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = parent.CFrame:ToObjectSpace(CFrame.new(worldPosition))
	attachment.Parent = parent
	return attachment
end

-- Seats in the cab: driver on the left, the launcher's operator beside him.
local driverPosition = Vector3.new(77.13, 4.5, -181.98)
local gunnerPosition = Vector3.new(74.27, 4.5, -181.98)
local driverSeat = rigPart("VehicleSeat", Vector3.new(2,1,2), facing(driverPosition), model, "VehicleSeat")
driverSeat.MaxSpeed = 0
local gunnerSeat = rigPart("Seat", Vector3.new(2,0.2,2), facing(gunnerPosition), model, "Seat")
attach("FrontDoor", Vector3.new(82.2, 2.9, -181.98), hull)
attach("SideDoor", Vector3.new(68.7, 2.9, -181.98), hull)

-- The launcher: TurretRing turns on the rear deck, Trunnion lifts the tubes
-- (its look vector runs along them), Launch is their open front end.
local tubeAngle = math.rad(16)
local tubeDirection = Vector3.new(0, math.sin(tubeAngle), math.cos(tubeAngle))
local ring = rigPart("TurretRing", Vector3.new(2,0.5,2), facing(Vector3.new(75.67, 5.5, -199.3)), model)
ring.Massless = true
local trunnion = rigPart("Trunnion", Vector3.new(2,0.5,2), facing(Vector3.new(75.67, 7.3, -199.6), tubeDirection), model)
trunnion.Massless = true
local launch = Instance.new("Attachment")
launch.Name = "Launch"
launch.CFrame = CFrame.new(0, 0, -12)
launch.Parent = trunnion
local rear = Instance.new("Attachment")
rear.Name = "Rear"
rear.CFrame = CFrame.new(0, 0, 1.5)
rear.Parent = trunnion

local humanoid = Instance.new("Humanoid")
humanoid.Parent = model

local settings = Instance.new("Folder")
settings.Name = "Settings"
settings.Parent = model
local health = Instance.new("IntValue")
health.Name = "Health"
health.Value = 800
health.Parent = settings
local respawn = Instance.new("IntValue")
respawn.Name = "RespawnDelay"
respawn.Value = 15
respawn.Parent = settings
local team = Instance.new("StringValue")
team.Name = "Team"
team.Value = ""
team.Parent = settings

model.PrimaryPart = hull
fs.writeFile(out, roblox.serializeModel({model}))

local counts = {}
for _,d in model:GetDescendants() do counts[d.ClassName] = (counts[d.ClassName] or 0) + 1 end
for c,n in counts do print(c,n) end

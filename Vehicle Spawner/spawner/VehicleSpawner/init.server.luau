--[[
	Vehicle Spawner

	Serves the "Vehicle Spawner" tool in StarterPack. Clicking the ground drops
	in a vehicle cloned from ServerStorage.BloxianVehicles, facing where the
	player looks. The tool's panel picks the vehicle, which team may crew it,
	and whether it comes with Bloxians already aboard (cloned from
	ServerStorage.BLOXIAN).

	Spawned vehicles do not respawn: wrecked or abandoned, they are removed.

	An aircraft (Aircraft attribute, like the Apache) flies itself: it appears
	Settings.Height studs above the click with no crew, and the team picked is
	its own.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Teams = game:GetService("Teams")

--The folder in ServerStorage the vehicles are cloned from (every Model in it is
--offered), and the soldier cloned for a crew.
local FOLDER_NAME = "BloxianVehicles"
local SOLDIER_NAME = "BLOXIAN"

--The tool's name in StarterPack; a request only counts while the player holds it.
local TOOL_NAME = "Vehicle Spawner"

--Who may spawn with the tool: everyone in Studio (if ALLOW_IN_STUDIO), the place's owner,
--these user ids, and anyone at MIN_GROUP_RANK or above in GROUP_ID (0 is off).
local ALLOW_IN_STUDIO = true
local ALLOWED_USER_IDS = {}
local GROUP_ID = 0
local MIN_GROUP_RANK = 255

--Most spawned vehicles alive at once on the server, and seconds between one player's spawns.
local MAX_ALIVE = 8
local SPAWN_COOLDOWN = 2

--Furthest a click can be from the player.
local MAX_SPAWN_DISTANCE = 400

--Seconds a vehicle gets to set itself up before its crew is put in.
local CREW_DELAY = 0.5

--Panel teams. Any lets every Bloxian crew it (a crew spawned with it is
--Hostile). Hostile fights everyone, Friendly fights Bloxians of other teams but
--never players, and any team in Teams sides with that team's players.
local ANY_TEAM = "Any"
local HOSTILE_TEAM = "Hostile"
local FRIENDLY_TEAM = "Friendly"

local CREWS = {None = {}, Driver = {"Driver"}, Full = {"Driver","Gunner"}}

local TAG = "VehicleSpawned"
--Crew carry the Bloxian Spawner's tag too, so its Clear and its limit count them.
local SOLDIER_TAG = "BloxianSpawned"

local allowedCache = {}
local lastSpawn = {}
local busy = {}

local remote = Instance.new("RemoteEvent")
remote.Name = "VehicleSpawnerRemote"
remote.Parent = ReplicatedStorage

local function isAllowed(player)
	if allowedCache[player] ~= nil then
		return allowedCache[player]
	end

	local allowed = (ALLOW_IN_STUDIO and RunService:IsStudio())
		or table.find(ALLOWED_USER_IDS,player.UserId) ~= nil
		or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
	if not allowed and game.CreatorType == Enum.CreatorType.Group then
		local ok,rank = pcall(player.GetRankInGroup,player,game.CreatorId)
		allowed = ok and rank == 255
	end
	if not allowed and GROUP_ID ~= 0 then
		local ok,rank = pcall(player.GetRankInGroup,player,GROUP_ID)
		allowed = ok and rank >= MIN_GROUP_RANK
	end

	allowedCache[player] = allowed
	return allowed
end

local function folder()
	return ServerStorage:FindFirstChild(FOLDER_NAME)
end

local function templateFor(name)
	local holder = folder()
	local template = holder and holder:FindFirstChild(name)
	return template and template:IsA("Model") and template or nil
end

local function flat(v)
	return Vector3.new(v.X,0,v.Z)
end

local function finite(vector)
	return vector == vector and vector.Magnitude < 1e6
end

local function aliveCount()
	local count = 0
	for _,model in ipairs(CollectionService:GetTagged(TAG)) do
		local human = model:FindFirstChildOfClass("Humanoid")
		if model:IsDescendantOf(workspace) and (not human or human.Health > 0) then
			count += 1
		end
	end
	return count
end

local function groundAt(position)
	local ignore = CollectionService:GetTagged(SOLDIER_TAG)
	for _,player in ipairs(Players:GetPlayers()) do
		if player.Character then
			ignore[#ignore+1] = player.Character
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(position + Vector3.new(0,20,0),Vector3.new(0,-60,0),params)
	return result and result.Position
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

--Which way the vehicle's driver faces, flat, relative to its pivot.
local function seatLook(template)
	local seat = template:FindFirstChild("VehicleSeat")
	local look = seat and flat(template:GetPivot():VectorToObjectSpace(seat.CFrame.LookVector))
	if not look or look.Magnitude < 0.01 then
		return Vector3.new(0,0,-1)
	end
	return look.Unit
end

--Footprint (width, length) for the tool's marker, as the vehicle will stand.
local function footprint(template)
	local _,size = template:GetBoundingBox()
	local look = seatLook(template)
	if math.abs(look.X) > math.abs(look.Z) then
		return Vector2.new(size.Z,size.X)
	end
	return Vector2.new(size.X,size.Z)
end

--The vehicle list and footprints go to the tool as attributes on the remote:
--clients cannot see ServerStorage.
local function publishVehicles()
	for name in pairs(remote:GetAttributes()) do
		remote:SetAttribute(name,nil)
	end
	local names = {}
	local holder = folder()
	if holder then
		for _,template in ipairs(holder:GetChildren()) do
			if template:IsA("Model") then
				table.insert(names,template.Name)
				remote:SetAttribute("Size_"..template.Name:gsub("%W","_"),footprint(template))
			end
		end
	end
	table.sort(names)
	remote:SetAttribute("Vehicles",table.concat(names,","))
end

local function crewUp(player,car,ground,forward,width,options)
	local roles = CREWS[options.crew]
	if #roles == 0 then
		return ""
	end
	local soldierTemplate = ServerStorage:FindFirstChild(SOLDIER_NAME)
	if not soldierTemplate then
		return ", but there is no "..SOLDIER_NAME.." in ServerStorage for a crew"
	end

	local crewTeam = options.team == ANY_TEAM and HOSTILE_TEAM or options.team
	local boxCFrame,boxSize = soldierTemplate:GetBoundingBox()
	local footOffset = soldierTemplate:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y/2)
	local side = forward:Cross(Vector3.yAxis)

	task.wait(CREW_DELAY)
	for index,role in ipairs(roles) do
		if not car.Parent then break end
		local soldier = soldierTemplate:Clone()
		local settings = soldier:FindFirstChild("Settings")
		if settings then
			setValue(settings,"Team","StringValue",crewTeam)
			setValue(settings,"AttackPlayers","BoolValue",crewTeam == HOSTILE_TEAM)
			setValue(settings,"Weapon","StringValue","Random")
			setValue(settings,"Role","StringValue","Rifleman")
			setValue(settings,"Respawn","BoolValue",false)
			setValue(settings,"Vehicle","ObjectValue",car)
			setValue(settings,"VehicleRole","StringValue",role)
		end
		soldier:SetAttribute("SpawnedBy",player.UserId)
		soldier:SetAttribute("VehicleCrew",true)
		soldier:AddTag(SOLDIER_TAG)

		--Beside the vehicle; his own script seats him.
		local spot = ground + side*(width/2 + 3) + forward*((index - 1)*3)
		local at = (groundAt(spot) or spot) + Vector3.new(0,footOffset,0)
		soldier:PivotTo(CFrame.lookAt(at,at + forward))
		soldier.Parent = workspace
		task.wait(0.1)
	end
	return #roles == 1 and " with a driver" or " with a crew"
end

local function spawnVehicle(player,position,look,options)
	local template = templateFor(options.vehicle)
	if not template then
		return "No "..options.vehicle.." in ServerStorage."..FOLDER_NAME
	end
	if aliveCount() >= MAX_ALIVE then
		return "Server limit reached ("..MAX_ALIVE.." vehicles)"
	end
	local ground = groundAt(position)
	if not ground then
		return "No ground there"
	end

	local forward = flat(look)
	forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0,0,-1)
	local turn = CFrame.lookAt(Vector3.zero,forward) * CFrame.lookAt(Vector3.zero,seatLook(template)):Inverse()
	local pivot = template:GetPivot()
	local boxCFrame,boxSize = template:GetBoundingBox()
	local footOffset = pivot.Position.Y - (boxCFrame.Position.Y - boxSize.Y/2)

	local car = template:Clone()
	car:SetAttribute("NoRespawn",true)
	car:SetAttribute("SpawnedBy",player.UserId)
	car:AddTag(TAG)
	local settings = car:FindFirstChild("Settings")
	local aircraft = template:GetAttribute("Aircraft")
	local height = 0
	if settings and aircraft then
		local team = options.team == ANY_TEAM and HOSTILE_TEAM or options.team
		setValue(settings,"Team","StringValue",team)
		setValue(settings,"AttackPlayers","BoolValue",team ~= FRIENDLY_TEAM)
		local heightValue = settings:FindFirstChild("Height")
		height = heightValue and heightValue.Value or 0
	elseif settings then
		setValue(settings,"Team","StringValue",options.team == ANY_TEAM and "" or options.team)
	end
	car:PivotTo(CFrame.new(ground + Vector3.new(0,footOffset + 0.5 + height,0)) * turn)
	car.Parent = workspace

	if aircraft then
		return "Spawned "..template.Name
	end
	return "Spawned "..template.Name..crewUp(player,car,ground,forward,footprint(template).X,options)
end

local function clearFor(player)
	local cleared = 0
	for _,car in ipairs(CollectionService:GetTagged(TAG)) do
		if car:GetAttribute("SpawnedBy") == player.UserId then
			car:Destroy()
			cleared += 1
		end
	end
	for _,soldier in ipairs(CollectionService:GetTagged(SOLDIER_TAG)) do
		if soldier:GetAttribute("VehicleCrew") and soldier:GetAttribute("SpawnedBy") == player.UserId then
			soldier:Destroy()
		end
	end
	return "Cleared "..cleared..(cleared == 1 and " vehicle" or " vehicles")
end

local function validTeam(name)
	if name == ANY_TEAM or name == HOSTILE_TEAM or name == FRIENDLY_TEAM then
		return true
	end
	local team = Teams:FindFirstChild(name)
	return team ~= nil and team:IsA("Team")
end

local function validOptions(options)
	return typeof(options) == "table"
		and type(options.vehicle) == "string" and templateFor(options.vehicle) ~= nil
		and type(options.team) == "string" and validTeam(options.team)
		and type(options.crew) == "string" and CREWS[options.crew] ~= nil
end

local function onRequest(player,action,position,look,options)
	if action == "clear" then
		return clearFor(player)
	elseif action ~= "spawn" then
		return nil
	end

	if typeof(position) ~= "Vector3" or typeof(look) ~= "Vector3" or not finite(position) or not finite(look) then
		return nil
	end
	if not validOptions(options) then
		return "Pick a vehicle first"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - position).Magnitude > MAX_SPAWN_DISTANCE then
		return "Too far away"
	end

	local now = os.clock()
	if busy[player] or now - (lastSpawn[player] or 0) < SPAWN_COOLDOWN then
		return nil
	end
	lastSpawn[player] = now
	busy[player] = true
	local ok,message = pcall(spawnVehicle,player,position,look,options)
	busy[player] = nil
	if not ok then
		warn("[VehicleSpawner] "..tostring(message))
		return "Spawn failed"
	end
	return message
end

local function holdsTool(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	return (backpack and backpack:FindFirstChild(TOOL_NAME))
		or (character and character:FindFirstChild(TOOL_NAME))
end

remote.OnServerEvent:Connect(function(player,action,position,look,options)
	if not holdsTool(player) then
		return
	end
	if not isAllowed(player) then
		remote:FireClient(player,"You are not allowed to spawn vehicles")
		return
	end
	local message = onRequest(player,action,position,look,options)
	if message and player.Parent then
		remote:FireClient(player,message)
	end
end)

publishVehicles()
ServerStorage.ChildAdded:Connect(function(child)
	if child.Name == FOLDER_NAME then
		publishVehicles()
		child.ChildAdded:Connect(publishVehicles)
		child.ChildRemoved:Connect(publishVehicles)
	end
end)
local holder = folder()
if holder then
	holder.ChildAdded:Connect(publishVehicles)
	holder.ChildRemoved:Connect(publishVehicles)
else
	warn("[VehicleSpawner] ServerStorage."..FOLDER_NAME.." is missing: put the vehicle models (Warthog, Abrams) in a folder of that name.")
end

--Group rank lookups yield, so they are done before the first click.
Players.PlayerAdded:Connect(isAllowed)
for _,player in ipairs(Players:GetPlayers()) do
	task.spawn(isAllowed,player)
end

Players.PlayerRemoving:Connect(function(player)
	allowedCache[player] = nil
	lastSpawn[player] = nil
	busy[player] = nil
end)

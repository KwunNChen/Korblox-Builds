--[[
	Vehicle Spawner

	Serves the Vehicles mode of the "Bloxian Spawner" tool. Clicking the ground drops
	in a vehicle cloned from ServerStorage.BloxianVehicles, facing where the
	player looks. The panel picks the vehicle, which team may crew it,
	and whether it comes with Bloxians already aboard (cloned from
	ServerStorage.bloxian).

	Spawned vehicles do not respawn: wrecked or abandoned, they are removed.

	An aircraft (Aircraft attribute, like the Apache) appears Settings.Height
	studs above the click, and its crew wear the Pilot uniform with the FN FAL.
	One with the Uncrewed attribute too (the F-4 Phantom) flies itself and gets no crew.
	One with NeedsTeam (the AC-130) is refused on team Any.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local kit = require(game:GetService("ServerScriptService"):WaitForChild("BloxianSpawner"):WaitForChild("SpawnerKit"))

--The folder in ServerStorage the vehicles are cloned from (every Model in it is
--offered), and the soldier cloned for a crew.
local FOLDER_NAME = "BloxianVehicles"
local SOLDIER_NAME = "BLOXIAN"

--The tool's name in StarterPack; a request only counts while the player holds it.
local TOOL_NAME = "Bloxian Spawner"

--Most spawned vehicles alive at once on the server, and seconds between one player's spawns.
local MAX_ALIVE = 10
local SPAWN_COOLDOWN = 2

--Furthest a click can be from the player, and how far above it ground is looked for.
local MAX_SPAWN_DISTANCE = 5000
local GROUND_HEADROOM = 20

--Seconds a vehicle gets to set itself up before its crew is put in.
local CREW_DELAY = 0.5

--Panel teams. Any lets every Bloxian crew it (a crew spawned with it is
--Hostile). Hostile fights everyone, Friendly fights Bloxians of other teams but
--never players, and any team in Teams sides with that team's players.
local ANY_TEAM = "Any"
local HOSTILE_TEAM = "Hostile"

--Crew choices. A gunner-only vehicle stands still with its gun manned (its
--GunnerOnly attribute keeps him from climbing over to drive).
local CREWS = {None = {}, Gunner = {"Gunner"}, Full = {"Driver","Gunner"}}

--What an aircraft's crew wear and carry (a UniformModule unit, a WeaponProfiles name).
local PILOT_UNIT = "Pilot"
local PILOT_WEAPON = "Rifle"

local TAG = "VehicleSpawned"
--Crew carry the Bloxian Spawner's tag too, so its Clear and its limit count them.
local SOLDIER_TAG = "BloxianSpawned"

local lastSpawn = {}
local busy = {}

local remote = Instance.new("RemoteEvent")
remote.Name = "VehicleSpawnerRemote"
remote.Parent = ReplicatedStorage

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
				if template:GetAttribute("Aircraft") then
					remote:SetAttribute("Aircraft_"..template.Name:gsub("%W","_"),true)
				end
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
			kit.setValue(settings,"Team","StringValue",crewTeam)
			kit.setValue(settings,"AttackPlayers","BoolValue",crewTeam == HOSTILE_TEAM)
			kit.setValue(settings,"Weapon","StringValue",car:GetAttribute("Aircraft") and PILOT_WEAPON or "Random")
			kit.setValue(settings,"Role","StringValue","Rifleman")
			if car:GetAttribute("Aircraft") then
				kit.setValue(settings,"Unit","StringValue",PILOT_UNIT)
			end
			kit.setValue(settings,"Respawn","BoolValue",false)
			kit.setValue(settings,"Vehicle","ObjectValue",car)
			kit.setValue(settings,"VehicleRole","StringValue",role)
		end
		soldier:SetAttribute("SpawnedBy",player.UserId)
		soldier:SetAttribute("VehicleCrew",true)
		soldier:SetAttribute("UniformPreset",options.uniform)
		soldier:AddTag(SOLDIER_TAG)

		--Beside the vehicle; his own script seats him.
		local spot = ground + side*(width/2 + 3) + forward*((index - 1)*3)
		local at = (kit.groundAt(spot,SOLDIER_TAG,GROUND_HEADROOM) or spot) + Vector3.new(0,footOffset,0)
		soldier:PivotTo(CFrame.lookAt(at,at + forward))
		soldier.Parent = workspace
		task.wait(0.1)
	end
	return #roles == 1 and " with a gunner" or " with a crew"
end

local function spawnVehicle(player,position,look,options)
	local template = templateFor(options.vehicle)
	if not template then
		return "No "..options.vehicle.." in ServerStorage."..FOLDER_NAME
	end
	if aliveCount() >= MAX_ALIVE then
		return "Server limit reached ("..MAX_ALIVE.." vehicles)"
	end
	local ground = kit.groundAt(position,SOLDIER_TAG,GROUND_HEADROOM)
	if not ground then
		return "No ground there"
	end
	--One that fights for a side (NeedsTeam, the AC-130) has to be given one.
	if template:GetAttribute("NeedsTeam") and options.team == ANY_TEAM then
		return "Pick a team for the "..template.Name
	end
	--An aircraft always comes with its whole crew: nobody can get in once it is up.
	--One that flies itself (Uncrewed, like the F-4 Phantom) gets none.
	if template:GetAttribute("Uncrewed") then
		options.crew = "None"
	elseif template:GetAttribute("Aircraft") then
		options.crew = "Full"
	end

	local forward = flat(look)
	forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0,0,-1)
	local turn = CFrame.lookAt(Vector3.zero,forward) * CFrame.lookAt(Vector3.zero,seatLook(template)):Inverse()
	local pivot = template:GetPivot()
	local boxCFrame,boxSize = template:GetBoundingBox()
	local footOffset = pivot.Position.Y - (boxCFrame.Position.Y - boxSize.Y/2)

	local car = template:Clone()
	car:SetAttribute("NoRespawn",true)
	if options.crew == "Gunner" then
		car:SetAttribute("GunnerOnly",true)
	end
	car:SetAttribute("SpawnedBy",player.UserId)
	car:AddTag(TAG)
	local settings = car:FindFirstChild("Settings")
	local height = 0
	if settings then
		kit.setValue(settings,"Team","StringValue",options.team == ANY_TEAM and "" or options.team)
		local heightValue = template:GetAttribute("Aircraft") and settings:FindFirstChild("Height")
		height = heightValue and heightValue.Value or 0
	end
	car:PivotTo(CFrame.new(ground + Vector3.new(0,footOffset + 0.5 + height,0)) * turn)
	car.Parent = workspace

	return "Spawned "..template.Name..crewUp(player,car,ground,forward,footprint(template).X,options)
end

local function clearAll()
	local cleared = 0
	for _,car in ipairs(CollectionService:GetTagged(TAG)) do
		car:Destroy()
		cleared += 1
	end
	for _,soldier in ipairs(CollectionService:GetTagged(SOLDIER_TAG)) do
		if soldier:GetAttribute("VehicleCrew") then
			soldier:Destroy()
		end
	end
	return "Cleared "..cleared..(cleared == 1 and " vehicle" or " vehicles")
end

local function validOptions(options)
	return typeof(options) == "table"
		and type(options.vehicle) == "string" and templateFor(options.vehicle) ~= nil
		and type(options.team) == "string" and (options.team == ANY_TEAM or kit.validTeam(options.team))
		and type(options.crew) == "string" and CREWS[options.crew] ~= nil
		and (options.uniform == nil or type(options.uniform) == "string")
end

local function onRequest(player,action,position,look,options)
	if action == "clear" then
		return clearAll()
	elseif action ~= "spawn" then
		return nil
	end

	if typeof(position) ~= "Vector3" or typeof(look) ~= "Vector3" or not kit.finite(position) or not kit.finite(look) then
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

remote.OnServerEvent:Connect(function(player,action,position,look,options)
	if not kit.holdsTool(player,TOOL_NAME) then
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

Players.PlayerRemoving:Connect(function(player)
	lastSpawn[player] = nil
	busy[player] = nil
end)

--[[
	Bloxian Spawner

	Serves the "Bloxian Spawner" tool in StarterPack. Clicking the ground drops
	in a unit cloned from ServerStorage.BLOXIAN, standing in a wedge facing
	where the player looks. The tool's panel picks the unit (infantry, or a
	sniper team or AT team), and for infantry the group size, weapon and radioman.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Teams = game:GetService("Teams")

--The soldier cloned for every spawn, by name, in ServerStorage.
local TEMPLATE_NAME = "BLOXIAN"

--The tool's name in StarterPack; a request only counts while the player holds it.
local TOOL_NAME = "Bloxian Spawner"

--Most spawned soldiers alive at once on the server, and seconds between one player's spawns.
local MAX_ALIVE = 40
local SPAWN_COOLDOWN = 1

--Furthest a click can be from the player, and the gap between soldiers in a wedge.
local MAX_SPAWN_DISTANCE = 400
local SPACING = 5

--Whether spawned soldiers respawn after dying.
local SPAWNED_RESPAWN = false

--Panel teams that are not Roblox teams: Hostile fights everyone, Friendly fights
--Bloxians of other teams but never players. Any team in Teams can also be picked;
--those soldiers side with its players and leave players with no team alone.
local HOSTILE_TEAM = "Hostile"
local FRIENDLY_TEAM = "Friendly"

local GROUP_SIZES = {1,4,9}
local WEAPONS = {Random = true, Rifle = true, DMR = true, Carbine = true, LMG = true, Sniper = true}

--Each unit's soldiers in spawn order, as {Settings.Unit, weapon, role}. Infantry
--is built from the panel's group, weapon and radioman instead.
local UNITS = {
	Infantry = true,
	["Sniper team"] = {
		{"Sniper", "Sniper", "Rifleman"},
		{"Spotter", "Rifle", "Rifleman"},
	},
	["AT team"] = {
		{"Rocketeer", "Carbine", "Rifleman"},
		{"Loader", "Rifle", "Rifleman"},
	},
}
local RADIO = {Random = true, Leader = true, None = true}

local TAG = "BloxianSpawned"

local lastSpawn = {}
local busy = {}
local nextTeamId = 0

local function aliveCount()
	local count = 0
	for _,model in ipairs(CollectionService:GetTagged(TAG)) do
		local human = model:FindFirstChildOfClass("Humanoid")
		if human and human.Health > 0 and model:IsDescendantOf(workspace) then
			count += 1
		end
	end
	return count
end

local function finite(vector)
	return vector == vector and vector.Magnitude < 1e6
end

local function groundAt(position)
	local ignore = CollectionService:GetTagged(TAG)
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

local function roleFor(index,radio)
	if radio == "Leader" then
		return index == 1 and "Radioman" or "Rifleman"
	elseif radio == "None" then
		return "Rifleman"
	end
	return "Random"
end

local function spawnGroup(player,position,look,options)
	local template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	if not template then
		return "No "..TEMPLATE_NAME.." in ServerStorage"
	end

	local room = MAX_ALIVE - aliveCount()
	if room <= 0 then
		return "Server limit reached ("..MAX_ALIVE.." alive)"
	end

	local forward = Vector3.new(look.X,0,look.Z)
	forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0,0,-1)
	local right = forward:Cross(Vector3.yAxis)

	local boxCFrame,boxSize = template:GetBoundingBox()
	local footOffset = template:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y/2)
	local attackPlayers = options.team == HOSTILE_TEAM

	local roster = UNITS[options.unit]
	if roster == true then
		roster = nil
	end
	local size = roster and #roster or options.size
	if roster and room < size then
		return "Server limit reached ("..MAX_ALIVE.." alive)"
	end
	nextTeamId += 1

	local spawned = 0
	for index = 1,math.min(size,room) do
		local k = index - 1
		local row = math.ceil(k/2)
		local side = k % 2 == 1 and -1 or 1
		local ground = groundAt(position + right*(side*row*SPACING) - forward*(row*SPACING))

		if ground then
			local soldier = template:Clone()
			local settings = soldier:FindFirstChild("Settings")
			if settings then
				setValue(settings,"Team","StringValue",options.team)
				setValue(settings,"AttackPlayers","BoolValue",attackPlayers)
				setValue(settings,"Respawn","BoolValue",SPAWNED_RESPAWN)
				if roster then
					local slot = roster[index]
					setValue(settings,"Unit","StringValue",slot[1])
					setValue(settings,"Weapon","StringValue",slot[2])
					setValue(settings,"Role","StringValue",slot[3])
					setValue(settings,"Guerrilla","BoolValue",false)
					setValue(settings,"Wander","BoolValue",false)
					setValue(settings,"UseVehicles","BoolValue",false)
					soldier:SetAttribute("PairId",nextTeamId)
				else
					setValue(settings,"Unit","StringValue","Infantry")
					setValue(settings,"Weapon","StringValue",options.weapon)
					setValue(settings,"Role","StringValue",roleFor(index,options.radio))
				end
			end
			soldier:SetAttribute("SpawnedBy",player.UserId)
			soldier:AddTag(TAG)

			local at = ground + Vector3.new(0,footOffset,0)
			soldier:PivotTo(CFrame.lookAt(at,at + forward))
			soldier.Parent = workspace
			spawned += 1

			--Spread the script start-up over a few frames.
			task.wait(0.1)
		end
	end

	if spawned == 0 then
		return "No ground there"
	end
	return "Spawned "..spawned..(spawned == 1 and " soldier" or " soldiers")
end

local function clearFor(player)
	local cleared = 0
	for _,model in ipairs(CollectionService:GetTagged(TAG)) do
		if model:GetAttribute("SpawnedBy") == player.UserId then
			local settings = model:FindFirstChild("Settings")
			local respawn = settings and settings:FindFirstChild("Respawn")
			if respawn then
				respawn.Value = false
			end
			model:Destroy()
			cleared += 1
		end
	end
	return "Cleared "..cleared
end

local function validTeam(name)
	if name == HOSTILE_TEAM or name == FRIENDLY_TEAM then
		return true
	end
	local team = Teams:FindFirstChild(name)
	return team ~= nil and team:IsA("Team")
end

local function validOptions(options)
	return typeof(options) == "table"
		and type(options.unit) == "string" and UNITS[options.unit] ~= nil
		and table.find(GROUP_SIZES,options.size) ~= nil
		and type(options.team) == "string" and validTeam(options.team)
		and type(options.weapon) == "string" and WEAPONS[options.weapon] ~= nil
		and type(options.radio) == "string" and RADIO[options.radio] ~= nil
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
		return nil
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
	local ok,message = pcall(spawnGroup,player,position,look,options)
	busy[player] = nil
	if not ok then
		warn("[BloxianSpawner] "..tostring(message))
		return "Spawn failed"
	end
	return message
end

local remote = Instance.new("RemoteEvent")
remote.Name = "BloxianSpawnerRemote"
remote.Parent = ReplicatedStorage

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
	local message = onRequest(player,action,position,look,options)
	if message and player.Parent then
		remote:FireClient(player,message)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastSpawn[player] = nil
	busy[player] = nil
end)

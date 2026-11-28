--[[
	Bloxian Spawner

	Serves the "Bloxian Spawner" tool in StarterPack. Clicking the ground drops
	in a unit cloned from ServerStorage.BLOXIAN, standing in a wedge facing
	where the player looks. The tool's panel picks the unit (infantry, or a
	sniper team or AT team), and for infantry the group size, weapon and radioman.
	Its Kinetic Events tab calls artillery or an airstrike on the clicked spot.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local kit = require(script:WaitForChild("SpawnerKit"))

--The soldier cloned for every spawn, by name, in ServerStorage.
local TEMPLATE_NAME = "BLOXIAN"

--The tool's name in StarterPack; a request only counts while the player holds it.
local TOOL_NAME = "Bloxian Spawner"

--Most spawned soldiers alive at once on the server, and seconds between one player's spawns.
local MAX_ALIVE = 60
local SPAWN_COOLDOWN = 1

--Ground is looked for from this far above the clicked height, so a soldier lands
--where the cursor points, not on a roof, tree or ledge over it.
local SPAWN_HEADROOM = 4

--Furthest a click can be from the player, and the gap between soldiers in a wedge.
local MAX_SPAWN_DISTANCE = 5000
local SPACING = 5

--Whether spawned soldiers respawn after dying.
local SPAWNED_RESPAWN = false

--Hostile fights everyone, Friendly fights Bloxians of other teams but never
--players. Any team in Teams can also be picked; those soldiers side with its
--players and leave players with no team alone.
local HOSTILE_TEAM = "Hostile"

--Infantry spawned this close to a living infantry unit of their team join it.
local UNIT_JOIN_RANGE = 30

local GROUP_SIZES = {1,4,9}
local WEAPONS = {Random = true, Rifle = true, DMR = true, Carbine = true, LMG = true, Sniper = true}

--Special operations sizes the panel can pick.
local SOF_SIZES = {Recce = true, Fireteam = true}

--A special operations kind (SofModule) by size, each a named unit labelled
--with its echelon from the start: a Recce (radioman and rifleman) or a Fireteam
--(radioman, two riflemen and a shotgunner). rifle is the kind's rifleman weapon.
local function sofUnit(unit,rifle)
	local function build(echelon,slots)
		local roster = {squad = true, echelon = echelon}
		for index,slot in ipairs(slots) do
			roster[index] = {unit, slot[1], slot[2]}
		end
		return roster
	end
	return {sizes = {
		Recce = build("Recce",{{rifle,"Radioman"},{rifle,"Rifleman"}}),
		Fireteam = build("SOF Fireteam",{{rifle,"Radioman"},{rifle,"Rifleman"},{rifle,"Rifleman"},{"Shotgun","Rifleman"}}),
	}}
end

--Each unit's soldiers in spawn order, as {Settings.Unit, weapon, role}. Infantry
--is built from the panel's group, weapon and radioman instead. A roster with
--squad = true is a unit with a name (SquadModule), like an infantry squad.
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
	["Special Recon"] = sofUnit("Special Recon","Rifle"),
}
local RADIO = {Random = true, Leader = true, None = true}

--Kinetic Events: seconds between one player's calls, and how far off the battery's
--shells have to be before soldiers run from them.
local KINETIC_COOLDOWN = 10
local SHELLS_SEEN_AT = 4
--Airstrike: an F-4 from ServerStorage.BloxianVehicles comes in STRIKE_HEIGHT studs
--up, STRIKE_OFFSET off, attacks only infantry, those within STRIKE_RADIUS of the
--spot first, and leaves after STRIKE_RUNS strafes. The tool's ring shows STRIKE_RADIUS.
local STRIKE_HEIGHT = 650
local STRIKE_OFFSET = 800
local STRIKE_RADIUS = 150
local STRIKE_RUNS = 3
local KINETIC_EVENTS = {Artillery = true, Airstrike = true}

local TAG = "BloxianSpawned"

--What the tracker calls each kind of two-man team, before its number.
local PAIR_LABELS = {["Sniper team"] = "Sniper Team", ["AT team"] = "AT Team"}

local pairCounts = {}
local lastSpawn = {}
local lastKinetic = {}
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

local function roleFor(index,radio)
	if radio == "Leader" then
		return index == 1 and "Radioman" or "Rifleman"
	elseif radio == "None" then
		return "Rifleman"
	end
	return "Random"
end

--A living spawned infantry unit of team with a soldier within UNIT_JOIN_RANGE of position.
local function unitAt(position,team)
	for _,model in ipairs(CollectionService:GetTagged(TAG)) do
		local settings = model:FindFirstChild("Settings")
		local human = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if settings and human and root and human.Health > 0 and model:GetAttribute("SquadId")
			and settings.Team.Value == team and settings.Unit.Value == "Infantry"
			and (root.Position - position).Magnitude <= UNIT_JOIN_RANGE then
			return model
		end
	end
	return nil
end

local function pairLabel(kind)
	pairCounts[kind] = (pairCounts[kind] or 0) + 1
	return PAIR_LABELS[kind].." "..pairCounts[kind]
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
	elseif roster.sizes then
		roster = roster.sizes[options.sofSize] or roster.sizes.Recce
	end
	local size = roster and #roster or options.size
	if roster and room < size then
		return "Server limit reached ("..MAX_ALIVE.." alive)"
	end
	nextTeamId += 1
	local squadId = nextTeamId

	local function groundInWedge(index)
		local k = index - 1
		local row = math.ceil(k/2)
		local side = k % 2 == 1 and -1 or 1
		return kit.groundAt(position + right*(side*row*SPACING) - forward*(row*SPACING),TAG,SPAWN_HEADROOM)
	end

	--Every spot with ground first, so each soldier (and his respawn copy) knows
	--how many made it.
	local spots = {}
	for index = 1,math.min(size,room) do
		local ground = groundInWedge(index)
		if ground then
			spots[#spots+1] = {index = index, ground = ground}
		end
	end
	if #spots == 0 then
		return "No ground there"
	end
	--Infantry groups of more than one are a unit; the soldiers name it (SquadModule).
	local count = #spots
	local isUnit = (not roster or roster.squad) and count > 1
	local joined = not roster and unitAt(position,options.team)
	local unitId = joined and joined:GetAttribute("SquadId") or squadId
	local unitSize = joined and joined:GetAttribute("SquadSize") + count or count
	--Special operations are labelled from the start: four random digits.
	local sofName = roster and roster.squad and string.format("%04d",math.random(0,9999))

	--Each squad brings an AT team, at the back of the wedge, when there is room.
	local atTeam = UNITS["AT team"]
	local atTeamId = nil
	local rosterLabel = roster and not roster.squad and pairLabel(options.unit)
	if isUnit and not roster and room - count >= #atTeam then
		nextTeamId += 1
		atTeamId = nextTeamId
		for index,slot in ipairs(atTeam) do
			local ground = groundInWedge(size + index)
			if ground then
				spots[#spots+1] = {index = index, ground = ground, slot = slot}
				unitSize += 1
			end
		end
	end

	if joined then
		for _,model in ipairs(CollectionService:GetTagged(TAG)) do
			if model:GetAttribute("SquadId") == unitId then
				model:SetAttribute("SquadSize",unitSize)
			end
		end
	end

	local spawned = 0
	for _,spot in ipairs(spots) do
		local index,ground = spot.index,spot.ground
		local soldier = template:Clone()
		local settings = soldier:FindFirstChild("Settings")
		if settings then
			kit.setValue(settings,"Team","StringValue",options.team)
			kit.setValue(settings,"AttackPlayers","BoolValue",attackPlayers)
			kit.setValue(settings,"Respawn","BoolValue",SPAWNED_RESPAWN)
			local slot = spot.slot or roster and roster[index]
			if slot then
				kit.setValue(settings,"Unit","StringValue",slot[1])
				kit.setValue(settings,"Weapon","StringValue",slot[2])
				kit.setValue(settings,"Role","StringValue",slot[3])
				kit.setValue(settings,"Guerrilla","BoolValue",false)
				--Special operations patrol to find the enemy; pairs hold where they are put.
				kit.setValue(settings,"Wander","BoolValue",roster ~= nil and roster.squad == true)
				kit.setValue(settings,"UseVehicles","BoolValue",false)
				if not (roster and roster.squad) then
					soldier:SetAttribute("PairId",spot.slot and atTeamId or squadId)
					--A squad's AT team is part of the squad: it shows on the squad's tag, not its own.
				soldier:SetAttribute("TeamLabel",not spot.slot and rosterLabel or nil)
					soldier:SetAttribute("AttachedTo",spot.slot and unitId or nil)
				end
			else
				kit.setValue(settings,"Unit","StringValue","Infantry")
				kit.setValue(settings,"Weapon","StringValue",options.weapon)
				kit.setValue(settings,"Role","StringValue",roleFor(index,options.radio))
			end
		end
		soldier:SetAttribute("SpawnedBy",player.UserId)
		--Set before he goes in, so his respawn copy is in the same squad.
		if isUnit or joined then
			soldier:SetAttribute("SquadId",unitId)
			soldier:SetAttribute("SquadSize",unitSize)
			if sofName then
				soldier:SetAttribute("SquadName",sofName)
				soldier:SetAttribute("SquadEchelon",roster.echelon)
			end
		end
		soldier:SetAttribute("UniformPreset",options.uniform)
		soldier:AddTag(TAG)

		local at = ground + Vector3.new(0,footOffset,0)
		soldier:PivotTo(CFrame.lookAt(at,at + forward))
		soldier.Parent = workspace
		spawned += 1

		--Spread the script start-up over a few frames.
		task.wait(0.1)
	end

	return "Spawned "..spawned..(spawned == 1 and " soldier" or " soldiers")
end

local function clearAll()
	local cleared = 0
	for _,model in ipairs(CollectionService:GetTagged(TAG)) do
		local settings = model:FindFirstChild("Settings")
		local respawn = settings and settings:FindFirstChild("Respawn")
		if respawn then
			respawn.Value = false
		end
		model:Destroy()
		cleared += 1
	end
	table.clear(pairCounts)
	return "Cleared "..cleared
end

--Soldiers run from every barrage on the list (FireSupportModule).
local function callArtillery(position)
	local mission = ServerStorage:FindFirstChild("ArtilleryFireMission")
	if not mission then
		return "No artillery installed"
	end
	local called,ok,info = pcall(mission.Invoke,mission,position)
	if not called or not ok then
		return "Artillery refused: "..tostring(called and info or ok)
	end
	_G.BloxianArtilleryZones = _G.BloxianArtilleryZones or {}
	local now = os.clock()
	table.insert(_G.BloxianArtilleryZones,{
		center = position,
		radius = info.radius,
		untilTime = now + info.duration,
		runsAt = now + info.firstImpact - SHELLS_SEEN_AT,
	})
	return "Called artillery"
end

--The model in ServerStorage.BloxianVehicles that flies itself with a Jet script.
local function jetTemplate()
	local folder = ServerStorage:FindFirstChild("BloxianVehicles")
	for _,model in ipairs(folder and folder:GetChildren() or {}) do
		if model:IsA("Model") and model:FindFirstChild("Jet") then
			return model
		end
	end
	return nil
end

--Everyone near the spot, for the F-4s to strike first (BloxianSpotted).
local function markStrike(position,team)
	_G.BloxianSpotted = _G.BloxianSpotted or setmetatable({},{__mode = "k"})
	local report = {team = team, at = workspace:GetServerTimeNow()}
	local function mark(root)
		if root and (root.Position - position).Magnitude <= STRIKE_RADIUS then
			_G.BloxianSpotted[root] = report
		end
	end
	for _,entry in pairs(_G.BloxianRadio or {}) do
		mark(entry.root)
	end
	for _,player in ipairs(Players:GetPlayers()) do
		local human = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		mark(human and human.RootPart)
	end
end

local function callAirstrike(player,position,team)
	local template = jetTemplate()
	if not template then
		return "No F-4 in ServerStorage.BloxianVehicles"
	end
	markStrike(position,team)

	local angle = math.random()*math.pi*2
	local at = position + Vector3.new(math.cos(angle)*STRIKE_OFFSET,STRIKE_HEIGHT,math.sin(angle)*STRIKE_OFFSET)
	local jet = template:Clone()
	local settings = jet:FindFirstChild("Settings")
	if settings then
		kit.setValue(settings,"Team","StringValue",team)
	end
	jet:SetAttribute("Strafes",STRIKE_RUNS)
	jet:SetAttribute("InfantryOnly",true)
	jet:SetAttribute("NoRespawn",true)
	jet:SetAttribute("SpawnedBy",player.UserId)
	jet:AddTag("VehicleSpawned")
	jet:PivotTo(CFrame.lookAt(at,Vector3.new(position.X,at.Y,position.Z)))
	jet.Parent = workspace
	return "Called airstrike"
end

local function validOptions(options)
	return typeof(options) == "table"
		and type(options.unit) == "string" and UNITS[options.unit] ~= nil
		and table.find(GROUP_SIZES,options.size) ~= nil
		and type(options.team) == "string" and kit.validTeam(options.team)
		and type(options.weapon) == "string" and WEAPONS[options.weapon] ~= nil
		and type(options.radio) == "string" and RADIO[options.radio] ~= nil
		and (options.sofSize == nil or SOF_SIZES[options.sofSize] == true)
		and (options.uniform == nil or type(options.uniform) == "string")
end

local function callKinetic(player,position,options)
	local now = os.clock()
	if now - (lastKinetic[player] or -math.huge) < KINETIC_COOLDOWN then
		return "Kinetic event on cooldown"
	end
	lastKinetic[player] = now
	if options.event == "Artillery" then
		return callArtillery(position)
	end
	return callAirstrike(player,position,options.team)
end

local function validKinetic(options)
	return typeof(options) == "table"
		and type(options.event) == "string" and KINETIC_EVENTS[options.event] == true
		and type(options.team) == "string" and kit.validTeam(options.team)
end

local function onRequest(player,action,position,look,options)
	if action == "clear" then
		return clearAll()
	elseif action ~= "spawn" and action ~= "kinetic" then
		return nil
	end

	if typeof(position) ~= "Vector3" or typeof(look) ~= "Vector3" or not kit.finite(position) or not kit.finite(look) then
		return nil
	end
	local kinetic = action == "kinetic"
	if not (if kinetic then validKinetic(options) else validOptions(options)) then
		return nil
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - position).Magnitude > MAX_SPAWN_DISTANCE then
		return "Too far away"
	end
	if kinetic then
		return callKinetic(player,position,options)
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

remote.OnServerEvent:Connect(function(player,action,position,look,options)
	if not kit.holdsTool(player,TOOL_NAME) then
		return
	end
	local message = onRequest(player,action,position,look,options)
	if message and player.Parent then
		remote:FireClient(player,message)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastSpawn[player] = nil
	lastKinetic[player] = nil
	busy[player] = nil
end)

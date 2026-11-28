--[[
	TowerRun

	The co-op tower loop. "Enter" at the Garrison HQ doors sends every Korblox
	player to floor 1 of a stack of prefabs from ServerStorage.TowerFloors, built
	far from the city at ZONE. Each floor spawns Bloxian AI at its EnemySpawn parts.
	When none are left standing the StairDoor opens; touching StairExit moves the
	squad up. After the last floor the squad comes out on the real tower roof,
	fights a last wave, and boards the extraction heli.

	Attributes on this script:
	  Floors (number)  floors before the roof, overriding the difficulty's. Set it to 3 for a quick test.

	Difficulty: ReplicatedStorage.TowerDifficulties (floors, respawn waves, kit). Picked with F at the tavern
	table while no raid runs; TowerStatus.Difficulty shows it.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

local PLAYER_TEAM = "Korblox Confederacy"
local ENEMY_TEAM = "Bloxian Commonwealth"
local ZONE = Vector3.new(30000, 0, 0) -- floor 1's centre; floors stack straight up
local FLOOR_GAP = 17 -- prefab height
local ENEMY_BASE = 5 -- enemies on floor 1 with one player
local ENEMY_PER_FLOOR = 0.5
local ENEMY_PER_EXTRA_PLAYER = 2
local MAX_ALIVE = 14 -- the rest trickle in as others die
local ROOF_WAVE = 10
local HELI_WAIT = 60 -- seconds of roof fighting before the heli comes in anyway
local SPAWN_TAG = "BloxianSpawned" -- the BloxianSpawner's tag, so its clear button covers ours too
local ENEMY_TAG = "TowerEnemy"
local GET_READY = 6 -- seconds on a new floor before enemies spawn; players carry a ForceField meanwhile
local SAFE_RADIUS = 40 -- no enemy spawns this close to where the squad arrives
local BUILD_BATCH = 400 -- parts added (or removed) per frame when a floor goes in or out; all at once froze server and clients
local Difficulties = require(ReplicatedStorage:WaitForChild("TowerDifficulties"))
local Bosses = require(ServerStorage:WaitForChild("TowerBosses")) -- mini-boss floors (TowerDifficulties bossFloors / bossPool)
local POINTS = { floor = 500, kill = 100, head = 50, revive = 250, death = -200, extract = 2500 }
local FOREST_RUN, FOREST_TIME = 150, 5 -- leg 1: studs / seconds pulling away from the staging post
local CUT_TIME = 1.2 -- black between the legs (the drive in, skipped)
local CITY_RUN, CITY_TIME = 220, 8 -- leg 2 (long, so the van is still far off while the Insertion camera tilts down): studs / seconds up the plaza road into the stop
local INSERT_STOP = CFrame.lookAt(Vector3.new(0, 0, -83), Vector3.new(1, 0, -83)) -- plaza-side lane, right flank (side door) to the tower
local STAGE_WAIT = 20 -- deploy countdown once anyone in the staging zone is ready
local STAGE_ALL_READY = 5 -- ...cut to this once everyone in the zone is ready (so a solo player waits 5 s)

-- Respawns are ours: run deaths wait for the difficulty's respawnWaves, everyone else after Players.RespawnTime.
Players.CharacterAutoLoads = false

local floorsFolder = ServerStorage:WaitForChild("TowerFloors")
local template = ServerStorage:WaitForChild("BLOXIAN")
local heliTemplate = ServerStorage:WaitForChild("ExtractionHeli")
local vanTemplate = ReplicatedStorage:WaitForChild("InsertionVan") -- replicated so clients preload its mesh
local tower = workspace:WaitForChild("GarrisonTower")
local prompt = tower:WaitForChild("Entrance"):WaitForChild("Doors"):WaitForChild("EnterPrompt") -- join a raid in progress
local staging = workspace:WaitForChild("Staging")
local stageZone = staging:WaitForChild("Zone")
local stagingVan = staging:WaitForChild("StagingVan")
local readyPrompt = staging:WaitForChild("ReadyPoint"):WaitForChild("ReadyPrompt")
local difficultyPrompt = staging.ReadyPoint:WaitForChild("DifficultyPrompt")

-- Status the HUD (StarterGui.TowerHUD) shows: Banner text, Floor, Floors, Enemies.
local status = ReplicatedStorage:FindFirstChild("TowerStatus") or Instance.new("Folder")
status.Name = "TowerStatus"
status.Parent = ReplicatedStorage
-- the selected difficulty; it can't change while a run is on, so it is also the run's
local difficulty = if Difficulties[status:GetAttribute("Difficulty") or ""] then status:GetAttribute("Difficulty") else Difficulties.default
status:SetAttribute("Difficulty", difficulty)
local function diff() return Difficulties[difficulty] end
-- SPH_Server and ExplosionFX read teamKill on every hit, so flipping it here takes effect at once
local sphConfig = require(ReplicatedStorage:WaitForChild("SPH_Assets"):WaitForChild("GameConfig"))
local function applyFriendlyFire()
	sphConfig.teamKill = diff().friendlyFire == true
	status:SetAttribute("FriendlyFire", sphConfig.teamKill) -- for HUDs (and to check it from outside)
end
applyFriendlyFire()

local runFolder = workspace:FindFirstChild("TowerRunFloors") or Instance.new("Folder")
runFolder.Name = "TowerRunFloors"
runFolder.Parent = workspace

local running = false
local runId = 0 -- bumps each run, so loops from an old run stop
local floorN = 0
local floors = {} -- [n] = model
local lastPick = nil
local cleared = false
local crew = {} -- [player] = true for everyone deployed in this run (staged at start, or joined at the doors)
local held = {} -- [player] = cleared floors left before they respawn; the count shows on their own death screen (attribute RespawnWaves)
local returning = {} -- [player] = true while a held player is loaded back into the run, so CharacterAdded keeps their InTowerRun

-- End-of-raid score (StarterPlayerScripts.RaidReport draws it) and each player's best run per difficulty.
-- Record = most floors cleared, ties broken by score. Saved in DataStore TowerRecords, key "u<UserId>" = { [difficulty] = { floors, score } }.
local report = Instance.new("RemoteEvent")
report.Name = "RaidReport"
report.Parent = ReplicatedStorage
local records = DataStoreService:GetDataStore("TowerRecords")
-- /leaderboards (StarterPlayerScripts.RaidReport): an OrderedDataStore per difficulty, value = floors * 1e6 + score so floors rank first
local function topStore(name) return DataStoreService:GetOrderedDataStore("TowerTop_" .. name) end
local function postTop(p, name, rec)
	local v = rec.floors * 1e6 + math.clamp(math.floor(rec.score), 0, 999999)
	local ok, err = pcall(topStore(name).UpdateAsync, topStore(name), "u" .. p.UserId, function(old)
		if old and old >= v then return nil end -- another server may hold a better run
		return v
	end)
	if not ok then warn("TowerRun: leaderboard not updated for " .. p.Name .. ": " .. tostring(err)) end
end
local boardFn = Instance.new("RemoteFunction")
boardFn.Name = "TowerLeaderboards"
boardFn.Parent = ReplicatedStorage
local boardCache, boardAt, boardBusy, boardNames = nil, -math.huge, false, {}
local function nameOf(userId)
	if boardNames[userId] == nil then
		local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		boardNames[userId] = if ok then n else false
	end
	return boardNames[userId] or ("User " .. userId)
end
boardFn.OnServerInvoke = function()
	while boardBusy do task.wait() end
	if os.clock() - boardAt < 60 then return boardCache end -- one fetch a minute, however many players ask
	boardBusy = true
	local boards = {}
	for _, name in Difficulties.order do
		local rows = {}
		local ok, pages = pcall(function() return topStore(name):GetSortedAsync(false, 10) end)
		if ok then
			for i, e in pages:GetCurrentPage() do
				local id = tonumber(e.key:sub(2))
				rows[i] = { name = if id then nameOf(id) else e.key, floors = e.value // 1e6, score = e.value % 1e6 }
			end
		end
		if ok then boards[name] = rows end -- left out on a failed fetch, so the card says UNAVAILABLE, not empty
	end
	boardCache, boardAt, boardBusy = boards, os.clock(), false
	return boards
end
-- StarterPlayerScripts.Insertion films the drive-up: (drive seconds, stop CFrame); it finds workspace.InsertionVan itself
local insertCue = Instance.new("RemoteEvent")
insertCue.Name = "Insertion"
insertCue.Parent = ReplicatedStorage
local bests = {} -- [player] = { [difficulty] = { floors, score } }, loaded on join
local stats = {} -- [player] = this run's tallies, for everyone who entered it
local floorsCleared = 0
local runStart = 0
local splits = {} -- { { n, t = seconds from GET READY ending to the clear, boss = true? } } for this run

-- Run grade on the raid card. Par is per cleared floor; deaths, slow floors and failing cost, accuracy and revives add.
local PAR_FLOOR, PAR_BOSS = 120, 180
local function fmtTime(s) s = math.floor(s) return string.format("%d:%02d", s // 60, s % 60) end
local function gradeOf(g) -- g = { extracted, floors, total, used, par, deaths, revives, accuracy? }
	local pts = 100
	if not g.extracted then pts -= 25 + 40 * (1 - g.floors / math.max(g.total, 1)) end
	pts -= 12 * g.deaths
	if g.par > 0 then
		local ratio = g.used / g.par
		if ratio > 1 then pts -= math.min(30, (ratio - 1) * 50) elseif ratio < 0.75 then pts += 5 end
	end
	pts += math.min(12, 4 * g.revives)
	if g.accuracy then pts += math.clamp((g.accuracy - 0.35) * 25, -8, 8) end
	if not g.extracted and g.floors == 0 then return "F" end
	return if pts >= 95 then "S" elseif pts >= 85 then "A" elseif pts >= 70 then "B" elseif pts >= 55 then "C" else "D"
end
-- self-check: a clean extraction at par is S, a wipe on floor 1 is F, a death and slow floors drop it to C
assert(gradeOf({ extracted = true, floors = 5, total = 5, used = 600, par = 600, deaths = 0, revives = 0 }) == "S")
assert(gradeOf({ extracted = false, floors = 0, total = 5, used = 0, par = 0, deaths = 1, revives = 0 }) == "F")
assert(gradeOf({ extracted = true, floors = 5, total = 5, used = 900, par = 600, deaths = 1, revives = 0 }) == "C")

local function better(a, b)
	return not b or a.floors > b.floors or (a.floors == b.floors and a.score > b.score)
end

local function totalFloors()
	return script:GetAttribute("Floors") or diff().floors
end

-- /PR (StarterPlayerScripts.RaidReport) reads these: the record on the hardest difficulty the player has one on.
local function publishRecord(p)
	local name, rec = nil, nil
	for _, n in Difficulties.order do -- easiest to hardest, so the last hit wins
		if bests[p] and bests[p][n] then name, rec = n, bests[p][n] end
	end
	p:SetAttribute("PRDifficulty", name)
	p:SetAttribute("PRFloors", rec and rec.floors)
	p:SetAttribute("PRScore", rec and rec.score)
end

local function loadRecord(p)
	local ok, data = pcall(records.GetAsync, records, "u" .. p.UserId)
	if p.Parent then
		bests[p] = if ok and type(data) == "table" then data else {}
		publishRecord(p)
		for name, rec in bests[p] do -- backfills the boards with records set before they existed
			if Difficulties[name] and type(rec) == "table" and rec.floors then task.spawn(postTop, p, name, rec) end
		end
	end
end

local function saveRecord(p, rec, name)
	local ok, err = pcall(records.UpdateAsync, records, "u" .. p.UserId, function(old)
		old = type(old) == "table" and old or {}
		if not better(rec, old[name]) then return nil end -- nil keeps what's stored
		old[name] = rec
		return old
	end)
	if not ok then warn("TowerRun: record not saved for " .. p.Name .. ": " .. tostring(err)) end
end

local function sendReports(extracted, seconds)
	local list, floorsDone = stats, floorsCleared
	stats = {}
	local used, par, fastest = 0, 0, nil
	for _, sp in splits do
		used += sp.t
		par += if sp.boss then PAR_BOSS else PAR_FLOOR
		fastest = math.min(fastest or math.huge, sp.t)
	end
	local timing = { used = used, par = par, fastest = fastest, avg = if #splits > 0 then used / #splits else nil }
	local squadRows = {} -- everyone's tallies, for the squad table on each card
	for p, s in list do
		if not p.Parent then continue end
		local shots = (p:GetAttribute("ShotsFired") or 0) - s.shots0
		table.insert(squadRows, {
			name = p.DisplayName, userId = p.UserId, kills = s.kills, heads = s.heads, deaths = s.deaths,
			revives = (p:GetAttribute("Revives") or 0) - s.revives0,
			accuracy = if shots > 0 then ((p:GetAttribute("ShotsHit") or 0) - s.hits0) / shots else nil,
		})
	end
	table.sort(squadRows, function(a, b) return a.kills > b.kills end)
	for p, s in list do
		if not p.Parent then continue end
		local revives = (p:GetAttribute("Revives") or 0) - s.revives0
		local lines = {
			{ "FLOORS CLEARED", floorsDone, floorsDone * POINTS.floor },
			{ "HOSTILES KILLED", s.kills, s.kills * POINTS.kill },
			{ "HEADSHOTS", s.heads, s.heads * POINTS.head },
			{ "SQUADMATES REVIVED", revives, revives * POINTS.revive },
			{ "TIMES KILLED", s.deaths, s.deaths * POINTS.death },
		}
		if extracted then table.insert(lines, { "EXTRACTION", 1, POINTS.extract }) end
		local shots = (p:GetAttribute("ShotsFired") or 0) - s.shots0
		local grade = gradeOf({ extracted = extracted, floors = floorsDone, total = totalFloors(), used = used, par = par,
			deaths = s.deaths, revives = revives,
			accuracy = if shots >= 20 then ((p:GetAttribute("ShotsHit") or 0) - s.hits0) / shots else nil })
		local score = 0
		for _, l in lines do score += l[3] end
		local rec = { floors = floorsDone, score = math.max(score, 0) }
		local mine = bests[p] or {}
		bests[p] = mine
		local newBest = floorsDone > 0 and better(rec, mine[difficulty])
		if newBest then
			mine[difficulty] = rec
			publishRecord(p)
			task.spawn(saveRecord, p, rec, difficulty)
			task.spawn(postTop, p, difficulty, rec)
		end
		report:FireClient(p, {
			result = if extracted then "EXTRACTED" else "RAID FAILED",
			difficulty = difficulty, floors = floorsDone, total = totalFloors(), time = seconds,
			lines = lines, score = rec.score, best = mine[difficulty], newBest = newBest, squad = squadRows,
			grade = grade, timing = timing,
		})
	end
end

local function setStatus(banner, enemies)
	status:SetAttribute("Banner", banner)
	status:SetAttribute("Floor", floorN)
	status:SetAttribute("Floors", totalFloors())
	status:SetAttribute("Enemies", enemies)
end

-- The difficulty's medical kit, replacing whatever Bandages / Medkits the player has. Medics get a Medkit on top.
local function giveKit(p)
	local backpack = p:WaitForChild("Backpack", 10)
	if not backpack then return end
	for _, holder in { backpack, p.Character } do
		for _, t in holder and holder:GetChildren() or {} do
			if t:IsA("Tool") and (t.Name == "Bandage" or t.Name == "Medkit") then t:Destroy() end
		end
	end
	local kit = table.clone(diff().kit)
	if p:GetAttribute("Medic") then kit.Medkit = (kit.Medkit or 0) + 1 end
	for _, name in { "Bandage", "Medkit" } do -- fixed order, so the hotbar slots don't shuffle
		for _ = 1, kit[name] or 0 do ServerStorage[name]:Clone().Parent = backpack end
	end
end

local function isOut(model)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	return not hum or hum.Health <= 0 or model:GetAttribute("Downed") == true or not model.Parent
end

local function squad()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Team and p.Team.Name == PLAYER_TEAM then
			table.insert(list, p)
		end
	end
	return list
end

local function inRun(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and player:GetAttribute("InTowerRun") == true and not isOut(player.Character)
end

-- Everyone in the run who still has a living character, downed included: they move with the squad.
local function carried(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return player:GetAttribute("InTowerRun") == true and hum ~= nil and hum.Health > 0
		and char:FindFirstChild("HumanoidRootPart") ~= nil
end

local function teleport(player, cf, includeDowned)
	local char = player.Character
	if not char or (isOut(char) and not (includeDowned and carried(player))) then return end
	if running and not stats[player] then
		stats[player] = { kills = 0, heads = 0, deaths = 0, revives0 = player:GetAttribute("Revives") or 0,
			shots0 = player:GetAttribute("ShotsFired") or 0, hits0 = player:GetAttribute("ShotsHit") or 0 }
	end
	local shield = Instance.new("ForceField")
	shield.Visible = false
	shield.Parent = char
	game:GetService("Debris"):AddItem(shield, GET_READY + 3)
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(cf.Position, 5) end)
		if char.Parent then char:PivotTo(cf) end
	end)
	player:SetAttribute("InTowerRun", true)
	player:SetAttribute("Riding", nil)
end

local goUp -- defined below; the stair trigger calls it

local function hookStairs(m)
	local exit = m:FindFirstChild("StairExit", true)
	if not exit then return end
	exit.CanTouch = true
	exit.Touched:Connect(function(hit)
		local p = Players:GetPlayerFromCharacter(hit.Parent)
		if p and inRun(p) and cleared and floors[floorN] == m then goUp(runId) end
	end)
end

local function floorOrigin(n)
	return CFrame.new(ZONE + Vector3.new(0, 8 + (n - 1) * FLOOR_GAP, 0))
end

local forcedMap = nil -- console "map <name>": the next floor built uses this prefab
local function buildFloor(n)
	local options = floorsFolder:GetChildren()
	local pick = forcedMap and floorsFolder:FindFirstChild(forcedMap)
	forcedMap = nil
	if not pick then
		pick = options[math.random(#options)]
		if #options > 1 then
			while pick == lastPick do pick = options[math.random(#options)] end
		end
	end
	lastPick = pick
	-- an empty shell first, then the prefab cloned in piece by piece, BUILD_BATCH parts a frame:
	-- cloning a whole floor took up to ~450 ms in one frame, and parenting it froze every client too
	local m = Instance.new("Model")
	m.Name = "Floor" .. n .. "_" .. pick.Name
	for k, v in pick:GetAttributes() do m:SetAttribute(k, v) end
	m.WorldPivot = floorOrigin(n)
	local shift = floorOrigin(n) * pick:GetPivot():Inverse()
	m:SetAttribute("Building", true)
	m.Parent = runFolder
	floors[n] = m
	local pieces = pick:GetChildren()
	table.sort(pieces, function(a, b) return a:IsA("BasePart") and not b:IsA("BasePart") end) -- structure first, props after
	local budget = 0
	for _, src in pieces do
		if not m.Parent then return m end -- the run ended mid-build
		local c = src:Clone()
		if c:IsA("PVInstance") then
			c:PivotTo(shift * src:GetPivot())
		else
			for _, d in c:GetDescendants() do if d:IsA("BasePart") then d.CFrame = shift * d.CFrame end end
		end
		for _, d in if c:IsA("BasePart") then { c } else c:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "EnemySpawn" or d.Name == "EntryPoint" or d.Name == "StairExit") then
				d.Transparency = 1
				d.CanCollide = false
			end
		end
		c.Parent = m
		budget += if c:IsA("BasePart") then 1 else #c:GetDescendants()
		if budget >= BUILD_BATCH then budget = 0 task.wait() end
	end
	m:SetAttribute("Building", nil)
	hookStairs(m)
	return m
end

-- Waits out a floor that is still being built.
local function built(m)
	while m.Parent and m:GetAttribute("Building") do task.wait() end
	return m
end

-- Destroys a floor BUILD_BATCH parts a frame.
local function scrap(m)
	local budget = 0
	for _, c in m:GetChildren() do
		budget += if c:IsA("BasePart") then 1 else #c:GetDescendants()
		c:Destroy()
		if budget >= BUILD_BATCH then budget = 0 task.wait() end
	end
	m:Destroy()
end

-- True while any player's character is inside floor m (with a little margin).
local function anyoneOn(m)
	local cf, size = m:GetBoundingBox()
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local l = cf:PointToObjectSpace(root.Position)
			if math.abs(l.X) < size.X / 2 + 4 and math.abs(l.Y) < size.Y / 2 - 1 and math.abs(l.Z) < size.Z / 2 + 4 then
				return true
			end
		end
	end
	return false
end

-- Drops floor n from the run, but leaves it standing until every player is out of it.
local function retireFloor(n)
	local m = floors[n]
	if not m then return end
	floors[n] = nil
	task.spawn(function()
		while m.Parent and anyoneOn(m) do task.wait(1) end
		if m.Parent then scrap(m) end
	end)
end

local function part(m, name)
	return m:FindFirstChild(name, true)
end

local warnedUntil = 0 -- floors up to this one start alerted and reinforced (a Signals Officer got his warning out)
local bossesUsed = {} -- boss ids already fought this run; a boss floor picks from the rest of bossPool
local forcedBoss = nil -- "/boss <name>": the next floor fights this boss, boss floor or not

local function spawnSoldier(cf, alerted, setup)
	alerted = alerted or floorN <= warnedUntil
	local soldier = template:Clone()
	-- HoldRoom: never push, hold angles. Unalerted: no hearing/sensing through walls or doors until a squadmate dies.
	soldier:SetAttribute("HoldRoom", true)
	soldier:SetAttribute("NoGrenades", floorN < 10) -- grenades and M203 from floor 10 up
	soldier:SetAttribute("Unalerted", not alerted)
	local settings = soldier:FindFirstChild("Settings")
	if settings then
		for name, value in {
			Team = ENEMY_TEAM, AttackPlayers = true, Respawn = false, UseVehicles = false, Unit = "Infantry",
			-- hold their rooms and react to what they can see or hear, so the squad clears room by room
			Wander = false, DetectionRange = 70, AwarenessRange = 90, HearingRange = 50,
			SquadTactics = false, Guerrilla = false,
		} do
			local v = settings:FindFirstChild(name)
			if v then v.Value = value end
		end
	end
	if setup then setup(soldier) end -- a boss's own kit, before his scripts start
	soldier:AddTag(SPAWN_TAG)
	soldier:AddTag(ENEMY_TAG)
	soldier:PivotTo(cf)
	soldier.Parent = workspace
	local hum = soldier:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Once(function()
			-- SPH's kill credit; Medical's kill feed reads the same
			local k = soldier:FindFirstChild("Killer")
			local s = k and k:IsA("ObjectValue") and stats[k.Value]
			if s then
				s.kills += 1
				-- GoreHit is already cleared by Gore.ApplyMarked when this deferred handler runs; KillHit keeps it
				if (soldier:GetAttribute("GoreHit") or soldier:GetAttribute("KillHit")) == "Head" then s.heads += 1 end
			end
		end)
	end
	return soldier
end

local function enemyCount(players)
	if floorN <= warnedUntil then return math.ceil((floorN + 1) * 1.5) end
	return floorN + 1
end

-- Spawns `count` soldiers at the given CFrames (cycled), at most MAX_ALIVE up at once.
-- boss (optional, from TowerBosses): its models count toward the clear, and TowerStatus BossName/BossLeft track them.
-- Returns when every one of them is out, or the run ended.
local wipeWave = false -- set by the Studio /wipe chat command below
local reinforcements = {} -- soldiers a boss called in mid-fight (ctx.reinforce); fightWave adds them to the clear

local function fightWave(id, spots, count, label, boss)
	local alive = if boss then table.clone(boss.models) else {}
	local left = count
	local spot = 0
	local alerted = floorN <= warnedUntil
	while running and runId == id do
		for i = #alive, 1, -1 do
			if isOut(alive[i]) then
				table.remove(alive, i)
				if not alerted then
					-- first man down: the whole floor now hears and hunts by sound
					alerted = true
					for _, s in alive do s:SetAttribute("Unalerted", false) end
				end
			end
		end
		while #reinforcements > 0 do table.insert(alive, table.remove(reinforcements)) end
		if wipeWave then wipeWave = false left = 0 end
		while left > 0 and #alive < MAX_ALIVE do
			spot = spot % #spots + 1
			local ok, soldier = pcall(spawnSoldier, spots[spot], alerted)
			if ok then table.insert(alive, soldier) end
			left -= 1
			task.wait(0.15)
		end
		setStatus(label, #alive + left)
		if boss then
			local up = 0
			for _, b in boss.models do if not isOut(b) then up += 1 end end
			status:SetAttribute("BossLeft", up)
		end
		if #alive == 0 and left == 0 then return true end
		task.wait(0.5)
	end
	return false
end

local function clearEnemies()
	for _, m in CollectionService:GetTagged(ENEMY_TAG) do
		m:Destroy()
	end
	-- player corpses (SPH RagdollMod) and blood decals (Gore) would otherwise carry into the next raid
	local bodies = workspace:FindFirstChild("SPH_Workspace") and workspace.SPH_Workspace:FindFirstChild("Bodies")
	if bodies then bodies:ClearAllChildren() end
	for _, c in workspace:GetChildren() do
		if c.Name == "BloodDecal" then c:Destroy() end
	end
end

local function reloadAll()
	for p in crew do
		if not p.Parent then continue end
		p:SetAttribute("InTowerRun", nil)
		task.spawn(function()
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum:UnequipTools() end
			task.wait(0.4) -- SPH needs the tool gone before the character is replaced
			p:LoadCharacter()
		end)
	end
end

local function endRun(banner)
	if not running then return end
	running = false
	runId += 1
	status:SetAttribute("FloorStart", nil)
	setStatus(banner, 0)
	local seconds = os.clock() - runStart
	if banner == "EXTRACTED" then
		task.delay(4.5, sendReports, true, seconds) -- the heli takes off now: show the score once it has flown off
	else
		task.delay(3, sendReports, false, seconds) -- the RAID FAILED header holds for a moment first
	end
	task.delay(6, function()
		clearEnemies()
		for n, m in floors do
			m:Destroy()
			floors[n] = nil
		end
		runFolder:ClearAllChildren()
		local wasHeld = held
		held = {}
		for p in wasHeld do
			p:SetAttribute("RespawnWaves", nil)
			-- squad members come back through reloadAll; anyone who switched team meanwhile is loaded here
			if p.Parent and not (crew[p] and p.Team and p.Team.Name == PLAYER_TEAM) then task.spawn(p.LoadCharacter, p) end -- late joiners aren't crew
		end
		reloadAll()
		crew = {}
		prompt.Enabled = false
		stagingVan.Parent = staging -- back at the curb for the next squad
		lastPick = nil
		buildFloor(1)
		task.wait(4)
		if not running then setStatus(nil, 0) end
	end)
end

local function spinRotor(heli, id)
	local rotor = heli:FindFirstChild("Rotor", true)
	local hub = heli:FindFirstChild("Union", true) -- the mast head the blades turn on
	local tail = heli:FindFirstChild("TailRotor", true) -- blades span the model's Y, so it turns about Z
	if not rotor or not hub then return end
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not heli.Parent then conn:Disconnect() return end
		local axis = CFrame.new(hub.Position) * (heli:GetPivot().Rotation)
		rotor.CFrame = axis * CFrame.Angles(0, dt * 25, 0) * axis:Inverse() * rotor.CFrame
		if tail then
			local ta = CFrame.new(tail.Position) * (heli:GetPivot().Rotation)
			tail.CFrame = ta * CFrame.Angles(0, 0, dt * 40) * ta:Inverse() * tail.CFrame
		end
	end)
end

-- riders: {[character] = offset from the heli pivot}, carried along with it
local function fly(heli, from, to, seconds, riders)
	local t = 0
	while t < seconds and heli.Parent do
		t += RunService.Heartbeat:Wait()
		local a = math.clamp(t / seconds, 0, 1)
		a = a * a * (3 - 2 * a)
		local cf = from:Lerp(to, a)
		heli:PivotTo(cf)
		for char, offset in riders or {} do
			if char.Parent then char:PivotTo(cf * offset) end
		end
	end
end

local function extraction(id)
	local roofY = tower:WaitForChild("RoofY").Value
	local pad = tower.Roof.Helipad.Position
	local land = CFrame.new(pad.X, roofY, pad.Z) * CFrame.Angles(0, math.rad(90), 0) -- nose (+X of the model) to the south
	-- squad comes out at Roof.Exit (south main level of the West-Hills roof); RoofY is the helipad surface
	local exit = tower.Roof.Exit.CFrame + Vector3.new(0, 3, 0)
	for i, p in squad() do
		if carried(p) then
			p:SetAttribute("OnRoof", true) -- WeatherClient brings the snowstorm back
			teleport(p, exit * CFrame.new((i - 1) * 3 - 6, 0, 0), true)
		end
	end
	-- a teleport can lose a race with the client's own movement and leave someone on the floor below; send them again
	task.delay(1.5, function()
		for i, p in squad() do
			if carried(p) and p.Character:GetPivot().Y < roofY - 20 then teleport(p, exit * CFrame.new((i - 1) * 3 - 6, 0, 0), true) end
		end
	end)
	for n in floors do
		retireFloor(n)
	end
	floorsCleared = totalFloors()
	floorN = totalFloors() + 1

	-- the Apache (TowerBosses) has to come down before the evac heli is sent; RPGs at Roof.RPGSpots, cover in Roof.Cover
	setStatus("ROOFTOP", nil)
	local rpgSpots = {}
	for _, s in tower.Roof.RPGSpots:GetChildren() do table.insert(rpgSpots, s.CFrame) end
	local live = function() return running and runId == id end
	local ok, boss = pcall(Bosses.Apache, { live = live, status = status, center = Vector3.new(0, roofY, 0), rpgSpots = rpgSpots })
	if ok then
		status:SetAttribute("BossTagline", boss.tagline)
		status:SetAttribute("BossName", boss.name)
		while live() and not boss.models[1]:GetAttribute("Down") do task.wait(0.5) end
	else
		warn("TowerRun: Apache failed to spawn: " .. tostring(boss))
	end
	for _, a in { "BossName", "BossTagline", "BossPhase", "BossLeft", "BossWarning", "BossObjective" } do status:SetAttribute(a, nil) end
	if not live() then return end
	setStatus("HELI INBOUND", nil)
	local heli = heliTemplate:Clone()
	for _, j in heli:GetDescendants() do
		if j:IsA("JointInstance") then j:Destroy() end -- all parts are anchored; joints would drag the rotors with the hull
	end
	heli.Parent = workspace
	spinRotor(heli, id)
	local start = land * CFrame.new(-400, 150, 0)
	heli:PivotTo(start)
	fly(heli, start, land * CFrame.new(0, 30, 0), 14)
	fly(heli, land * CFrame.new(0, 30, 0), land, 4)

	setStatus("EXTRACTION", nil)
	-- leave when every standing squad member is on the pad, or after 25 s
	local waited = 0
	while running and runId == id and waited < 25 do
		local ready, standing = 0, 0
		for _, p in squad() do
			if inRun(p) then
				standing += 1
				local r = p.Character.HumanoidRootPart.Position
				if Vector2.new(r.X - pad.X, r.Z - pad.Z).Magnitude < 22 and math.abs(r.Y - roofY) < 12 then
					ready += 1
				end
			end
		end
		if standing > 0 and ready == standing then break end
		waited += task.wait(0.5)
	end
	if not running or runId ~= id then heli:Destroy() return end
	-- everyone standing sits on the cabin bench (ExtractionHeli CabinSeat1..5) and rides out welded to it
	local seats = {}
	for _, s in heli:GetDescendants() do
		if s:IsA("Seat") then table.insert(seats, s) end
	end
	table.sort(seats, function(a, b) return a.Name < b.Name end)
	local riders = {}
	local n = 0
	for _, p in squad() do
		if inRun(p) then
			n += 1
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			hum.JumpPower, hum.JumpHeight = 0, 0 -- no hopping out mid-air; the respawn in endRun resets it
			local seat = seats[n]
			if seat then
				p.Character:PivotTo(seat.CFrame * CFrame.new(0, 2, 0))
				seat:Sit(hum)
			else
				-- more riders than seats: stand in the cabin, carried along
				p.Character.HumanoidRootPart.Anchored = true
				local at = land * CFrame.new(12.5, 6.2, (n % 4) * 2.5 - 3.75)
				riders[p.Character] = land:ToObjectSpace(at)
				p.Character:PivotTo(at)
			end
		end
	end
	endRun("EXTRACTED")
	task.spawn(function()
		fly(heli, land, land * CFrame.new(300, 200, 0), 10, riders)
		heli:Destroy()
	end)
end

-- The squad boards at the forest staging post and the van pulls off down the track (leg 1); the screen cuts
-- to black (the drive in, fast-forwarded), then the van comes up the plaza road at speed and brakes at the
-- doors (leg 2). The van faces -Z, so CFrame.new(0, 0, -d) is d studs forward. Clients run the camera.
local function drive(van, wheels, radius, from, run, seconds, ease, id, rolled)
	local t = 0
	while t < seconds and running and runId == id do
		t += RunService.Heartbeat:Wait()
		local d = run * ease(math.clamp(t / seconds, 0, 1))
		local cf = from * CFrame.new(0, 0, -d)
		van:PivotTo(cf)
		for w, offset in wheels do
			w.CFrame = cf * CFrame.new(offset.Position) * CFrame.Angles(-(rolled + d) / radius, 0, 0) * offset.Rotation
		end
	end
	return rolled + run
end

local function insertion(id)
	local van = vanTemplate:Clone()
	local start = stagingVan:GetPivot()
	local cityStart = INSERT_STOP * CFrame.new(0, 0, CITY_RUN)
	van:PivotTo(start)
	stagingVan.Parent = nil -- the parked one becomes the one that drives off
	van.Parent = workspace
	local seats = {}
	for i = 1, 5 do table.insert(seats, van.Body:FindFirstChild("Seat" .. i)) end
	for p in crew do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		p:SetAttribute("InTowerRun", true) -- counts as in the run, so the fail check waits for the ride
		p:SetAttribute("Riding", true) -- TowerMusic waits until they're in the tower; teleport clears it
		-- shortcut: 5 seats; a sixth player waits in the lobby and is teleported in with the rest
		local seat = table.remove(seats, 1)
		if seat then
			hum:UnequipTools() -- holster for the ride: SPH guns break if drawn/fired in a plain Seat under the cutscene camera
			char:PivotTo(seat.CFrame * CFrame.new(0, 2, 0))
			seat:Sit(hum)
		end
		insertCue:FireClient(p, { forest = FOREST_TIME, cut = CUT_TIME, city = CITY_TIME, start = start, stop = INSERT_STOP })
		-- the city is ~3000 studs away: have it streamed in before the cut lands there
		task.spawn(function() pcall(function() p:RequestStreamAroundAsync(INSERT_STOP.Position, 8) end) end)
	end
	-- wheels roll by distance travelled; they spin about the van's right (X) axis
	local wheels = {}
	for _, w in van.Wheels:GetChildren() do wheels[w] = start:ToObjectSpace(w.CFrame) end
	local radius = van.Wheels.FL.Size.Y / 2
	local rolled = drive(van, wheels, radius, start, FOREST_RUN, FOREST_TIME, function(a) return a * a end, id, 0) -- pulls away
	if not running or runId ~= id then van:Destroy() return end
	van:PivotTo(cityStart) -- riders are seated, so they come along
	task.wait(CUT_TIME)
	drive(van, wheels, radius, cityStart, CITY_RUN, CITY_TIME, function(a) return 1 - (1 - a) ^ 3 end, id, rolled) -- brakes into the stop
	task.wait(1.2) -- parked; clients fade to black
	for p in crew do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.Sit = false end
	end
	van:Destroy() -- takes the SeatWelds with it, so the teleport can move everyone
end

local function playFloor(id, n)
	cleared = false
	floorN = n
	local m = built(floors[n] or buildFloor(n))
	local spots = {}
	for _, d in m:GetDescendants() do
		if d.Name == "EnemySpawn" and d:IsA("BasePart") then
			table.insert(spots, CFrame.new(d.Position + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.rad(math.random(0, 3) * 90), 0))
		end
	end
	retireFloor(n - 1)
	local entry = part(m, "EntryPoint")
	if entry then
		local far = {}
		for _, cf in spots do
			if (cf.Position - entry.Position).Magnitude > SAFE_RADIUS then table.insert(far, cf) end
		end
		if #far > 0 then spots = far end
	end
	local label = "FLOOR " .. n .. "/" .. totalFloors()
	if n <= warnedUntil then label ..= "  ·  ON ALERT" end -- a Signals Officer warned this floor
	-- doors are held shut through GET READY: no breaching, opening or closing until the countdown ends
	local heldPrompts = {}
	for _, door in CollectionService:GetTagged("BreachDoor") do
		if door:IsDescendantOf(m) then
			for _, pr in door:GetDescendants() do
				if pr:IsA("ProximityPrompt") and pr.Enabled then
					pr.Enabled = false
					table.insert(heldPrompts, pr)
				end
			end
		end
	end
	for t = GET_READY, 1, -1 do
		if not running or runId ~= id then return end
		setStatus(label .. ": GET READY " .. t, nil)
		task.wait(1)
	end
	for _, pr in heldPrompts do pr.Enabled = true end
	local fightStart = os.clock()
	status:SetAttribute("FloorStart", workspace:GetServerTimeNow()) -- TowerHUD runs the floor clock from this
	reinforcements = {}
	local players = 0
	for _, p in squad() do if inRun(p) then players += 1 end end
	local count = enemyCount(players)
	local pool = diff().bossPool or {}
	local boss = nil
	if #spots > 0 and (forcedBoss or (#pool > 0 and table.find(diff().bossFloors or {}, n))) then
		-- boss floor: the boss holds the rooms farthest from the stairs, with half the usual guard
		local from = if entry then entry.Position else m:GetPivot().Position
		local sorted = table.clone(spots)
		table.sort(sorted, function(a, b) return (a.Position - from).Magnitude > (b.Position - from).Magnitude end)
		local pick = forcedBoss
		forcedBoss = nil
		if not pick then
			local fresh = {}
			for _, b in pool do if not bossesUsed[b] then table.insert(fresh, b) end end
			if #fresh == 0 then fresh = pool end -- more boss floors than bosses: repeats are unavoidable
			pick = fresh[math.random(#fresh)]
		end
		bossesUsed[pick] = true
		local ok, res = pcall(Bosses[pick], {
			spawn = function(cf, setup) return spawnSoldier(cf, false, setup) end,
			spots = sorted,
			entry = entry, -- EntryPoint part or nil (CBRN lays its gas mask on the desk nearest it)
			floor = m,
			live = function() return running and runId == id and floorN == n end,
			warnAhead = function(k) warnedUntil = math.max(warnedUntil, n + k) end, -- the next k floors start alerted, half as many again
			status = status, -- TowerStatus: bosses set BossWarning (BossFX shows it)
			reinforce = function(cf) -- a soldier the boss calls in mid-fight; he counts toward the clear
				local s = spawnSoldier(cf, true)
				table.insert(reinforcements, s)
				return s
			end,
		})
		if ok and res then
			boss = res
			count = math.ceil(count / 2)
			status:SetAttribute("BossTagline", boss.tagline) -- BossFX's intro card reads it when BossName lands
			status:SetAttribute("BossName", boss.name)
		else
			warn("TowerRun: boss failed to spawn: " .. tostring(res))
		end
	end
	local won = #spots == 0 or fightWave(id, spots, count, label, boss)
	status:SetAttribute("BossName", nil)
	status:SetAttribute("BossTagline", nil)
	status:SetAttribute("BossPhase", nil)
	status:SetAttribute("BossLeft", nil)
	status:SetAttribute("BossWarning", nil)
	status:SetAttribute("BossObjective", nil)
	status:SetAttribute("FloorStart", nil)
	if not won then return end
	if not running or runId ~= id then return end
	cleared = true
	floorsCleared = n
	local took = os.clock() - fightStart
	table.insert(splits, { n = n, t = took, boss = boss ~= nil or nil })	-- a cleared floor is a wave: count down the dead, and bring back whoever has sat out enough
	for p, left in held do
		if left <= 1 then
			held[p] = nil
			p:SetAttribute("RespawnWaves", nil)
			task.spawn(function()
				if not p.Parent then return end
				returning[p] = true
				crew[p] = true -- a late joiner's first time in
				p:LoadCharacter()
				local entry = running and runId == id and floors[floorN] and part(floors[floorN], "EntryPoint")
				if entry then teleport(p, CFrame.new(entry.Position + Vector3.new(0, 3, 0))) else p:SetAttribute("InTowerRun", nil) end -- run ended meanwhile: back in the lobby
			end)
		else
			held[p] = left - 1
			p:SetAttribute("RespawnWaves", left - 1)
		end
	end
	local door = part(m, "StairDoor")
	if door then
		door.CanCollide = false
		door.Transparency = 1
		for _, g in door:GetChildren() do if g:IsA("BillboardGui") then g.Enabled = false end end
	end
	setStatus("FLOOR " .. n .. " CLEAR: " .. fmtTime(took), 0)
	-- build the next floor now, while nobody is shooting, so the hitch is harmless
	if n < totalFloors() and not floors[n + 1] then buildFloor(n + 1) end
end

function goUp(id)
	if not running or runId ~= id or not cleared then return end
	cleared = false
	local n = floorN
	if n >= totalFloors() then
		task.spawn(extraction, id)
		return
	end
	local nextFloor = built(floors[n + 1] or buildFloor(n + 1))
	if not running or runId ~= id then return end
	local entry = part(nextFloor, "EntryPoint")
	for i, p in squad() do
		if carried(p) then teleport(p, CFrame.new(entry.Position + Vector3.new((i - 1) % 3 * 3 - 3, 3, -math.floor((i - 1) / 3) * 3)), true) end
	end
	task.spawn(playFloor, id, n + 1)
end


-- Floor 1 waits ready, so pressing Enter only teleports.
task.defer(function() if not floors[1] then buildFloor(1) end end)

-- Fail: nobody in the run is still standing for 4 s in a row.
task.spawn(function()
	local down = 0
	while true do
		task.wait(1)
		if running then
			local standing = 0
			for _, p in squad() do if inRun(p) then standing += 1 end end
			down = standing == 0 and down + 1 or 0
			if down >= 4 then endRun("RAID FAILED") down = 0 end
		end
	end
end)

-- members: the players to deploy (the staging zone's roster); the Studio test attribute sends every squad player
local function startRun(members)
	running = true
	runId += 1
	local id = runId
	crew = {}
	for _, p in members do
		crew[p] = true
		task.spawn(giveKit, p) -- the difficulty may have changed since they spawned
	end
	prompt.Enabled = true
	floorN = 1
	stats, floorsCleared, runStart, splits = {}, 0, os.clock(), {}
	warnedUntil = 0
	bossesUsed = {}
	setStatus("INSERTION: GARRISON TOWER", 0)
	insertion(id)
	if not running or runId ~= id then return end
	local m = built(floors[1] or buildFloor(1))
	if not running or runId ~= id then return end
	local entry = part(m, "EntryPoint")
	local i = 0
	for p in crew do
		i += 1
		teleport(p, CFrame.new(entry.Position + Vector3.new((i - 1) % 3 * 3 - 3, 3, -math.floor((i - 1) / 3) * 3)))
	end
	playFloor(id, 1)
end

-- The doors only let a late player join a raid in progress; raids start from the staging zone.
prompt.Enabled = false
prompt.Triggered:Connect(function(player)
	if not player.Team or player.Team.Name ~= PLAYER_TEAM then return end
	if running and floors[floorN] and not floors[floorN]:GetAttribute("Building") and not held[player] then
		crew[player] = true
		local entry = part(floors[floorN], "EntryPoint")
		teleport(player, CFrame.new(entry.Position + Vector3.new(0, 3, 0)))
	end
end)

-- Staging: Korblox players inside workspace.Staging.Zone are the next raid's squad (attribute Staged);
-- the ReadyPrompt on the briefing table toggles Ready. Once anyone is ready a STAGE_WAIT countdown runs, cut to
-- STAGE_ALL_READY once all of them are; TowerStatus.Deploy carries the seconds left for the Staging panel.
local deployAt = nil

local function inZone(p)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root or isOut(p.Character) then return false end
	local l = stageZone.CFrame:PointToObjectSpace(root.Position)
	local s = stageZone.Size / 2
	return math.abs(l.X) <= s.X and math.abs(l.Y) <= s.Y and math.abs(l.Z) <= s.Z
end

readyPrompt.Triggered:Connect(function(player)
	if running or not inZone(player) or not player.Team or player.Team.Name ~= PLAYER_TEAM then return end
	player:SetAttribute("Ready", not player:GetAttribute("Ready") or nil)
end)

difficultyPrompt.Triggered:Connect(function(player)
	if running or not inZone(player) or not player.Team or player.Team.Name ~= PLAYER_TEAM then return end
	local order = Difficulties.order
	difficulty = order[(table.find(order, difficulty) or 0) % #order + 1]
	status:SetAttribute("Difficulty", difficulty)
	applyFriendlyFire()
	for _, p in Players:GetPlayers() do p:SetAttribute("Ready", nil) end -- everyone re-readies for the new setting
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		local roster, ready = {}, 0
		for _, p in Players:GetPlayers() do
			local staged = not running and p.Team ~= nil and p.Team.Name == PLAYER_TEAM and inZone(p)
			p:SetAttribute("Staged", staged or nil)
			if not staged then p:SetAttribute("Ready", nil) continue end
			table.insert(roster, p)
			if p:GetAttribute("Ready") then ready += 1 end
		end
		if running or ready == 0 then
			deployAt = nil
		else
			local want = os.clock() + (if ready == #roster then STAGE_ALL_READY else STAGE_WAIT)
			deployAt = if deployAt then math.min(deployAt, want) else want
		end
		status:SetAttribute("Deploy", deployAt and math.max(0, math.ceil(deployAt - os.clock())) or nil)
		if deployAt and os.clock() >= deployAt then
			deployAt = nil
			status:SetAttribute("Deploy", nil)
			for _, p in roster do p:SetAttribute("Staged", nil) p:SetAttribute("Ready", nil) end
			task.spawn(startRun, roster)
		end
	end
end)

-- Studio testing: set this script's StartRun attribute to true to start without the prompt.
script:GetAttributeChangedSignal("StartRun"):Connect(function()
	if script:GetAttribute("StartRun") and not running then task.spawn(startRun, squad()) end
	script:SetAttribute("StartRun", nil)
end)

-- A new character starts in the staging compound (VanSpawn, by the command tent), outside the run, until Enter or a teleport puts it back in.
local function onDied(p, char)
	if held[p] then return end
	if running and p:GetAttribute("InTowerRun") then
		if stats[p] then stats[p].deaths += 1 end
		held[p] = diff().respawnWaves
		p:SetAttribute("RespawnWaves", held[p])
	else
		task.delay(Players.RespawnTime, function()
			if p.Parent and not held[p] and p.Character == char then p:LoadCharacter() end
		end)
	end
end

local function hookCharacter(p, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then hum.Died:Once(function() onDied(p, char) end) end
end

-- Kills every enemy (boss squad too) and skips the rest of the wave.
local function wipe()
	wipeWave = true
	for _, m in CollectionService:GetTagged(ENEMY_TAG) do
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = 0 end
	end
end

local ADMIN_PASSWORD = "korblox-7314"
-- matches a boss id case-insensitively and queues it; returns (id or nil, "A, B, C")
local function queueBoss(want)
	local names = {}
	for id in Bosses do
		if id == "Apache" then continue end -- the roof boss, not a floor boss
		table.insert(names, id)
		if want and id:lower() == want:lower() then
			forcedBoss = id
			return id, ""
		end
	end
	return nil, table.concat(names, ", ")
end
-- Admin console (StarterPlayerScripts.AdminConsole): "/admin <password>" in chat opens it (a TextChatCommand, so
-- the line never reaches chat and nobody sees the password). The client sends each typed line, the server runs it
-- and returns the text to print. Only players who opened it with the password can run commands.
local consoleAuthed, consoleFails = {}, {}
-- the console's autofill and hints read this list ("?spec"); args = what the command takes after its name
local CONSOLE_COMMANDS = {
	{ name = "help", args = "", desc = "list commands" },
	{ name = "wipe", args = "", desc = "kill every enemy, skip the rest of the wave" },
	{ name = "boss", args = "<name | clear>", desc = "next floor fights that boss (this floor during GET READY)" },
	{ name = "map", args = "<name | clear>", desc = "next floor built uses that map (no run: rebuilds floor 1 now)" },
	{ name = "status", args = "", desc = "run state, queued boss and map" },
	{ name = "close", args = "", desc = "hide the console (/admin <password> reopens it)" },
}
local helpLines = {}
for _, c in CONSOLE_COMMANDS do
	table.insert(helpLines, string.format("%-20s %s", c.name .. (if c.args ~= "" then " " .. c.args else ""), c.desc))
end
local CONSOLE_HELP = table.concat(helpLines, "\n")
local consoleRemote = Instance.new("RemoteFunction")
consoleRemote.Name = "AdminConsole"
consoleRemote.Parent = ReplicatedStorage
consoleRemote.OnServerInvoke = function(p, line)
	if type(line) ~= "string" or #line > 200 then return "bad input" end
	local cmd, arg = line:lower():match("^%s*(%S+)%s*(%S*)")
	if not cmd then return "" end
	if not consoleAuthed[p] then return "locked: open the console with /admin <password>" end
	if cmd == "?spec" then
		local bosses = {}
		for id in Bosses do if id ~= "Apache" then table.insert(bosses, id) end end
		table.sort(bosses)
		table.insert(bosses, "clear")
		local maps = {}
		for _, f in floorsFolder:GetChildren() do table.insert(maps, f.Name) end
		table.sort(maps)
		table.insert(maps, "clear")
		return { commands = CONSOLE_COMMANDS, args = { boss = bosses, map = maps } } -- args: command -> values it takes
	end
	if cmd == "help" then return CONSOLE_HELP end
	if cmd == "wipe" then
		wipe()
		print("TowerRun: console wipe by " .. p.Name)
		return "wave wiped"
	elseif cmd == "boss" then
		if arg == "clear" then forcedBoss = nil return "queued boss cleared" end
		local id, names = queueBoss(if arg ~= "" then arg else nil)
		if id then
			print("TowerRun: " .. p.Name .. " queued boss " .. id .. " for the next floor")
			return id .. " queued for the next floor"
		end
		return (if arg ~= "" then "no boss '" .. arg .. "'. " else "") .. "bosses: " .. names
	elseif cmd == "map" then
		if arg == "clear" then forcedMap = nil return "queued map cleared" end
		local names, found = {}, nil
		for _, f in floorsFolder:GetChildren() do
			table.insert(names, f.Name)
			if f.Name:lower() == arg then found = f.Name end
		end
		table.sort(names)
		if not found then
			return (if arg ~= "" then "no map '" .. arg .. "'. " else "") .. "maps: " .. table.concat(names, ", ")
		end
		forcedMap = found
		print("TowerRun: " .. p.Name .. " queued map " .. found)
		if not running then
			-- floor 1 is already waiting in the lobby: swap it now so the next run starts on this map
			local old = floors[1]
			floors[1] = nil
			task.spawn(function()
				if old then scrap(built(old)) end
				if not running and not floors[1] then buildFloor(1) end
			end)
			return "floor 1 rebuilding as " .. found
		end
		if floors[floorN + 1] then return found .. " queued: floor " .. (floorN + 1) .. " is already built, so it'll be floor " .. (floorN + 2) end
		return found .. " queued for the next floor"
	elseif cmd == "status" then
		return (if running then "run active, floor " .. floorN else "no run") .. "\nqueued boss: " .. (forcedBoss or "none")
			.. "\nqueued map: " .. (forcedMap or "none")
	end
	return "unknown command '" .. cmd .. "' (type help)"
end
local consoleOpen = Instance.new("RemoteEvent")
consoleOpen.Name = "AdminConsoleOpen" -- server -> client: show the console
consoleOpen.Parent = ReplicatedStorage
do
	local TextChatService = game:GetService("TextChatService")
	local folder = TextChatService:FindFirstChild("TextChatCommands") or Instance.new("Folder")
	folder.Name = "TextChatCommands"
	folder.Parent = TextChatService
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "AdminConsole"
	cmd.PrimaryAlias = "/admin"
	cmd.Parent = folder
	cmd.Triggered:Connect(function(source, text)
		local p = Players:GetPlayerByUserId(source.UserId)
		if not p then return end
		if (consoleFails[p] or 0) >= 5 then return end -- too many wrong passwords this session
		if text:match("^%S+%s+(%S+)%s*$") == ADMIN_PASSWORD then
			consoleAuthed[p] = true
			consoleOpen:FireClient(p)
		else
			consoleFails[p] = (consoleFails[p] or 0) + 1
			warn("TowerRun: wrong /admin password from " .. p.Name)
		end
	end)
end

local function watch(p)
	task.spawn(loadRecord, p)
	if RunService:IsStudio() then
		-- debug: "/wipe" with no password, Studio only
		p.Chatted:Connect(function(msg)
			if msg:lower() == "/wipe" then wipe() end
		end)
	end
	p.CharacterAdded:Connect(function(char)
		-- CharacterAdded can fire after the respawn's teleport has already set InTowerRun; don't wipe it then
		if returning[p] then returning[p] = nil else p:SetAttribute("InTowerRun", nil) end
		p:SetAttribute("OnRoof", nil)
		p:SetAttribute("Riding", nil)
		task.spawn(giveKit, p)
		hookCharacter(p, char)
	end)
	if p.Character then
		task.spawn(hookCharacter, p, p.Character)
	elseif running then
		-- joined mid-raid: no character yet; they spectate (StarterPlayerScripts.Spectate) and drop in after the next cleared floor
		held[p] = 1
		p:SetAttribute("RespawnWaves", 1)
	else
		task.spawn(p.LoadCharacter, p) -- first spawn, now that CharacterAutoLoads is off
	end
end
Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do watch(p) end

Players.PlayerRemoving:Connect(function(p)
	consoleAuthed[p], consoleFails[p] = nil, nil
	held[p] = nil
	returning[p] = nil
	bests[p] = nil
	task.defer(function()
		if running and #Players:GetPlayers() == 0 then endRun("RAID FAILED") end
	end)
end)

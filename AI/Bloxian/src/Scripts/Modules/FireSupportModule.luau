--[[
	Artillery, called in by radiomen.

	A radioman with an enemy far enough off calls a fire mission on him through
	the Random Arty package (ServerStorage.ArtilleryFireMission). Without that
	package installed he simply never calls one. It is always the artillery
	battery; an AC-130 fires its own barrages and is never called. The barrage
	stops once he is dead.

	Every Bloxian near the call zone then gets as far from it as he can and stays
	out until the last shell is down: inside the zone he runs straight out past
	its edge, close to it he holds where he is. He keeps shooting while he goes.
	The caller's side clears out during the warning; the side it is called on
	never heard the call, and only runs once the shells are seen coming in.
]]

local fireSupport = {}

local ServerStorage = game:GetService("ServerStorage")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local movement = require(modules.MovementModule)
local chatter = require(modules.ChatterModule)
local radioNet = require(modules.RadioModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart
local artilleryValue = marine.Settings:FindFirstChild("CallArtillery")
local teamValue = marine.Settings.Team

--Calling it in. The target must be at least MIN_CALL_DISTANCE from the
--radioman and at most MAX_CALL_DISTANCE. Squads near it clear out during the
--warning, but none is called while a friend is within DANGER_CLOSE of the target.
local MIN_CALL_DISTANCE = 70
local MAX_CALL_DISTANCE = 450
local DANGER_CLOSE = 30

--Seconds between one radioman's fire missions, how often he considers one, and
--the chance he calls it when he could.
local MISSION_COOLDOWN = 90
local CHECK_INTERVAL = 3
local CALL_CHANCE = 0.35

--Clearing the zone. Inside the impact radius plus EVAC_MARGIN a soldier runs
--out; within HOLD_BAND further he stays put rather than walk back in.
local EVAC_MARGIN = 40
local HOLD_BAND = 40

--Where he runs to is picked once per zone: straight out from its centre, else
--the next of these turns (degrees) off that whose spot is on dry ground, tried
--again in turn whenever there is no path to the one he has.
local ESCAPE_TURNS = {0, 35, -35, 70, -70, 110, -110}

--The side a mission is called on runs this many seconds before the first shell
--lands (when the shells are seen coming in).
local ENEMY_WARNING = 4

--The radio call, played from the radioman, how loud, and how far it carries.
local RADIO_CALL_SOUND = "rbxassetid://106856187646399"
local RADIO_CALL_VOLUME = 1
local RADIO_CALL_HEARING = 80

--Every live fire mission on the server, so every soldier can steer clear.
_G.BloxianArtilleryZones = _G.BloxianArtilleryZones or {}
local zones = _G.BloxianArtilleryZones

local function flat(vector)
	return Vector3.new(vector.X,0,vector.Z)
end

local function enabled()
	return not artilleryValue or artilleryValue.Value
end

local function missionTarget(maxDistance)
	local target = status:get("currentTarget")
	if not target or not target.Parent or not core.knows(target) then
		return nil
	end
	local dist = core.checkDist(myRoot,target)
	if dist < MIN_CALL_DISTANCE or dist > maxDistance then
		return nil
	end

	for _,entry in ipairs(radioNet.netMembers()) do
		if (entry.root.Position - target.Position).Magnitude < DANGER_CLOSE then
			return nil
		end
	end
	return target
end

local warnedMissing = false

local function callMission(target)
	local mission = ServerStorage:FindFirstChild("ArtilleryFireMission")
	if not mission then
		if not warnedMissing then
			warnedMissing = true
			warn("[Bloxian] a radioman tried to call artillery, but ServerStorage.ArtilleryFireMission is missing. Install or re-sync the current Random Arty package.")
		end
		return false
	end

	local center = target.Position
	local called,ok,info = pcall(mission.Invoke,mission,center,{caller = marine})
	if not called or not ok then
		local why = tostring(called and info or ok)
		log("artillery","fire mission refused: "..why,5)
		--Busy guns are normal; anything else means the package is not set up.
		if why ~= "the guns are already firing" and not _G.BloxianArtyRefusalWarned then
			_G.BloxianArtyRefusalWarned = true
			warn("[Bloxian] a radioman's fire mission was refused by Random Arty: "..why)
		end
		return false
	end

	local now = os.clock()
	zones[#zones+1] = {
		center = center,
		radius = info.radius,
		untilTime = now + info.duration,
		caller = myHuman,
		team = teamValue.Value,
		--An older Random Arty does not say; its shells take at least 5 s to fly.
		enemyRunsAt = now + (info.firstImpact or info.warning + 5) - ENEMY_WARNING,
	}

	local call = Instance.new("Sound")
	call.SoundId = RADIO_CALL_SOUND
	call.Volume = RADIO_CALL_VOLUME
	call.RollOffMaxDistance = RADIO_CALL_HEARING
	call.Parent = myRoot
	call:Play()
	call.Ended:Once(function() call:Destroy() end)
	log("artillery",string.format("fire mission called, %d stud radius, %ds",info.radius,math.floor(info.duration)))
	chatter.callout("fireMission")
	return true
end

--A Random Arty from before ArtilleryBlast still fires random barrages of its own,
--which no radioman called. Said once per server.
if ServerStorage:FindFirstChild("ArtilleryFireMission") and not _G.BloxianArtyChecked then
	_G.BloxianArtyChecked = true
	task.delay(5,function()
		if not ServerStorage:FindFirstChild("ArtilleryBlast") then
			warn("[Bloxian] Random Arty in this place is out of date: it fires its own random barrages and AC-130s cannot fire. Re-sync or reinstall the current Random Arty package.")
		end
	end)
end

--The radioman's own loop: looks for a chance to call one every CHECK_INTERVAL seconds.
if radioNet.role == "Radioman" then
	task.spawn(function()
		local nextMission = 0
		while myHuman.Parent and marine.Parent and myHuman.Health > 0 do
			task.wait(CHECK_INTERVAL)
			if enabled() and os.clock() >= nextMission then
				local target = missionTarget(MAX_CALL_DISTANCE)
				if target and math.random() < CALL_CHANCE and callMission(target) then
					nextMission = os.clock() + MISSION_COOLDOWN
				end
			end
		end
	end)
end

--The zone he is caught near, if any. Finished ones are dropped.
local function nearestZone()
	local now = os.clock()
	local found,foundDist = nil,math.huge
	for i = #zones,1,-1 do
		local zone = zones[i]
		if now >= zone.untilTime or (zone.caller and (zone.caller.Health <= 0 or not zone.caller.Parent)) then
			table.remove(zones,i)
		else
			local dist = flat(myRoot.Position - zone.center).Magnitude
			local knows = zone.team == teamValue.Value or now >= (zone.enemyRunsAt or 0)
			if knows and dist < zone.radius + EVAC_MARGIN + HOLD_BAND and dist < foundDist then
				found,foundDist = zone,dist
			end
		end
	end
	return found,foundDist
end

--Near a barrage he keeps every enemy he knew of in mind, where he last saw them,
--so he picks the fight back up once it lifts.
local function rememberEnemies()
	for _,root in ipairs(status:get("potentialTargets") or {}) do
		core.keepInMind(root)
	end
end

--A spot past the zone's edge on the ground, starting at ESCAPE_TURNS[from], and
--the index it was found at. nil when none of the turns from there lands on any.
local function escapePoint(zone,from)
	local away = flat(myRoot.Position - zone.center)
	if away.Magnitude < 1 then
		local angle = math.random()*math.pi*2
		away = Vector3.new(math.cos(angle),0,math.sin(angle))
	end
	away = away.Unit
	local reach = zone.radius + EVAC_MARGIN + HOLD_BAND*0.5
	for index = from,#ESCAPE_TURNS do
		local direction = CFrame.fromAxisAngle(Vector3.yAxis,math.rad(ESCAPE_TURNS[index])):VectorToWorldSpace(away)
		local spot = zone.center + direction*reach
		local hit,result = core.raycast(Vector3.new(spot.X,myRoot.Position.Y + 60,spot.Z),Vector3.new(0,-200,0))
		if hit and result.Material ~= Enum.Material.Water then
			return result.Position + Vector3.new(0,3,0),index
		end
	end
	return nil,#ESCAPE_TURNS
end

local escape = nil --{zone, point, turn}: where he is running to

--Runs out of any artillery impact zone. True while it is steering him.
function fireSupport.evacuate()
	local zone,dist = nearestZone()
	if not zone or dist >= zone.radius + EVAC_MARGIN then
		escape = nil
		status:set("evacuating",nil)
		if zone then
			rememberEnemies()
		end
		return false
	end
	rememberEnemies()
	status:set("evacuating",true)

	--One spot for the whole run, so his path is not thrown away every step;
	--a new one only when there is no way to it.
	if not escape or escape.zone ~= zone or movement.failed() then
		local from = escape and escape.zone == zone and escape.turn % #ESCAPE_TURNS + 1 or 1
		local point,turn = escapePoint(zone,from)
		if not point and from > 1 then
			point,turn = escapePoint(zone,1)
		end
		escape = {zone = zone,point = point,turn = turn}
		log("artillery","clearing the impact zone")
	end
	movement.navigate(escape.point or zone.center + flat(myRoot.Position - zone.center).Unit*(zone.radius + EVAC_MARGIN + HOLD_BAND*0.5))
	task.wait(0.2)
	return true
end

--Just outside a zone, stays put rather than walk back in. Runs after air cover,
--so aircraft still send him to cover. True while it holds him.
function fireSupport.holdOutside()
	if not nearestZone() then
		return false
	end
	log("artillery","holding outside the impact zone")
	movement.stop()
	task.wait(0.2)
	return true
end

return fireSupport

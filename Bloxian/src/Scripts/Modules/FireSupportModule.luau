--[[
	Artillery, called in by radiomen.

	A radioman with an enemy far enough off calls a fire mission on him through
	the Random Arty package (ServerStorage.ArtilleryFireMission). Without that
	package installed he simply never calls one.

	Every Bloxian near the call zone, on either team, then gets as far from it as
	he can and stays out until the last shell is down: inside the zone he runs
	straight out past its edge, close to it he holds where he is. He keeps
	shooting while he goes.
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

--Every live fire mission on the server, so every soldier can steer clear.
_G.BloxianArtilleryZones = _G.BloxianArtilleryZones or {}
local zones = _G.BloxianArtilleryZones

local function flat(vector)
	return Vector3.new(vector.X,0,vector.Z)
end

local function enabled()
	return not artilleryValue or artilleryValue.Value
end

local function missionTarget()
	local target = status:get("currentTarget")
	if not target or not target.Parent or not core.knows(target) then
		return nil
	end
	local dist = core.checkDist(myRoot,target)
	if dist < MIN_CALL_DISTANCE or dist > MAX_CALL_DISTANCE then
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
	local called,ok,info = pcall(mission.Invoke,mission,center)
	if not called or not ok then
		log("artillery","fire mission refused: "..tostring(called and info or ok),5)
		return false
	end

	zones[#zones+1] = {
		center = center,
		radius = info.radius,
		untilTime = os.clock() + info.duration,
	}
	log("artillery",string.format("fire mission called, %d stud radius, %ds",info.radius,math.floor(info.duration)))
	chatter.callout("fireMission")
	return true
end

--The radioman's own loop: looks for a chance to call one every CHECK_INTERVAL seconds.
if radioNet.role == "Radioman" then
	task.spawn(function()
		local nextMission = 0
		while myHuman.Parent and marine.Parent and myHuman.Health > 0 do
			task.wait(CHECK_INTERVAL)
			if enabled() and os.clock() >= nextMission then
				local target = missionTarget()
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
		if now >= zone.untilTime then
			table.remove(zones,i)
		else
			local dist = flat(myRoot.Position - zone.center).Magnitude
			if dist < zone.radius + EVAC_MARGIN + HOLD_BAND and dist < foundDist then
				found,foundDist = zone,dist
			end
		end
	end
	return found,foundDist
end

--Clears or stays out of any artillery zone. True while it is steering him.
function fireSupport.evacuate()
	local zone,dist = nearestZone()
	if not zone then
		return false
	end

	if dist < zone.radius + EVAC_MARGIN then
		--As far from it as he can get: straight out from the centre, past the edge.
		local away = flat(myRoot.Position - zone.center)
		if away.Magnitude < 1 then
			local angle = math.random()*math.pi*2
			away = Vector3.new(math.cos(angle),0,math.sin(angle))
		end
		local safe = zone.center + away.Unit*(zone.radius + EVAC_MARGIN + HOLD_BAND*0.5)
		log("artillery","clearing the impact zone")
		movement.navigate(Vector3.new(safe.X,myRoot.Position.Y,safe.Z))
	else
		log("artillery","holding outside the impact zone")
		movement.stop()
	end
	task.wait(0.2)
	return true
end

return fireSupport

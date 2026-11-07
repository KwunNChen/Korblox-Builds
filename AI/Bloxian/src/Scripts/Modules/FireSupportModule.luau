--[[
	Clearing artillery. Barrages are called from the spawner tool's Kinetic Events
	tab, which lists them in _G.BloxianArtilleryZones.

	Every Bloxian near a zone gets as far from it as he can and stays out until the
	last shell is down: inside the zone he runs straight out past its edge, close
	to it he holds where he is. He keeps shooting while he goes. Nobody runs until
	the shells are seen coming in.
]]

local fireSupport = {}

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local movement = require(modules.MovementModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart

--Clearing the zone. Inside the impact radius plus EVAC_MARGIN a soldier runs
--out; within HOLD_BAND further he stays put rather than walk back in.
local EVAC_MARGIN = 40
local HOLD_BAND = 40

--Where he runs to is picked once per zone: straight out from its centre, else
--the next of these turns (degrees) off that whose spot is on dry ground, tried
--again in turn whenever there is no path to the one he has.
local ESCAPE_TURNS = {0, 35, -35, 70, -70, 110, -110}

--Every live fire mission on the server, so every soldier can steer clear.
_G.BloxianArtilleryZones = _G.BloxianArtilleryZones or {}
local zones = _G.BloxianArtilleryZones

local function flat(vector)
	return Vector3.new(vector.X,0,vector.Z)
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
			if now >= zone.runsAt and dist < zone.radius + EVAC_MARGIN + HOLD_BAND and dist < foundDist then
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

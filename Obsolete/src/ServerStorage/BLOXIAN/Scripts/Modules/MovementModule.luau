local movement = {}

--Services
local pathfindingService = game:GetService("PathfindingService")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local troubleshoot = require(modules.Troubleshoot)
local log = troubleshoot.log

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart

--Studs between floor checks when scanning ahead. Smaller is safer on narrow
--ledges, bigger is cheaper.
local PROBE_SPACING = 3

--How far each movement option looks ahead, in studs.
local STRAFE_DISTANCE = 20
local RETREAT_DISTANCE = 5

local DOWN = Vector3.new(0,-7,0)

--How many times longer a stud of road counts on a route. Set it to 1 to walk roads freely.
local ROAD_COST = 3

--Pathfinding agent: how wide and tall the soldier is, and spacing between path points.
local AGENT = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	WaypointSpacing = 4,
	Costs = {Asphalt = ROAD_COST, Pavement = ROAD_COST},
}

--Working out a path is the most expensive thing a soldier does. The whole
--server shares this many per second; extra requests wait their turn.
local PATHS_PER_SECOND = 24

_G.BloxianPathBudget = _G.BloxianPathBudget or {tokens = PATHS_PER_SECOND, last = os.clock()}
local pathBudget = _G.BloxianPathBudget

--Waits for a turn, then works out a path from start (default: where he stands)
--to goal. False if it failed.
local function computePath(pathObject,goal,start)
	while true do
		local now = os.clock()
		pathBudget.tokens = math.min(PATHS_PER_SECOND,pathBudget.tokens + (now - pathBudget.last)*PATHS_PER_SECOND)
		pathBudget.last = now
		if pathBudget.tokens >= 1 then
			pathBudget.tokens -= 1
			break
		end
		task.wait(0.05)
	end
	return (pcall(pathObject.ComputeAsync,pathObject,start or myRoot.Position,goal))
end

--Least exposure: in a fight, a path over DETOUR_MIN studs long that has more
--than EXPOSED_SHARE of its points in his enemy's view is weighed against two
--routes bent DETOUR_OFFSET studs out to either side through its middle. The
--one with the fewest studs in view wins, each extra stud walked counting as
--DETOUR_LENGTH_COST of a stud in view. At most EXPOSURE_SAMPLES points of a
--route are checked.
local DETOUR_MIN = 40
--Fewer path turns than this left in the shared budget (a fight with many moving): the direct route.
local DETOUR_BUDGET = PATHS_PER_SECOND/4
local EXPOSED_SHARE = 0.4
local DETOUR_OFFSET = 30
local DETOUR_LENGTH_COST = 0.3
local EXPOSURE_SAMPLES = 16

local CHEST = Vector3.new(0,1.5,0)

local function pathLength(waypoints)
	local length = 0
	for i = 2,#waypoints do
		length += (waypoints[i].Position - waypoints[i-1].Position).Magnitude
	end
	return length
end

--Share of a route's points the target can see a man standing on.
local function exposedShare(waypoints,target)
	local eye = target.Position + CHEST
	local stride = math.max(1,math.ceil(#waypoints/EXPOSURE_SAMPLES))
	local seen,checked = 0,0
	for i = 1,#waypoints,stride do
		local from = waypoints[i].Position + CHEST
		local hit,result = core.raycast(from,eye - from)
		if not hit or result.Instance:IsDescendantOf(target.Parent) then
			seen += 1
		end
		checked += 1
	end
	return checked > 0 and seen/checked or 0
end

--Waypoints from start through the ground under via on to goal, or nil.
local function pathThrough(pathObject,start,via,goal)
	local hit,result = core.raycast(via + Vector3.new(0,30,0),Vector3.new(0,-60,0))
	if not hit then return nil end
	via = result.Position + Vector3.new(0,3,0)
	local first = computePath(pathObject,via,start) and pathObject.Status == Enum.PathStatus.Success
		and pathObject:GetWaypoints()
	local second = first and computePath(pathObject,goal,via) and pathObject.Status == Enum.PathStatus.Success
		and pathObject:GetWaypoints()
	if not second then return nil end
	for i = 2,#second do
		first[#first+1] = second[i]
	end
	return first
end

--The route to goal he is seen least on: waypoints itself, or one bent round
--to the side.
local function saferRoute(pathObject,waypoints,goal)
	local target = status:get("currentTarget")
	--Running from artillery, the shortest way out beats a covered one.
	if not target or not target.Parent or #waypoints < 2 or status:get("evacuating")
		or pathBudget.tokens < DETOUR_BUDGET then return waypoints end
	local length = pathLength(waypoints)
	local share = exposedShare(waypoints,target)
	if length < DETOUR_MIN or share <= EXPOSED_SHARE then return waypoints end

	local start = waypoints[1].Position
	local line = Vector3.new(goal.X - start.X,0,goal.Z - start.Z)
	if line.Magnitude < 1 then return waypoints end
	local side = line.Unit:Cross(Vector3.yAxis)

	local best,bestScore = waypoints,share*length
	for _,sign in ipairs({1,-1}) do
		local bent = pathThrough(pathObject,start,(start + goal)/2 + side*sign*DETOUR_OFFSET,goal)
		if bent then
			local bentLength = pathLength(bent)
			local score = exposedShare(bent,target)*bentLength + (bentLength - length)*DETOUR_LENGTH_COST
			if score < bestScore then
				best,bestScore = bent,score
			end
		end
	end
	if best ~= waypoints then
		log("nav",string.format("taking a covered route (%d%% of the direct one in view)",math.floor(share*100)))
	end
	return best
end

--A soldier that moves less than this many studs in STUCK_TIME is snagged: he
--jumps, and if that does not free him the path is worked out again. Snagged
--MAX_REPATHS times running, he goes another way: through a point SNAG_DETOUR
--studs to one side of the snag, then the other side, then he gives up.
local STUCK_DISTANCE = 0.5
local STUCK_TIME = 0.6
local MAX_REPATHS = 3
local SNAG_DETOUR = 15
local MAX_DETOURS = 2

--How close to a waypoint counts as reached. He is sent on to the next one from
--here, so he flows through a path instead of stopping on every point. Bigger
--cuts corners, and cut corners snag on walls.
local WAYPOINT_REACH = 2

--Seconds between keepGoing checks while walking, they can be raycasts.
local CHECK_INTERVAL = 0.25

--Seconds a trip to a point may take, and how close counts as arrived.
local GO_TO_TIMEOUT = 8
local ARRIVE_DISTANCE = 3

--A goal this close and in a clear straight line is walked to directly, no path.
local DIRECT_DISTANCE = 25

--The path is worked out again when the goal moves this far, or this many
--seconds after the last one. Until the new one is ready he keeps walking the old.
local REPATH_DISTANCE = 4
local REPATH_TIME = 4

--How far past the goal a passThrough walk aims, so he is still moving when it returns.
local OVERSHOOT = 4

local function flatDistanceTo(point)
	local offset = point - myRoot.Position
	return Vector3.new(offset.X,0,offset.Z).Magnitude
end

--Whether he can walk straight to a point: nothing in the way at knee height.
local function clearLine(goal)
	local from = myRoot.Position - Vector3.new(0,1.5,0)
	local offset = goal - myRoot.Position
	local flat = Vector3.new(offset.X,0,offset.Z)
	if flat.Magnitude < 0.5 then return true end
	return not core.raycast(from,flat)
end
movement.clearLine = clearLine

--[[
	The navigator walks him to the current goal on its own thread, so nothing
	else ever waits on a path. New paths are worked out in the background while
	he keeps walking the old one, then swapped in. Everything that moves the
	soldier goes through navigate(), walkTo() or stop().
]]
local navPath = pathfindingService:CreatePath(AGENT)
local nav = {
	goal = nil,
	retracing = false,
	passThrough = false,
	waypoints = nil,
	index = 2,
	pathGoal = nil,
	pathAt = -math.huge,
	computing = false,
	failed = false,
	failedAt = -math.huge,
	repaths = 0,
	via = nil,
	detours = 0,
	detourSign = 1,
	lastMoveTo = nil,
	lastMoveAt = 0,
	arrivedAim = nil,
}

--He drops a crumb every CRUMB_SPACING studs, keeping the last MAX_CRUMBS. With no
--path out of a building he walks them back the way he came. A ceiling within
--ROOF_REACH studs means indoors. A crumb further than CRUMB_GAP from the last
--means he was teleported or carried, and the trail starts over.
local CRUMB_SPACING = 4
local MAX_CRUMBS = 30
local CRUMB_GAP = 16
local ROOF_REACH = 16

local crumbs = {}
local lastOutside = nil

local function indoors(pos)
	return (core.raycast(pos,Vector3.new(0,ROOF_REACH,0)))
end
movement.indoors = indoors

local function dropCrumb()
	if nav.retracing or status:get("mounted") or myHuman.FloorMaterial == Enum.Material.Air then return end
	local pos = myRoot.Position
	local last = crumbs[#crumbs]
	local gap = last and (pos - last).Magnitude or math.huge
	if gap < CRUMB_SPACING then return end
	if gap > CRUMB_GAP then
		table.clear(crumbs)
	end
	crumbs[#crumbs+1] = pos
	if #crumbs > MAX_CRUMBS then
		table.remove(crumbs,1)
	end
	if not indoors(pos) then
		lastOutside = pos
	end
end

--Sets him walking his crumbs backward from the nearest one. False with no trail.
local function retrace()
	if #crumbs < 2 then return false end
	local nearest,nearestDist = #crumbs,math.huge
	for i = #crumbs,1,-1 do
		local dist = (crumbs[i] - myRoot.Position).Magnitude
		if dist < nearestDist then
			nearest,nearestDist = i,dist
		end
	end
	local trail = {}
	for i = nearest,1,-1 do
		trail[#trail+1] = {Position = crumbs[i], Action = Enum.PathWaypointAction.Walk}
	end
	log("nav","no way on, going back the way he came")
	nav.retracing = true
	nav.failed = false
	nav.waypoints = trail
	nav.index = 1
	nav.pathGoal = nav.goal
	return true
end

local function moveTo(point)
	--Only reissue when the point changes, or every second so MoveTo's own
	--8 second give-up never kicks in.
	if nav.lastMoveTo and (nav.lastMoveTo - point).Magnitude < 0.5 and os.clock() - nav.lastMoveAt < 1 then
		return
	end
	nav.lastMoveTo = point
	nav.lastMoveAt = os.clock()
	myHuman:MoveTo(point)
end

local function finalAim()
	local goal = nav.goal
	if not nav.passThrough then return goal end
	local offset = goal - myRoot.Position
	local flat = Vector3.new(offset.X,0,offset.Z)
	if flat.Magnitude < 0.5 then return goal end
	return goal + flat.Unit*OVERSHOOT
end

local function requestPath()
	if nav.computing then return end
	nav.computing = true
	local goal = nav.goal
	task.spawn(function()
		local waypoints
		if nav.via then
			waypoints = pathThrough(navPath,myRoot.Position,nav.via,goal)
		elseif computePath(navPath,goal) and navPath.Status == Enum.PathStatus.Success then
			waypoints = saferRoute(navPath,navPath:GetWaypoints(),goal)
		end
		nav.computing = false
		nav.pathAt = os.clock()
		if not nav.goal or (nav.goal - goal).Magnitude > REPATH_DISTANCE*3 then return end

		if waypoints then
			--He kept walking while the path was worked out, so its first points
			--may be behind him now. Start from the point after the nearest one,
			--or he turns round and steps back.
			local nearest,nearestDist = 1,math.huge
			for i = 1,math.min(#waypoints,8) do
				local dist = flatDistanceTo(waypoints[i].Position)
				if dist < nearestDist then
					nearest,nearestDist = i,dist
				end
			end
			nav.retracing = false
			nav.waypoints = waypoints
			nav.index = math.min(nearest + 1,#waypoints)
			nav.pathGoal = goal
			troubleshoot.visualizePath(nav.waypoints)
		elseif nav.retracing or (indoors(myRoot.Position) and retrace()) then
			--Still walking his trail out.
			return
		else
			--No way there: stand rather than keep walking into whatever is in the way.
			log("nav","no path to goal, stopping")
			nav.waypoints = nil
			nav.failed = true
			nav.failedAt = os.clock()
			moveTo(myRoot.Position)
		end
	end)
end

local lastPos,lastMoved = myRoot.Position,os.clock()
local nextLineCheck,lineClear,lineVotes = 0,false,0

local function navStep()
	local goal = nav.goal
	if not goal or nav.failed then return end

	local now = os.clock()
	local distance = flatDistanceTo(goal)

	--Arrived. The aim is fixed the moment he gets here: worked out afresh it
	--would swing round behind him once he passed the goal and walk him back.
	if distance < ARRIVE_DISTANCE then
		nav.arrivedAim = nav.arrivedAim or finalAim()
		moveTo(nav.arrivedAim)
		return
	end
	nav.arrivedAim = nil
	if nav.via and flatDistanceTo(nav.via) < WAYPOINT_REACH*2 then
		nav.via = nil
	end

	--Switching between walking straight and following a path takes two checks
	--in a row that agree, so a ray grazing an edge cannot make him zigzag.
	if now >= nextLineCheck then
		nextLineCheck = now + CHECK_INTERVAL
		local clear = distance <= DIRECT_DISTANCE and clearLine(goal)
		if clear == lineClear then
			lineVotes = 0
		else
			lineVotes += 1
			if lineVotes >= 2 or (clear == false and not nav.waypoints and not nav.computing) then
				lineClear = clear
				lineVotes = 0
			end
		end
		log("nav",lineClear and "walking straight" or (nav.waypoints and "following path" or "waiting for a path"))
	end

	if lineClear and not nav.via and not nav.retracing then
		nav.waypoints = nil
		moveTo(finalAim())
	else
		local stale = not nav.pathGoal or (goal - nav.pathGoal).Magnitude > REPATH_DISTANCE or now - nav.pathAt > REPATH_TIME
		if not nav.waypoints or stale then
			requestPath()
		end

		local waypoints = nav.waypoints
		if waypoints then
			--Skip every waypoint already within reach, so he never stops on one.
			while waypoints[nav.index] and flatDistanceTo(waypoints[nav.index].Position) < WAYPOINT_REACH do
				nav.index += 1
			end

			local waypoint = waypoints[nav.index]
			if waypoint then
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					myHuman.Jump = true
				end
				moveTo(waypoint.Position)
			elseif nav.retracing then
				nav.retracing = false
				nav.waypoints = nil
				nav.pathAt = -math.huge
				table.clear(crumbs)
			else
				moveTo(finalAim())
			end
		end
		--No path yet: keep walking whatever he was already walking to.
	end

	--Snagged: hop first, then throw the path away and work out a new one.
	if (myRoot.Position - lastPos).Magnitude > STUCK_DISTANCE then
		lastPos,lastMoved = myRoot.Position,now
		nav.repaths = 0
	elseif now - lastMoved > STUCK_TIME then
		log("nav","snagged, hopping")
		myHuman.Jump = true
		lastMoved = now
		nav.repaths += 1
		nav.pathAt = -math.huge
		if nav.repaths >= MAX_REPATHS then
			nav.repaths = 0
			nav.detours += 1
			if nav.detours > MAX_DETOURS then
				nav.via = nil
				if nav.retracing or not retrace() then
					log("nav","blocked every way round, stopping")
					nav.retracing = false
					nav.failed = true
					nav.failedAt = now
				end
			else
				--The other side from last time.
				nav.detourSign = nav.detours == 1 and (math.random(2) == 1 and 1 or -1) or -nav.detourSign
				local line = Vector3.new(goal.X - myRoot.Position.X,0,goal.Z - myRoot.Position.Z)
				local side = line.Magnitude > 0.5 and line.Unit:Cross(Vector3.yAxis) or myRoot.CFrame.RightVector
				nav.via = myRoot.Position + side*nav.detourSign*SNAG_DETOUR
				nav.waypoints = nil
				log("nav","blocked, trying another way round")
			end
		end
	end
end

--Seconds between checks that the server still simulates him. A nearby
--player's client can take over his physics when his welds change (drawing or
--slinging the rifle), and a client-simulated NPC stutters under server MoveTo.
local OWNERSHIP_CHECK = 1

local function keepServerOwnership()
	--Seated, his body is part of the vehicle, which sorts out its own physics.
	if status:get("mounted") or not myRoot:CanSetNetworkOwnership() then return end
	if myRoot:GetNetworkOwnershipAuto() or myRoot:GetNetworkOwner() ~= nil then
		log("nav","took physics back from a client")
		myRoot:SetNetworkOwner(nil)
	end
end

task.spawn(function()
	local nextOwnershipCheck = 0
	while myHuman.Parent and marine.Parent do
		if myHuman.Health <= 0 then break end
		dropCrumb()
		navStep()
		if os.clock() >= nextOwnershipCheck then
			nextOwnershipCheck = os.clock() + OWNERSHIP_CHECK
			keepServerOwnership()
		end
		task.wait(0.05)
	end
end)

--Sends him toward goal without waiting. Calling it again with a goal close to
--the current one carries on the same walk instead of starting over.
function movement.navigate(goal,passThrough)
	if myHuman.Health <= 0 then return end
	local previous = nav.goal
	nav.goal = goal
	nav.passThrough = passThrough == true

	--A failed goal gets another try a second later, the way may have opened up.
	if nav.failed and os.clock() - nav.failedAt > 1 then
		nav.failed = false
		nav.repaths = 0
		nav.pathAt = -math.huge
	end

	--Nudged goal (a moving target, a sliding formation slot): same walk.
	if previous and (previous - goal).Magnitude < REPATH_DISTANCE then
		return
	end
	nav.arrivedAim = nil
	nav.failed = false
	nav.repaths = 0
	nav.via = nil
	nav.detours = 0
	nextLineCheck = 0
	lastPos,lastMoved = myRoot.Position,os.clock()
end

--Indoors, heads for the last place he stood outside. False when he is out already.
function movement.getOut()
	if not lastOutside or not indoors(myRoot.Position) then return false end
	log("nav","nothing to do in here, heading outside")
	movement.navigate(lastOutside)
	return true
end

--Whether the current goal has no path to it (he is standing still).
function movement.failed()
	return nav.failed
end

--Walks straight at a point, no pathfinding. Cancels any navigation.
function movement.walkTo(point)
	nav.goal = nil
	nav.retracing = false
	nav.waypoints = nil
	nav.arrivedAim = nil
	nav.lastMoveTo = point
	nav.lastMoveAt = os.clock()
	myHuman:MoveTo(point)
end

--Stands still. Cancels any navigation.
function movement.stop()
	movement.walkTo(myRoot.Position)
end

local planPath = pathfindingService:CreatePath(AGENT)

--The waypoints of a path to goal, or nil when there is no way there.
function movement.findPath(goal)
	local computed = computePath(planPath,goal)
	if not computed or planPath.Status ~= Enum.PathStatus.Success then
		return nil
	end
	return planPath:GetWaypoints()
end

--[[
	Walks to a point and waits until he gets there. Gives back whether he did.
	keepGoing()  asked every CHECK_INTERVAL, false gives up waiting
	passThrough  he keeps walking past the goal instead of stopping on it, so
	             the caller can chain the next move without a halt
	When it gives up he is not stopped: the next move picks up from wherever
	he is, still walking.
]]
function movement.goToPosition(goal,keepGoing,timeout,passThrough)
	if myHuman.Health <= 0 then return false end
	movement.navigate(goal,passThrough)

	local deadline = os.clock() + (timeout or GO_TO_TIMEOUT)
	local nextCheck = 0
	while flatDistanceTo(goal) >= ARRIVE_DISTANCE do
		local now = os.clock()
		if nav.failed or now > deadline or myHuman.Health <= 0 or nav.goal ~= goal or status:get("scramble") then
			return false
		end
		if keepGoing and now >= nextCheck then
			nextCheck = now + CHECK_INTERVAL
			if not keepGoing() then return false end
		end
		task.wait(0.05)
	end
	return true
end

--Chases a target for up to a second at a time. The navigator re-paths as he
--moves, so the chase never pauses to think.
function movement.pathToLocation(target)
	if not target or not target.Parent or myHuman.Health <= 0 then return end

	local deadline = os.clock() + 1
	while os.clock() < deadline do
		if not target.Parent or status:get("currentTarget") ~= target or myHuman.Health <= 0 then
			return
		end
		movement.navigate(target.Position)

		local canSee = core.checkSight(target)
		if canSee and core.checkDist(myRoot,target) < 30 then
			return
		elseif canSee and target.Position.Y <= myRoot.Position.Y - 5 then
			movement.stop()
			return
		end
		task.wait(0.1)
	end
end

--A random spot from 30% of radius out to radius from center, on open ground he
--can walk to; nil if a few tries find none.
function movement.patrolPoint(center,radius)
	for _ = 1,6 do
		local angle = math.random()*math.pi*2
		local reach = radius*(0.3 + 0.7*math.random())
		local hit,result = core.raycast(center + Vector3.new(math.cos(angle)*reach,60,math.sin(angle)*reach),Vector3.new(0,-120,0))
		if hit and result.Normal.Y > 0.7 and result.Material ~= Enum.Material.Water and not core.getHuman(result.Instance.Parent) then
			local spot = result.Position + Vector3.new(0,3,0)
			if movement.findPath(spot) then
				return spot
			end
		end
	end
	return nil
end

local function flatDirection(vector)
	local flat = Vector3.new(vector.X,0,vector.Z)
	if flat.Magnitude < 0.001 then
		return nil
	end
	return flat.Unit
end

local function walkableDistance(origin, dir, length)
	local hit,result = core.raycast(origin,dir*length)
	local reach = hit and math.max(result.Distance - 1,0) or length

	local walked = 0
	while walked < reach do
		local nextStep = math.min(walked + PROBE_SPACING,reach)
		if not core.raycast(origin + dir*nextStep,DOWN) then
			break
		end
		walked = nextStep
	end
	return walked
end

--When strafing make sure you can see target from end pos
function movement.strafe()
	local origin = myRoot.Position
	local target = status:get("currentTarget")
	if not target then return origin end

	local side = myRoot.CFrame.RightVector
	if math.random(2) == 2 then
		side = -side
	end

	local dir = flatDirection(side)
	if not dir then return origin end

	local goal = origin + dir*walkableDistance(origin,dir,STRAFE_DISTANCE)

	local toTarget = target.Position - goal
	if toTarget.Magnitude < 0.001 then return goal end

	local hit,result = core.raycast(goal,toTarget.Unit*(toTarget.Magnitude + 3))
	if hit and not result.Instance:IsDescendantOf(target.Parent) then
		return origin
	end
	return goal
end

local function checkDirection(dir)
	local origin = myRoot.Position
	if not dir then return false,origin end

	local walked = walkableDistance(origin,dir,RETREAT_DISTANCE)
	return walked >= RETREAT_DISTANCE,origin + dir*walked
end

function movement.retreat()
	local target = status:get("currentTarget")
	if not target then return myRoot.Position end

	--Check if we can retreat directly from the enemy.
	local result,pos = checkDirection(flatDirection(myRoot.Position - target.Position))
	if result then
		return pos
	end

	--Check if we can move away to the right.
	result,pos = checkDirection(flatDirection(myRoot.CFrame.RightVector))
	if result then
		return pos
	end

	--Check if can move away to the left.
	result,pos = checkDirection(flatDirection(-myRoot.CFrame.RightVector))
	if result then
		return pos
	end

	return myRoot.Position
end

return movement

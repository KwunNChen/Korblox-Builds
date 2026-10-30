--[[
	Small unit tactics, after the US Army / Ranger battle drills.

	Soldiers of the same team within SQUAD_RANGE of each other form a squad.
	The highest ranked one leads. Everyone is split into two fire teams,
	Alpha and Bravo, alternating down the rank order.

	No contact: followers hold a wedge on the leader.
	Contact:
		React     every soldier gets into the nearest cover and returns fire
		          (Battle Drill 1), then the leader picks one of:
		Bound     bounding overwatch toward the enemy. One team rushes to the
		          next cover while the other suppresses, then they swap.
		Flank     Alpha is the base of fire, Bravo bounds round to the side
		          and assaults. Alpha shifts fire as Bravo closes in.
		Break     outnumbered or badly hurt: the teams bound backwards,
		          covering each other, then rally on the leader.
		Fight     already close: everyone fights on their own.
]]

local squad = {}

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local movement = require(modules.MovementModule)
local tactics = require(modules.TacticsModule)
local chatter = require(modules.ChatterModule)
local radioNet = require(modules.RadioModule)
local specialTeam = require(modules.SpecialTeamModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart

local mySettings = marine.Settings
local teamValue = mySettings.Team
local squadValue = mySettings:FindFirstChild("SquadTactics")

--Allies closer than this join up into one squad. Once in, a soldier stays in
--his squad until he is further than SQUAD_BREAK_RANGE from the rest of it.
local SQUAD_RANGE = 60
local SQUAD_BREAK_RANGE = 150

--How far from the middle of the squad a soldier may get before he heads back.
--Rushes and the flanking team are allowed out past it.
local LEASH = 30

--In a fight the leash is looser, so the squad can close in on the enemy together.
local COMBAT_LEASH = 60

--How far round himself a soldier looks for a spot with a clear shot.
local FIRING_RINGS = {6, 12, 18}

--Wedge spacing between soldiers, and how far out of place before a follower moves.
local FORMATION_SPACING = 8
local FORMATION_SLACK = 4

--Squad column: the gap between Alpha's wedge and Bravo's wedge behind it.
local COLUMN_GAP = 10

--File: walls closer than NARROW_WIDTH on both sides of the leader put the squad
--in single file, FILE_SPACING apart.
local NARROW_WIDTH = 7
local FILE_SPACING = 6

--Security halt: the leader standing still this many seconds puts the squad in a
--circle round him, HALT_RADIUS out, covering every direction.
local HALT_TIME = 3
local HALT_RADIUS = 7

--Seconds everyone spends getting into cover before the leader picks a plan.
local REACT_TIME = 1.5

--Length of one rush, walk speed during it, and the most time it may take.
local BOUND_DISTANCE = 22
local RUSH_SPEED = 20
local RUSH_TIMEOUT = 5

--Seconds the leader waits for a team to finish its rush before swapping anyway,
--and the least a turn lasts even when everyone is done.
local TURN_TIMEOUT = 6
local MIN_TURN_TIME = 2

--A rush has to carry him at least this far, or it is not worth leaving cover for.
local MIN_RUSH = 5

--Inside this distance the squad stops bounding and just fights.
local ASSAULT_DISTANCE = 30

--Most bounds in an advance before the squad just fights.
local MAX_BOUNDS = 6

--Where the flanking team heads: this far to the side of the enemy. Close enough
--to the flank point counts as arrived, and the flank gives up after FLANK_TIMEOUT.
local FLANK_OFFSET = 30
local FLANK_ARRIVE = 12
local FLANK_TIMEOUT = 45

--The base of fire stops shooting once the assault team is this close to the enemy.
local SHIFT_FIRE_DISTANCE = 15

--Break contact when the squad's average health falls below this, or the enemy
--outnumbers it by this many.
local BREAK_HEALTH = 0.4
local BREAK_ODDS = 2

--Bounds back before rallying, and seconds the rally holds.
local BREAK_BOUNDS = 4
local RALLY_TIME = 15

local radio = _G.BloxianRadio
local myEntry = radio[marine]
myEntry.rank = math.random()
myEntry.squadId = myEntry.rank
myEntry.healthFraction = function()
	return myHuman.Health/myHuman.MaxHealth
end

local plan = nil

--The plan and turn of this soldier's last rush, so he rushes once per turn.
local lastBoundPlan = nil
local lastBoundTurn = nil

local function setPlan(newPlan)
	log("squadPlan","leader plan: "..(newPlan and newPlan.kind or "none"))
	plan = newPlan
	myEntry.plan = newPlan
end

local function flat(vector)
	return Vector3.new(vector.X,0,vector.Z)
end

--This soldier and his squad, highest rank first. The first one leads. A squad
--is everyone who joined up within SQUAD_RANGE, and it holds together out to
--SQUAD_BREAK_RANGE, so a soldier who gets separated rejoins instead of going it alone.
local function members()
	local list = {myEntry}
	local team = teamValue.Value
	for other,entry in pairs(radio) do
		local mounted = entry.isMounted and entry.isMounted()
		if other ~= marine and entry.root.Parent and entry.human.Health > 0 and entry.team.Value == team and not mounted
			and not specialTeam.detached(other) then
			local dist = (entry.root.Position - myRoot.Position).Magnitude
			if dist <= SQUAD_RANGE or (entry.squadId == myEntry.squadId and dist <= SQUAD_BREAK_RANGE) then
				list[#list+1] = entry
			end
		end
	end
	table.sort(list,function(a,b) return (a.rank or 0) > (b.rank or 0) end)

	--Everyone carries the leader's id, which is what keeps the squad together.
	myEntry.squadId = list[1].rank
	return list
end

local function centerOf(list)
	local sum = Vector3.zero
	for _,entry in ipairs(list) do
		sum += entry.root.Position
	end
	return sum/#list
end

--Heads back toward the middle of the squad when he has strayed past the leash.
local function regroup(center,inCombat)
	local leash = inCombat and COMBAT_LEASH or LEASH
	if flat(center - myRoot.Position).Magnitude <= leash then
		return false
	end
	log("squadRole","strayed from the squad, regrouping")
	movement.goToPosition(center,function()
		return myHuman.Health > 0 and flat(center - myRoot.Position).Magnitude > leash*0.6
	end,3,true)
	return true
end

--Alone means no squadmates and no radio net: on a net he is part of the platoon.
function squad.isAlone()
	return #members() == 1 and not radioNet.inNet()
end

local function teamOf(index)
	return index % 2 == 1 and "A" or "B"
end

local function holdStill()
	movement.stop()
end

local function averageHealth(list)
	local total = 0
	for _,entry in ipairs(list) do
		total += entry.healthFraction and entry.healthFraction() or 1
	end
	return total/#list
end

local function startPlan(kind,target,extra)
	local now = os.clock()
	local newPlan = {
		kind = kind,
		target = target,
		started = now,
		moving = "B",
		turn = 1,
		turnStart = now,
		done = {},
		bounds = 0,
	}
	for key,value in pairs(extra or {}) do
		newPlan[key] = value
	end
	setPlan(newPlan)
end

local function startRally()
	setPlan({kind = "rally", untilTime = os.clock() + RALLY_TIME})
	chatter.callout("rally")
end

--A spot on the enemy's side, square to the line between the squad and him.
local function findFlankPoint(target)
	local line = flat(target.Position - myRoot.Position)
	if line.Magnitude < 1 then return nil end
	line = line.Unit

	local side = line:Cross(Vector3.yAxis)
	local options = {}
	for _,sign in ipairs({1,-1}) do
		local point = tactics.ground(target.Position + side*sign*FLANK_OFFSET - line*8)
		if point then
			options[#options+1] = {point = point, sign = sign, hidden = tactics.isHidden(point,target)}
		end
	end
	if #options == 0 then return nil end

	--Prefer a side the enemy cannot see.
	table.sort(options,function(a,b)
		if a.hidden ~= b.hidden then return a.hidden end
		return math.random() < 0.5
	end)
	return options[1].point,options[1].sign
end

local function choosePlan(target,list)
	local size = #list
	local enemies = math.max(#status:get("potentialTargets"),1)
	local dist = core.checkDist(myRoot,target)

	if averageHealth(list) < BREAK_HEALTH or enemies >= size + BREAK_ODDS then
		startPlan("break",target)
		chatter.callout("orderBreak")
		return
	end

	if size >= 3 and enemies <= size and dist > ASSAULT_DISTANCE*0.6 then
		local flankPoint,sign = findFlankPoint(target)
		if flankPoint then
			startPlan("flank",target,{flankPoint = flankPoint, phase = "move"})
			chatter.callout("orderFlank",{side = sign > 0 and "right" or "left"})
			return
		end
	end

	if dist > ASSAULT_DISTANCE then
		startPlan("bound",target)
		chatter.callout("orderBound")
	else
		startPlan("fight",target)
	end
end

local function teamFinished(list)
	for index,entry in ipairs(list) do
		if teamOf(index) == plan.moving and not plan.done[entry] then
			return false
		end
	end
	return true
end

local function hasTeam(list,team)
	for index in ipairs(list) do
		if teamOf(index) == team then return true end
	end
	return false
end

--The leader keeps the plan moving: swaps the bounding team, ends phases.
local function leaderThink(target,list)
	local now = os.clock()

	if plan and plan.kind == "rally" then
		if now < plan.untilTime then return end
		setPlan(nil)
	end

	if not target then
		if plan and plan.kind == "break" then
			startRally()
		elseif plan then
			setPlan(nil)
		end
		return
	end

	--New contact: Battle Drill 1.
	if not plan then
		startPlan("react",target)
		return
	end
	plan.target = target

	if plan.kind == "react" then
		if now - plan.started >= REACT_TIME then
			choosePlan(target,list)
		end
		return
	end

	if plan.kind == "fight" then return end

	if plan.kind == "flank" and not hasTeam(list,"B") then
		startPlan("fight",target)
		return
	end

	if plan.kind == "flank" and plan.phase == "move" then
		local arrived = true
		for index,entry in ipairs(list) do
			if teamOf(index) == "B" and (flat(entry.root.Position - plan.flankPoint)).Magnitude > FLANK_ARRIVE then
				arrived = false
			end
		end
		if arrived or now - plan.started > FLANK_TIMEOUT then
			plan.phase = "assault"
			chatter.callout("orderAssault")
		end
	elseif plan.kind == "flank" and plan.phase == "assault" and not plan.shiftFire then
		for index,entry in ipairs(list) do
			if teamOf(index) == "B" and (entry.root.Position - target.Position).Magnitude < SHIFT_FIRE_DISTANCE then
				plan.shiftFire = true
				chatter.callout("shiftFire")
				break
			end
		end
	end

	if plan.kind ~= "flank" or plan.phase == "move" then
		local turnAge = now - plan.turnStart
		if turnAge > TURN_TIMEOUT or (turnAge > MIN_TURN_TIME and teamFinished(list)) then
			plan.bounds += 1
			plan.turn += 1
			plan.turnStart = now
			plan.done = {}
			if plan.kind ~= "flank" then
				plan.moving = plan.moving == "A" and "B" or "A"
			end
		end
	end

	if plan.kind == "bound" and (core.checkDist(myRoot,target) <= ASSAULT_DISTANCE or plan.bounds >= MAX_BOUNDS) then
		startPlan("fight",target)
	elseif plan.kind == "break" and plan.bounds >= BREAK_BOUNDS then
		startRally()
	end
end

--Where this soldier's next rush ends.
local function boundGoal(currentPlan,target)
	local myPos = myRoot.Position

	if currentPlan.kind == "break" then
		local away = flat(myPos - target.Position)
		if away.Magnitude < 1 then return nil end
		return myPos + away.Unit*BOUND_DISTANCE
	end

	local toward = currentPlan.kind == "flank" and currentPlan.flankPoint or target.Position
	local offset = flat(toward - myPos)
	local stopShort = currentPlan.kind == "bound" and ASSAULT_DISTANCE*0.8 or 0
	local step = math.min(BOUND_DISTANCE,offset.Magnitude - stopShort)
	if step <= 2 then return nil end
	return myPos + offset.Unit*step
end

--One 3-5 second rush, cover to cover. Gives back whether he actually moved.
local function bound(goal,target)
	--A rush is meant to leave the squad's current spot, so it is not held to it.
	tactics.setAnchor(nil)

	--Cover near the goal, but only one that gets him somewhere: the nearest
	--cover to the goal can be the spot he is already in.
	local myPos = myRoot.Position
	local spot
	for _,candidate in ipairs(tactics.findCoverNear(goal,target)) do
		if flat(candidate.pos - myPos).Magnitude >= MIN_RUSH then
			spot = candidate
			break
		end
	end
	local destination = spot and spot.pos or tactics.ground(goal)
	if not destination or flat(destination - myPos).Magnitude < MIN_RUSH then
		return false
	end

	tactics.release()

	chatter.callout("rush",nil,0.5)
	myHuman.WalkSpeed = RUSH_SPEED
	movement.goToPosition(destination,function() return myHuman.Health > 0 end,RUSH_TIMEOUT)
	myHuman.WalkSpeed = status:get("weaponAimed") and 10 or 16

	if spot then
		tactics.occupy(spot,{suppress = true})
	end
	chatter.callout("set",nil,0.4)
	return true
end

local SUPPRESS = {force = true, suppress = true, hold = true}

--The nearest spot he can walk straight to with a clear shot at the target.
local function firingPosition(target)
	local myPos = myRoot.Position
	local best,bestDist = nil,math.huge
	for _,ring in ipairs(FIRING_RINGS) do
		for i = 1,12 do
			local angle = i/12*math.pi*2
			local pos = tactics.floor(myPos + Vector3.new(math.cos(angle)*ring,0,math.sin(angle)*ring))
			if pos and ring < bestDist and not tactics.isHidden(pos,target) and movement.clearLine(pos) and tactics.roomAt(pos) then
				best,bestDist = pos,ring
			end
		end
		if best then break end
	end
	return best
end

--Get a shot on the target: stand and fire if he has one, else step to a spot
--that has one, else push toward the enemy.
local function engage(target)
	if core.checkSight(target) then
		holdStill()
		return true
	end

	local spot = firingPosition(target)
	if spot then
		log("squadRole","moving to a firing position",2)
		movement.goToPosition(spot,function()
			return myHuman.Health > 0 and not core.checkSight(target)
		end,4)
	else
		log("squadRole","no firing position, pushing toward the enemy",2)
		movement.pathToLocation(target)
	end
	return true
end

--Base of fire: cover with a firing spot and keep shooting. With no such cover,
--get a shot from wherever he can.
local function overwatch(target)
	if tactics.update(SUPPRESS) then
		return true
	end
	return engage(target)
end

--The leader's position facing the way he is walking (or looking, when still).
local function leaderFrame(leaderEntry)
	local root = leaderEntry.root
	local velocity = flat(root.AssemblyLinearVelocity)
	local forward = velocity.Magnitude > 2 and velocity or flat(root.CFrame.LookVector)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0,0,-1)
	end
	return CFrame.lookAt(root.Position,root.Position + forward.Unit),velocity.Magnitude
end

--Slot k of a wedge, 0 being the point. In the leader's frame +Z is behind him.
local function wedgeOffset(k)
	if k == 0 then return Vector3.zero end
	local row = math.ceil(k/2)
	local side = k % 2 == 1 and -1 or 1
	return Vector3.new(side*FORMATION_SPACING*row,0,FORMATION_SPACING*row)
end

local function narrowAt(frame)
	local right = frame.RightVector
	local pos = frame.Position
	return core.raycast(pos + right*1.5,right*NARROW_WIDTH) and core.raycast(pos - right*1.5,-right*NARROW_WIDTH)
end

local leaderStillSince = nil

--Where this soldier belongs, and the formation's name.
local function formationSlot(list,myIndex,leaderEntry,halt)
	local frame,speed = leaderFrame(leaderEntry)
	local count = #list

	if speed < 1 then
		leaderStillSince = leaderStillSince or os.clock()
	else
		leaderStillSince = nil
	end

	if halt or (leaderStillSince and os.clock() - leaderStillSince > HALT_TIME) then
		local angle = (myIndex - 1)/(count - 1)*math.pi*2
		return frame.Position + Vector3.new(math.cos(angle),0,math.sin(angle))*HALT_RADIUS,"security halt"
	end

	if narrowAt(frame) then
		return frame:PointToWorldSpace(Vector3.new(0,0,FILE_SPACING*(myIndex - 1))),"file"
	end

	--Three or fewer is one fire team: a single wedge on the leader.
	if count <= 3 then
		return frame:PointToWorldSpace(wedgeOffset(myIndex - 1)),"fire team wedge"
	end

	--Squad column: Alpha's wedge leads with the squad leader at its point,
	--Bravo's wedge follows behind it.
	local offset = wedgeOffset(math.floor((myIndex - 1)/2))
	if teamOf(myIndex) == "B" then
		local alphaRows = math.ceil((math.ceil(count/2) - 1)/2)
		offset += Vector3.new(0,0,COLUMN_GAP + FORMATION_SPACING*alphaRows)
	end
	return frame:PointToWorldSpace(offset),"column of wedges"
end

--halt: form the security circle now (rally), and keep moving even with an enemy around.
local function followFormation(list,myIndex,leaderEntry,halt)
	if leaderEntry == myEntry then
		return false
	end

	local slot,shape = formationSlot(list,myIndex,leaderEntry,halt)
	log("formation",shape)

	--A slot inside a wall: try halfway in toward the leader, then the leader himself.
	local leaderPos = leaderEntry.root.Position
	slot = tactics.ground(slot) or tactics.ground(leaderPos + (slot - leaderPos)*0.5) or leaderPos

	--The navigator walks there on its own thread, straight when the way is clear
	--and pathing round otherwise. While the leader walks the slot is fed in every
	--update and he walks through it, so he keeps pace instead of stopping and starting.
	local leaderMoving = leaderEntry.root.AssemblyLinearVelocity.Magnitude > 2
	if leaderMoving or flat(slot - myRoot.Position).Magnitude > FORMATION_SLACK then
		movement.navigate(slot,leaderMoving)
	end
	task.wait(0.15)
	return true
end

--A squad leader on a radio net walks his squad's slot in the platoon; his men
--follow him in their own formation. False when his squad leads, or there is no net.
local function followPlatoon()
	local slot,leadMoving = radioNet.platoonSlot(myEntry)
	if not slot then
		return false
	end
	log("formation","platoon: holding my squad's slot")

	slot = tactics.ground(slot) or slot
	if leadMoving or flat(slot - myRoot.Position).Magnitude > FORMATION_SLACK then
		movement.navigate(slot,leadMoving)
	end
	task.wait(0.15)
	return true
end

local function act(currentPlan,myIndex,list,target,leaderEntry)
	local myTeam = teamOf(myIndex)
	local kind = currentPlan.kind
	if require(modules.Troubleshoot).printing() then
		log("squadRole",string.format("%s, team %s, %d in squad",kind,myTeam,#list))
	end

	if kind == "rally" then
		status:set("squadHoldFire",true)
		if leaderEntry == myEntry then
			holdStill()
			return true
		end
		return followFormation(list,myIndex,leaderEntry,true)
	end

	if not target then return false end

	if kind == "fight" then
		return false
	end

	--Battle Drill 1: into cover and return fire, or straight to a firing spot.
	if kind == "react" then
		return overwatch(target)
	end

	if kind == "flank" and currentPlan.phase == "assault" then
		if myTeam == "B" then
			--The assault team fights its way in, off the leash.
			tactics.release()
			return false,true
		end
		status:set("squadHoldFire",currentPlan.shiftFire == true)
		return overwatch(target)
	end

	if currentPlan.moving == myTeam and (lastBoundPlan ~= currentPlan or lastBoundTurn ~= currentPlan.turn) then
		lastBoundPlan = currentPlan
		lastBoundTurn = currentPlan.turn
		local goal = boundGoal(currentPlan,target)
		if goal then
			bound(goal,target)
		end
		currentPlan.done[myEntry] = true
		return true
	end

	return overwatch(target)
end

--Runs the squad for this tick. True when the squad is steering this soldier.
function squad.update()
	if specialTeam.detached(marine) then
		return false
	end
	status:set("squadHoldFire",false)
	if squadValue and not squadValue.Value then return false end

	local list = members()
	if #list < 2 then
		if plan then setPlan(nil) end
		tactics.setAnchor(nil)

		--No squadmates but on a radio net: a squad of one, in the platoon.
		local target = status:get("currentTarget")
		if (not target or not target.Parent) and followPlatoon() then
			return true
		end
		return false
	end

	--Cover is only picked within reach of the rest of the squad.
	local center = centerOf(list)
	tactics.setAnchor(center,LEASH)

	local myIndex = table.find(list,myEntry)
	local leaderEntry = list[1]

	local target = status:get("currentTarget")
	if not target or not target.Parent then
		target = nil
	end

	if leaderEntry == myEntry then
		leaderThink(target,list)
	elseif plan then
		setPlan(nil)
	end

	local currentPlan = leaderEntry.plan

	--Fight the squad's enemy even if this soldier has not seen him himself.
	if not target and currentPlan and currentPlan.kind ~= "rally" and currentPlan.target and currentPlan.target.Parent
		and not core.isAlly(currentPlan.target.Parent) then
		target = currentPlan.target
		core.markSeen(target)
		status:set("currentTarget",target)
	end

	if currentPlan then
		local steering,offLeash = act(currentPlan,myIndex,list,target,leaderEntry)
		if steering then return true end
		if offLeash then return false end
	end

	--Nothing else is steering him: fighting freely or patrolling, he still
	--stays with his squad.
	if regroup(center,target ~= nil) then
		return true
	end

	if not target then
		if leaderEntry == myEntry and followPlatoon() then
			return true
		end
		return followFormation(list,myIndex,leaderEntry)
	end
	return false
end

return squad

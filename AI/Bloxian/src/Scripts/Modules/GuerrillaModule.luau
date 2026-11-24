--[[
	A soldier with no squadmates nearby, or the last man left of a squad, fights
	like a guerrilla.

	Special operations always stalk, in or out of a squad, but only fight when
	sof.engaged says so: no strike up close or out of patience. They hop from
	cover to cover, buildings before anything thinner, and stay outside STALK_RING
	of the player, backing off when he comes closer. With a line to him in
	observation range they stop, go prone and watch. Engaged, they break contact:
	away from him, cover to cover, shooting on the way, until the unit is no longer
	engaged. With no sight of him for HUNT_AFTER seconds they work toward him,
	ring or not, in short hops between cover until they have it. A sniper gets the
	same from the start. They don't search or hit and run.

	He picks the closest player he knows about (seen in the last STALK_MEMORY
	seconds, or close enough to hear) and heads for the nearest ambush spot: a
	clear shot at the player from somewhere the player is not looking. He moves
	through spots the player cannot see where he can, and says nothing.

	He shoots the moment he has a shot and keeps fighting while he has one.
	Losing the angle sends him round to a new one. Only badly hurt and taking
	fire does he fall back and hide for a few seconds. Lose track of the player
	and he goes to where he last saw him and looks around before giving up.
	After STALK_PATIENCE seconds of sneaking without getting his ambush (the
	player keeps turning to face him), he gives up on it and goes straight at him.
]]

local guerrilla = {}

local Players = game:GetService("Players")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local speed = require(modules.SpeedModule)
local movement = require(modules.MovementModule)
local tactics = require(modules.TacticsModule)
local squad = require(modules.SquadModule)
local sof = require(modules.SofModule)
local chatter = require(modules.ChatterModule)
local weapon = require(modules.WeaponProfiles).current
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart

local guerrillaValue = marine.Settings:FindFirstChild("Guerrilla")

--How far away a player can be and still get stalked, and how long after
--last seeing him he keeps hunting. SOF_STALK_RANGE is the range for special operations.
local STALK_RANGE = 300
local SOF_STALK_RANGE = 800
--Special operations sense a player this close through anything and start stalking him.
local SOF_DETECT_RADIUS = 300

--Special operations: how far out they stay, how far one hop may go (rings round
--him) and directions per ring, seconds between hops, the longest a hop may take,
--how many studs of range being behind the player is worth, how far to back off
--with no cover to go to, and the closest to the player a run for cover may end.
local STALK_RING = sof.OBSERVE_MIN
local COVER_HOPS = {15, 25, 35, 50, 75, 100, 140}
local COVER_HOP_DIRECTIONS = 8
local COVER_HOLD_MIN = 2
local COVER_HOLD_MAX = 4
local COVER_HOP_TIME = 8
local BEHIND_WEIGHT = 20
local BACK_OFF = 25
local COVER_MIN_DISTANCE = 30
--Seconds without sight of the player before special operations go looking for him,
--how much a stud of hop costs against a stud gained on him (higher: shorter hops),
--and how far one leg goes with no cover to hop to.
local HUNT_AFTER = 8
local COVER_HOP_COST = 1.5
local HUNT_STEP = 50
local STALK_MEMORY = 60
--Breaking contact, each hop ends at least this many studs further from the player.
local BREAK_GAIN = 15
--Seconds of prone each tick on an observation post keeps him down.
local OBSERVE_PRONE = 1
--Seconds a radio call about a player sends special operations toward him.
local RADIO_CALL_TIME = 20

--Seconds of stalking one player before he gives up sneaking and goes straight in.
local STALK_PATIENCE = 40

--After losing track: seconds spent going to the last known spot and looking round.
local SEARCH_TIME = 20

--Below this share of health, being hit sends him off to hide instead of fighting on.
local FALL_BACK_HEALTH = 0.4

--Seconds without a line of fire before a strike ends and he looks for a new angle.
local LOST_ANGLE_TIME = 1.5

--Inside this range he stops being sneaky and closes in for the kill, round
--whatever is in the way.
local CLOSE_QUARTERS = 15

--Where he tries to end up: this far behind the player.
local BEHIND_DISTANCE = 20

--Spots tried for each sneaking step: distances out and directions per ring.
local STEP_RINGS = {10, 16, 22}
local STEP_DIRECTIONS = 12

--Never sneak closer to the player than this.
local MIN_QUARRY_DISTANCE = 12

--How the player's facing is read. Below BEHIND_DOT the player has his back to
--him; above VIEW_DOT he is inside the player's field of view.
local BEHIND_DOT = -0.3
local VIEW_DOT = 0.3

--An unnoticed shot within this range starts a strike.
local STRIKE_RANGE = 70

--Seconds hidden after a strike before stalking again, more when hurt.
local HIDE_MIN = 2
local HIDE_MAX = 3.5
local HURT_HIDE_EXTRA = 2

--Hit and run: seconds he fights from one spot before slipping off to hit
--again from a new angle. Inside CLOSE_QUARTERS he fights on regardless.
local STRIKE_TIME_MIN = 4
local STRIKE_TIME_MAX = 7

--Falling back stays close: never more than this many studs further from the
--player than he was, so he keeps track of him and comes back fast.
local FADE_MAX_BACKOFF = 12

--Breaking off: how far to look for a hidden spot, and run speed.
local FADE_RINGS = {8, 14, 20}
local FADE_SPEED = 20

--How far along a planned route is checked for being in the player's view
--before he commits to walking it.
local ROUTE_CHECK_DISTANCE = 30

--Turning away from the way he was already heading costs this much when
--choosing a step, so he moves in lines instead of zigzagging.
local TURN_PENALTY = 6

--Longest one sneaking step or escape may take.
local MOVE_TIMEOUT = 6

local UP_HEAD = Vector3.new(0,1.5,0)

local state = nil --nil, "stalk", "strike", "fade", "hide" or "search"
local lastShotAngle = 0
local quarry = nil
local searchPoint = nil
local stateSince = 0
local stateUntil = 0

local viewParams = RaycastParams.new()

local function flat(vector)
	return Vector3.new(vector.X,0,vector.Z)
end

local function setState(newState,duration,reason)
	log("guerrilla",tostring(newState)..(reason and (" ("..reason..")") or ""))
	state = newState
	stateSince = os.clock()
	stateUntil = stateSince + (duration or 0)
end

--Stealth only keeps him quiet. He still shoots the moment he can see the player.
local function setStealth(on)
	status:set("stealth",on)
end

local huntStarted = nil

local function reset(reason)
	status:set("closingIn",false)
	if state then
		log("guerrilla","off ("..tostring(reason)..")")
		setStealth(false)
		speed.set(16)
	end
	state = nil
	quarry = nil
	huntStarted = nil
end

local function quarryAlive(root)
	local human = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	return human ~= nil and human.Health > 0
end

local stalkRange = sof.kind and SOF_STALK_RANGE or STALK_RANGE

local function sensed(root)
	return core.aware(root) or sof.kind ~= nil and (root.Position - myRoot.Position).Magnitude <= SOF_DETECT_RADIUS
end

--The player a radio call is sending him to, if any.
local function radioed()
	local target = status:get("radioTarget")
	return target and os.clock() - status:get("radioAt") < RADIO_CALL_TIME and quarryAlive(target)
		and Players:GetPlayerFromCharacter(target.Parent) and not core.isAlly(target.Parent) and target or nil
end

--Special operations: an enemy sniper heard firing, hunted like a player.
local heardSniper = nil
function guerrilla.hear(root)
	heardSniper = root
end

--The closest player, kept until he dies or gets well out of range.
local function pickQuarry()
	local target = status:get("currentTarget")
	if sof.kind and target and target.Parent and sof.closesOn(target) and quarryAlive(target) and not core.isAlly(target.Parent) then
		return target
	end
	local called = radioed()
	if called then
		return called
	end

	if quarry and quarryAlive(quarry) and not core.isAlly(quarry.Parent)
		and (core.knows(quarry,STALK_MEMORY) or sensed(quarry))
		and (quarry.Position - myRoot.Position).Magnitude <= stalkRange*1.2 then
		return quarry
	end

	local best,bestDist = nil,stalkRange
	for _,player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and quarryAlive(root) and not core.isAlly(character)
			and (core.knows(root,STALK_MEMORY) or sensed(root) or core.checkSight(root)) then
			local dist = (root.Position - myRoot.Position).Magnitude
			if dist < bestDist then
				best,bestDist = root,dist
			end
		end
	end
	if heardSniper and quarryAlive(heardSniper) and core.knows(heardSniper,STALK_MEMORY)
		and (heardSniper.Position - myRoot.Position).Magnitude < bestDist then
		best = heardSniper
	end
	return best
end

--Whether the player could see a soldier standing at pos.
local function quarrySees(pos)
	local character = quarry.Parent
	local head = character:FindFirstChild("Head")
	local eye = head and head.Position or quarry.Position + UP_HEAD

	local toMe = (pos + UP_HEAD) - eye
	if toMe.Magnitude < 1 then return true end
	if quarry.CFrame.LookVector:Dot(toMe.Unit) < VIEW_DOT then return false end

	viewParams.FilterDescendantsInstances = {marine,character}
	return workspace:Raycast(eye,toMe,viewParams) == nil
end

local function behindQuarry()
	local fromQuarry = flat(myRoot.Position - quarry.Position)
	if fromQuarry.Magnitude < 1 then return false end
	return flat(quarry.CFrame.LookVector):Dot(fromQuarry.Unit) < BEHIND_DOT
end

local function ringSpots(rings,directions)
	local spots = {}
	local myPos = myRoot.Position
	for _,ring in ipairs(rings) do
		for i = 1,directions do
			local angle = i/directions*math.pi*2
			local pos = tactics.floor(myPos + Vector3.new(math.cos(angle)*ring,0,math.sin(angle)*ring))
			if pos then
				spots[#spots+1] = pos
			end
		end
	end
	return spots
end

--The spot behind the player he is working toward.
local function behindPoint()
	local look = flat(quarry.CFrame.LookVector)
	if look.Magnitude < 0.001 then look = Vector3.zAxis end
	return quarry.Position - look.Unit*BEHIND_DISTANCE
end

--The next unseen spot he can walk straight to that gets him closer to the
--player's back. Spots past a wall are left to pathfinding.
local lastHeading = nil

--Where the current sneaking leg ends, and when it started. The next leg is
--planned once he is within PLAN_AHEAD studs of the end.
local currentStep = nil
local stepStarted = 0
local stepUntil = 0
local PLAN_AHEAD = 6

--The route check is cached this many seconds, it costs a path computation.
local ROUTE_RECHECK = 2
local routeCheckedAt = -math.huge
local routeGoal = nil
local routeOk = false

--Rings round the player searched for an ambush spot: distances out, directions per ring.
local AMBUSH_RINGS = {10, 18, 28, 40}
local AMBUSH_DIRECTIONS = 12

--A spot behind the player is worth this many studs of extra walking over one
--to his side. Small, so he takes the nearest good angle, not always the back.
local BEHIND_BONUS = 8

--The nearest spot that has a clear shot at the player and is out of his view:
--his flank, his back, or round the near end of a wall. nil if there is none.
local function ambushPoint()
	local qPos = quarry.Position
	local look = flat(quarry.CFrame.LookVector)
	look = look.Magnitude > 0.001 and look.Unit or Vector3.zAxis
	local myPos = myRoot.Position
	local myDist = flat(qPos - myPos).Magnitude

	local candidates = {}
	for _,ring in ipairs(AMBUSH_RINGS) do
		for i = 1,AMBUSH_DIRECTIONS do
			local angle = i/AMBUSH_DIRECTIONS*math.pi*2
			local offset = Vector3.new(math.cos(angle),0,math.sin(angle))
			local pos = tactics.floor(qPos + offset*ring)
			if pos then
				--Never back off to get an angle: only spots no further from the
				--player than he already is.
				if ring <= myDist + 5 then
					local score = flat(pos - myPos).Magnitude
					if look:Dot(offset) < BEHIND_DOT then
						score -= BEHIND_BONUS
					end
					candidates[#candidates+1] = {pos = pos, score = score}
				end
			end
		end
	end
	table.sort(candidates,function(a,b) return a.score < b.score end)

	--Cheap sort first, raycasts only until one passes.
	for _,candidate in ipairs(candidates) do
		local pos = candidate.pos
		if not quarrySees(pos) and not tactics.isHidden(pos,quarry) and tactics.roomAt(pos) then
			return pos
		end
	end
	return nil
end

local function stalkStep(goal)
	local qPos = quarry.Position
	local myPos = myRoot.Position

	local best = nil
	local bestScore = flat(myPos - goal).Magnitude - 3
	for _,pos in ipairs(ringSpots(STEP_RINGS,STEP_DIRECTIONS)) do
		if (pos - qPos).Magnitude >= MIN_QUARRY_DISTANCE then
			local score = flat(pos - goal).Magnitude
			local heading = flat(pos - myPos)
			if lastHeading and heading.Magnitude > 0.1 then
				score += (1 - heading.Unit:Dot(lastHeading))*TURN_PENALTY
			end
			--Cheapest checks first: only a spot that would beat the best so far gets raycast.
			if score < bestScore and not quarrySees(pos) and movement.clearLine(pos) and tactics.roomAt(pos) then
				best,bestScore = pos,score
			end
		end
	end

	if best then
		local heading = flat(best - myPos)
		lastHeading = heading.Magnitude > 0.1 and heading.Unit or lastHeading
	end
	return best
end

--Whether the first stretch of a route stays out of the player's sight.
local function routeHidden(waypoints)
	local travelled = 0
	local previous = myRoot.Position
	for index = 2,#waypoints do
		local point = waypoints[index].Position + Vector3.new(0,3,0)
		travelled += (point - previous).Magnitude
		previous = point
		if quarrySees(point) then
			return false
		end
		if travelled > ROUTE_CHECK_DISTANCE then
			break
		end
	end
	return true
end

--A spot further from the player that he cannot shoot into.
--A nearby spot the player cannot shoot into, round to a different side of him
--so the next strike comes from a new angle. It never takes him far away.
local function fadeSpot()
	local qPos = quarry.Position
	local myOffset = flat(myRoot.Position - qPos)
	local myDist = myOffset.Magnitude
	local myBearing = myDist > 0.1 and myOffset.Unit or Vector3.xAxis

	local best,bestScore = nil,-math.huge
	for _,pos in ipairs(ringSpots(FADE_RINGS,10)) do
		local offset = flat(pos - qPos)
		local dist = offset.Magnitude
		if dist >= MIN_QUARRY_DISTANCE and dist <= myDist + FADE_MAX_BACKOFF then
			--Swinging round the player scores, walking far does not.
			local swing = 1 - offset.Unit:Dot(myBearing)
			local score = swing*10 - (pos - myRoot.Position).Magnitude*0.2
			if score > bestScore and tactics.isHidden(pos,quarry) and tactics.roomAt(pos) then
				best,bestScore = pos,score
			end
		end
	end
	return best
end

local function rushTo(pos)
	speed.set(FADE_SPEED)
	movement.goToPosition(pos,function() return myHuman.Health > 0 end,MOVE_TIMEOUT)
	speed.set(16)
end

local function shotSince(time)
	return status:get("lastDamaged") > time
end

local function strikeTime()
	return STRIKE_TIME_MIN + math.random()*(STRIKE_TIME_MAX - STRIKE_TIME_MIN)
end

local function healthFraction()
	return myHuman.Health/myHuman.MaxHealth
end

--His cover is blown. With a shot inside his gun's range he fights; only badly
--hurt, or with no shot at all, does he slip away.
local function blown()
	local inRange = (quarry.Position - myRoot.Position).Magnitude <= weapon.range
	if inRange and healthFraction() >= FALL_BACK_HEALTH and core.checkSight(quarry) then
		if sof.kind then
			chatter.callout("breakContact",nil,0.6)
		end
		setState("strike",strikeTime(),sof.kind and "compromised, breaking contact" or "spotted, fighting back")
	elseif healthFraction() < FALL_BACK_HEALTH then
		setState("fade",nil,"spotted and hurt, falling back")
	else
		--Seen but no shot: keep working round to an angle instead of running.
		setState("stalk",nil,"spotted, no shot, finding an angle")
	end
end

--The next spot behind a building in reach, as near the ring and the player's back
--as it can get; inside the ring, only one further out than he is. Exposed, the
--nearest one instead. Advancing, a short hop that gains on the player. Breaking
--contact, the nearest one further from him. With no building, any hidden spot.
--nil if there is none.
local function nextCover(exposed,advancing,breaking)
	local qPos = quarry.Position
	local myPos = myRoot.Position
	local myDist = flat(qPos - myPos).Magnitude
	local look = flat(quarry.CFrame.LookVector)
	local spin = math.random()*math.pi*2
	local spots = {}
	for _,ring in ipairs(COVER_HOPS) do
		for i = 1,COVER_HOP_DIRECTIONS do
			local angle = spin + i/COVER_HOP_DIRECTIONS*math.pi*2
			local pos = myPos + Vector3.new(math.cos(angle)*ring,0,math.sin(angle)*ring)
			local offset = flat(pos - qPos)
			local dist = offset.Magnitude
			if breaking then
				if dist >= myDist + BREAK_GAIN then
					spots[#spots+1] = {pos = pos, score = ring}
				end
			elseif advancing then
				if dist < myDist - 5 then
					spots[#spots+1] = {pos = pos, score = ring*COVER_HOP_COST - (myDist - dist)}
				end
			elseif exposed and dist >= COVER_MIN_DISTANCE then
				spots[#spots+1] = {pos = pos, score = ring}
			elseif not exposed and dist >= math.min(STALK_RING,myDist + 5) then
				spots[#spots+1] = {pos = pos, score = math.abs(dist - STALK_RING) + look:Dot(offset.Unit)*BEHIND_WEIGHT}
			end
		end
	end
	table.sort(spots,function(a,b) return a.score < b.score end)
	local fallback = nil
	for _,spot in ipairs(spots) do
		local pos = tactics.floor(spot.pos)
		if pos and tactics.hardCover(pos,quarry) then
			if tactics.roomAt(pos) then
				return pos
			end
		elseif pos and not fallback and tactics.isHidden(pos,quarry) and tactics.roomAt(pos) then
			fallback = pos
		end
	end
	return fallback
end

local nextPlan = 0
local lastPlan = -math.huge
local diving = false
local hunting = false
local lastSawQuarry = -math.huge

--With no cover to hop to: a leg in the open toward the player, or to him up close.
local function huntLeg()
	local toward = flat(quarry.Position - myRoot.Position)
	if toward.Magnitude > HUNT_STEP then
		return tactics.ground(myRoot.Position + toward.Unit*HUNT_STEP) or quarry.Position
	end
	return quarry.Position
end

--One tick of cover to cover: walking a hop, holding in cover, or picking the next.
--The player inside the ring or a clear line to him cuts the hold short, and on a
--clear line he runs.
local function stalkCover(now)
	local closing = sof.closesOn(quarry)
	status:set("closingIn",closing)
	local sight = core.checkSight(quarry)
	if closing and sight and (quarry.Position - myRoot.Position).Magnitude <= sof.SNIPER_RANGE then
		status:set("closingIn",false)
		currentStep = nil
		movement.stop()
		return
	end

	if sight then
		lastSawQuarry = now
		if hunting then
			hunting = false
			currentStep = nil
			movement.stop()
		end
	elseif now - math.max(lastSawQuarry,huntStarted) > HUNT_AFTER or radioed() == quarry then
		hunting = true
	end

	--Compromised he gets away from the player. Unseen with a line to him, he watches.
	local breaking = state == "strike" and not closing
	local distance = flat(quarry.Position - myRoot.Position).Magnitude
	if state == "stalk" and not closing and sof.observes(distance,sight) and not sof.engaged(quarry) then
		log("guerrilla","eyes on, holding the observation post",3)
		currentStep = nil
		speed.set(16)
		movement.stop()
		status:set("proneUntil",now + OBSERVE_PRONE)
		return
	end
	local advancing = not breaking and (closing or hunting)

	if currentStep then
		if flat(currentStep - myRoot.Position).Magnitude > 4 and now < stepUntil then
			if diving then
				speed.set(FADE_SPEED)
			end
			return
		end
		currentStep = nil
		speed.set(16)
		movement.stop()
		nextPlan = now + COVER_HOLD_MIN + math.random()*(COVER_HOLD_MAX - COVER_HOLD_MIN)
	end

	if now - lastPlan < 1 then
		return
	end
	lastPlan = now
	local away = flat(myRoot.Position - quarry.Position)
	local inside = away.Magnitude < STALK_RING
	local exposed = not tactics.isHidden(myRoot.Position,quarry)
	if now < nextPlan and not exposed and not breaking and not closing and (advancing or not inside) then
		return
	end
	nextPlan = now + COVER_HOLD_MIN

	local spot = nextCover(exposed,advancing,breaking) or advancing and huntLeg()
		or (inside or breaking) and away.Magnitude > 1 and tactics.ground(myRoot.Position + away.Unit*BACK_OFF) or nil
	if spot then
		currentStep = spot
		stepStarted = now
		stepUntil = now + COVER_HOP_TIME
		diving = exposed or breaking or closing
		speed.set(diving and FADE_SPEED or 16)
		movement.navigate(spot)
	else
		lastPlan = now + COVER_HOLD_MIN
	end
end

--Whether his cover is blown. Special operations go on sneaking until engaged with a
--shot, and badly hurt they keep to cover.
local function noticed(since)
	if sof.kind then
		return healthFraction() >= FALL_BACK_HEALTH and sof.engaged(quarry) and core.checkSight(quarry)
			and (quarry.Position - myRoot.Position).Magnitude <= weapon.range
	end
	return shotSince(since) or quarrySees(myRoot.Position)
end

--Runs the guerrilla for this tick. True when he is steering the soldier.
function guerrilla.update()
	if not sof.kind and ((guerrillaValue and not guerrillaValue.Value) or not squad.isAlone() or tactics.holdsBack()) then
		reset("not alone, turned off, or a sniper team")
		return false
	end

	local newQuarry = pickQuarry()
	if not newQuarry then
		--Lost him mid-hunt: check where he was last seen before giving up.
		if not sof.kind and quarry and state and state ~= "search" then
			searchPoint = core.lastKnown(quarry)
			if searchPoint then
				setState("search",SEARCH_TIME,"lost him, checking his last known spot")
			end
		end

		if state == "search" and os.clock() < stateUntil and myHuman.Health > 0 then
			setStealth(true)
			local lostQuarry = quarry
			if flat(searchPoint - myRoot.Position).Magnitude > 4 then
				movement.goToPosition(searchPoint,function()
					return myHuman.Health > 0 and not core.knows(lostQuarry,STALK_MEMORY)
				end,6)
			else
				movement.stop()
				task.wait(0.5)
			end
			return true
		end

		reset(state == "search" and "searched, found nothing" or "no known player to stalk")
		return false
	end

	if state == "search" then
		setState("stalk",nil,"found him again")
	end

	--Already fighting another player: he becomes the quarry. Fighting an NPC:
	--leave that to the normal combat logic.
	local target = status:get("currentTarget")
	if target and target.Parent and target.Parent ~= newQuarry.Parent then
		if Players:GetPlayerFromCharacter(target.Parent) and quarryAlive(target) and not core.isAlly(target.Parent) then
			newQuarry = target
		else
			reset("fighting an NPC instead")
			return false
		end
	end

	if not state then
		tactics.release()
		setState("stalk")
	end
	if quarry ~= newQuarry then
		huntStarted = os.clock()
	end
	quarry = newQuarry

	local now = os.clock()

	if state == "stalk" then
		setStealth(true)
		sof.report(quarry)
		sof.relay(quarry)
		--A leg planned before he last left stalking is stale.
		if stepStarted < stateSince then
			currentStep = nil
		end

		if noticed(stateSince) then
			blown()
			return true
		end

		--Out of patience: no more sneaking, straight at him until he has a shot.
		if not sof.kind and huntStarted and now - huntStarted > STALK_PATIENCE then
			setStealth(false)
			if core.checkSight(quarry) then
				setState("strike",strikeTime(),"done sneaking, going straight at him")
			else
				movement.navigate(quarry.Position)
			end
			return true
		end

		--Right on top of him: no more sneaking, go and fight.
		if not sof.kind and (quarry.Position - myRoot.Position).Magnitude <= CLOSE_QUARTERS then
			setState("strike",strikeTime(),"close quarters, going in")
			return true
		end

		--Any clear shot while the player has not seen him is an ambush. Getting
		--behind him is only how he moves when he has no shot yet.
		if not sof.kind and (quarry.Position - myRoot.Position).Magnitude <= STRIKE_RANGE and core.checkSight(quarry) then
			setState("strike",strikeTime(),behindQuarry() and "behind him with a shot" or "caught him off guard")
			return true
		end

		if sof.kind then
			stalkCover(now)
			return true
		end

		--Plan the next move while still walking the current one: only once he is
		--within PLAN_AHEAD of where he is headed, or has nowhere to go. The walk
		--itself runs on the navigator, so planning never makes him stop.
		local headed = currentStep and flat(currentStep - myRoot.Position).Magnitude > PLAN_AHEAD
			and os.clock() < stepUntil
		if not headed then
			--Head for the nearest angle with a shot he is not watching. With no
			--such spot (open ground in every direction he is looking), his back.
			local goal = ambushPoint() or behindPoint()
			if os.clock() - routeCheckedAt > ROUTE_RECHECK or not routeGoal or (goal - routeGoal).Magnitude > 10 then
				local route = movement.findPath(goal)
				routeOk = route ~= nil and routeHidden(route)
				routeCheckedAt = os.clock()
				routeGoal = goal
			end

			local nextStep
			if routeOk then
				log("stalkStep","route to the ambush spot is hidden, following it",3)
				nextStep = goal
			else
				--The route would show him, so pick his way from hidden spot to hidden spot.
				nextStep = stalkStep(goal)
				if nextStep then
					log("stalkStep","sneaking to next hidden spot",3)
				else
					--No hidden way at all: go anyway rather than stand behind the
					--wall. If he is spotted on the way he fights back.
					log("stalkStep","no hidden way, taking the route anyway",3)
					nextStep = goal
				end
			end

			if nextStep then
				currentStep = nextStep
				stepStarted = os.clock()
				--A leg toward a moving player is re-aimed sooner than one to a fixed hiding spot.
				stepUntil = stepStarted + (routeOk and ROUTE_RECHECK or MOVE_TIMEOUT)
				--Passes through each spot still walking, so the next one chains on.
				movement.navigate(nextStep,true)
			else
				currentStep = nil
				lastHeading = nil
				movement.stop()
			end
		end

	elseif state == "strike" then
		setStealth(false)
		status:set("currentTarget",quarry)

		local close = (quarry.Position - myRoot.Position).Magnitude <= CLOSE_QUARTERS

		--Stand and shoot. Without a clear shot: up close, walk round whatever is
		--in the way straight to him; further out, edge toward him until the
		--rifle clears the corner. Special operations shoot on the way to cover.
		if sof.kind then
			stalkCover(now)
		elseif core.checkShot(quarry) then
			movement.stop()
		elseif close then
			movement.navigate(quarry.Position)
		else
			local toward = flat(quarry.Position - myRoot.Position)
			if toward.Magnitude > 1 then
				movement.walkTo(myRoot.Position + toward.Unit*3)
			end
		end

		--He keeps fighting as long as he has a shot, or is close enough to get
		--one. Hurt and being hit, he falls back. Lose the angle further out and he
		--works round to a new one; he does not run.
		if core.checkSight(quarry) or close or lastShotAngle < stateSince then
			lastShotAngle = now
		end
		if sof.kind and (not sof.engaged(quarry) or healthFraction() < FALL_BACK_HEALTH) then
			setState("stalk",nil,"back to stalking")
		elseif healthFraction() < FALL_BACK_HEALTH and shotSince(now - 2) then
			setState("fade",nil,"hurt and taking fire, falling back")
		elseif not sof.kind and now >= stateUntil and not close then
			setState("fade",nil,"hit and run, relocating")
		elseif now - lastShotAngle > LOST_ANGLE_TIME then
			setState("stalk",nil,"lost the angle, finding a new one")
		end

	elseif state == "fade" then
		setStealth(true)
		core.markSeen(quarry)
		local spot = fadeSpot()
		if spot then
			rushTo(spot)
		end

		local hide = HIDE_MIN + math.random()*(HIDE_MAX - HIDE_MIN)
		if myHuman.Health/myHuman.MaxHealth < 0.5 then
			hide += HURT_HIDE_EXTRA
		end
		setState("hide",hide)

	elseif state == "hide" then
		setStealth(true)
		movement.stop()

		--A moment's grace first, so hiding and being spotted cannot flip back and forth.
		if now - stateSince > 0.5 and noticed(stateSince) then
			blown()
		elseif now >= stateUntil then
			setState("stalk")
		end
	end

	return true
end

return guerrilla

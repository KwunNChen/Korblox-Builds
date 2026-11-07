local tactics = {}

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local movement = require(modules.MovementModule)
local actions = require(modules.ActionsModule)
local chatter = require(modules.ChatterModule)
local log = require(modules.Troubleshoot).log
local morale = require(modules.MoraleModule)
local sof = require(modules.SofModule)
local openings = require(modules.OpeningsModule)
local threat = require(modules.ThreatModule)

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart

local mySettings = marine.Settings
local useCoverValue = mySettings:FindFirstChild("UseCover")
local weapon = require(modules.WeaponProfiles).current

--Where to look for cover: how far out, and how many directions per ring.
local RINGS = {0, 7, 14, 22}
local DIRECTIONS = 10

--Shot in the open with nothing that close, he scrambles for any wall further
--out (these rings, ignoring his squad's leash), at SCRAMBLE_SPEED, for up to
--SCRAMBLE_TIMEOUT seconds, firing as he goes.
local SCRAMBLE_RINGS = {30, 40, 50}
local SCRAMBLE_DIRECTIONS = 12
local SCRAMBLE_SPEED = 16
local SCRAMBLE_TIMEOUT = 10

--Cover only counts if the wall is this close to the spot, and the spot is at
--least this far from the enemy.
local WALL_MAX_DISTANCE = 7
--Hard cover: how wide it must be, and how far from the soldier it may stand.
local COVER_WIDTH = 10
local COVER_REACH = 20
local MIN_THREAT_DISTANCE = 12

--How far to step sideways to shoot around the cover, and how far apart two
--soldiers' cover spots must be.
local PEEK_OFFSET = 3
local CLAIM_SPACING = 5

--Below this share of health a soldier hides more and peeks less.
local LOW_HEALTH = 0.5

--Reload in cover once the magazine is down to this share.
local RELOAD_AT = 0.3

--Closer than this and he fights instead of hiding.
local MELEE_DISTANCE = 10

--Seconds hidden between peeks: normal, hurt, and laying down a base of fire.
local HIDE_MIN = 0.8
local HIDE_MAX = 1.6
local HURT_HIDE_MIN = 4
local HURT_HIDE_MAX = 7
local SUPPRESS_HIDE_MIN = 0.8
local SUPPRESS_HIDE_MAX = 1.5

--Seconds out on a peek: normal, hurt, and laying down a base of fire.
local PEEK_TIME_MIN = 2.5
local PEEK_TIME_MAX = 4
local HURT_PEEK_TIME = 1.2
local SUPPRESS_PEEK_MIN = 2
local SUPPRESS_PEEK_MAX = 3.5

--Against an automatic he hides this many times longer between peeks; against
--a sniper he peeks for this share of the usual time.
local AUTO_HIDE = 1.6
local SNIPER_PEEK = 0.5

--Longest he stays in cover before pushing on if healthy, loaded and not
--outnumbered.
local COVER_MAX_TIME = 12

--Seconds in one cover spot without once seeing his target before he gives it up.
local COVER_BLIND = 12

--Peeks from one cover spot before he moves to another, so he is not
--predictable. The spot he left is not taken again straight off.
local PEEKS_PER_SPOT = 3

--Pinned down (set by CombatModule when a round passes close by) he hides SUPPRESSED_HIDE times longer and peeks
--SUPPRESSED_PEEK of the usual time.
local SUPPRESSED_HIDE = 1.5
local SUPPRESSED_PEEK = 0.5

--Seconds between cover searches, and quiet time after leaving cover before
--non-urgent reasons can send him back.
local SEARCH_COOLDOWN = 2
local COVER_COOLDOWN = 6

--Longest one run to a cover spot may take, and the most time spent trying
--spots before giving up.
local COVER_RUN_TIMEOUT = 6
local COVER_SEARCH_BUDGET = 8

--How likely a soldier is to take cover when only under fire or outnumbered
--(hurt or low on ammo always sends him). Each soldier rolls his own between these.
local CAUTION_MIN = 0.5
local CAUTION_MAX = 0.95

local UP_HEAD = Vector3.new(0,1.5,0)
local NO_OPTIONS = {}
local caution = CAUTION_MIN + math.random()*(CAUTION_MAX - CAUTION_MIN)

--Squads keep cover within reach of each other: spots further than anchorRadius
--from anchor are skipped. nil when the soldier is on his own.
local anchor = nil
local anchorRadius = 0

function tactics.setAnchor(point,radius)
	anchor = point
	anchorRadius = radius or 0
end

--Spots soldiers are using, so two do not pile into the same one.
_G.BloxianCover = _G.BloxianCover or {}
local claims = _G.BloxianCover

local state = nil --nil, "hiding" or "peeking"
local peeks = 0
local abandoned = nil --a spot he just moved off, not to be taken again at once
--The enemy aircraft he is hiding from, if any, and the enemy armor (armorCover).
local airThreat = nil
local armorThreat = nil
local echoThreat = nil
local spot
local stateSince = 0
--Hit in the open with no cover in reach, he drops prone and shoots back for
--this many seconds, renewed each time he is hit again.
local PRONE_HOLD = 6

local stateUntil = 0
local proneUntil = 0
local coverStart = 0
local lastCoverEnd = -math.huge
local lastSearch = -math.huge
local lastSight = -math.huge
local damagedAt = -math.huge

local lastHealth = myHuman.Health
myHuman.HealthChanged:Connect(function(health)
	if health < lastHealth then
		damagedAt = os.clock()
	end
	lastHealth = health
end)

local function healthFraction()
	return myHuman.Health/myHuman.MaxHealth
end

local function claimedByOther(pos)
	for other,claimed in pairs(claims) do
		if other ~= marine then
			if not other.Parent then
				claims[other] = nil
			elseif (claimed - pos).Magnitude < CLAIM_SPACING then
				return true
			end
		end
	end
	return false
end

--A spot is thrown out if its floor is more than this far above or below his.
local MAX_HEIGHT_CHANGE = 4

local BODY_SIZE = Vector3.new(2,4,2)
local overlapParams = OverlapParams.new()
overlapParams.FilterDescendantsInstances = {marine}

--Walkable floor under point, at root height. nil over a drop, on a slope, or on
--top of a wall or crate. One raycast: cheap enough to run on every candidate.
function tactics.floor(point)
	local hit,result = core.raycast(point + Vector3.new(0,2,0),Vector3.new(0,-14,0))
	if not hit or result.Normal.Y <= 0.7 then
		return nil
	end

	local standing = result.Position + Vector3.new(0,3,0)
	if math.abs(standing.Y - myRoot.Position.Y) > MAX_HEIGHT_CHANGE then
		return nil
	end
	return standing
end

--Whether a body fits at a floor spot, nothing solid in the way. Costlier: only
--run it on spots that already passed everything else.
function tactics.roomAt(standing)
	for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(standing + Vector3.new(0,0.5,0)),BODY_SIZE,overlapParams)) do
		if part.CanCollide then
			return false
		end
	end
	return true
end

--A standing spot: floor plus room to stand.
function tactics.ground(point)
	local standing = tactics.floor(point)
	if standing and tactics.roomAt(standing) then
		return standing
	end
	return nil
end
local groundPoint = tactics.ground

-- Off the open --------------------------------------------------------------

--With no cover he never fights from the middle of a road or field. He runs for
--the edge of it: a spot with something solid within EDGE_REACH studs on any side,
--not indoors, searched out to the last of EDGE_RINGS at most every EDGE_COOLDOWN seconds.
local EDGE_RINGS = {6, 12, 18, 26, 34, 42, 50}
local EDGE_DIRECTIONS = 12
local EDGE_RAYS = 6
local EDGE_REACH = 5
local EDGE_COOLDOWN = 3

--Holding an angle, a spot out in the open counts this many studs further off.
local OPEN_COST = 15

local function againstSomething(pos)
	for i = 1,EDGE_RAYS do
		local angle = i/EDGE_RAYS*math.pi*2
		local hit,result = core.raycast(pos + UP_HEAD,Vector3.new(math.cos(angle),0,math.sin(angle))*EDGE_REACH)
		if hit and result.Instance.CanCollide and not core.getHuman(result.Instance.Parent) then
			return true
		end
	end
	return false
end

--The nearest edge to center within reach studs, with a clear shot at the target
--if needsShot. Nil if there is none.
function tactics.findEdge(center,target,reach,needsShot)
	for _,ring in ipairs(EDGE_RINGS) do
		if ring > reach then break end
		local best,bestDist = nil,math.huge
		for i = 1,EDGE_DIRECTIONS do
			local angle = i/EDGE_DIRECTIONS*math.pi*2
			local pos = tactics.floor(center + Vector3.new(math.cos(angle)*ring,0,math.sin(angle)*ring))
			local dist = pos and (pos - myRoot.Position).Magnitude
			if pos and dist < bestDist and (pos - target.Position).Magnitude >= MIN_THREAT_DISTANCE and not claimedByOther(pos)
				and againstSomething(pos) and not movement.indoors(pos)
				and (not needsShot or not tactics.isHidden(pos,target)) and tactics.roomAt(pos) then
				best,bestDist = pos,dist
			end
		end
		if best then return best end
	end
	return nil
end

-- Holding angles and pushing in numbers -------------------------------------

--He only pushes at the enemy with at least MASS_MIN of his side (him included,
--none broken) within MASS_RANGE, and at least MASS_RATIO times as many as the
--enemies he knows about. Otherwise he holds an angle.
local MASS_RANGE = 60
local MASS_MIN = 2
local MASS_RATIO = 1

--Against a sniper, fewer will do: he is worst up close.
local SNIPER_MASS_MIN = 2
local SNIPER_MASS_RATIO = 1

--Holding an angle: spots this far round him that can see where the enemy
--was, a spot with something waist-high in front of it toward the enemy
--(within LOW_COVER_REACH) counting LOW_COVER_BONUS studs nearer, picked again
--every HOLD_RECHECK seconds.
local HOLD_RINGS = {0, 6, 12}
local HOLD_DIRECTIONS = 8
local LOW_COVER_REACH = 6
local LOW_COVER_BONUS = 10
local HOLD_RECHECK = 6

local teamValue = marine.Settings.Team

--Hostile air: while an enemy F-4, Apache or AC-130 is up (AIRBORNE_HEIGHT studs
--or more off whatever is below it) within AIR_DANGER studs across the ground,
--whatever his own side has up, he gets indoors (a ceiling within ROOF_REACH
--studs over his head), or behind cover from it. A spot open to the sky costs
--OPEN_SKY_COST studs of extra walking against an indoor one. He stays hidden,
--not peeking, at most AIR_HIDE_MAX seconds, then fights for AIR_FIGHT seconds
--before he will hide from the air again. Checked every AIR_CHECK seconds.
--With no cover (or while fighting back) he never stands still under it: he runs
--legs of AIR_EVADE_DISTANCE studs across its path and away from it, a new one
--every AIR_EVADE_LEG seconds, firing as he goes.
local AIR_TAGS = {"BloxianJet","BloxianAircraft","BloxianGunship"}
local AIR_DANGER = 3000
local AIRBORNE_HEIGHT = 20
local ROOF_REACH = 40
local OPEN_SKY_COST = 20
local AIR_CHECK = 0.5
local AIR_HIDE_MAX = 8
local AIR_FIGHT = 12
local AIR_EVADE_DISTANCE = 25
local AIR_EVADE_LEG = 1.5
local CollectionService = game:GetService("CollectionService")

--Units that never push, whatever the numbers: they hold angles from where they are.
local NEVER_PUSH = {Sniper = true, Spotter = true, ["Special Recon"] = true}
local unitValue = marine.Settings:FindFirstChild("Unit")

--Whether he is one that never pushes: a sniper team while both are alive, or
--a demoralized squad (SquadModule sets Demoralized).
function tactics.holdsBack()
	return NEVER_PUSH[marine:GetAttribute("Unit") or (unitValue and unitValue.Value)] == true
		or marine:GetAttribute("Demoralized") == true
end

--Whether his side has the numbers here to push. Worked out at most every
--ADVANTAGE_CACHE seconds, it is asked many times a second.
local ADVANTAGE_CACHE = 0.5
local advantageAt,advantageResult = -math.huge,false
local advantageFriends,advantageEnemies = 1,1
function tactics.advantage()
	if tactics.holdsBack() then
		return false
	end
	if openings.pushing() then
		return true
	end
	local now = os.clock()
	if now - advantageAt < ADVANTAGE_CACHE then
		return advantageResult
	end
	advantageAt = now
	local friends = 1
	for other,entry in pairs(_G.BloxianRadio or {}) do
		if other ~= marine and entry.root.Parent and entry.human.Health > 0 and entry.team.Value == teamValue.Value
			and other:GetAttribute("MoraleState") ~= "broken"
			and (entry.root.Position - myRoot.Position).Magnitude <= MASS_RANGE then
			friends += 1
		end
	end
	local enemies = math.max(#status:get("potentialTargets"),1)
	local sniper = threat.current() == "long"
	advantageFriends,advantageEnemies = friends,enemies
	advantageResult = friends >= (sniper and SNIPER_MASS_MIN or MASS_MIN)
		and friends >= enemies*(sniper and SNIPER_MASS_RATIO or MASS_RATIO)
	return advantageResult
end

--Whether his side here is at least as many as the enemies he knows of.
function tactics.notOutnumbered()
	if tactics.holdsBack() then
		return false
	end
	tactics.advantage()
	return advantageFriends >= advantageEnemies
end

local function seesPoint(from,point)
	local hit,result = core.raycast(from,point - from)
	return not hit or (result.Position - point).Magnitude < 4
end

local angleSpot = nil
local angleFor = nil
local angleAt = -math.huge
local holdingSince = nil
local lastHold = -math.huge

--Holds an angle on point (where the enemy was): moves to a spot close by that
--sees it, low cover in front if there is one, and faces it.
function tactics.holdAngle(point)
	local now = os.clock()
	local look = point + Vector3.new(0,2,0)
	if not angleFor or (angleFor - point).Magnitude > 10 or now - angleAt > HOLD_RECHECK then
		angleFor,angleAt = point,now
		angleSpot = nil
		local bestScore = math.huge
		for _,ring in ipairs(HOLD_RINGS) do
			local steps = ring == 0 and 1 or HOLD_DIRECTIONS
			for i = 1,steps do
				local pos
				if ring == 0 then
					pos = myRoot.Position
				else
					local angle = i/steps*math.pi*2
					pos = groundPoint(myRoot.Position + Vector3.new(math.cos(angle)*ring,0,math.sin(angle)*ring))
				end
				if pos and (ring == 0 or not claimedByOther(pos)) and seesPoint(pos + UP_HEAD,look) then
					local toward = Vector3.new(look.X - pos.X,0,look.Z - pos.Z)
					local low = toward.Magnitude > 1 and core.raycast(pos - Vector3.new(0,1.5,0),toward.Unit*LOW_COVER_REACH)
					local score = (pos - myRoot.Position).Magnitude - (low and LOW_COVER_BONUS or 0)
						+ (againstSomething(pos) and 0 or OPEN_COST)
					if score < bestScore then
						angleSpot,bestScore = pos,score
					end
				end
			end
		end
	end

	if now - lastHold > 2 then
		holdingSince = now
		chatter.callout("holdAngle",nil,0.35)
	end
	lastHold = now

	--Inside with no view of it: he is no use in here.
	if not angleSpot and movement.getOut() then
		return
	end

	if angleSpot and Vector3.new(angleSpot.X - myRoot.Position.X,0,angleSpot.Z - myRoot.Position.Z).Magnitude > 2 then
		movement.navigate(angleSpot)
		return
	end
	movement.stop()
	if not status:get("weaponAimed") then
		local flat = Vector3.new(point.X,myRoot.Position.Y,point.Z)
		if (flat - myRoot.Position).Magnitude > 1 and myRoot.CFrame.LookVector:Dot((flat - myRoot.Position).Unit) < 0.94 then
			myRoot.CFrame = CFrame.lookAt(myRoot.Position,flat)
		end
	end
end

--Whether he is holding an angle right now.
function tactics.holdingAngle()
	return os.clock() - lastHold < 1
end

--Whether something other than the threat is in the way, and how far from the spot it is.
local function blockedFrom(from,threat)
	local toThreat = threat.Position - from
	if toThreat.Magnitude < 0.001 then return false end

	local hit,result = core.raycast(from,toThreat.Unit*(toThreat.Magnitude + 3))
	if hit and not result.Instance:IsDescendantOf(threat.Parent) then
		return true,result.Distance
	end
	return false
end

--Whether a man standing at pos has a ceiling over him.
local function roofed(pos)
	return (core.raycast(pos + UP_HEAD,Vector3.new(0,ROOF_REACH,0)))
end

--Whether a standing soldier at pos is out of the threat's line of fire. From
--the air, a roof is enough.
function tactics.isHidden(pos,threat)
	if threat == airThreat and roofed(pos) then
		return true
	end
	return (blockedFrom(pos + UP_HEAD,threat))
end

--Whether something COVER_WIDTH wide stands between pos and the threat: a building, not a tree.
function tactics.hardCover(pos,threat)
	local eye = pos + UP_HEAD
	local toThreat = threat.Position - eye
	local side = Vector3.new(-toThreat.Z,0,toThreat.X)
	if side.Magnitude < 1 then return false end
	side = side.Unit*COVER_WIDTH/2
	local reach = toThreat.Unit*COVER_REACH
	for _,offset in ipairs({Vector3.zero,side,-side}) do
		local hit,result = core.raycast(eye + offset,reach)
		if not hit or result.Instance:IsDescendantOf(threat.Parent) or core.getHuman(result.Instance.Parent) then
			return false
		end
	end
	return true
end

--A spot a step to the side of the cover with a clear shot at the threat.
local function findPeek(pos,threat)
	local toThreat = threat.Position - pos
	local flat = Vector3.new(toThreat.X,0,toThreat.Z)
	if flat.Magnitude < 1 then return nil end

	local side = flat.Unit:Cross(Vector3.yAxis)*PEEK_OFFSET
	local first = math.random(2) == 1 and 1 or -1
	for _,sign in ipairs({first,-first}) do
		local peek = groundPoint(pos + side*sign)
		if peek and not blockedFrom(peek + UP_HEAD,threat) then
			return peek
		end
	end
	return nil
end

--Cover spots around center (default: where he stands), nearest and least exposed
--first. wide: the scramble rings, ignoring the squad's leash.
local function findCover(threat,center,wide)
	local myPos = myRoot.Position
	local aroundMe = center == nil
	center = center or myPos

	local threatPos = threat.Position
	local centerThreatDist = (center - threatPos).Magnitude
	local found = {}

	for _,ring in ipairs(wide and SCRAMBLE_RINGS or RINGS) do
		local steps = ring == 0 and 1 or (wide and SCRAMBLE_DIRECTIONS or DIRECTIONS)
		for i = 1,steps do
			local pos
			if ring == 0 then
				pos = aroundMe and myPos or tactics.floor(center)
			else
				local angle = i/steps*math.pi*2
				pos = tactics.floor(center + Vector3.new(math.cos(angle)*ring,0,math.sin(angle)*ring))
			end

			if pos and anchor and not wide and (pos - anchor).Magnitude > anchorRadius then
				pos = nil
			end

			if pos then
				local threatDist = (pos - threatPos).Magnitude
				if threatDist >= MIN_THREAT_DISTANCE and (threatDist <= weapon.range + 20 or threat == airThreat or threat == armorThreat or threat == echoThreat)
					and not claimedByOther(pos) then
					local blocked,wallDist = blockedFrom(pos + UP_HEAD,threat)
					local indoors = threat == airThreat and roofed(pos)
					if (indoors or blocked and wallDist <= WALL_MAX_DISTANCE) and (pos == myPos or tactics.roomAt(pos)) then
						local peek = findPeek(pos,threat)
						local score = (pos - center).Magnitude
						score += math.max(centerThreatDist - threatDist,0)*1.5
						if not peek then
							score += 15
						end
						if threat == airThreat and not indoors then
							score += OPEN_SKY_COST
						end
						found[#found+1] = {pos = pos, peek = peek, score = score}
					end
				end
			end
		end
	end

	table.sort(found,function(a,b) return a.score < b.score end)
	return found
end

function tactics.findCoverNear(center,threat)
	return findCover(threat,center)
end

local function stillFighting()
	local target = status:get("currentTarget")
	return myHuman.Health > 0 and target ~= nil and target ~= false
end

local function magLow()
	return status:get("mag") <= weapon.magSize*RELOAD_AT
end

local function setState(newState)
	log("cover",newState)
	state = newState
	stateSince = os.clock()
	status:set("coverState",newState)
end

local function leaveCover(reason)
	if state then
		log("cover","left cover: "..tostring(reason or "released"))
	end
	state = nil
	spot = nil
	claims[marine] = nil
	lastCoverEnd = os.clock()
	status:set("coverState",nil)
end
tactics.release = leaveCover

myHuman.Died:Connect(function()
	leaveCover("died")
end)
marine.Destroying:Connect(function()
	claims[marine] = nil
end)

local function suppressed()
	return ((_G.BloxianSuppressed or {})[marine] or 0) > os.clock()
end

local function hideTime(options)
	local scale = morale.hideScale()*(threat.current() == "auto" and AUTO_HIDE or 1)
		*(suppressed() and SUPPRESSED_HIDE or 1)
	if healthFraction() < LOW_HEALTH then
		return (HURT_HIDE_MIN + math.random()*(HURT_HIDE_MAX - HURT_HIDE_MIN))*scale
	elseif options.suppress then
		return (SUPPRESS_HIDE_MIN + math.random()*(SUPPRESS_HIDE_MAX - SUPPRESS_HIDE_MIN))*scale
	end
	return (HIDE_MIN + math.random()*(HIDE_MAX - HIDE_MIN))*scale
end

local function peekTime(options)
	local scale = suppressed() and SUPPRESSED_PEEK or 1
	if threat.current() == "long" then
		return (PEEK_TIME_MIN + math.random()*(PEEK_TIME_MAX - PEEK_TIME_MIN))*SNIPER_PEEK*scale
	end
	if healthFraction() < LOW_HEALTH then
		return HURT_PEEK_TIME*scale
	elseif options.suppress then
		return (SUPPRESS_PEEK_MIN + math.random()*(SUPPRESS_PEEK_MAX - SUPPRESS_PEEK_MIN))*scale
	end
	return (PEEK_TIME_MIN + math.random()*(PEEK_TIME_MAX - PEEK_TIME_MIN))*scale
end

--Takes up a cover spot found elsewhere (a squad bound ends in one).
function tactics.occupy(newSpot,options)
	claims[marine] = newSpot.pos
	spot = newSpot
	peeks = 0
	coverStart = os.clock()
	setState("hiding")
	stateUntil = os.clock() + hideTime(options or NO_OPTIONS)
end

local function shouldTakeCover(target,options)
	local now = os.clock()
	if now - lastSearch < SEARCH_COOLDOWN then return false end
	if options.force then return true end
	if status:get("knifeEquipped") or core.checkDist(myRoot,target) < MELEE_DISTANCE then return false end

	--Hurt or nearly dry: always.
	if healthFraction() < LOW_HEALTH or status:get("reloading") or magLow() then
		return true
	end

	--Shot, or just standing where the enemy can see him: always, however
	--recently he left cover. He fights from cover, peeking, not in the open.
	local underFire = now - damagedAt < 2
	local exposed = not tactics.isHidden(myRoot.Position,target)
	if exposed and (underFire or core.checkSight(target) and not openings.pushing()) then
		return true
	end

	if now - lastCoverEnd < COVER_COOLDOWN then return false end
	local outnumbered = #status:get("potentialTargets") >= 2 and core.checkDist(myRoot,target) > 25
	return (underFire or outnumbered) and math.random() < caution
end

--Runs for the edge of the open. True if he ran.
local lastEdgeRun = -math.huge
local function offTheOpen(target,options)
	local now = os.clock()
	if options.noPeek or now - lastEdgeRun < EDGE_COOLDOWN or againstSomething(myRoot.Position) then
		return false
	end
	lastEdgeRun = now
	local edge = tactics.findEdge(myRoot.Position,target,EDGE_RINGS[#EDGE_RINGS])
	if not edge then
		return false
	end
	log("cover","in the open, running for the edge")
	claims[marine] = edge
	chatter.cover()
	local walkSpeed = myHuman.WalkSpeed
	myHuman.WalkSpeed = SCRAMBLE_SPEED
	movement.goToPosition(edge,options.keepGoing or stillFighting,SCRAMBLE_TIMEOUT)
	if myHuman.WalkSpeed == SCRAMBLE_SPEED then
		myHuman.WalkSpeed = status:get("weaponAimed") and math.min(walkSpeed,10) or walkSpeed
	end
	return true
end

local function enterCover(target,options)
	local started = os.clock()
	lastSearch = started

	local keepGoing = options.keepGoing or stillFighting
	local candidates = findCover(target)
	if abandoned then
		for index = #candidates,1,-1 do
			if (candidates[index].pos - abandoned).Magnitude < CLAIM_SPACING then
				table.remove(candidates,index)
			end
		end
		abandoned = nil
	end
	log("coverSearch",string.format("%d cover spots found",#candidates),1)
	--A spot with no way to shoot out of it is only worth it hurt; laying down
	--fire, never.
	if not options.noPeek and (options.suppress or healthFraction() >= LOW_HEALTH) then
		local usable = {}
		for _,candidate in ipairs(candidates) do
			if candidate.peek then
				usable[#usable+1] = candidate
			end
		end
		candidates = usable
	end

	--Shot, or seen in the open, with nothing close: any wall further out will do.
	local scramble = false
	if #candidates == 0 and (os.clock() - damagedAt < 2 or core.checkSight(target)) then
		candidates = findCover(target,nil,true)
		scramble = #candidates > 0
		log("coverSearch",string.format("scrambling: %d spots further out",#candidates),1)
	end

	--He keeps his rifle on the enemy and fires on the run; scrambling, he runs flat out.
	local walkSpeed = myHuman.WalkSpeed
	if scramble then
		myHuman.WalkSpeed = SCRAMBLE_SPEED
	end
	local reached = false
	for index,candidate in ipairs(candidates) do
		if index > 3 or os.clock() - started > COVER_SEARCH_BUDGET + (scramble and SCRAMBLE_TIMEOUT or 0) then break end

		claims[marine] = candidate.pos
		if index == 1 then
			chatter.cover()
		end

		if movement.goToPosition(candidate.pos,keepGoing,scramble and SCRAMBLE_TIMEOUT or COVER_RUN_TIMEOUT) then
			tactics.occupy(candidate,options)
			reached = true
			break
		elseif not keepGoing() then
			break
		end
	end
	if scramble and myHuman.WalkSpeed == SCRAMBLE_SPEED then
		myHuman.WalkSpeed = status:get("weaponAimed") and math.min(walkSpeed,10) or walkSpeed
	end
	if reached then
		return
	end
	claims[marine] = nil

	if offTheOpen(target,options) then
		return
	end

	--Nowhere to go and being shot (special operations: just seen): down on the ground
	--and shoot back. A line squad keeps moving instead.
	if #candidates == 0 and (not anchor or sof.kind) and (os.clock() - damagedAt < 2 or sof.kind and core.checkSight(target)) then
		log("cover","no cover, going prone")
		proneUntil = os.clock() + PRONE_HOLD
		status:set("proneUntil",proneUntil)
	end
end

function tactics.active()
	return state ~= nil
end

--Whether an aircraft is his side's (a jet with a blank Settings.Team flies for Friendly).
local function isFriendlyCraft(craft)
	if craft:HasTag("BloxianVehicle") then
		return not core.isEnemyVehicle(craft)
	end
	local settings = craft:FindFirstChild("Settings")
	local teamSetting = settings and settings:FindFirstChild("Team")
	local team = craft:GetAttribute("Team") or (teamSetting and teamSetting.Value)
	return (team == "" and "Friendly" or team) == teamValue.Value
end

local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Exclude
local function airborne(craft,root)
	if craft:GetAttribute("Wrecked") or craft:GetAttribute("ShotDown") or craft:GetAttribute("Status") == "Down" then
		return false
	end
	skyParams.FilterDescendantsInstances = {craft}
	return workspace:Raycast(root.Position,Vector3.new(0,-AIRBORNE_HEIGHT,0),skyParams) == nil
end

--Every aircraft in the air, worked out once per AIR_CHECK for the whole server.
_G.BloxianAirUp = _G.BloxianAirUp or {at = -math.huge, crafts = {}}
local airUp = _G.BloxianAirUp
local function aircraftUp()
	local now = os.clock()
	if now - airUp.at >= AIR_CHECK then
		airUp.at = now
		table.clear(airUp.crafts)
		for _,tag in ipairs(AIR_TAGS) do
			for _,craft in ipairs(CollectionService:GetTagged(tag)) do
				local root = craft.PrimaryPart
				if root and craft:IsDescendantOf(workspace) and airborne(craft,root) then
					airUp.crafts[#airUp.crafts+1] = craft
				end
			end
		end
	end
	return airUp.crafts
end

--The nearest enemy aircraft up within AIR_DANGER, or nil.
local airCheckAt = -math.huge
local function findAirThreat()
	local now = os.clock()
	if now - airCheckAt < AIR_CHECK then return airThreat end
	airCheckAt = now
	local best,bestDist = nil,AIR_DANGER
	for _,craft in ipairs(aircraftUp()) do
		local root = craft.PrimaryPart
		if root then
			local offset = root.Position - myRoot.Position
			local dist = Vector3.new(offset.X,0,offset.Z).Magnitude
			if dist < bestDist and not isFriendlyCraft(craft) then
				best,bestDist = root,dist
			end
		end
	end
	return best
end

--Everyone but the AT team keeps out of an enemy tank's sight: an enemy vehicle
--(not an aircraft) within ARMOR_DANGER studs with a line to him sends him into
--cover from it, hidden and not peeking, ahead of any squad drill. With no cover
--to reach he runs ARMOR_RUN studs straight away from it. He hides at most
--ARMOR_HIDE_MAX seconds, then fights for ARMOR_FIGHT before hiding from armor
--again. The AT team and the F-4s deal with it. Checked every ARMOR_CHECK seconds.
local ARMOR_DANGER = 250
local ARMOR_RUN = 60
local AT_UNITS = {Rocketeer = true, Loader = true}
local ARMOR_HIDE_MAX = 15
local ARMOR_FIGHT = 10
local ARMOR_CHECK = 0.5

local armorCheckAt = -math.huge
local function findArmor()
	local now = os.clock()
	if now - armorCheckAt < ARMOR_CHECK then return armorThreat end
	armorCheckAt = now
	local near = {}
	for _,car in ipairs(CollectionService:GetTagged("BloxianVehicle")) do
		local root = car.PrimaryPart
		if root and car:IsDescendantOf(workspace) and not car:GetAttribute("Aircraft") and not car:GetAttribute("Wrecked")
			and (root.Position - myRoot.Position).Magnitude < ARMOR_DANGER and core.isEnemyVehicle(car) then
			near[#near+1] = {root = root, dist = (root.Position - myRoot.Position).Magnitude}
		end
	end
	table.sort(near,function(a,b) return a.dist < b.dist end)
	for _,entry in ipairs(near) do
		--The one he already hides from stays a threat while in range, seen or not.
		if entry.root == armorThreat or not tactics.isHidden(myRoot.Position,entry.root) then
			return entry.root
		end
	end
	return nil
end

local ARMOR_OPTIONS = {force = true, noPeek = true, hold = true, keepGoing = function()
	return myHuman.Health > 0
end}

--Takes cover from enemy armor, or runs from it. True while it is in charge of him.
local armorHideStart = nil
local armorFightUntil = 0
function tactics.armorCover()
	if AT_UNITS[marine:GetAttribute("Unit")] or (useCoverValue and not useCoverValue.Value) then return false end
	local now = os.clock()
	local car = now >= armorFightUntil and findArmor() or nil
	if car and armorHideStart and now - armorHideStart > ARMOR_HIDE_MAX then
		armorFightUntil = now + ARMOR_FIGHT
		car = nil
	end
	if not car then
		armorHideStart = nil
		if armorThreat then
			armorThreat = nil
			leaveCover("done hiding from armor")
		end
		return false
	end
	armorHideStart = armorHideStart or now
	if armorThreat ~= car then
		armorThreat = car
		log("cover","enemy armor, taking cover from it")
	end
	ARMOR_OPTIONS.threat = car
	if tactics.update(ARMOR_OPTIONS) then
		return true
	end
	local away = Vector3.new(myRoot.Position.X - car.Position.X,0,myRoot.Position.Z - car.Position.Z)
	if away.Magnitude > 0.5 then
		log("cover","no cover from armor, running")
		movement.navigate(myRoot.Position + away.Unit*ARMOR_RUN)
		task.wait(0.2)
		return true
	end
	return false
end

--A sniper's shot heard: hide from where it came, not peeking, at most ECHO_HIDE_MAX
--seconds, then ECHO_FIGHT seconds before one sends him into cover again.
local ECHO_HIDE_MAX = 8
local ECHO_FIGHT = 12
local ECHO_OPTIONS = {force = true, noPeek = true, hold = true, keepGoing = function()
	return myHuman.Health > 0
end}
local echoStart = nil
local echoFightUntil = 0

--True when this sends him into cover, false when he already is or won't.
function tactics.hideFromShot(root)
	if echoThreat or os.clock() < echoFightUntil then return false end
	echoThreat = root
	return true
end

--True while the cover from a sniper's shot is in charge of him.
function tactics.echoCover()
	if not echoThreat then return false end
	local now = os.clock()
	echoStart = echoStart or now
	if now - echoStart > ECHO_HIDE_MAX or not echoThreat.Parent then
		echoThreat,echoStart = nil,nil
		echoFightUntil = now + ECHO_FIGHT
		if state then
			leaveCover("done hiding from the sniper")
		end
		return false
	end
	ECHO_OPTIONS.threat = echoThreat
	return tactics.update(ECHO_OPTIONS)
end

--Whether his own side has an aircraft up anywhere.
local AIR_OPTIONS = {force = true, noPeek = true, hold = true, keepGoing = function()
	return myHuman.Health > 0
end}

--Takes cover from enemy aircraft. True while it is in charge of him. Runs
--ahead of squad drills, so it pulls soldiers out of any plan.
local airHideStart = nil
local airFightUntil = 0
local evadeGoal,evadeUntil = nil,0

--Out in the open under it: a leg across its path and away from it, never still.
local function evadeAir(craft,now)
	if not evadeGoal or now >= evadeUntil or (evadeGoal - myRoot.Position).Magnitude < 4 then
		local away = Vector3.new(myRoot.Position.X - craft.Position.X,0,myRoot.Position.Z - craft.Position.Z)
		if away.Magnitude < 1 then
			local angle = math.random()*math.pi*2
			away = Vector3.new(math.cos(angle),0,math.sin(angle))
		end
		away = away.Unit
		local across = away:Cross(Vector3.yAxis)*(math.random(2) == 1 and 1 or -1)
		evadeGoal = myRoot.Position + (away*0.5 + across).Unit*AIR_EVADE_DISTANCE
		evadeUntil = now + AIR_EVADE_LEG
	end
	movement.navigate(evadeGoal)
end

--AT teams keep hunting armor under enemy aircraft: they are the answer to them.
local AIR_IGNORE_UNITS = {Rocketeer = true, Loader = true}

function tactics.airCover()
	if AIR_IGNORE_UNITS[marine:GetAttribute("Unit") or (unitValue and unitValue.Value)] then
		return false
	end
	local now = os.clock()
	local craft = findAirThreat()
	if not craft then
		airHideStart = nil
		evadeGoal = nil
		if airThreat then
			airThreat = nil
			leaveCover("done hiding from the air")
		end
		return false
	end
	if airThreat ~= craft then
		airThreat = craft
		chatter.callout("air",nil,0.5)
		log("cover","enemy aircraft overhead, taking cover")
	end
	local canHide = now >= airFightUntil and not (useCoverValue and not useCoverValue.Value)
	if canHide then
		airHideStart = airHideStart or now
		if now - airHideStart > AIR_HIDE_MAX then
			airFightUntil = now + AIR_FIGHT
			airHideStart = nil
			if state then
				leaveCover("fighting back from the air")
			end
		else
			AIR_OPTIONS.threat = craft
			if tactics.update(AIR_OPTIONS) then
				return true
			end
		end
	end
	evadeAir(craft,now)
	return true
end

--[[
	Runs the cover routine for this tick. True when it is in charge of movement.
	options:
		force     take cover now, whatever the reason
		suppress  base of fire: hide briefly, peek long
		hold      never leave cover to push on by itself
		noPeek    stay hidden, never step out
		threat    hide from this part instead of the current target
		keepGoing called during the run to cover, false aborts it
]]
function tactics.update(options)
	options = options or NO_OPTIONS
	if useCoverValue and not useCoverValue.Value then return false end

	local target = options.threat or status:get("currentTarget")
	if not target or not target.Parent then
		if state then leaveCover("no target") end
		proneUntil = 0
		status:set("proneUntil",0)
		return false
	end

	if not state then
		local now = os.clock()
		if now < proneUntil then
			--Lying in the open: stay down and fight, longer while still being hit.
			if core.checkDist(myRoot,target) < MELEE_DISTANCE then
				proneUntil = 0
			else
				if damagedAt > proneUntil - PRONE_HOLD then
					proneUntil = damagedAt + PRONE_HOLD
				end
				status:set("proneUntil",proneUntil)
				movement.stop()
				return true
			end
			status:set("proneUntil",0)
		end
		if shouldTakeCover(target,options) then
			enterCover(target,options)
		end
		return state ~= nil or os.clock() < proneUntil
	end

	local now = os.clock()

	--Cover from an enemy he can no longer get a shot at is a place to be stuck in.
	if core.checkSight(target) then
		lastSight = now
	elseif not options.noPeek and now - math.max(lastSight,coverStart) > COVER_BLIND then
		abandoned = spot.pos
		leaveCover("lost sight of the enemy")
		return false
	end

	--Pushing on: stuck in cover too long, or the enemy is on top of him.
	if core.checkDist(myRoot,target) < MELEE_DISTANCE then
		leaveCover("enemy too close")
		return false
	end
	--The enemy reloading or healing close by is a chance to push straight away.
	if not options.hold and not magLow() and openings.pushing() then
		leaveCover("enemy busy, pushing")
		return false
	end
	if not options.hold and now - coverStart > COVER_MAX_TIME and healthFraction() >= LOW_HEALTH and not magLow()
		and tactics.notOutnumbered() and not core.checkSight(target) then
		leaveCover("pushing on")
		chatter.advance()
		return false
	end

	if state == "hiding" then
		movement.walkTo(spot.pos)

		--Top up while nobody can see him.
		if magLow() and not status:get("reloading") then
			task.spawn(actions.reload)
		end

		--The enemy moved and can see him now, find somewhere new.
		if now - stateSince > 1 and not tactics.isHidden(myRoot.Position,target) then
			leaveCover("cover blown, enemy can see this spot")
			lastSearch = -math.huge
			return false
		end

		if now >= stateUntil and spot.peek and not options.noPeek and not status:get("reloading") and not magLow() then
			peeks += 1
			if peeks > PEEKS_PER_SPOT and not options.hold then
				abandoned = spot.pos
				leaveCover("moving to a fresh spot")
				lastSearch = -math.huge
				return false
			end
			movement.goToPosition(spot.peek,stillFighting,2)
			setState("peeking")
			stateUntil = os.clock() + peekTime(options)
		end
	else
		movement.walkTo(spot.peek)

		--Back behind the wall when time is up, he is hit, or he runs dry.
		if now >= stateUntil or damagedAt > stateSince or status:get("reloading") or magLow() or options.noPeek then
			movement.goToPosition(spot.pos,stillFighting,3)
			setState("hiding")
			stateUntil = os.clock() + hideTime(options)
		end
	end

	return true
end

return tactics

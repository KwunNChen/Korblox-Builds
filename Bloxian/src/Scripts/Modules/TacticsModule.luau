local tactics = {}

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local movement = require(modules.MovementModule)
local actions = require(modules.ActionsModule)
local chatter = require(modules.ChatterModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart

local mySettings = marine.Settings
local useCoverValue = mySettings:FindFirstChild("UseCover")
local weapon = require(modules.WeaponProfiles).current

--Where to look for cover: how far out, and how many directions per ring.
local RINGS = {0, 7, 14, 22}
local DIRECTIONS = 10

--Cover only counts if the wall is this close to the spot, and the spot is at
--least this far from the enemy.
local WALL_MAX_DISTANCE = 7
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
local HIDE_MIN = 1.5
local HIDE_MAX = 3
local HURT_HIDE_MIN = 4
local HURT_HIDE_MAX = 7
local SUPPRESS_HIDE_MIN = 0.8
local SUPPRESS_HIDE_MAX = 1.5

--Seconds out on a peek: normal, hurt, and laying down a base of fire.
local PEEK_TIME_MIN = 1.5
local PEEK_TIME_MAX = 2.5
local HURT_PEEK_TIME = 1.2
local SUPPRESS_PEEK_MIN = 2
local SUPPRESS_PEEK_MAX = 3.5

--Longest he stays in cover before pushing on if healthy and loaded.
local COVER_MAX_TIME = 25

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
local spot
local stateSince = 0
local stateUntil = 0
local coverStart = 0
local lastCoverEnd = -math.huge
local lastSearch = -math.huge
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

--Whether a standing soldier at pos is out of the threat's line of fire.
function tactics.isHidden(pos,threat)
	return (blockedFrom(pos + UP_HEAD,threat))
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

--Cover spots around center (default: where he stands), nearest and least exposed first.
local function findCover(threat,center)
	local myPos = myRoot.Position
	local aroundMe = center == nil
	center = center or myPos

	local threatPos = threat.Position
	local centerThreatDist = (center - threatPos).Magnitude
	local found = {}

	for _,ring in ipairs(RINGS) do
		local steps = ring == 0 and 1 or DIRECTIONS
		for i = 1,steps do
			local pos
			if ring == 0 then
				pos = aroundMe and myPos or tactics.floor(center)
			else
				local angle = i/steps*math.pi*2
				pos = tactics.floor(center + Vector3.new(math.cos(angle)*ring,0,math.sin(angle)*ring))
			end

			if pos and anchor and (pos - anchor).Magnitude > anchorRadius then
				pos = nil
			end

			if pos then
				local threatDist = (pos - threatPos).Magnitude
				if threatDist >= MIN_THREAT_DISTANCE and threatDist <= weapon.range + 20 and not claimedByOther(pos) then
					local blocked,wallDist = blockedFrom(pos + UP_HEAD,threat)
					if blocked and wallDist <= WALL_MAX_DISTANCE and (pos == myPos or tactics.roomAt(pos)) then
						local peek = findPeek(pos,threat)
						local score = (pos - center).Magnitude
						score += math.max(centerThreatDist - threatDist,0)*1.5
						if not peek then
							score += 15
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

local function hideTime(options)
	if healthFraction() < LOW_HEALTH then
		return HURT_HIDE_MIN + math.random()*(HURT_HIDE_MAX - HURT_HIDE_MIN)
	elseif options.suppress then
		return SUPPRESS_HIDE_MIN + math.random()*(SUPPRESS_HIDE_MAX - SUPPRESS_HIDE_MIN)
	end
	return HIDE_MIN + math.random()*(HIDE_MAX - HIDE_MIN)
end

local function peekTime(options)
	if healthFraction() < LOW_HEALTH then
		return HURT_PEEK_TIME
	elseif options.suppress then
		return SUPPRESS_PEEK_MIN + math.random()*(SUPPRESS_PEEK_MAX - SUPPRESS_PEEK_MIN)
	end
	return PEEK_TIME_MIN + math.random()*(PEEK_TIME_MAX - PEEK_TIME_MIN)
end

--Takes up a cover spot found elsewhere (a squad bound ends in one).
function tactics.occupy(newSpot,options)
	claims[marine] = newSpot.pos
	spot = newSpot
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

	if now - lastCoverEnd < COVER_COOLDOWN then return false end

	local underFire = now - damagedAt < 2
	local outnumbered = #status:get("potentialTargets") >= 2 and core.checkDist(myRoot,target) > 25
	return (underFire or outnumbered) and math.random() < caution
end

local function enterCover(target,options)
	local started = os.clock()
	lastSearch = started

	local keepGoing = options.keepGoing or stillFighting
	local candidates = findCover(target)
	log("coverSearch",string.format("%d cover spots found",#candidates),1)
	--Laying down fire from a spot with no way to shoot out of it is useless.
	if options.suppress then
		local usable = {}
		for _,candidate in ipairs(candidates) do
			if candidate.peek then
				usable[#usable+1] = candidate
			end
		end
		candidates = usable
	end

	for index,candidate in ipairs(candidates) do
		if index > 3 or os.clock() - started > COVER_SEARCH_BUDGET then break end

		claims[marine] = candidate.pos
		if index == 1 then
			chatter.cover()
		end

		if movement.goToPosition(candidate.pos,keepGoing,COVER_RUN_TIMEOUT) then
			tactics.occupy(candidate,options)
			return
		elseif not keepGoing() then
			break
		end
	end
	claims[marine] = nil
end

function tactics.active()
	return state ~= nil
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
		return false
	end

	if not state then
		if shouldTakeCover(target,options) then
			enterCover(target,options)
		end
		return state ~= nil
	end

	local now = os.clock()

	--Pushing on: stuck in cover too long, or the enemy is on top of him.
	if core.checkDist(myRoot,target) < MELEE_DISTANCE then
		leaveCover("enemy too close")
		return false
	end
	if not options.hold and now - coverStart > COVER_MAX_TIME and healthFraction() >= LOW_HEALTH and not magLow() then
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

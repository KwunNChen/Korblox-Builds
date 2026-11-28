--[[
	Two-man special teams, spawned together by the spawner and linked by the
	same PairId attribute:

		Sniper team   a Sniper and his Spotter
		AT team       a Rocketeer with a Javelin and his Loader

	They work apart from squads: no chasing, investigating or wandering. The
	second man (Spotter, Loader) never leaves his leader's shoulder, even with
	an enemy close: he guards him from there. Once the leader is down, he fights
	on as an ordinary rifleman.

	The Sniper, as soon as he is put down, looks around for a perch: higher
	ground with something close around him to hide in and still a view out. He
	goes there and holds it lying prone. After a few shots, or as soon as he is
	hit, the enemy knows where he is: he calls it and moves to another perch.
	If he has had no shot at his target for a few seconds, he moves to a perch
	that has one.

	The Spotter lies down beside his sniper.

	The AT team a squad brings (AttachedTo, and its unit's SquadId) is part of
	that squad: it moves, takes cover and fights by the squad's drills, merges
	and splits with it, and the Rocketeer only stands still to fire. If he goes
	down his Loader fights on as a rifleman of the squad.

	The Rocketeer of a team on its own goes hunting (JavelinModule sets
	specialTeam.hunt): toward any enemy vehicle he hears of, or patrolling around
	where he was put down.

	Settings.Unit is "Sniper", "Spotter", "Rocketeer", "Loader" or "Infantry".
]]

local specialTeam = {}

local modules = script.Parent
local core = require(modules.CoreModule)
local movement = require(modules.MovementModule)
local status = require(modules.Status)
local log = require(modules.Troubleshoot).log
local weapon = require(modules.WeaponProfiles).current
local chatter = require(modules.ChatterModule)
local sof = require(modules.SofModule)

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local unitValue = marine.Settings:FindFirstChild("Unit")
local unit = unitValue and unitValue.Value or "Infantry"

--Each second man, and the leader he guards.
local LEADER_OF = {Spotter = "Sniper", Loader = "Rocketeer"}
local LEADERS = {Sniper = true, Rocketeer = true}

--An enemy closer than this is too close for the leader's weapon; he fights him like a rifleman.
local TOO_CLOSE = 40

--How far the second man may drift from his leader, and the spot he takes beside
--and behind him.
local GUARD_LEASH = 8
local GUARD_OFFSET = Vector3.new(4,0,3)

--Seconds a sniper stays on an enemy sniper he heard fire.
local COUNTER_TIME = 20

--How far a sniper team spots enemies; it raises Settings.DetectionRange to this.
local SPOT_RANGE = 600

--A sniper with his spotter down: the share of his shots that go true, and the
--studs off his range, until a spotter of his pair is back.
local NO_SPOTTER_ACCURACY = 0.5
local NO_SPOTTER_RANGE_LOSS = 200

--Where the sniper looks for a perch: rings this far out from where he was put
--down, this many spots on each, and how much higher than him a spot may be.
local PERCH_RINGS = {12,24,40,60,85,115}
local PERCH_DIRECTIONS = 12
local PERCH_MAX_CLIMB = 50

--How a perch is scored: per stud of height gained, per side closed in within
--CONCEAL_REACH, for a roof overhead, and taken off per stud of walking.
local HEIGHT_WEIGHT = 1
local CONCEAL_WEIGHT = 4
local OVERHEAD_WEIGHT = 6
local DISTANCE_WEIGHT = 0.15
local CONCEAL_REACH = 6

--A perch needs at least this many of 8 directions open for VIEW_REACH studs,
--seen from low eye height (LOW_EYE above where he stands), to shoot from.
local MIN_VIEWS = 3
local VIEW_REACH = 80
local LOW_EYE = Vector3.new(0,0.5,0)

--With a target to see, a perch must see it standing; seeing it from low eye height scores this much more.
local LOW_SIGHT_WEIGHT = 25

--Enemies he knows of (up to SIGHT_CHECKS of them): a perch scores ENEMY_SIGHT_WEIGHT
--for each it overlooks, and none within PERCH_STANDOFF studs of one is taken.
local ENEMY_SIGHT_WEIGHT = 10
local PERCH_STANDOFF = 100
local SIGHT_CHECKS = 6

--How many of the best perches get a path tried, and how long he walks before settling where he is.
local PERCH_PATH_TRIES = 6
local PERCH_TIMEOUT = 40

--A sniper moves to a new perch after this many shots from one, or once he is
--hit there; the new one is at least RELOCATE_MIN studs from the old.
local SHOTS_BEFORE_MOVE = 3
local RELOCATE_MIN = 25

--Seconds without a shot at a target in range before he moves for one, and
--before trying again when no perch had one.
local BLIND_TIME = 3
local BLIND_RETRY = 15

marine:SetAttribute("Unit",unit)

local detection = marine.Settings:FindFirstChild("DetectionRange")
if detection and (unit == "Sniper" or unit == "Spotter") and detection.Value < SPOT_RANGE then
	detection.Value = SPOT_RANGE
end

--Set by JavelinModule for the Rocketeer: given whether he has a target, where
--to walk now, or nil to stand.
specialTeam.hunt = nil

--Sniper and AT teams keep to themselves, unless the AT team came with a unit.
--Riflemen, special operations, and pilots on the ground, join squads.
function specialTeam.detached(model)
	local kind = model:GetAttribute("Unit")
	return kind ~= nil and kind ~= "Infantry" and kind ~= "Pilot" and not sof.UNITS[kind]
		and not model:GetAttribute("AttachedTo")
end

--The other man of this soldier's pair, alive, with the given unit; or nil.
function specialTeam.partner(wantedUnit)
	local id = marine:GetAttribute("PairId")
	if not id then return nil end
	for model,entry in pairs(_G.BloxianRadio or {}) do
		if model ~= marine and model:GetAttribute("PairId") == id and model:GetAttribute("Unit") == wantedUnit
			and entry.root.Parent and entry.human.Health > 0 then
			return entry
		end
	end
	return nil
end

local fullRange = weapon.range
local spotterDown = false

local function checkSpotter()
	local down = marine:GetAttribute("PairId") ~= nil and not specialTeam.partner("Spotter")
	if down == spotterDown then return end
	spotterDown = down
	weapon.range = down and fullRange - NO_SPOTTER_RANGE_LOSS or fullRange
	weapon.accuracy = down and NO_SPOTTER_ACCURACY or nil
	log("brain",down and "spotter down, range and accuracy cut" or "spotter back, full range and accuracy")
end

-- Sniper's perch ------------------------------------------------------------

local BODY_SIZE = Vector3.new(2,4,2)
local UP_HEAD = Vector3.new(0,1.5,0)
local overlapParams = OverlapParams.new()
overlapParams.FilterDescendantsInstances = {marine}

--Where he would stand on the highest walkable surface above (x, z), or nil.
local function standingAt(x,z,top,depth)
	local hit,result = core.raycast(Vector3.new(x,top,z),Vector3.new(0,-depth,0))
	if not hit or result.Normal.Y <= 0.7 or result.Material == Enum.Material.Water
		or core.getHuman(result.Instance.Parent) then
		return nil
	end
	local standing = result.Position + Vector3.new(0,3,0)
	for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(standing + Vector3.new(0,0.5,0)),BODY_SIZE,overlapParams)) do
		if part.CanCollide then
			return nil
		end
	end
	return standing
end

local function seesFrom(eye,target)
	local hit,result = core.raycast(eye,target.Position - eye)
	return not hit or result.Instance:IsDescendantOf(target.Parent)
end

--How good a spot is to snipe from; nil if it has no view out, or no view of threat.
local function perchScore(spot,home,threat)
	local head = spot + UP_HEAD
	local low = spot + LOW_EYE
	local closed,views = 0,0
	for i = 1,8 do
		local angle = i/8*math.pi*2
		local dir = Vector3.new(math.cos(angle),0,math.sin(angle))
		if core.raycast(head,dir*CONCEAL_REACH) then
			closed += 1
		end
		if not core.raycast(low,dir*VIEW_REACH) then
			views += 1
		end
	end
	if views < MIN_VIEWS then
		return nil
	end

	local sight = 0
	for index,enemy in ipairs(status:get("potentialTargets") or {}) do
		if index > SIGHT_CHECKS then break end
		if enemy.Parent then
			if (enemy.Position - spot).Magnitude < PERCH_STANDOFF then
				return nil
			end
			if seesFrom(head,enemy) then
				sight += ENEMY_SIGHT_WEIGHT
			end
		end
	end
	if threat then
		if seesFrom(low,threat) then
			sight += LOW_SIGHT_WEIGHT
		elseif not seesFrom(head,threat) then
			return nil
		end
	end

	local covered = core.raycast(head,Vector3.new(0,25,0))
	local height = math.clamp(spot.Y - home.Y,0,PERCH_MAX_CLIMB)
	return height*HEIGHT_WEIGHT + closed*CONCEAL_WEIGHT + (covered and OVERHEAD_WEIGHT or 0) + sight
		- (spot - home).Magnitude*DISTANCE_WEIGHT
end

--The way the view out of spot is widest: the open directions averaged, so he
--faces away from the wall he hides by. nil if there is none.
local function openFacing(spot)
	local low = spot + LOW_EYE
	local sum = Vector3.zero
	for i = 1,8 do
		local angle = i/8*math.pi*2
		local dir = Vector3.new(math.cos(angle),0,math.sin(angle))
		if not core.raycast(low,dir*VIEW_REACH) then
			sum += dir
		end
	end
	return sum.Magnitude > 0.1 and sum.Unit or nil
end

--Turns him to look along dir, unless he is aiming at someone.
local function face(dir)
	if not dir or status:get("weaponAimed") then return end
	local flat = Vector3.new(dir.X,0,dir.Z)
	if flat.Magnitude < 0.1 then return end
	if myRoot.CFrame.LookVector:Dot(flat.Unit) < 0.94 then
		myRoot.CFrame = CFrame.lookAt(myRoot.Position,myRoot.Position + flat)
	end
end

--The best perch he can walk to, or nil to stay where he is. relocating: any
--perch at least RELOCATE_MIN away beats staying. threat: a target the perch must see.
local function findPerch(relocating,threat)
	local home = myRoot.Position
	local top,depth = home.Y + PERCH_MAX_CLIMB + 3,PERCH_MAX_CLIMB + 30
	local stayScore = not relocating and perchScore(home,home,threat) or -math.huge
	local found = {}

	for _,ring in ipairs(PERCH_RINGS) do
		for i = 1,PERCH_DIRECTIONS do
			local angle = (i + ring)/PERCH_DIRECTIONS*math.pi*2
			local spot = standingAt(home.X + math.cos(angle)*ring,home.Z + math.sin(angle)*ring,top,depth)
			local score = spot and (not relocating or (spot - home).Magnitude >= RELOCATE_MIN) and perchScore(spot,home,threat)
			if score and score > stayScore then
				found[#found+1] = {spot = spot, score = score}
			end
		end
		task.wait()
	end

	table.sort(found,function(a,b) return a.score > b.score end)
	for i = 1,math.min(#found,PERCH_PATH_TRIES) do
		if marine.Parent == nil then return nil end
		if movement.findPath(found[i].spot) then
			return found[i].spot
		end
	end
	return nil
end

local perchState = "none"
local perch = nil
local perchDeadline = 0
local settledAt = 0
local settledShots = 0
local blindSince = nil
local blindRetryAt = 0
local perchFacing = nil

local function settle()
	perchState = "holding"
	settledAt = os.clock()
	settledShots = status:get("shotsFired")
	blindSince = nil
	perchFacing = openFacing(myRoot.Position)
end

local function searchPerch(relocating,threat)
	perchState = "searching"
	task.spawn(function()
		perch = findPerch(relocating,threat)
		perchDeadline = os.clock() + PERCH_TIMEOUT
		if perch then
			perchState = "moving"
			log("brain",threat and "sniper moving for a shot" or relocating and "sniper relocating" or "sniper heading for a perch")
		else
			settle()
			if threat then
				blindRetryAt = os.clock() + BLIND_RETRY
			end
			log("brain","sniper holding where he is")
		end
	end)
end

--An enemy sniper heard in range becomes his target, and he moves for a line to him.
local counterTarget = nil
local counterUntil = 0
function specialTeam.counterSnipe(root)
	if core.checkDist(root,myRoot) > weapon.range then return end
	if counterTarget ~= root or os.clock() >= counterUntil then
		chatter.callout("counterSnipe")
	end
	counterTarget = root
	counterUntil = os.clock() + COUNTER_TIME
end

local function holdCounterTarget()
	if not counterTarget or os.clock() >= counterUntil then return end
	local human = counterTarget.Parent and counterTarget.Parent:FindFirstChildOfClass("Humanoid")
	local current = status:get("currentTarget")
	if not human or human.Health <= 0 then
		counterTarget = nil
	elseif not (current and current.Parent and core.checkDist(current,myRoot) < TOO_CLOSE) then
		status:set("currentTarget",counterTarget)
	end
end

--His target, if it is in range but he has no line to it.
local function blindTarget()
	local target = status:get("currentTarget")
	if target and target.Parent and core.checkDist(target,myRoot) <= weapon.range and not core.checkSight(target) then
		return target
	end
	return nil
end

--Where the sniper is headed, or nil to hold. Starts the search the first time.
local function perchGoal()
	if perchState == "none" then
		searchPerch(false)
		return nil
	end
	if perchState == "holding" then
		local spotted = status:get("shotsFired") - settledShots >= SHOTS_BEFORE_MOVE
			or status:get("lastDamaged") > settledAt
		if spotted then
			chatter.callout("relocate")
			local target = status:get("currentTarget")
			searchPerch(true,target and target.Parent and target or nil)
			return nil
		end

		local blind = blindTarget()
		blindSince = blind and (blindSince or os.clock()) or nil
		if blind and os.clock() - blindSince >= BLIND_TIME and os.clock() >= blindRetryAt then
			chatter.callout("relocate")
			searchPerch(false,blind)
		end
		return nil
	end
	if perchState ~= "moving" then
		return nil
	end
	if (perch - myRoot.Position).Magnitude < 3 or os.clock() > perchDeadline then
		settle()
		return nil
	end
	return perch
end

-- Brain ---------------------------------------------------------------------

--True while this module moves him; false hands him back to the usual brain.
function specialTeam.update()
	local leaderUnit = LEADER_OF[unit]
	if not leaderUnit and not LEADERS[unit] then
		return false
	end

	if unit == "Sniper" then
		checkSpotter()
		holdCounterTarget()
	end

	local embedded = marine:GetAttribute("AttachedTo") ~= nil

	if leaderUnit then
		local leader = specialTeam.partner(leaderUnit)
		if not leader then
			log("brain",string.lower(leaderUnit).." down, fighting as a rifleman")
			unit = "Infantry"
			marine:SetAttribute("Unit",unit)
			status:set("teamStance",nil)
			return false
		end
		if embedded then return false end
		if (leader.root.Position - myRoot.Position).Magnitude > GUARD_LEASH then
			movement.navigate(leader.root.CFrame:PointToWorldSpace(GUARD_OFFSET))
			return true
		end
		--Prone beside a prone sniper, looking the same way.
		local leaderStance = leader.root.Parent:GetAttribute("Stance")
		status:set("teamStance",unit == "Spotter" and leaderStance == "prone" and "prone" or nil)
		if unit == "Spotter" and leaderStance == "prone" then
			face(leader.root.CFrame.LookVector)
		end
	else
		if embedded then
			if not status:get("launching") then return false end
			movement.stop()
			return true
		end
		local target = status:get("currentTarget")
		if target and target.Parent and core.checkDist(target,myRoot) < TOO_CLOSE then
			status:set("teamStance",nil)
			return false
		end

		local goal = nil
		if status:get("launching") then
			goal = nil
		elseif unit == "Sniper" then
			goal = perchGoal()
		elseif specialTeam.hunt then
			goal = specialTeam.hunt(target ~= nil and target.Parent ~= nil)
		end
		if goal then
			status:set("teamStance",nil)
			movement.navigate(goal)
			return true
		end
		status:set("teamStance",unit == "Sniper" and perchState == "holding" and "prone" or nil)
		if unit == "Sniper" and perchState == "holding" then
			face(perchFacing)
		end
	end

	movement.stop()
	return true
end

return specialTeam

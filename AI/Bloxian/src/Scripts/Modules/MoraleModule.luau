--[[
	Morale, 0 to 100, starting full.

	It drops when a friend dies near him (more the closer he was), when he is hit,
	and while he faces a crowd of enemies. It comes back with every kill he makes,
	and over time while no enemy is in sight, faster with steady friends around.

		steady   at or above SHAKEN_AT: no effect
		shaken   below SHAKEN_AT: his aim is worse and he hides longer in cover
		broken   below BROKEN_AT: he runs from the enemy, only firing at anyone
		         who gets close, until morale climbs back to RALLY_AT

	He says so when he is shaken, breaks and rallies, and those near him answer.
	The Morale and MoraleState attributes on the soldier show where he is.
]]

local morale = {}

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local movement = require(modules.MovementModule)
local chatter = require(modules.ChatterModule)
local log = require(modules.Troubleshoot).log
local sof = require(modules.SofModule)

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart
local teamValue = marine.Settings.Team

--Thresholds: shaken below SHAKEN_AT, broken below BROKEN_AT, and a broken
--soldier rallies once back up to RALLY_AT.
local SHAKEN_AT = 60
local BROKEN_AT = 25
local RALLY_AT = 50

--Losses: a friend dying within CLOSE_LOSS_RANGE, or within LOSS_RANGE; each hit
--he takes; per second facing CROWD or more enemies.
local CLOSE_LOSS_RANGE = 25
local CLOSE_LOSS = 25
local LOSS_RANGE = 70
local LOSS = 12
local HIT_LOSS = 4
local CROWD = 3
local CROWD_LOSS = 1

--Gains: each kill he makes; per second with no enemy in sight, plus per steady
--friend within FRIEND_RANGE (counting up to MAX_FRIENDS; a special operations
--soldier counts as SOF_STEADY friends).
local KILL_GAIN = 8
local RECOVER_RATE = 1.5
local FRIEND_GAIN = 1
local FRIEND_RANGE = 30
local MAX_FRIENDS = 3
local SOF_STEADY = 3

--Shaken and broken: spread multiplier on his shots, and multiplier on time hidden in cover.
local SHAKEN_SPREAD = 1.6
local BROKEN_SPREAD = 2.5
local SHAKEN_HIDE = 1.6

--Broken: he runs FLEE_DISTANCE from the threat, and only shoots anyone inside PANIC_RANGE.
local FLEE_DISTANCE = 90
local PANIC_RANGE = 25

local TICK = 0.5

local value = 100
local state = "steady"
local threatAt = nil

local function publish()
	marine:SetAttribute("Morale",math.floor(value + 0.5))
	marine:SetAttribute("MoraleState",state)
end
publish()

local function setState(newState)
	if newState == state then return end
	local old = state
	state = newState
	log("morale",string.format("%s (%d)",newState,value))
	if newState == "broken" then
		chatter.callout("broken")
	elseif newState == "shaken" and old == "steady" then
		chatter.callout("shaken",nil,0.7)
	elseif old == "broken" then
		chatter.callout("rallied")
	end
	publish()
end

local function change(amount)
	if myHuman.Health <= 0 or sof.kind then return end
	value = math.clamp(value + amount,0,100)
	if state == "broken" then
		if value >= RALLY_AT then
			setState(value >= SHAKEN_AT and "steady" or "shaken")
		end
	elseif value < BROKEN_AT then
		setState("broken")
	elseif value < SHAKEN_AT then
		setState("shaken")
	else
		setState("steady")
	end
	publish()
end

function morale.state()
	return state
end

function morale.broken()
	return state == "broken"
end

function morale.spreadScale()
	if sof.kind then return sof.SPREAD end
	return state == "broken" and BROKEN_SPREAD or state == "shaken" and SHAKEN_SPREAD or 1
end

function morale.hideScale()
	return state == "steady" and 1 or SHAKEN_HIDE
end

function morale.onKill()
	change(KILL_GAIN)
end

--Whether he may shoot at target now: broken, only at someone close.
function morale.mayShoot(target)
	return state ~= "broken" or (target and target.Parent and core.checkDist(myRoot,target) <= PANIC_RANGE)
end

--A friend died at position.
local function witnessLoss(position)
	local dist = (position - myRoot.Position).Magnitude
	if dist <= CLOSE_LOSS_RANGE then
		change(-CLOSE_LOSS)
	elseif dist <= LOSS_RANGE then
		change(-LOSS)
	else
		return
	end
	threatAt = threatAt or position
end

_G.BloxianRadio = _G.BloxianRadio or {}
local radio = _G.BloxianRadio
if radio[marine] then
	radio[marine].moraleLoss = witnessLoss
end

myHuman.Died:Connect(function()
	local at = myRoot.Position
	for other,entry in pairs(radio) do
		if other ~= marine and entry.moraleLoss and entry.human.Health > 0 and entry.team.Value == teamValue.Value then
			task.spawn(entry.moraleLoss,at)
		end
	end
end)

local lastHealth = myHuman.Health
myHuman.HealthChanged:Connect(function(health)
	if health < lastHealth and health > 0 then
		change(-HIT_LOSS)
	end
	lastHealth = health
end)

local function steadyFriendsNear()
	local count = 0
	for other,entry in pairs(radio) do
		if other ~= marine and entry.root.Parent and entry.human.Health > 0 and entry.team.Value == teamValue.Value
			and other:GetAttribute("MoraleState") ~= "broken"
			and (entry.root.Position - myRoot.Position).Magnitude <= FRIEND_RANGE then
			count += sof.kindOf(other) and SOF_STEADY or 1
			if count >= MAX_FRIENDS then break end
		end
	end
	return count
end

task.spawn(function()
	while myHuman.Health > 0 and marine.Parent do
		task.wait(TICK)
		local target = status:get("currentTarget")
		local inSight = target and target.Parent and core.checkSight(target)
		if inSight then
			threatAt = target.Position
			if #status:get("potentialTargets") >= CROWD then
				change(-CROWD_LOSS*TICK)
			end
		else
			--In a shot-up squad he only recovers to its strength (never below RALLY_AT).
			local ceiling = math.max(marine:GetAttribute("SquadStrength") or 100,RALLY_AT)
			if value < ceiling then
				change(math.min((RECOVER_RATE + FRIEND_GAIN*steadyFriendsNear())*TICK,ceiling - value))
			end
		end
	end
end)

--Broken: runs from the threat. True while it is moving him.
function morale.update()
	if state ~= "broken" then
		return false
	end
	local target = status:get("currentTarget")
	local from = target and target.Parent and target.Position or threatAt
	if not from then
		movement.stop()
		return true
	end

	local away = Vector3.new(myRoot.Position.X - from.X,0,myRoot.Position.Z - from.Z)
	local dist = away.Magnitude
	if dist >= FLEE_DISTANCE then
		movement.stop()
		return true
	end
	away = dist > 0.1 and away.Unit or -myRoot.CFrame.LookVector
	local goal = myRoot.Position + away*(FLEE_DISTANCE - dist + 20)
	local hit,result = core.raycast(goal + Vector3.new(0,40,0),Vector3.new(0,-100,0))
	movement.navigate(hit and result.Position + Vector3.new(0,3,0) or goal)
	return true
end

return morale

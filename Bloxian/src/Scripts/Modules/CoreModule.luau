local core = {}

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local modules = script.Parent
local status = require(modules.Status)

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local myHead = marine.Head
local barrel = marine.M4.Barrel

local mySettings = marine.Settings
local weapon = require(modules.WeaponProfiles).current
local detectionRange = mySettings.DetectionRange
local teamValue = mySettings.Team
local attackPlayersValue = mySettings.AttackPlayers

--Lets the spawner tool find and track every soldier.
marine:AddTag("Bloxian")

--Seconds a sight result is reused. Every loop asks about the same target.
local SIGHT_CACHE_TIME = 0.1

--Model names that are never attacked, whatever their team.
local allies = {}

--The Settings.Team that fights everyone: every player, and every soldier not on it.
local HOSTILE_TEAM = "Hostile"

--Seconds an enemy is remembered after he was last seen or heard.
local MEMORY_TIME = 10

--Hearing works through walls. Settings.HearingRange is how far he hears an
--enemy who is moving; one standing still is only heard at this share of it.
local DEFAULT_HEARING_RANGE = 120
local STILL_HEARING_SHARE = 0.5
local hearingValue = mySettings:FindFirstChild("HearingRange")

--General awareness: within Settings.AwarenessRange he always has a rough idea
--where an enemy is, through any walls, without seeing or hearing him. The fix
--is only good to within AWARENESS_ERROR studs and is refreshed every
--AWARENESS_INTERVAL seconds, so he heads for the area, not the exact spot.
local DEFAULT_AWARENESS_RANGE = 250
local AWARENESS_ERROR = 20
local AWARENESS_INTERVAL = 4
local awarenessValue = mySettings:FindFirstChild("AwarenessRange")
local roughFixes = setmetatable({},{__mode = "k"})

local lastSeen = setmetatable({},{__mode = "k"})
local lastSeenAt = setmetatable({},{__mode = "k"})

function core.markSeen(root)
	if root then
		lastSeen[root] = os.clock()
		lastSeenAt[root] = root.Position
	end
end

--Where root was when last seen, and how many seconds ago. nil if never seen.
function core.lastKnown(root)
	local seen = root and lastSeen[root]
	if not seen then return nil end
	return lastSeenAt[root],os.clock() - seen
end

--Whether he can hear root through any walls: footsteps carry, standing still is quiet.
function core.hears(root)
	local range = hearingValue and hearingValue.Value or DEFAULT_HEARING_RANGE
	local velocity = root.AssemblyLinearVelocity
	if Vector3.new(velocity.X,0,velocity.Z).Magnitude < 2 then
		range *= STILL_HEARING_SHARE
	end
	return (root.Position - myRoot.Position).Magnitude <= range
end

--Whether this soldier has any way of knowing where root is: seen lately, told
--about by a squadmate, or close enough to hear.
function core.aware(root)
	if not root or not root.Parent then return false end
	local range = awarenessValue and awarenessValue.Value or DEFAULT_AWARENESS_RANGE
	return (root.Position - myRoot.Position).Magnitude <= range
end

--Roughly where root is: the real position thrown off by up to AWARENESS_ERROR,
--held for AWARENESS_INTERVAL seconds before a new guess.
function core.roughPosition(root)
	local now = os.clock()
	local fix = roughFixes[root]
	if not fix or now - fix.time > AWARENESS_INTERVAL then
		local angle = math.random()*math.pi*2
		local offset = Vector3.new(math.cos(angle),0,math.sin(angle))*math.random()*AWARENESS_ERROR
		fix = {pos = root.Position + offset, time = now}
		roughFixes[root] = fix
	end
	return fix.pos
end

function core.knows(root,memory)
	if not root or not root.Parent then return false end

	--Hearing him counts as a fresh sighting, so he is still remembered for a
	--while after he goes quiet or moves out of earshot.
	if core.hears(root) then
		core.markSeen(root)
		return true
	end

	local seen = lastSeen[root]
	return seen ~= nil and os.clock() - seen <= (memory or MEMORY_TIME)
end

local raycastParams = RaycastParams.new()
raycastParams.FilterDescendantsInstances = {marine}

function core.checkDist(part1,part2)
	return (part1.Position - part2.Position).Magnitude
end

function core.getHuman(instance)
	if instance:IsA("Tool") or instance:IsA("Accessory") then
		instance = instance.Parent
	end

	return instance and instance:FindFirstChild("Humanoid")
end

--On a Roblox team's name he sides with that team's players and fights the
--rest; Hostile fights every player; any other name leaves it to AttackPlayers.
--Players with no team also fall back to AttackPlayers.
local function playerIsAlly(player)
	local myTeam = teamValue.Value
	if myTeam == HOSTILE_TEAM then
		return false
	end
	local robloxTeam = Teams:FindFirstChild(myTeam)
	if robloxTeam and robloxTeam:IsA("Team") and player.Team and not player.Neutral then
		return player.Team == robloxTeam
	end
	return not attackPlayersValue.Value
end

function core.isAlly(model)
	for _,ally in ipairs(allies) do
		if model.Name == ally then
			return true
		end
	end

	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return playerIsAlly(player)
	end

	local teamTag = model:FindFirstChild("Team")
	local targetTeam
	if teamTag then
		targetTeam = teamTag.Value
	else
		local settings = model:FindFirstChild("Settings")
		local settingsTeam = settings and settings:FindFirstChild("Team")
		if settingsTeam then
			targetTeam = settingsTeam.Value
		end
	end

	return targetTeam ~= nil and targetTeam == teamValue.Value
end

function core.applyDamage(human,dmg)
	if human.Health > 0 and not core.isAlly(human.Parent) then
		human:TakeDamage(dmg)
	end
end

--The vehicle (a model tagged BloxianVehicle or MarineVehicle) a part belongs to, if any.
function core.vehicleOf(instance)
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if model:HasTag("BloxianVehicle") or model:HasTag("MarineVehicle") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function crewOf(car)
	local crew = {}
	for _,name in ipairs({"VehicleSeat","Seat"}) do
		local seat = car:FindFirstChild(name)
		local occupant = seat and seat.Occupant
		if occupant and occupant.Parent and occupant.Health > 0 then
			table.insert(crew,occupant.Parent)
		end
	end
	return crew
end

--On his side when anyone aboard is, or when it is kept to his team. An empty one
--open to anyone is nobody's.
function core.isAllyVehicle(car)
	for _,member in ipairs(crewOf(car)) do
		if core.isAlly(member) then
			return true
		end
	end
	local settings = car:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	return team ~= nil and team.Value ~= "" and team.Value == teamValue.Value
end

--Worth fighting: someone aboard is an enemy and nobody aboard is a friend.
function core.isEnemyVehicle(car)
	if core.isAllyVehicle(car) then
		return false
	end
	return #crewOf(car) > 0
end

--Crewed by an enemy, or kept to a team other than his. An empty vehicle open to
--anyone is nobody's, so stray rounds never wreck one a soldier might want to take.
local function isHostileVehicle(car)
	if core.isEnemyVehicle(car) then
		return true
	end
	if core.isAllyVehicle(car) then
		return false
	end
	local settings = car:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	return team ~= nil and team.Value ~= "" and team.Value ~= teamValue.Value
end

--Rounds that hit a vehicle hurt it, scaled by its SmallArmsScale attribute (its
--armour against bullets: the Abrams barely notices them). Anti-tank weapons
--(antiTank true) ignore that armour.
function core.damageVehicle(car,dmg,antiTank)
	local human = car:FindFirstChildOfClass("Humanoid")
	if human and human.Health > 0 and isHostileVehicle(car) then
		human:TakeDamage(antiTank and dmg or dmg*(car:GetAttribute("SmallArmsScale") or 1))
	end
end

--A ray that stops on this counts as reaching the target: his body, or any part
--of the vehicle when the target is one.
local function reaches(hit,target)
	if hit:IsDescendantOf(target.Parent) then
		return true
	end
	local car = core.vehicleOf(target)
	return car ~= nil and hit:IsDescendantOf(car)
end

local function computeSight(target)
	local origin = myHead.Position
	local offset = target.Position - origin
	if offset.Magnitude < 0.001 then
		return true
	end

	--He can see as far as DetectionRange or his gun's range, whichever is longer.
	local sightRange = math.max(detectionRange.Value,weapon.range)
	local result = workspace:Raycast(origin,offset.Unit*sightRange,raycastParams)
	if not result then
		return false
	end

	local hit = result.Instance
	if reaches(hit,target) or hit.Name == "Bullet" then
		core.markSeen(target)
		return true
	end

	--Something hostile is in the way, shoot that instead.
	local human = core.getHuman(hit.Parent)
	if human and human.Health > 0 and human.RootPart and not core.isAlly(human.Parent) then
		core.markSeen(human.RootPart)
		status:set("currentTarget",human.RootPart)
		return true
	end
	return false
end

local sightCache = setmetatable({},{__mode = "k"})
function core.checkSight(target)
	if not target or not target.Parent then
		return false
	end

	local now = os.clock()
	local cached = sightCache[target]
	if cached and now - cached.time < SIGHT_CACHE_TIME then
		return cached.result
	end

	local result = computeSight(target)
	sightCache[target] = {time = now, result = result}
	return result
end

function core.checkPotentialSight(target)
	local offset = Vector3.new(target.Position.X,myHead.Position.Y,target.Position.Z) - myHead.Position
	if offset.Magnitude < 0.001 then
		return true
	end

	local dist = core.checkDist(myHead,target)
	return workspace:Raycast(myHead.Position,offset.Unit*dist,raycastParams) == nil
end

function core.raycast(origin,dir)
	local result = workspace:Raycast(origin,dir,raycastParams)
	if result then
		return true, result
	else
		return false
	end
end

--Whether a bullet from the barrel would reach the target. Only the barrel
--matters: peeking round a corner, his head can see past an edge his rifle cannot.
function core.checkShot(target)
	local barrelPos = barrel.WorldPosition
	local offset = target.Position - barrelPos
	if offset.Magnitude < 0.001 then
		return false
	end

	local result = workspace:Raycast(barrelPos,offset.Unit*(offset.Magnitude + 3),raycastParams)
	if not result then
		return false
	end
	if reaches(result.Instance,target) or result.Instance.Name == "Bullet" then
		return true
	end

	local human = core.getHuman(result.Instance.Parent)
	if human and human.Health > 0 and human.RootPart and not core.isAlly(human.Parent) then
		status:set("currentTarget",human.RootPart)
		return true
	end
	return false
end

--Where to aim so a bullet at this speed meets him: where he will be after the
--flight time, if he keeps going the way he is. Jumps are not led.
function core.leadPoint(target,origin,speed)
	local velocity = target.AssemblyLinearVelocity
	local flight = (target.Position - origin).Magnitude/speed
	return target.Position + Vector3.new(velocity.X,0,velocity.Z)*flight
end

function core.facingTarget()
	local target = status:get("currentTarget")
	if not target then
		return false
	end

	local rootPos = myRoot.Position
	local flat = Vector3.new(target.Position.X - rootPos.X,0,target.Position.Z - rootPos.Z)
	if flat.Magnitude < 0.001 then
		return true
	end

	return (myRoot.CFrame.LookVector - flat.Unit).Magnitude < 0.5
end

return core

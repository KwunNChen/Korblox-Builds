local module = {}

local Players = game:GetService("Players")

local modules = script.Parent
local status = require(modules.Status)
local core = require(modules.CoreModule)

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local myHuman = marine:FindFirstChildOfClass("Humanoid")
local rangeValue = marine.Settings.DetectionRange
local weapon = require(modules.WeaponProfiles).current

--Seconds one workspace scan is shared between every soldier in the server.
local SCAN_CACHE_TIME = 0.5

--Each scan he looks for his SIGHT_NEAREST nearest enemies and every SIGHT_SPREADth
--of the rest, a different share each scan, so nobody goes unchecked for long.
local SIGHT_NEAREST = 6
local SIGHT_SPREAD = 6
local sightTurn = 0

_G.BloxianScan = _G.BloxianScan or {time = -math.huge, list = {}}
local scanCache = _G.BloxianScan

local function addCandidate(list,seen,model)
	if not model or seen[model] or not model:IsA("Model") then return end
	local human = model:FindFirstChild("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	if human and root then
		seen[model] = true
		list[#list+1] = {model = model, human = human, root = root}
	end
end

--Players, every Bloxian (even inside folders), and any other humanoid at the top of Workspace.
local function getCandidates()
	local now = os.clock()
	if now - scanCache.time > SCAN_CACHE_TIME then
		local list,seen = {},{}
		for _,player in ipairs(Players:GetPlayers()) do
			addCandidate(list,seen,player.Character)
		end
		for soldier in pairs(_G.BloxianRadio or {}) do
			if soldier.Parent then
				addCandidate(list,seen,soldier)
			end
		end
		for _,v in ipairs(workspace:GetChildren()) do
			addCandidate(list,seen,v)
		end
		scanCache.list = list
		scanCache.time = now
	end
	return scanCache.list
end

--Someone sitting in a vehicle is fought as the vehicle: he is hidden inside it,
--and it is what takes the hits.
local function aimPart(entry)
	local seat = entry.human.SeatPart
	local car = seat and core.vehicleOf(seat)
	if car then
		return car.PrimaryPart or (car:FindFirstChild("Body") and car.Body:FindFirstChild("Body")) or entry.root
	end
	return entry.root
end

--The nearest enemy within radius he can see, or nil. For catching someone who
--walks right up on him while he is busy with another target.
function module.closeThreat(radius)
	local myPos = myRoot.Position
	local closest,closestDist = nil,radius
	for _,entry in ipairs(getCandidates()) do
		local root = entry.root
		if entry.model ~= marine and root.Parent and entry.human.Health > 0 then
			local dist = (root.Position - myPos).Magnitude
			if dist < closestDist and not core.isAlly(entry.model) and core.checkSight(root) then
				closest,closestDist = root,dist
			end
		end
	end
	return closest
end

function module.findTarget()
	--Same reach as his eyes: DetectionRange, or further if his gun outranges it
	--or the vehicle he crews spots further (its SpotRange attribute).
	local car = myHuman and myHuman.SeatPart and core.vehicleOf(myHuman.SeatPart)
	local range = math.max(rangeValue.Value,weapon.range,car and car:GetAttribute("SpotRange") or 0)
	local myPos = myRoot.Position
	local current = status:get("currentTarget")
	local potentialTargets = {}
	local activeAllies = {}
	local enemies = {}

	--Only enemies he can see, remembers, or hears count. Nobody is tracked through walls.
	local nearest,nearestSeen,nearestSensed
	local nearestDist,nearestSeenDist,nearestSensedDist = range,range,math.huge
	for _,entry in ipairs(getCandidates()) do
		local root = aimPart(entry)
		local dist = (myPos - root.Position).Magnitude
		if entry.model ~= marine and root.Parent and entry.human.Health > 0
			and not core.isAlly(entry.model) and dist < nearestSensedDist and core.aware(root) then
			nearestSensed,nearestSensedDist = root,dist
		end
		if entry.model ~= marine and root.Parent and entry.human.Health > 0
			and dist < (root == current and math.max(range,core.ENGAGED_RANGE) or range) then
			if core.isAlly(entry.model) then
				activeAllies[#activeAllies+1] = root
			else
				enemies[#enemies+1] = {root = root, dist = dist}
			end
		end
	end

	table.sort(enemies,function(a,b) return a.dist < b.dist end)
	sightTurn += 1
	for index,enemy in ipairs(enemies) do
		local root,dist = enemy.root,enemy.dist
		local seen = (index <= SIGHT_NEAREST or root == current or (index + sightTurn) % SIGHT_SPREAD == 0)
			and core.checkSight(root)
		if seen or core.knows(root) then
			potentialTargets[#potentialTargets+1] = root
			if dist < nearestDist then
				nearestDist = dist
				nearest = root
			end
			if seen and dist < nearestSeenDist then
				nearestSeenDist = dist
				nearestSeen = root
			end
		end
	end
	status:set("potentialTargets",potentialTargets)
	status:set("activeAllies",activeAllies)

	local target = nearestSeen or nearest
	status:set("currentTarget",target)

	--Nobody seen, heard or remembered, but he senses roughly where someone is:
	--that area is worth checking. It is never a target to shoot at.
	status:set("investigate",not target and nearestSensed and core.roughPosition(nearestSensed) or nil)
end

return module

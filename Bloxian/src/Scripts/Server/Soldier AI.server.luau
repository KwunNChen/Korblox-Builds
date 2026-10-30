local marine = script.Parent.Parent.Parent

------Fix network issues------
pcall(function()
	local root = marine.HumanoidRootPart
	if root:GetNetworkOwnershipAuto() then
		root:SetNetworkOwner(nil)
	end
end)

-----Settings------
local mySettings = marine.Settings

------Modules------
local modules = script.Parent.Parent.Modules
local core = require(modules.CoreModule)
local actions = require(modules.ActionsModule)
local combat = require(modules.CombatModule)
local targeting = require(modules.TargetModule)
local movement = require(modules.MovementModule)
local status = require(modules.Status)
local troubleshoot = require(modules.Troubleshoot)
local chatter = require(modules.ChatterModule)
local tactics = require(modules.TacticsModule)
local squad = require(modules.SquadModule)
local guerrilla = require(modules.GuerrillaModule)
local weapon = require(modules.WeaponProfiles).current
local vehicle = require(modules.VehicleModule)
local fireSupport = require(modules.FireSupportModule)
local specialTeam = require(modules.SpecialTeamModule)
require(modules.JavelinModule)

------Body Variables------
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart
local myHead = marine.Head

--Seconds between sweeps for attackers the target search missed.
local ATTACKER_SCAN_INTERVAL = 1

--A soldier told to hold fire still shoots back if he was hit this recently,
--or if the enemy is this close.
local SELF_DEFENSE_TIME = 3
local SELF_DEFENSE_DISTANCE = 15

------Mood------
status:set("currentFace",myHead.faceIdle)

local function alive()
	return myHuman.Health > 0 and myHuman.Parent ~= nil
end

local log = troubleshoot.log

--Seconds between target searches. Lower reacts faster, costs a few more raycasts.
local SEARCH_INTERVAL = 0.3

--Idle pauses. They end early the moment he has a target, so these only set how
--long he loiters, never how slow he is to react.
local IDLE_PAUSE = 3

local function waitUnlessTarget(seconds)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and alive() and not status:get("currentTarget") do
		task.wait(0.1)
	end
end

local function describe(target)
	if not target or not target.Parent then return "none" end
	return string.format("%s (%d studs, %s)",target.Parent.Name,math.floor(core.checkDist(myRoot,target)),
		core.checkSight(target) and "visible" or "not visible")
end

log("start",string.format("weapon="..weapon.name.." team=%s attackPlayers=%s squad=%s guerrilla=%s cover=%s",
	tostring(mySettings.Team.Value),tostring(mySettings.AttackPlayers.Value),
	tostring(mySettings:FindFirstChild("SquadTactics") and mySettings.SquadTactics.Value),
	tostring(mySettings:FindFirstChild("Guerrilla") and mySettings.Guerrilla.Value),
	tostring(mySettings:FindFirstChild("UseCover") and mySettings.UseCover.Value)))

local attackerParams = RaycastParams.new()
attackerParams.FilterDescendantsInstances = {marine}

--Seconds between sidesteps while trading fire: enough to not be a statue,
--not so often he twitches.
local SIDESTEP_INTERVAL = 2.5

--Within this range and in sight he stands his ground and shoots.
local HOLD_RANGE = 50

local lastSidestep = 0
local function movementLogic()
	local target = status:get("currentTarget")
	if not target or not target.Parent then return end

	local dist = core.checkDist(target,myRoot)
	local canSee = core.checkSight(target)

	--Knife range: close the last few studs.
	if (dist < 4 and canSee) or status:get("knifeEquipped") then
		movement.navigate(target.Position)
		return
	end

	--Out of sight or out of range: one continuous chase on the navigator.
	if not canSee or dist > HOLD_RANGE then
		movement.pathToLocation(target)
		return
	end

	--In sight and in range: hold and shoot, now and then sidestepping or backing
	--off as a single smooth move.
	if status:get("m4Equipped") and os.clock() - lastSidestep > SIDESTEP_INTERVAL then
		lastSidestep = os.clock()
		movement.navigate(dist < 20 and movement.retreat() or movement.strafe())
	end
end


local function movementLoop()
	while alive() do
		--In or heading for a vehicle first, then squad drills, lone guerrilla, plain cover.
		if vehicle.update() then
			log("brain","vehicle")
		elseif fireSupport.evacuate() then
			log("brain","clearing artillery zone")
		elseif specialTeam.update() then
			log("brain","special team holding")
		elseif squad.update() then
			log("brain","squad")
		elseif guerrilla.update() then
			log("brain","guerrilla")
		elseif tactics.update() then
			log("brain","cover")
		elseif status:get("currentTarget") then
			log("brain","chase/fight")
			movementLogic()
		elseif status:get("investigate") then
			--He senses roughly where someone is: go and look. Squadmates follow in formation.
			log("brain","investigating")
			movement.goToPosition(status:get("investigate"),function()
				return not status:get("currentTarget")
			end,4,true)
		else
			log("brain","idle")
			if mySettings.Wander.Value and math.random(4) == 3 then
				movement.walkRandom()
			end
			waitUnlessTarget(IDLE_PAUSE)
		end
		task.wait(0.1)
	end
end

local function getIncomingAttackers()

	local closest = nil
	local closestDist = math.huge
	for i = -20, 20, 2 do
		local origin = myRoot.Position + Vector3.new(-20,0,i)
		local dir = Vector3.new(40,0,0)
		troubleshoot.createBeam(origin,dir)
		local result = workspace:Raycast(origin,dir,attackerParams)
		if result then
			local human = core.getHuman(result.Instance.Parent)
			local root = human and human.RootPart
			if human and human.Health > 0 and root and not core.isAlly(human.Parent) then
				local dist = core.checkDist(root,myRoot)
				if dist < closestDist and core.checkSight(root) then
					closestDist = dist
					closest = root
				end
			end
		end
	end

	if closest then
		status:set("currentTarget",closest)
	end
end

--Dead, gone, or now on his side (a player can join his team mid-fight).
local function targetInvalid(target)
	if not target or not target.Parent then return true end
	local human = target.Parent:FindFirstChild("Humanoid")
	return not human or human.Health <= 0 or core.isAlly(target.Parent)
end

local function searchTargetLoop()
	local hadTarget = false
	local lastTarget = nil
	local nextAttackerScan = 0

	while alive() do
		if os.clock() >= nextAttackerScan then
			nextAttackerScan = os.clock() + ATTACKER_SCAN_INTERVAL
			getIncomingAttackers()
		end

		local target = status:get("currentTarget")
		if targetInvalid(target) or status:get("tookDamage") then
			status:set("tookDamage",false)
			status:set("currentTarget",nil)
			targeting.findTarget()
		elseif not core.checkSight(target) then
			targeting.findTarget()
		end

		--Call out a fresh contact so nearby soldiers turn to it.
		local newTarget = status:get("currentTarget")
		log("target",newTarget and newTarget.Parent and newTarget.Parent.Name or "none")
		--describe() raycasts, so it only runs when someone is reading the log.
		if troubleshoot.printing() then
			log("targetInfo",describe(newTarget),5)
		end
		--Only a soldier who actually sees him shouts it. One told about him by gunfire stays quiet.
		if newTarget and not hadTarget and core.checkSight(newTarget) then
			chatter.spotted(newTarget)
		elseif lastTarget and not newTarget and not targetInvalid(lastTarget) then
			chatter.lost()
		end
		hadTarget = newTarget and true or false
		lastTarget = newTarget or nil

		task.wait(SEARCH_INTERVAL)
	end
end

local function aimingLoop()
	while alive() do
		local target = status:get("currentTarget")
		if vehicle.mounted() then
			task.wait(0.3)
		elseif target then
			if core.checkSight(target) and status:get("m4Equipped") then
				actions.aim(target)
			end
		else
			waitUnlessTarget(2)
		end
		task.wait(0.1)
	end
end

--Grenades are thrown between these distances: at a group, at an enemy standing
--still in the open, or over cover at one he knows is there but has not been
--able to see for FLUSH_DELAY seconds.
local GRENADE_MIN_RANGE = 15
local GRENADE_MAX_RANGE = 70
local FLUSH_DELAY = 2

--When he last had the target in sight, for flushing him out of cover.
local lastSawTarget = 0

--Whether this is a moment for a grenade, and why. The last check is whether a
--clear arc exists at all: no throw that would bounce off a wall above the cover.
local function wantsGrenade(target,visible,distance)
	if not status:get("grenadeCool") or distance < GRENADE_MIN_RANGE or distance > GRENADE_MAX_RANGE then
		return false
	end

	local why = nil
	if visible then
		local velocity = target.AssemblyLinearVelocity
		if combat.checkCluster(target) then
			why = "group of enemies"
		elseif distance > 25 and Vector3.new(velocity.X,0,velocity.Z).Magnitude < 2 then
			why = "enemy standing still"
		end
	elseif core.knows(target) and os.clock() - lastSawTarget > FLUSH_DELAY then
		why = "flushing him out of cover"
	end

	if not why then
		return false
	end
	if not combat.canThrowAt(target) then
		log("attack","wanted a grenade ("..why.."), no clear arc",3)
		return false
	end
	return true,why
end

--Squad orders (rally, shift fire) hold fire, except in self-defence.
local function holdingFire(target)
	if not status:get("squadHoldFire") then
		return false
	end
	if os.clock() - status:get("lastDamaged") < SELF_DEFENSE_TIME then
		return false
	end
	return core.checkDist(myRoot,target) > SELF_DEFENSE_DISTANCE
end

local function attackLogic()
	local target = status:get("currentTarget")

	--The Javelin has him: the rifle is slung until the missile is away.
	if status:get("launching") then
		return
	end

	if holdingFire(target) then
		log("attack","holding fire (squad order)",2)
		if not status:get("m4Equipped") and not status:get("reloading") then
			actions.drawM4()
		end
		return
	end

	actions.updateFace("Attacking")

	local distance = core.checkDist(myRoot,target)
	if distance > 7 then

		local throw,why = wantsGrenade(target,true,distance)
		if throw then
			log("attack","throwing grenade: "..why)
			combat.throwGrenade(target)
		elseif status:get("m4Equipped") then
			if not status:get("weaponCool") then
				log("attack","weapon cooling",2)
			elseif status:get("reloading") then
				log("attack","reloading",2)
			elseif not core.facingTarget() then
				log("attack","turning to face target",2)
			elseif not core.checkShot(target) then
				log("attack","shot blocked (something between the barrel and him)",2)
			else
				log("attack","FIRING",2)
				combat.shoot(target)
			end
		else
			log("attack","drawing M4",2)
			actions.drawM4()
		end
	else
		log("attack","knife range")
		actions.drawKnife()
		combat.stab()
	end
end

local function attackLoop()
	while alive() do
		if status:get("launching") then
			task.wait(0.1)
			continue
		end

		local target = status:get("currentTarget")

		--Seated: the vehicle does the fighting (the gunner works the turret).
		while vehicle.mounted() and alive() do
			task.wait(0.3)
		end
		target = status:get("currentTarget")

		if target and target.Parent then
			actions.updateFace("Hunting")

			--If we have a target we can see
			local visible = core.checkSight(target)
			if visible then
				lastSawTarget = os.clock()
			end
			local throw,why = false,nil
			if not visible and not holdingFire(target) then
				throw,why = wantsGrenade(target,false,core.checkDist(myRoot,target))
			end

			if visible and core.checkDist(myRoot,target) < weapon.range then
				attackLogic()
			elseif throw then
				--He knows where the enemy is but cannot see him: lob one over the cover.
				log("attack","throwing grenade: "..why)
				combat.throwGrenade(target)
			else
				log("attack",core.checkSight(target) and "out of range" or "no line of sight",2)
				--Lowering and redrawing every time sight flickers looks twitchy, so a
				--soldier in cover or stalking keeps his rifle up.
				if status:get("m4Equipped") and not status:get("weaponAimed") and not tactics.active() and not status:get("stealth") then
					actions.lowerM4()
				end
			end
		else
			actions.updateFace("Idle")
			--In a squad the rifle stays at low ready on patrol. Only a soldier on
			--his own with nothing going on slings it.
			if squad.isAlone() then
				actions.yieldWeapons()
			else
				actions.readyM4()
			end
			waitUnlessTarget(2)
		end
		task.wait(0.1)
	end
end

task.spawn(troubleshoot.guard("search",searchTargetLoop))
task.spawn(troubleshoot.guard("attack",attackLoop))
task.spawn(troubleshoot.guard("movement",movementLoop))
task.spawn(troubleshoot.guard("aim",aimingLoop))

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
local radioNet = require(modules.RadioModule)
local specialTeam = require(modules.SpecialTeamModule)
local morale = require(modules.MoraleModule)
local openings = require(modules.OpeningsModule)
local threat = require(modules.ThreatModule)
local sof = require(modules.SofModule)
require(modules.JavelinModule)

------Body Variables------
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart
local myHead = marine.Head

--Seconds between sweeps for attackers the target search missed, and how close
--one has to be.
local ATTACKER_SCAN_INTERVAL = 1
local ATTACKER_RADIUS = 20

--A soldier told to hold fire still shoots back if he was hit this recently,
--or if the enemy is this close.
local SELF_DEFENSE_TIME = 15
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

--With Wander on and nothing to do, he (or his squad leader, the squad following)
--patrols: legs out to PATROL_RADIUS from where he first went idle, a pause of
--PATROL_PAUSE_MIN to PATROL_PAUSE_MAX seconds between them, a leg given up
--after PATROL_LEG_TIME.
local PATROL_RADIUS = 150
local PATROL_PAUSE_MIN = 3
local PATROL_PAUSE_MAX = 8
local PATROL_LEG_TIME = 30

local function waitUnlessTarget(seconds)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and alive() and not status:get("currentTarget") and not status:get("scramble") do
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

--Seconds between sidesteps while trading fire: enough to not be a statue,
--not so often he twitches.
local SIDESTEP_INTERVAL = 2.5

local lastSidestep = 0

--An enemy with a shotgun or a melee weapon is backed away from inside this many studs.
local STANDOFF = 40
local pushing = false
--Until when he goes after a shooter who hit a friend (onAllyShot), pushing even without the numbers.
local huntUntil = 0

--Where the enemy was last seen, or where he is if never seen.
local function lastSpot(target)
	local seenAt = core.lastKnown(target)
	return seenAt or target.Position
end
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

	--Out of sight: push only with the numbers to do it in a mass, otherwise
	--hold an angle on where he was. In sight he is fought at any range.
	if not canSee then
		if not sof.recon and (tactics.advantage() or os.clock() < huntUntil) then
			if not pushing then
				pushing = true
				chatter.advance()
			end
			movement.pathToLocation(target)
		else
			pushing = false
			tactics.holdAngle(lastSpot(target))
		end
		return
	end
	pushing = false

	--A shotgun or a blade: keep him at arm's length and shoot him from there.
	if dist < STANDOFF and threat.current() == "close" then
		movement.navigate(movement.retreat())
		return
	end

	--In sight and in range: hold and shoot, now and then sidestepping or backing
	--off as a single smooth move.
	if status:get("m4Equipped") and os.clock() - lastSidestep > SIDESTEP_INTERVAL then
		lastSidestep = os.clock()
		movement.navigate(dist < 20 and movement.retreat() or movement.strafe())
	end
end


local patrolHome = nil

local function movementLoop()
	while alive() do
		--In or heading for a vehicle first, then squad drills, lone guerrilla, plain cover.
		if vehicle.update() then
			log("brain","vehicle")
		elseif fireSupport.evacuate() then
			log("brain","clearing artillery zone")
		elseif morale.update() then
			log("brain","broken, running")
			if tactics.active() then
				tactics.release("broken")
			end
		elseif tactics.airCover() then
			log("brain","hiding from aircraft")
		elseif tactics.armorCover() then
			log("brain","hiding from armor")
		elseif tactics.echoCover() then
			log("brain","hiding from a sniper")
		elseif fireSupport.holdOutside() then
			log("brain","holding outside artillery")
		elseif specialTeam.update() then
			log("brain","special team")
		elseif sof.kind and guerrilla.update() then
			log("brain","stalking")
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
			--He senses roughly where someone is: go and look in numbers (squadmates
			--follow in formation), otherwise watch that way.
			if tactics.advantage() then
				log("brain","investigating")
				movement.goToPosition(status:get("investigate"),function()
					return not status:get("currentTarget")
				end,4,true)
			else
				log("brain","holding an angle on a sound")
				tactics.holdAngle(status:get("investigate"))
				task.wait(0.2)
			end
		elseif mySettings.Wander.Value then
			log("brain","patrolling")
			patrolHome = patrolHome or myRoot.Position
			local spot = movement.patrolPoint(patrolHome,PATROL_RADIUS)
			if spot then
				movement.goToPosition(spot,function()
					return not status:get("currentTarget") and not status:get("investigate")
				end,PATROL_LEG_TIME)
			end
			waitUnlessTarget(PATROL_PAUSE_MIN + math.random()*(PATROL_PAUSE_MAX - PATROL_PAUSE_MIN))
		else
			log("brain","idle")
			waitUnlessTarget(IDLE_PAUSE)
		end
		task.wait(0.1)
	end
end

--Shot: he turns on whoever did it, and every friend within ALLY_ALERT_RANGE who
--is not already trading shots with someone he can see goes after that shooter
--for HUNT_TIME seconds, pushing toward him even without the numbers (snipers
--and demoralized squads excepted).
--A Bloxian's rounds say who fired them (BloxianShotBy, for SHOT_BY_TIME
--seconds). A player's are worked out: the enemy player holding a tool, with a
--clear line to him, whose body faces him most squarely (at least SHOOTER_FACING,
--a dot product), out to ENGAGED_RANGE.
--Word spreads: each friend told passes it on to his own friends within
--ALLY_ALERT_RANGE, so a whole group hears of it. He passes on the same shooter
--at most once every ALERT_REPEAT seconds.
local ALLY_ALERT_RANGE = 150
local ALERT_REPEAT = 5
local HUNT_TIME = 20
local SHOT_BY_TIME = 1
local SHOOTER_FACING = 0

local Players = game:GetService("Players")
_G.BloxianShotBy = _G.BloxianShotBy or setmetatable({},{__mode = "k"})

local function guessShooter()
	local best,bestFacing = nil,SHOOTER_FACING
	for _,player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local human = character and character:FindFirstChildOfClass("Humanoid")
		local root = human and human.Health > 0 and human.RootPart
		local head = character and character:FindFirstChild("Head")
		if root and head and character:FindFirstChildOfClass("Tool") and not core.isAlly(character) then
			local toMe = myRoot.Position - head.Position
			local facing = toMe.Magnitude > 0.1 and root.CFrame.LookVector:Dot(toMe.Unit) or 0
			if facing > bestFacing and toMe.Magnitude <= core.ENGAGED_RANGE then
				local hit,result = core.raycast(head.Position,toMe)
				if not hit or (result.Position - myRoot.Position).Magnitude < 4 or result.Instance:IsDescendantOf(character) then
					best,bestFacing = root,facing
				end
			end
		end
	end
	return best
end

--Hurt by a shell or a fall this recently (BlastHitAt, FellAt): nobody to blame.
local function hurtByNobody()
	local now = workspace:GetServerTimeNow()
	return now - (marine:GetAttribute("BlastHitAt") or -math.huge) <= SHOT_BY_TIME
		or now - (marine:GetAttribute("FellAt") or -math.huge) <= SHOT_BY_TIME
end

local function shooterOf()
	local record = _G.BloxianShotBy[marine]
	if record and os.clock() - record.at <= SHOT_BY_TIME and record.root.Parent then
		local model = record.root.Parent
		local human = model:FindFirstChildOfClass("Humanoid")
		if human and human.Health > 0 and not core.isAlly(model) then
			return record.root
		end
	end
	if hurtByNobody() then return nil end
	return guessShooter()
end

--A friend nearby was shot by shooter (or recon or the radio reported him, call
--"reconTasked", "contactRelay" or "unitCall"): go after him unless busy with someone in sight.
--Recon only notes where he is.
local alertAllies
_G.BloxianAlerted = _G.BloxianAlerted or setmetatable({},{__mode = "k"})

local function onSniperHeard(shooter)
	local unit = marine:GetAttribute("Unit")
	if sof.recon then
		core.markSeen(shooter)
		guerrilla.hear(shooter)
	elseif unit == "Sniper" then
		core.markSeen(shooter)
		specialTeam.counterSnipe(shooter)
	elseif unit ~= "Spotter" then
		local current = status:get("currentTarget")
		if not (current and current.Parent and core.checkSight(current)) and tactics.hideFromShot(shooter) then
			chatter.callout("sniperHeard",nil,0.4)
		end
	end
end

local function onAllyShot(shooter,call)
	if not alive() or not shooter.Parent or core.isAlly(shooter.Parent) then return end
	if call == "sniperHeard" then
		onSniperHeard(shooter)
		return
	end
	core.markSeen(shooter)
	if call then
		status:set("radioTarget",shooter)
		status:set("radioAt",os.clock())
	else
		alertAllies(shooter)
	end
	local current = status:get("currentTarget")
	if sof.recon or current and current.Parent and core.checkSight(current) then return end
	status:set("currentTarget",shooter)
	if not tactics.holdsBack() then
		huntUntil = os.clock() + HUNT_TIME
	end
	chatter.callout(call or "findShooter",nil,0.4)
	log("target","friend shot, going after the shooter")
end
if _G.BloxianRadio and _G.BloxianRadio[marine] then
	_G.BloxianRadio[marine].allyShot = onAllyShot
end

function alertAllies(shooter)
	local heard = _G.BloxianAlerted[shooter] or setmetatable({},{__mode = "k"})
	_G.BloxianAlerted[shooter] = heard
	local now = os.clock()
	heard[marine] = now
	for other,entry in pairs(_G.BloxianRadio or {}) do
		if other ~= marine and entry.allyShot and entry.root.Parent and entry.human.Health > 0
			and entry.team.Value == mySettings.Team.Value
			and now - (heard[other] or -math.huge) >= ALERT_REPEAT
			and (entry.root.Position - myRoot.Position).Magnitude <= ALLY_ALERT_RANGE then
			heard[other] = now
			task.spawn(entry.allyShot,shooter)
		end
	end
end

local function getIncomingAttackers()
	local closest = targeting.closeThreat(ATTACKER_RADIUS)
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
		local shooter = status:get("tookDamage") and shooterOf()
		if shooter then
			status:set("tookDamage",false)
			core.markSeen(shooter)
			status:set("currentTarget",shooter)
			log("target","shot, firing back")
			alertAllies(shooter)
			radioNet.callUnits(shooter)
		elseif targetInvalid(target) then
			status:set("tookDamage",false)
			status:set("currentTarget",nil)
			targeting.findTarget()
		elseif status:get("tookDamage") then
			--Hit by nobody he can name: the enemy he is on stays his target.
			status:set("tookDamage",false)
			if not core.checkSight(target) then
				targeting.findTarget()
			end
		elseif not core.checkSight(target) then
			targeting.findTarget()
		end

		--He hears the enemy reloading or healing: push, or top off.
		openings.update()
		threat.update()

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

--Squad orders (rally, shift fire) hold fire, except in self-defence. Special
--operations hold it until engaged.
local function holdingFire(target)
	if sof.kind then
		return not sof.engaged(target)
	end
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

	if not morale.mayShoot(target) then
		log("attack","broken, running instead of shooting",2)
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
			if status:get("weaponCool") and not status:get("reloading") and core.facingTarget() and combat.launch(target,distance) then
				log("attack","M203 round out")
			elseif not status:get("weaponCool") then
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

			--A sniper team only fires at what its rifle reaches; a spotter leaves further out to the sniper.
			local unit = marine:GetAttribute("Unit")
			if visible and (unit == "Spotter" or unit == "Sniper") and core.checkDist(myRoot,target) > weapon.range then
				log("attack","spotting, out of range",2)
			elseif visible then
				attackLogic()
			elseif throw then
				--He knows where the enemy is but cannot see him: lob one over the cover.
				log("attack","throwing grenade: "..why)
				combat.throwGrenade(target)
			elseif weapon.launcher and not holdingFire(target) and status:get("m4Equipped") and status:get("weaponCool")
				and not status:get("reloading") and combat.launch(target,core.checkDist(myRoot,target)) then
				log("attack","M203 round lobbed over his cover")
			else
				log("attack",core.checkSight(target) and "out of range" or "no line of sight",2)
				--Lowering and redrawing every time sight flickers looks twitchy, so a
				--soldier in cover or stalking keeps his rifle up.
				if status:get("m4Equipped") and not status:get("weaponAimed") and not tactics.active() and not status:get("stealth")
					and not actions.isDown() and not tactics.holdingAngle() then
					actions.lowerM4()
				end
			end
		else
			actions.updateFace("Idle")
			--In a squad the rifle stays at low ready on patrol. Only a soldier on
			--his own with nothing going on slings it. Stalking, it stays up.
			if actions.isDown() or status:get("stealth") then
				actions.drawM4()
			elseif squad.isAlone() then
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

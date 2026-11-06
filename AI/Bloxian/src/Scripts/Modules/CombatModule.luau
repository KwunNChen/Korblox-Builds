local combat = {}

--Services
local runService = game:GetService("RunService")
local debrisService = game:GetService("Debris")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local targeting = require(modules.TargetModule)
local actions = require(modules.ActionsModule)
local movement = require(modules.MovementModule)
local chatter = require(modules.ChatterModule)
local troubleshoot = require(modules.Troubleshoot)
local weapon = require(modules.WeaponProfiles).current
local morale = require(modules.MoraleModule)
local sof = require(modules.SofModule)

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local myHuman = marine.Humanoid
local myHead = marine.Head

local m4 = marine.M4
local barrel = m4.Barrel
barrel.PointLight:Destroy()
local chamber = m4.Chamber
local fireSound = m4.Fire
local impact = m4.Impact
local flashes = {barrel.FlashBG.Flash1, barrel.FlashBG.Flash2, barrel.FlashBG.Flash3}

--Bullet speed and how far one flies come from the weapon profile.
local BULLET_SPEED = weapon.bulletSpeed
local BULLET_RANGE = weapon.range + 10

--A round flies this far past the target it was fired at, never short of BULLET_RANGE.
local OVERSHOOT = 50

--When the rifle points within this many degrees of the target, the round goes at
--him (plus the weapon's spread) rather than wherever the swinging rifle points.
--A weapon's own aimAssist overrides it.
local AIM_ASSIST = weapon.aimAssist or 20

--Aim gets worse: MOVING_SPREAD times while he moves faster than MOVING_SPEED
--studs/s, NEW_TARGET_SPREAD times for NEW_TARGET_TIME seconds after he turns
--on a new target, and SUPPRESSED_SPREAD times while he is pinned down.
local MOVING_SPEED = 4
local MOVING_SPREAD = 2
local NEW_TARGET_TIME = 0.6
local NEW_TARGET_SPREAD = 2
local SUPPRESSED_SPREAD = 1.5

--A round passing within SUPPRESS_RADIUS studs of the Bloxian it was fired at
--pins him down for SUPPRESS_TIME seconds (TacticsModule reads it: he hides
--longer and peeks less).
local SUPPRESS_RADIUS = 4
local SUPPRESS_TIME = 3

--Who is pinned down until when, shared by every soldier on the server. Kept off
--attributes, which would send every near miss to every player.
_G.BloxianSuppressed = _G.BloxianSuppressed or setmetatable({},{__mode = "k"})
local suppressedUntil = _G.BloxianSuppressed

--Grenade blast: anyone within GRENADE_KILL_RADIUS dies; further out he loses
--GRENADE_WOUND of his max health, falling off to nothing at GRENADE_RADIUS. Sized
--to max health so a 200 HP soldier and a 100 HP player are hurt alike.
local GRENADE_RADIUS = 16
local GRENADE_KILL_RADIUS = 5
local GRENADE_WOUND = 0.8

--The blast only reaches a body it has a clear line to (torso or head) from
--this far above where the grenade lies.
local BLAST_LIFT = Vector3.new(0,0.5,0)
local BODY_POINTS = {"Torso","UpperTorso","Head"}
local blastParams = RaycastParams.new()

--Whether a wall, floor or anything else stands between the blast and him.
local function shielded(from,human)
	local body = human.Parent
	for _,name in ipairs(BODY_POINTS) do
		local part = body:FindFirstChild(name)
		if part then
			local result = workspace:Raycast(from,part.Position - from,blastParams)
			if not result or result.Instance:IsDescendantOf(body) then
				return false
			end
		end
	end
	return true
end

--Seconds after the throw a grenade goes off even if it never touches anything.
local GRENADE_FUSE = 3

--Seconds between one soldier's grenades.
local GRENADE_COOLDOWN = 20

--Throwing. The fastest he can throw, in studs per second, and the flight times
--tried for each throw, flattest arc first, highest lob last. A higher lob is
--slower to land but clears taller cover.
local MAX_THROW_SPEED = 150
local THROW_FLIGHT_TIMES = {0.6, 0.8, 1.0, 1.2, 1.45}

--An arc only counts as clear if the first thing it touches is within this many
--studs of where it was aimed. Anything else (a wall top, a ceiling, a ledge in
--between) means it would bounce off somewhere useless, so he does not throw.
local LANDING_TOLERANCE = 7

--How many straight pieces an arc is traced in. More is more exact, and costs more raycasts.
local ARC_STEPS = 14

--Seconds a "can I land one on him from here?" answer is reused.
local THROW_PLAN_CACHE = 1

local stabAnimation = myHuman:LoadAnimation(marine.Stab)
stabAnimation.Priority = Enum.AnimationPriority.Action
local stabPunchAnimation = myHuman:LoadAnimation(marine.StabPunch)
stabPunchAnimation.Priority = Enum.AnimationPriority.Action
local throwAnimation = myHuman:LoadAnimation(marine.ThrowAnimation)
throwAnimation.Priority = Enum.AnimationPriority.Action
throwAnimation.Looped = false

status:set("mag",weapon.magSize)
fireSound.PlaybackSpeed = weapon.soundSpeed
if weapon.sound then
	fireSound.SoundId = "rbxassetid://"..weapon.sound
end

--Tracers, casings and kicked-up chunks are drawn by each client (Scripts.Client
--.BloxianEffects). The first soldier in a server puts one copy of it, switched
--on, in ReplicatedStorage; every round fired is sent through its Remote.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local effects = ReplicatedStorage:FindFirstChild("BloxianEffects")
if not effects then
	effects = modules.Parent.Client.BloxianEffects:Clone()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Remote"
	remote.Parent = effects
	effects.Enabled = true
	effects.Parent = ReplicatedStorage
end
local effectsRemote = effects:WaitForChild("Remote")

local bulletParams = RaycastParams.new()

_G.BloxianShotBy = _G.BloxianShotBy or setmetatable({},{__mode = "k"})

local function onBulletHit(flight,result)
	impact.WorldPosition = result.Position

	--A vehicle takes the hit itself (its crew only when they are hit directly).
	local car = core.vehicleOf(result.Instance)
	if car then
		core.damageVehicle(car,math.random(flight.damage[1],flight.damage[2]))
		impact.Miss:Play()
		impact.Debris:Emit(1)
		return
	end

	local human = core.getHuman(result.Instance.Parent)

	--A crewman inside is protected by his vehicle: the round hits the vehicle instead.
	local seatCar = human and human.SeatPart and human.Parent:GetAttribute("InVehicle") and core.vehicleOf(human.SeatPart)
	if seatCar then
		core.damageVehicle(seatCar,math.random(flight.damage[1],flight.damage[2]))
		impact.Miss:Play()
		return
	end

	if human and human.Health > 0 then
		--Who shot him, for him to fire back at (Soldier AI reads it).
		_G.BloxianShotBy[human.Parent] = {root = myRoot, at = os.clock()}
		core.applyDamage(human,math.random(flight.damage[1],flight.damage[2]))
		impact.Hit:Play()
		if human.Health <= 0 then
			chatter.kill()
			morale.onKill()
			targeting.findTarget()
		end
	elseif not human then
		impact.Miss:Play()
		impact.Debris:Emit(1)
	end
end

--One Heartbeat connection moves every round in flight, and only exists while
--some are. Rounds here are just a position and heading: clients draw them.
local activeBullets = {}
local flightConnection

local function stepBullets(dt)
	dt = math.min(dt,0.1)

	for i = #activeBullets, 1, -1 do
		local flight = activeBullets[i]
		local step = flight.speed*dt
		local result = workspace:Raycast(flight.position,flight.direction*step,flight.params)

		if result then
			table.remove(activeBullets,i)
			onBulletHit(flight,result)
		else
			flight.travelled += step
			if flight.travelled > flight.range then
				table.remove(activeBullets,i)
			else
				flight.position += flight.direction*step
			end
		end
	end

	if #activeBullets == 0 and flightConnection then
		flightConnection:Disconnect()
		flightConnection = nil
	end
end

--[[
	Fires one round from origin, thrown off by up to spread degrees.
	shot: damage {min,max}, speed (studs/s), range (studs), color, params
	(RaycastParams, for a turret to skip its own vehicle), ignore (what the
	clients' tracer flies through: the turret's vehicle).
	caseAt: where a spent casing comes out, if any.
]]
function combat.fireFrom(origin,spread,shot,caseAt)
	spread = math.rad(spread)
	local aimed = origin * CFrame.Angles((math.random()*2 - 1)*spread,(math.random()*2 - 1)*spread,0)
	effectsRemote:FireAllClients(aimed,shot.speed,shot.range,shot.color,shot.ignore or marine,caseAt)

	activeBullets[#activeBullets+1] = {
		position = aimed.Position,
		direction = aimed.LookVector,
		travelled = 0,
		damage = shot.damage,
		speed = shot.speed,
		range = shot.range,
		params = shot.params or bulletParams,
	}
	if not flightConnection then
		flightConnection = runService.Heartbeat:Connect(stepBullets)
	end
	return aimed
end

--How far off his best aim this shot goes, from what he is doing right now.
local aimedAt,aimedSince = nil,0
local function aimScale(target)
	local now = os.clock()
	if target ~= aimedAt then
		aimedAt,aimedSince = target,now
	end
	local velocity = myRoot.AssemblyLinearVelocity
	local scale = morale.spreadScale()
	if Vector3.new(velocity.X,0,velocity.Z).Magnitude > MOVING_SPEED then
		scale *= MOVING_SPREAD
	end
	if now - aimedSince < NEW_TARGET_TIME then
		scale *= NEW_TARGET_SPREAD
	end
	if (suppressedUntil[marine] or 0) > now then
		scale *= SUPPRESSED_SPREAD
	end
	return scale
end

--A round that passes close by a Bloxian pins him down.
local function suppress(target,aimed)
	local model = target.Parent
	if not model or not model:FindFirstChild("Settings") then return end
	local offset = target.Position - aimed.Position
	local along = offset:Dot(aimed.LookVector)
	if along > 0 and (offset - aimed.LookVector*along).Magnitude < SUPPRESS_RADIUS then
		suppressedUntil[model] = os.clock() + SUPPRESS_TIME
	end
end

local rifleShot = {damage = weapon.damage, speed = BULLET_SPEED, range = BULLET_RANGE, color = weapon.tracer}

local flashIndex = 0
function combat.shoot(target)
	if status:get("weaponCool") and not status:get("reloading") then
		status:set("weaponCool",false)
		status:set("shotsFired",status:get("shotsFired") + 1)
		chatter.shareContact(target)

		local shot = core.checkDist(target,myRoot) > weapon.farDistance and weapon.burstFar or weapon.burstNear
		for _ = 1, shot do
			task.wait(weapon.shotInterval)
			if status:get("mag") <= 0 or myHuman.Health <= 0 or not target.Parent then break end
			status:set("mag",status:get("mag")-1)

			flashIndex = flashIndex % #flashes + 1
			local flash = flashes[flashIndex]
			task.spawn(function()
				flash.Visible = true
				task.wait(0.1)
				flash.Visible = false
			end)

			--From the Barrel attachment: GunModels moves it to a longer gun's real muzzle.
			local muzzle = m4.CFrame*CFrame.new(m4.Barrel.Position)
			local aimAt = core.leadPoint(target,muzzle.Position,BULLET_SPEED)
			if muzzle.LookVector:Dot((aimAt - muzzle.Position).Unit) > math.cos(math.rad(AIM_ASSIST)) then
				muzzle = CFrame.lookAt(muzzle.Position,aimAt)
			end
			rifleShot.range = math.max(BULLET_RANGE,(target.Position - muzzle.Position).Magnitude + OVERSHOOT)
			local spread = weapon.spread*aimScale(target)
			for pellet = 1,weapon.pellets or 1 do
				suppress(target,combat.fireFrom(muzzle,spread,rifleShot,pellet == 1 and chamber.WorldCFrame or nil))
			end

			fireSound:Play()

		end

		if status:get("mag") <= 0 then
			actions.reload()
		end

		task.wait(weapon.delay)
		status:set("weaponCool",true)
	end
end

local arcParams = RaycastParams.new()
arcParams.FilterDescendantsInstances = {marine}

local function gravity()
	return Vector3.new(0,-workspace.Gravity,0)
end

--The launch velocity that carries a grenade from origin onto goal in flightTime seconds.
local function launchVelocity(origin,goal,flightTime)
	return (goal - origin - 0.5*gravity()*flightTime*flightTime)/flightTime
end

--Traces the arc in ARC_STEPS straight pieces. Clear when the first thing it
--touches is near the aim point, or it touches nothing at all.
local function arcClear(origin,velocity,flightTime,goal)
	local g = gravity()
	local previous = origin
	for i = 1,ARC_STEPS do
		local t = flightTime*i/ARC_STEPS
		local point = origin + velocity*t + 0.5*g*t*t
		local result = workspace:Raycast(previous,point - previous,arcParams)
		if result then
			return (result.Position - goal).Magnitude <= LANDING_TOLERANCE
		end
		previous = point
	end
	return true
end

--His feet: a grenade landing there rolls to a stop beside him.
local function aimPoint(target)
	return target.Position - Vector3.new(0,2.5,0)
end

--Roughly where the grenade leaves his hand: above his head, a step toward the target.
local function releasePoint(target)
	local toward = Vector3.new(target.Position.X - myRoot.Position.X,0,target.Position.Z - myRoot.Position.Z)
	toward = toward.Magnitude > 0.1 and toward.Unit or myRoot.CFrame.LookVector
	return myHead.Position + Vector3.new(0,0.5,0) + toward*1.5
end

--The flattest arc from origin that comes down on goal without clipping
--anything on the way: the launch velocity and flight time, or nil if every
--arc up to the highest lob hits a wall, roof or ledge first, or needs a throw
--harder than he can manage.
local function solveArc(origin,goal)
	for _,flightTime in ipairs(THROW_FLIGHT_TIMES) do
		local velocity = launchVelocity(origin,goal,flightTime)
		if velocity.Magnitude <= MAX_THROW_SPEED and arcClear(origin,velocity,flightTime,goal) then
			return velocity,flightTime
		end
	end
	return nil
end

local planTarget,planTime,planOk = nil,-math.huge,false

--Whether there is a clear arc onto the target from where he stands.
function combat.canThrowAt(target)
	local now = os.clock()
	if planTarget == target and now - planTime < THROW_PLAN_CACHE then
		return planOk
	end
	planTarget,planTime = target,now
	planOk = solveArc(releasePoint(target),aimPoint(target)) ~= nil
	return planOk
end

--A burst at position: hurts everyone not shielded from it. Inside killRadius
--he dies; out to radius he loses up to wound of his max health, falling off
--with distance. A hand grenade's numbers unless given.
local function blast(position,radius,killRadius,wound)
	radius = radius or GRENADE_RADIUS
	killRadius = killRadius or GRENADE_KILL_RADIUS
	wound = wound or GRENADE_WOUND
	local blastAt = position + BLAST_LIFT
	local x = Instance.new("Explosion")
	x.Position = position
	x.BlastRadius = radius
	x.BlastPressure = 0
	x.DestroyJointRadiusPercent = 0

	--Explosion.Hit fires once per part: each body is hurt once, by its closest part.
	local closest = {}
	x.Hit:Connect(function(part,partDist)
		local human = core.getHuman(part.Parent)
		if human and partDist < (closest[human] or math.huge) then
			closest[human] = partDist
		end
	end)
	x.Parent = workspace
	task.delay(0.1,function()
		for human,dist in pairs(closest) do
			if shielded(blastAt,human) then
				continue
			end
			_G.BloxianShotBy[human.Parent] = {root = myRoot, at = os.clock()}
			if dist <= killRadius then
				core.applyDamage(human,human.MaxHealth)
			else
				local falloff = 1 - (dist - killRadius)/(radius - killRadius)
				core.applyDamage(human,human.MaxHealth*wound*math.max(falloff,0))
			end
		end
	end)
	debrisService:AddItem(x,2)
end

--Underbarrel launcher (weapon.launcher): a 40mm round from the muzzle onto the
--target's feet, the flattest clear arc of these flight times (as multiples of
--the straight-shot time), up to LOB_SPEED times the launcher's speed: the higher
--ones lob over cover onto an enemy he cannot see. True if it fired.
local LOB_TIMES = {1, 1.6, 2.4, 3.2}
local LOB_SPEED = 1.4
local launcherReadyAt = 0
function combat.launch(target,distance)
	local launcher = weapon.launcher
	if not launcher or os.clock() < launcherReadyAt or distance < launcher.minRange or distance > launcher.maxRange then
		return false
	end
	local origin = (m4.CFrame*CFrame.new(m4.Barrel.Position)).Position
	local goal = aimPoint(target)
	local straight = (goal - origin).Magnitude/launcher.speed
	local velocity,flightTime
	for _,lob in ipairs(LOB_TIMES) do
		local tryVelocity = launchVelocity(origin,goal,straight*lob)
		if tryVelocity.Magnitude <= launcher.speed*LOB_SPEED and arcClear(origin,tryVelocity,straight*lob,goal) then
			velocity,flightTime = tryVelocity,straight*lob
			break
		end
	end
	if not velocity then
		return false
	end
	launcherReadyAt = os.clock() + launcher.cooldown
	status:set("weaponCool",false)

	local round = Instance.new("Part")
	round.Name = "BloxianM203Round"
	round.Size = Vector3.new(0.35,0.35,0.6)
	round.Color = Color3.fromRGB(60,70,50)
	round.CanCollide = false
	round.CanQuery = false
	round.CFrame = CFrame.lookAt(origin,origin + velocity)
	round.Parent = workspace
	round:SetNetworkOwner(nil)
	round.AssemblyLinearVelocity = velocity
	debrisService:AddItem(round,flightTime + 3)

	local thump = fireSound:Clone()
	thump.PlaybackSpeed = 0.45
	thump.Parent = m4
	thump:Play()
	debrisService:AddItem(thump,3)

	local done = false
	local function burst()
		if done or not round.Parent then return end
		done = true
		blast(round.Position,launcher.radius,0,launcher.wound)
		round:Destroy()
	end
	round.Touched:Connect(function(hit)
		if not hit:IsDescendantOf(marine) then
			burst()
		end
	end)
	task.delay(flightTime + 0.1,burst)

	task.delay(0.6,function()
		status:set("weaponCool",true)
	end)
	return true
end

function combat.throwGrenade(target)
	--No clear arc: he keeps the grenade rather than bounce it off a wall.
	local plannedVelocity = solveArc(releasePoint(target),aimPoint(target))
	if not plannedVelocity then
		return false
	end

	if status:get("weaponCool") and status:get("grenadeCool") then
		status:set("weaponCool",false)
		status:set("grenadeCool",false)
		status:beginAction()
		actions.yieldWeapons()

		local g = marine.Grenade:Clone()
		--Dead bounce and high friction, so it stops where it lands instead of skipping off.
		g.CustomPhysicalProperties = PhysicalProperties.new(1,1,0.05,100,100)
		g.Boom.PlayOnRemove = true
		g.Parent = workspace
		g.CanCollide = true
		g.CFrame = marine["Right Arm"].CFrame * CFrame.new(0,-1.3,0) * CFrame.Angles(0,0,math.rad(90))
		g:SetNetworkOwner(nil)
		debrisService:AddItem(g,GRENADE_FUSE + 5)

		marine.Grenade.Transparency = 1

		local w = Instance.new("WeldConstraint")
		w.Part0 = marine["Right Arm"]
		w.Part1 = g
		w.Parent = g

		throwAnimation:Play()
		marine.Grenade.Pin:Play()
		chatter.grenade()

		--Rotate and throw
		myHuman.AutoRotate = false
		for _ = 1,4 do
			task.wait(0.1)
			myRoot.CFrame = CFrame.lookAt(myRoot.Position,Vector3.new(target.Position.X,myRoot.Position.Y,target.Position.Z))
		end
		myHuman.AutoRotate = true

		--Killed with it in his hand: it goes with him, silently.
		if myHuman.Health <= 0 then
			g.Boom.PlayOnRemove = false
			g:Destroy()
			status:endAction()
			return
		end

		throwAnimation:Stop()

		w.Part1 = nil

		--Solve again from where the grenade really is, at where he is now. If he
		--has moved behind something new in the last moment, the planned arc stands.
		local goal = aimPoint(target)
		troubleshoot.mark(goal)
		g.AssemblyLinearVelocity = solveArc(g.Position,goal) or plannedVelocity

		local exploded = false
		local touched
		local function explode()
			if exploded or not g.Parent then return end
			exploded = true
			if touched then touched:Disconnect() end
			blast(g.Position)
			g:Destroy()
		end

		--Wait until grenade is thrown before it can be primed
		touched = g.Touched:Connect(function(obj)
			if not obj:IsDescendantOf(marine) then
				touched:Disconnect()
				g.Pin:Play()
				task.delay(0.5,explode)
			end
		end)
		task.delay(GRENADE_FUSE,explode)

		local t = Instance.new("Trail")
		t.Attachment0 = g.Attach0
		t.Attachment1 = g.Attach1
		t.Lifetime = 0.5
		t.Color = ColorSequence.new(Color3.fromRGB(150,150,150))
		t.WidthScale = NumberSequence.new(1,0)
		t.Parent = g

		task.spawn(function()
			task.wait(1)
			status:set("weaponCool",true)
			task.wait((sof.grenadeCooldown or GRENADE_COOLDOWN) - 1)
			status:set("grenadeCool",true)
			marine.Grenade.Transparency = 0
		end)

		status:endAction()
		return true
	end
	return false
end

local knife = marine.Knife
function combat.stab()
	local target = status:get("currentTarget")
	if not target or not target.Parent then
		return
	end

	status:beginAction()
	local canStab = false
	for _,v in ipairs(target.Parent:GetChildren()) do
		if v:IsA("BasePart") and core.checkDist(v,myRoot) < 7 then
			canStab = true
			break
		end
	end

	local human = target.Parent:FindFirstChild("Humanoid")
	if canStab and human then
		movement.walkTo(target.Position)

		knife.Stab:Play()
		knife.Attack:Play()

		if math.random(2) == 1 then
			stabAnimation:Play(0.1,1,2)
		else
			stabPunchAnimation:Play()
		end

		core.applyDamage(human,math.random(18,24))
		if human.Health <= 0 then
			chatter.kill("knife")
			morale.onKill()
			targeting.findTarget()
		end

		task.wait(0.5)
	else
		task.wait(0.2)
	end
	status:endAction()
end

function combat.checkCluster(target)
	--Check for nearby allies
	for _,v in ipairs(status:get("activeAllies")) do
		if core.checkDist(target,v) < 30 then
			return false
		end
	end
	--Check if enemies are paired close together
	for _,v in ipairs(status:get("potentialTargets")) do
		if v ~= target then
			if core.checkDist(target,v) < 15 then
				return true
			end
		end
	end
	return false
end


return combat

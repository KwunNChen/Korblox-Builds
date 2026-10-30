local combat = {}

--Services
local runService = game:GetService("RunService")
local debrisService = game:GetService("Debris")
local tweenService = game:GetService("TweenService")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local targeting = require(modules.TargetModule)
local actions = require(modules.ActionsModule)
local movement = require(modules.MovementModule)
local chatter = require(modules.ChatterModule)
local troubleshoot = require(modules.Troubleshoot)
local weapon = require(modules.WeaponProfiles).current

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local myHuman = marine.Humanoid
local myHead = marine.Head

local m4 = marine.M4
local barrel = m4.Barrel
local lightFlash = barrel.PointLight
local chamber = m4.Chamber
local fireSound = m4.Fire
local impact = m4.Impact
local flashes = {barrel.FlashBG.Flash1, barrel.FlashBG.Flash2, barrel.FlashBG.Flash3}

--Bullet speed and how far one flies come from the weapon profile.
local BULLET_SPEED = weapon.bulletSpeed
local BULLET_RANGE = weapon.range + 10

--When the rifle points within this many degrees of the target, the round goes at
--him (plus the weapon's spread) rather than wherever the swinging rifle points.
local AIM_ASSIST = 20

--Grenade blast: anyone within GRENADE_KILL_RADIUS dies; further out he loses
--GRENADE_WOUND of his max health, falling off to nothing at GRENADE_RADIUS. Sized
--to max health so a 200 HP soldier and a 100 HP player are hurt alike.
local GRENADE_RADIUS = 16
local GRENADE_KILL_RADIUS = 5
local GRENADE_WOUND = 0.8

--Seconds after the throw a grenade goes off even if it never touches anything.
local GRENADE_FUSE = 3

--Seconds between one soldier's grenades.
local GRENADE_COOLDOWN = 10

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

function combat.getBullet()
	local bullet = Instance.new("Part")
	bullet.Size = Vector3.new(0.1,0.1,0.3)
	bullet.Color = weapon.tracer
	bullet.Material = Enum.Material.Neon
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CanQuery = false
	bullet.CanTouch = false
	bullet.CastShadow = false
	bullet.Name = "Bullet"

	local s = Instance.new("Sound")
	s.Name = "Whiz"
	s.Volume = 0.7
	s.PlaybackSpeed = 7
	s.Looped = true
	s.SoundId = "rbxasset://sounds/Rocket whoosh 01.wav"
	s.Parent = bullet

	local a1 = Instance.new("Attachment")
	a1.Parent = bullet
	a1.Position = Vector3.new(-0.1,-0.1,0)

	local a2 = Instance.new("Attachment")
	a2.Parent = bullet
	a2.Position = Vector3.new(0.1,0.1,0)

	local t = Instance.new("Trail")
	t.Enabled = false
	t.Parent = bullet
	t.Attachment0 = a1
	t.Attachment1 = a2
	t.Color = ColorSequence.new(bullet.Color)
	t.WidthScale = NumberSequence.new(1,0)
	t.Lifetime = 0.1
	t.MinLength = 1
	t.FaceCamera = true
	return bullet
end

function combat.getCase()
	local case = Instance.new("Part")
	case.Size = Vector3.new(0.1,0.1,0.4)
	case.Material = Enum.Material.Metal
	case.CanCollide = false
	case.CanQuery = false
	case.CanTouch = false
	case.BrickColor = BrickColor.new("New Yeller")

	local fileMesh = Instance.new("FileMesh")
	fileMesh.MeshId = "rbxassetid://5435476321"
	fileMesh.TextureId = "rbxassetid://5435476346"
	fileMesh.Scale = Vector3.new(0.1,0.1,0.1)
	fileMesh.Parent = case
	return case
end

--Spent bullets are parked here and reused, so firing does not build a new
--part, sound and trail every shot.
local bulletPool = {}

local function releaseBullet(bullet)
	bullet.Transparency = 1
	bullet.Whiz:Stop()
	bullet.Trail.Enabled = false

	--Leave it in the world long enough for the trail to fade out.
	task.delay(0.2,function()
		bullet.Parent = nil
		bulletPool[#bulletPool+1] = bullet
	end)
end

local bulletParams = RaycastParams.new()

local function onBulletHit(flight,result)
	local bullet = flight.part
	bullet.CFrame = CFrame.new(result.Position)
	releaseBullet(bullet)

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
		core.applyDamage(human,math.random(flight.damage[1],flight.damage[2]))
		impact.Hit:Play()
		if human.Health <= 0 then
			chatter.kill()
			targeting.findTarget()
		end
	elseif not human then
		impact.Miss:Play()
		impact.Debris:Emit(1)
		for _ = 1, math.random(2,3) do
			local chunk = Instance.new("Part")
			chunk.Color = result.Instance.Color
			chunk.Material = result.Instance.Material
			local size = math.random(5)/20
			chunk.Size = Vector3.new(size,size,size)
			chunk.CanQuery = false
			chunk.CanTouch = false
			chunk.CFrame = CFrame.new(result.Position)
			chunk.AssemblyLinearVelocity = Vector3.new(math.random(-20,20),math.random(10,20),math.random(-20,20))
			chunk.Parent = workspace
			debrisService:AddItem(chunk,1)
		end
	end
end

--One Heartbeat connection moves every bullet in flight, and only exists while some are.
local activeBullets = {}
local flightConnection

local function stepBullets(dt)
	dt = math.min(dt,0.1)

	for i = #activeBullets, 1, -1 do
		local flight = activeBullets[i]
		local bullet = flight.part
		local cframe = bullet.CFrame
		local step = flight.speed*dt
		local result = workspace:Raycast(cframe.Position,cframe.LookVector*step,flight.params)

		if result then
			table.remove(activeBullets,i)
			onBulletHit(flight,result)
		else
			flight.travelled += step
			if flight.travelled > flight.range then
				table.remove(activeBullets,i)
				releaseBullet(bullet)
			else
				bullet.CFrame = cframe + cframe.LookVector*step
			end
		end
	end

	if #activeBullets == 0 and flightConnection then
		flightConnection:Disconnect()
		flightConnection = nil
	end
end

--[[
	Fires one pooled bullet from origin, thrown off by up to spread degrees.
	shot: damage {min,max}, speed (studs/s), range (studs), color, params
	(RaycastParams, for a turret to skip its own vehicle).
]]
function combat.fireFrom(origin,spread,shot)
	local bullet = table.remove(bulletPool) or combat.getBullet()
	spread = math.rad(spread)
	bullet.Transparency = 0
	bullet.Color = shot.color
	bullet.Trail.Color = ColorSequence.new(shot.color)
	bullet.CFrame = origin * CFrame.Angles((math.random()*2 - 1)*spread,(math.random()*2 - 1)*spread,0)
	bullet.Parent = workspace
	bullet.Trail.Enabled = true
	bullet.Whiz:Play()

	activeBullets[#activeBullets+1] = {
		part = bullet,
		travelled = 0,
		damage = shot.damage,
		speed = shot.speed,
		range = shot.range,
		params = shot.params or bulletParams,
	}
	if not flightConnection then
		flightConnection = runService.Heartbeat:Connect(stepBullets)
	end
end

local rifleShot = {damage = weapon.damage, speed = BULLET_SPEED, range = BULLET_RANGE, color = weapon.tracer}

--Bullets in the air would freeze in place if the soldier is removed mid-flight.
marine.Destroying:Connect(function()
	for _,flight in ipairs(activeBullets) do
		flight.part:Destroy()
	end
	for _,bullet in ipairs(bulletPool) do
		bullet:Destroy()
	end
end)

local flashIndex = 0
function combat.shoot(target)
	if status:get("weaponCool") and not status:get("reloading") then
		status:set("weaponCool",false)
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
				lightFlash.Enabled = true
				task.wait(0.1)
				lightFlash.Enabled = false
				flash.Visible = false
			end)

			local muzzle = m4.CFrame*CFrame.new(0,0.2,-2.5)
			local aimAt = core.leadPoint(target,muzzle.Position,BULLET_SPEED)
			if muzzle.LookVector:Dot((aimAt - muzzle.Position).Unit) > math.cos(math.rad(AIM_ASSIST)) then
				muzzle = CFrame.lookAt(muzzle.Position,aimAt)
			end
			combat.fireFrom(muzzle,weapon.spread,rifleShot)

			local case = combat.getCase()
			case.CFrame = chamber.WorldCFrame
			case.Parent = workspace
			case.AssemblyLinearVelocity = case.CFrame.RightVector * -20 * Vector3.new(1,-3,1)
			task.delay(0.05,function()
				case.CanCollide = true
			end)
			debrisService:AddItem(case,2)

			fireSound:Play()

			--Kick
			local original = m4.HingeAttach1.Position
			m4.HingeAttach1.Position = original - Vector3.new(0,0,0.2)
			tweenService:Create(m4.HingeAttach1, TweenInfo.new(0.1),{Position = original}):Play()

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

		if myHuman.Health <= 0 then
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

			local x = Instance.new("Explosion")
			x.Position = g.Position
			x.BlastRadius = GRENADE_RADIUS
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
					if dist <= GRENADE_KILL_RADIUS then
						core.applyDamage(human,human.MaxHealth)
					else
						local falloff = 1 - (dist - GRENADE_KILL_RADIUS)/(GRENADE_RADIUS - GRENADE_KILL_RADIUS)
						core.applyDamage(human,human.MaxHealth*GRENADE_WOUND*math.max(falloff,0))
					end
				end
			end)
			g:Destroy()
			debrisService:AddItem(x,2)
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
			task.wait(GRENADE_COOLDOWN - 1)
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

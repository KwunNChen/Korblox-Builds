--Y3llow Mustang 2/26/2021--

local clone = script.Parent:Clone()
--Respawns go back where it was placed, not straight into Workspace.
local homeParent = script.Parent.Parent

--Placed higher than this (studs) above the ground, it starts in the air with the
--engine running and hovers at home instead of landing there.
local AIRBORNE_HEIGHT = 10
--Blast when it hits the ground after being shot down.
local WRECK_RADIUS = 25
local WRECK_DAMAGE = 120
--Seconds the wreck takes to fade out once Settings.Respawn.Time is up.
local FADE_TIME = 1

--Network Fix--
pcall(function()
	while script.Parent.PrimaryPart:GetNetworkOwnershipAuto() do
		script.Parent.PrimaryPart:SetNetworkOwner(nil)
	end
end)

--Effects draws the missile and wreck blasts on each client from this.
local vehicleFx = Instance.new("RemoteEvent")
vehicleFx.Name = "VehicleFx"
vehicleFx.Parent = script.Parent

--Modules--
local modules = script.Parent.Modules
local core = require(modules.Core)
local combat = require(modules.Combat)
local flight = require(modules.Flight)
local pathing = require(modules.Pathing)
local troubleshoot = require(modules.Troubleshoot)
local crew = require(modules.Crew)

--Settings--
local mySettings = script.Parent.Settings
local debugOption = mySettings.Debug.Value

--Core Helicopter Parts--
local body = script.Parent.Body
local myRoot = script.Parent.HumanoidRootPart
local myHuman = script.Parent.Humanoid
myHuman.Health = myHuman.MaxHealth
while myHuman:GetState() ~= Enum.HumanoidStateType.Physics do
	myHuman:ChangeState(Enum.HumanoidStateType.Physics)
	wait()
end

--Body Mover Setup--
local bp = body.BodyPosition
bp.Position = body.Position
bp.MaxForce = Vector3.new(math.huge,math.huge,math.huge)

local bg = myRoot.BodyGyro
bg.CFrame = myRoot.CFrame
bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
bgTorque = bg.MaxTorque

--Dynamic Variables--
local dodgingObstacles = script.Parent.DodgingObstacles
local criticalAction = false
local engineRunning = false
local desiredHeight = mySettings.Height.Value

--Where the helicopter will return to--
local pitch,yaw,roll = myRoot.CFrame:ToEulerAnglesXYZ()
local home = CFrame.new(body.Position) * CFrame.fromEulerAnglesXYZ(pitch,yaw,roll)

local groundParams = RaycastParams.new()
groundParams.FilterDescendantsInstances = {script.Parent}
local below = workspace:Raycast(body.Position,Vector3.new(0,-1000,0),groundParams)
local airborne = not below or body.Position.Y - body.Size.Y/2 - below.Position.Y > AIRBORNE_HEIGHT
local starting = false
local atHome = true

--Combat Variables--
local munition = combat.resetMunition()
local lastAttack = tick()
local target = nil

if not _G.ApachePathing then
	pathing.init()
end

function takeOff()
	startEngine()
	criticalAction = true
	while flight.checkHeight(desiredHeight) == 1 do
		wait(0.2)
	end
	criticalAction = false
end

function startEngine()
	starting = true
	bp.Position = body.Position
	bp.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
	bg.CFrame = myRoot.CFrame
	bg.MaxTorque = bgTorque
	
	body.BackBladeHinge.AngularVelocity = 1000
	body.FrontBladeHinge.AngularVelocity = 1000
	local soundTween = game:GetService("TweenService"):Create(body.Sound,TweenInfo.new(5),{Volume = 1})
	soundTween:Play()
	wait(5)
	engineRunning = true
	starting = false
end

function killEngine()
	engineRunning = false
	bp.MaxForce = Vector3.new()
	body.BackBladeHinge.AngularVelocity = 0
	body.FrontBladeHinge.AngularVelocity = 0
	body.FrontBladeHinge.AngularSpeed = 0
	game:GetService("TweenService"):Create(script.Parent["Main Propeller"],TweenInfo.new(5),{AssemblyAngularVelocity = Vector3.new()}):Play()
	local soundTween = game:GetService("TweenService"):Create(body.Sound,TweenInfo.new(5),{Volume = 0})
	soundTween:Play()
	wait(5)
	bg.MaxTorque = Vector3.new()
end

function findTurns(waypoints)
	local importantWaypoints = {}
	table.insert(importantWaypoints,waypoints[1])
	
	local index = 0
	local canseeIndex = 1
	local currentWaypoint = importantWaypoints[1]
	while true do
		if canseeIndex ~= #waypoints then
			local lookCFrame = CFrame.lookAt(currentWaypoint.Position,waypoints[canseeIndex].Position)
			for offset = -15, 15, 5 do
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = {script.Parent}
				local tempCFrame = lookCFrame * CFrame.new(offset,0,0)
				local dist = core.checkDist(tempCFrame.Position,waypoints[canseeIndex])
				local result = workspace:Raycast(tempCFrame.Position,tempCFrame.LookVector*dist,params)
				
				if result then
					
					currentWaypoint = waypoints[canseeIndex]
					table.insert(importantWaypoints,waypoints[canseeIndex-1])
					break
				end
			end
			canseeIndex = canseeIndex + 1
		else
			table.insert(importantWaypoints,waypoints[canseeIndex])
			break
		end 
	end
	
	return importantWaypoints
end

function flyPath(pos)

	local waypoints = pathing.findPath(myRoot.Position,pos)
	
	if not waypoints then
		warn("No valid path to target")
		wait(30)
		return false
	end
	
	waypoints = findTurns(waypoints)

	local timeout = core.checkDist(myRoot,pos)
	local killPath = false
	if waypoints then
		for _,waypoint in ipairs(waypoints) do
			
			local currentTarget = target 
			
			--While flying to next point
			while not flight.flyToPos(waypoint.Position) and not dodgingObstacles.Value do
				
				if currentTarget ~= target or (target and not combat.getMunition(munition)) then
					killPath = true
					break
				end
				
				timeout = timeout - 1
				if timeout < 0 then
					killPath = true
					break
				end
				wait()
			end
			if killPath then
				break
			end
		end
	end
end

function combatFlight()
	atHome = false
	if core.checkSight(target) then

		local turnAngle = core.findAngle(myRoot.Position,target.Position,myRoot)
		if core.checkDistXZ(myRoot,target) > 25 then
			--Angles the helicopter to fly towards the target

			flight.flyTowards(-35,-turnAngle)
		else
			flight.flyTowards(0,-turnAngle)
		end
	else

		flyPath(target.Position)

	end

	--When too close to target fly forward to gain some distance
	if target and core.checkDistXZ(target,myRoot) < 50 then
		for i = 1, 20 do
			wait()
			flight.flyTowards(-25,0)
			if dodgingObstacles.Value then
				break
			end
		end
	end
end

function flyHome()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {script.Parent}
	local dist = (myRoot.Position-home.Position).Magnitude
	local result = workspace:Raycast(myRoot.Position,(home.Position - myRoot.Position).Unit * dist, params)
	if not result then
		if flight.flyToPos(home.Position) then

			--Hovers at home and rearms there.
			if airborne then
				flight.level()
				if not atHome then
					atHome = true
					munition = combat.resetMunition()
				end
				return
			end

			criticalAction = true
			engineRunning = false
			flight.land(home)

			--Once we completely land we are available for other missions
			if core.checkDist(home.Position,myRoot) < 30 then
				criticalAction = false 
				munition = combat.resetMunition()
				killEngine()
			end
		end
	else
		flyPath(home.Position)
	end
end

function crash()
	body.BladeAttach.Smoke.Enabled = true
	body.RearBladeAttach.Smoke.Enabled = true

	flight.flyTowards(math.random(-80,80),nil,math.random(-80,80))

	for i = 1, math.random(4,10) do

		local posX = math.random(-body.Size.X,body.Size.X)
		local posY = math.random(-body.Size.Y,body.Size.Y)
		local posZ = math.random(-body.Size.Z,body.Size.Z)/3
		local pos = Vector3.new(posX,posY,posZ)
		pos = pos/2

		local attach = Instance.new("Attachment")
		attach.Parent = body
		attach.Position = pos

		local fire = Instance.new("Fire")
		fire.Parent = attach
		fire.Size = math.random(3,8)
		fire.Heat = math.random(math.random(10,20))
		
	end

	bg.MaxTorque = Vector3.new(100,100,100)
	
	local crashSpeed = math.random(1,3)/5
	local crashed = false
	body.Touched:Connect(function(part)
		if part:GetMass() > 50 or part:IsGrounded() then
			crashed = true
		end
	end)
	local maxIterations = 200
	while not crashed do
		flight.physics()
		bp.Position = bp.Position - Vector3.new(0,crashSpeed,0)
		maxIterations = maxIterations - 1
		if maxIterations < 0 then
			break
		end
		wait()
	end
	
	body.Sound:Stop()
	bp:Destroy()
	bg:Destroy()

	body.FrontBladeHinge:Destroy()
	body.BackBladeHinge:Destroy()
	script.Parent["Main Propeller"].CanCollide = false

	--Falls the rest of the way before it goes up.
	local falling = 0
	while not crashed and falling < 5 do
		falling = falling + wait()
	end

	local crashSound = Instance.new("Sound")
	crashSound.SoundId = "rbxassetid://106375405004450"
	crashSound.Volume = 5
	crashSound.RollOffMaxDistance = 600
	crashSound.Parent = core.tempAttach(myRoot.Position, 15)
	crashSound:Play()
	
	core.blast(myRoot.Position,WRECK_RADIUS,WRECK_DAMAGE,"wreck")
end


--Collision checking--
task.spawn(function()
	while myHuman.Health > 0 do
		
		if not criticalAction and engineRunning then
			flight.checkCollisions()
		end
		
		wait()
	end
end)

--Physics and maintaining height--
task.spawn(function()
	while myHuman.Health > 0 do
		if engineRunning then
			flight.physics()
			flight.maintainHeight(desiredHeight,target)
		end
		wait()
	end
end)

--Flight priority--
task.spawn(function()
	while myHuman.Health > 0 do	
		
		if target and not engineRunning and not starting then
			takeOff()
		end
		
		if not dodgingObstacles.Value and not criticalAction then
			if target and combat.getMunition(munition) then
				combatFlight()
			elseif engineRunning then
				flyHome()
			end
		end
		
		wait(0.1)
	end
end)



--Combat loop
task.spawn(function()
	while myHuman.Health > 0 do
		
		local targetHuman = target and target.Parent and core.humanOf(target)
		if targetHuman and targetHuman.Health>0 and core.checkSight(target) and engineRunning and core.checkDist(myRoot,target) < 300 then
			
			--Keeps track of our last attack so we don't update the target within 5 seconds of attacking
			lastAttack = tick()
			
			--Prioritizes weapon based on enemy type--
			if core.modelOf(target):GetExtentsSize().Magnitude > 10 then
				munition = combat.engageVehicle(munition,target)
			else
				munition = combat.engageLight(munition,target)
			end
			
		else
			--Aims M230 and Hydra to a neutral position when not in combat
			combat.resetM230()
			combat.resetHydra()
		end
		wait(0.1)
	end
end)

--Over complicated function for instantly switching targets upon kill
local targetDeathConnection = nil
local trackedTarget = nil
function trackDeath(newTarget)
	
	if trackedTarget ~= newTarget then
		
		if targetDeathConnection then
			targetDeathConnection:Disconnect()
			targetDeathConnection = nil
		end
		
		trackedTarget = newTarget
		
		local human = core.humanOf(newTarget)
		if not human then return end
		targetDeathConnection = human.HealthChanged:Connect(function(health)
			if health > 0 then return end
			
			targetDeathConnection:Disconnect()
			targetDeathConnection = nil
			
			if combat.getMunition(munition) then
				target = core.findTarget()
				if target then
					trackDeath(target)
				end
			end
		end)
	end
end

task.spawn(function()
	while myHuman.Health > 0 do
		
		
		if combat.getMunition(munition) then
			if target then
				
				--If we have a target unless we haven't attacked in 5 seconds don't switch
				if tick() - lastAttack > 5  then
					target = core.findTarget()
				end
			else
				target = core.findTarget()
			end
			
			if target then
				--Instant target switching
				trackDeath(target)
			end
		else
			--Sets target to nil when no ammo to return home and restock
			target = nil
		end
		
		wait(1)
	end
end)
local function fadeOut()
	local info = TweenInfo.new(FADE_TIME)
	for _,part in ipairs(script.Parent:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			game:GetService("TweenService"):Create(part,info,{Transparency = 1}):Play()
		end
	end
	wait(FADE_TIME)
end

local dead = false
local function destroyed()
	if dead then return end
	dead = true
	script.Parent:SetAttribute("Wrecked",true)

	if targetDeathConnection then
		targetDeathConnection:Disconnect()
		targetDeathConnection = nil
	end

	crash()
	wait(mySettings.Respawn.Time.Value)
	fadeOut()

	if mySettings.Respawn.Value and not script.Parent:GetAttribute("NoRespawn") then
		clone.Parent = homeParent or workspace
	end
	script.Parent:Destroy()
end
myHuman.HealthChanged:Connect(function(health)
	--The crew bail out when it is badly hit, and it goes down without them.
	if health <= myHuman.MaxHealth*crew.BAIL_HEALTH and crew.aboard() then
		crew.bail()
		myHuman.Health = 0
	end
	if myHuman.Health <= 0 then
		destroyed()
	end
end)
myHuman.Died:Connect(destroyed)

crew.board()

if airborne then
	task.spawn(startEngine)
end

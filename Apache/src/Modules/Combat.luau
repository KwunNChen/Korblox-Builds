--Y3llow Mustang 2/24/21--

--Core Bits--
local myModel = script.Parent.Parent
local myRoot = myModel.HumanoidRootPart

--Fx--
local projectiles = myModel.Projectiles
local fx = myModel.Fx

--Modules--
local modules = script.Parent
local core = require(modules.Core)
local troubleshoot = require(modules.Troubleshoot)

--Settings--
local mySettings = myModel.Settings

--Services--
local debrisService = game:GetService("Debris")

--Blast radius (studs) and damage of each missile. Vehicles take the full damage
--(an Abrams has 3000 health, a Warthog 400).
local HYDRA_RADIUS = 6
local HYDRA_DAMAGE = 200
local HELLFIRE_RADIUS = 12
local HELLFIRE_DAMAGE = 1000

--M230 damage per round (random between the two); against a vehicle it is cut by
--the vehicle's SmallArmsScale.
local M230_DAMAGE = {25,50}
local M230_TRACER = Color3.fromRGB(255,40,30)


--Hydra Varibales--
local hydraMissile1 = myModel.HydraMissile1
local hydraMissile2 = myModel.HydraMissile2
local hydraCannon1 = myModel.HydraCannon1
local hydraCannon2 = myModel.HydraCannon2
local hydra1Motor = myModel.HydraCannon1.Motor
local hydra2Motor = myModel.HydraCannon2.Motor
local hydraCool = true
local hydraCooldown = 1

--M230 Variables--
local m230 = myModel.M230
local m230Barrel = m230.Barrel
local m230Mount = myModel.M230Mount
local m230bg = m230.BodyGyro

--Hellfire Variables--
local hellfire = {}
for i = 1, 8 do
	table.insert(hellfire,myModel["Hellfire"..i])
end
local currentHellfire = 1
local hellfireCool = true
local hellfireCooldown = 2

local combat = {}

function combat.getTargetLocked(pos)
	local dist = core.checkDist(myRoot,pos)
	local aimLoc = myRoot.Position + myRoot.CFrame.LookVector*dist
	troubleshoot.waypoint(aimLoc)
	if core.checkDist(aimLoc,pos) < 20 then
		return true
	end
	return false
end

function activateMissile(missile,target,explosionSize,dmg)
	
	missile.Parent = projectiles
	missile:SetNetworkOwner(nil)
	
	local pos = target.Position
	
	missile.Back.Trail.Enabled = true
	missile.Transparency = 0
	
	--Cool shooting effect
	wait(0.5)
	
	if target then
		--Calculate how much to lead the shot
		--Distance
		--Target Velocity
		--Bullet Speed
		local dist = core.checkDist(m230,target)/190
		pos = target.Position + (target.Velocity * dist)
	end
	
	missile.WeldConstraint:Destroy()
	
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
	bv.Velocity = missile.CFrame.LookVector * 200
	bv.Parent = missile

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
	bg.P = 10000
	bg.CFrame = missile.CFrame
	bg.Parent = missile
	
	debrisService:AddItem(missile,10)
	
	
	local explosionSound = missile.Explosion

	local whizSound = missile.Whiz
	
	task.spawn(function()
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {missile,myModel}

		local guidanceLength = core.checkDist(missile,pos)/10

		while true do
			game:GetService("RunService").Heartbeat:Wait()
			if guidanceLength > 0 then
				guidanceLength = guidanceLength - 1
				bg.CFrame = CFrame.lookAt(missile.Position,pos)
			end

			bv.Velocity = missile.CFrame.LookVector * 200

			local origin = missile.Position + (missile.CFrame.LookVector * (missile.Size.Z/2))
			local result = workspace:Raycast(origin,missile.CFrame.LookVector*5,rayParams)
			if result then
				core.blast(result.Position,explosionSize,dmg)

				detonate(missile,explosionSound,missile.Back.Trail)

				missile:Destroy()
				break
			end
		end
	end)
end

function detonate(missile,sound,trail)
	local attach = Instance.new("Attachment")
	attach.Parent = workspace.Terrain
	attach.WorldPosition = missile.Position
	
	trail.Parent = attach
	trail.Enabled = false
	
	sound.Parent = attach
	sound:Play()
	
	game:GetService("Debris"):AddItem(attach,sound.TimeLength)
end

function combat.missileUsable(pos)
	local targetAngle = core.findAngle(myRoot.Position,pos,myRoot)
	if targetAngle < 45 and targetAngle > -45 then
		return true
	end
	return false
end

function combat.aimHydra(pos)
	
	if typeof(pos) == "Vector3" then
		
		local pitch = core.findPitch(myRoot.Position,pos,myRoot)
		
		pitch = math.clamp(pitch/100,-0.5,0.2)
		
		
		hydra1Motor.DesiredAngle = pitch
		hydra2Motor.DesiredAngle = pitch
		
		
	else
		hydra1Motor.DesiredAngle = pos
		hydra2Motor.DesiredAngle = pos
	end
end

function combat.resetHydra()
	hydra1Motor.DesiredAngle = 0
	hydra2Motor.DesiredAngle = 0
end

function combat.fireHydra(munition,target)
	
	if not hydraCool then return munition.hydra end
	
	hydraCool = false
	task.spawn(function() wait(hydraCooldown) hydraCool = true end)
	
	if not mySettings.Ammo.Infinite.Value then
		munition.hydra = munition.hydra - 1
	end
	
	local missile
	
	if munition.hydra % 2 == 0 then
		missile = hydraMissile1:Clone()
	else
		missile = hydraMissile2:Clone()
	end
	
	--Missile, Target Position, Explosion Size, Damage to human
	activateMissile(missile,target,HYDRA_RADIUS,HYDRA_DAMAGE)
	
	return munition.hydra
end

function combat.fireHellfire(munition,target)
	if not hellfireCool then return munition.hellfire end
	hellfireCool = false
	task.spawn(function() wait(hellfireCooldown) hellfireCool = true end)

	local missile = hellfire[currentHellfire]:Clone()
	if not mySettings.Ammo.Infinite.Value then
		munition.hellfire = munition.hellfire - 1

		hellfire[currentHellfire].Transparency = 1

		--Cycle through available hellfire missiles
		currentHellfire = currentHellfire + 1
		if currentHellfire > #hellfire then
			currentHellfire = 1
		end
	end

	

	--Missile, Target Position, Explosion Size, Damage to human
	activateMissile(missile,target,HELLFIRE_RADIUS,HELLFIRE_DAMAGE)

	return munition.hellfire
end

function combat.aimM230(pos)
	local distOffset = core.checkDist(m230.Position,pos)/41
	m230bg.CFrame = CFrame.lookAt(m230.Position,pos-Vector3.new(0,distOffset,0))
end

function combat.resetM230()
	m230bg.CFrame = myRoot.CFrame
end


local particleFlash = {m230Barrel.Flash1,m230Barrel.Flash2,m230Barrel.Flash3}
local currentFlash = 1
local lightFlash = m230Barrel.PointLight
function combat.fireM230(munition,target)
	
	--Calculate how much to lead the shot
	--Distance
	--Target Velocity
	--Bullet Speed
	local dist = core.checkDist(m230,target)/300
	local aim = target.Position + (target.Velocity * dist)
	
	local lookTarget = CFrame.new(m230.Position,aim).LookVector
	local currentLook = m230.CFrame.LookVector
	
	if (lookTarget - currentLook).Magnitude > 0.1 then
		return munition.m230
	end
	
	if not mySettings.Ammo.Infinite.Value then
		munition.m230 = munition.m230 - 1
	end
	
	
	local bullet = Instance.new("Part")
	bullet.CanCollide = false
	bullet.Size = Vector3.new(0.2,0.2,0.5)
	bullet.Material = Enum.Material.Neon
	bullet.Color = M230_TRACER
	bullet.Parent = projectiles
	bullet.CFrame = m230.Barrel.WorldCFrame
	bullet.CFrame = CFrame.lookAt(bullet.Position,aim)
	bullet.Anchored = true
	
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0.05,0,0.05)
	a0.Parent = bullet

	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-0.05,0,-0.05)
	a1.Parent = bullet

	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new(bullet.Color)
	trail.WidthScale = NumberSequence.new(1,0)
	trail.Lifetime = 0.2
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.Parent = bullet
	
	task.spawn(function()
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {myModel}
		game:GetService("RunService").Heartbeat:Wait()
		while true do
			
			game:GetService("RunService").Heartbeat:Wait()
			
			local startPos = bullet.Position
			local dir = bullet.CFrame.LookVector*5
			local result = workspace:Raycast(startPos,dir,rayParams)
			
			bullet.Position = bullet.Position + dir
			
			if result then
				
				if core.ownerOf(result.Instance) then
					core.damage(result.Instance,math.random(M230_DAMAGE[1],M230_DAMAGE[2]),true)
					core.playSound(fx.Hit,result.Position)
				else
					core.playSound(fx.Miss,result.Position)
					for i = 1, math.random(5,10) do
						local chunk = Instance.new("Part")
						chunk.Color = result.Instance.Color
						chunk.Material = result.Instance.Material
						local size = math.random(5)/10
						chunk.Size = Vector3.new(size,size,size)
						chunk.CFrame = CFrame.new(result.Position)
						chunk.Velocity = Vector3.new(math.random(-20,20),math.random(10,20),math.random(-20,20))
						chunk.Parent = workspace
						game:GetService("Debris"):AddItem(chunk,1)
					end
				end
				
				bullet:Destroy()
				break
			end
			
		end
	end)
	
	debrisService:AddItem(bullet,10)
	
	--Fx Sounds and Flashes--
	currentFlash += 1 
	if currentFlash > 3 then currentFlash = 1 end
	particleFlash[currentFlash]:Emit(1)
	
	lightFlash.Enabled = true
	task.spawn(function() wait() lightFlash.Enabled = false end)
	
	local shotSound = m230.Barrel.Shoot:Clone()
	shotSound.Parent = m230.Barrel
	shotSound:Play()
	debrisService:AddItem(shotSound,shotSound.TimeLength)
	
	return munition.m230
end

--Logic for attacking larger than normal targets--
--Prioritizes using missiles then resorts to the m230--
function combat.engageVehicle(munition,target)
	local pos = target.Position
	if combat.missileUsable(pos) then
		if munition.hellfire > 0 then
			munition.hellfire = combat.fireHellfire(munition,target)
			return munition
		elseif munition.hydra > 0 then
			combat.aimHydra(pos)
			munition.hydra = combat.fireHydra(munition,target)
			return munition
		end
	end
	if munition.m230 > 0 and myRoot.Position.Y > pos.Y then
		combat.aimM230(pos)
		munition.m230 = combat.fireM230(munition,target)
	end
	return munition
end

--Logic for attacking foot soldiers and small targets--
--Prioritizes Hydra and M23000
function combat.engageLight(munition,target)
	local pos = target.Position
	if combat.missileUsable(pos) and math.random(20) == 1 and munition.hydra > 0 then
		combat.aimHydra(pos)
		munition.hydra = combat.fireHydra(munition,target)
		return munition
	elseif munition.m230 > 0 and myRoot.Position.Y > pos.Y then
		combat.aimM230(pos)
		munition.m230 = combat.fireM230(munition,target)
		return munition
	end
	
	if munition.m230 <= 0 and munition.hydra <= 0 then
		if munition.hellfire > 0 then
			if combat.missileUsable(pos) then
				munition.hellfire = combat.fireHellfire(munition,target)
			end
		end
	end
	return munition
end

function combat.getMunition(munition)
	if munition.hydra > 0 or munition.m230 > 0 or munition.hellfire > 0 then
		return true
	end
	return false
end

function combat.resetMunition()
	local munition = {
		m230 = mySettings.Ammo.M230.Value,
		hydra = mySettings.Ammo.Hydra.Value, --38
		hellfire = mySettings.Ammo.Hellfire.Value --8
	}
	
	--Restore Hellfire missile transparency--
	for _,missile in ipairs(hellfire) do
		missile.Transparency = 1
	end
	for i = 1, math.clamp(munition.hellfire,0,8) do
		hellfire[i].Transparency = 0
	end
	
	currentHellfire = 1
	
	return munition
end

return combat

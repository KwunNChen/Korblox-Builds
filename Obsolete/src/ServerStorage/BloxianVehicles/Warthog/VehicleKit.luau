--[[
	What every vehicle and aircraft package does the same way, one copy built into
	each (a child named VehicleKit, next to a Sides):

		protect / unprotect   crew armour while seated
		personOf, vehicleOf   what a part belongs to
		canHurt, hurt         people a vehicle's guns, blasts and treads may hurt
		canHurtVehicle        vehicles they may hurt
		engulf, wreck         an aircraft going down in flames, and its wreck
		parachute             a crewman bailing out
		blastFx               Random Arty's impact, or a plain explosion without it
]]

local players = game:GetService("Players")
local debris = game:GetService("Debris")
local serverStorage = game:GetService("ServerStorage")
local tweenService = game:GetService("TweenService")

local sides = require(script.Parent:WaitForChild("Sides"))

local kit = {}

-- Crew armour ---------------------------------------------------------------

--The crew are not hurt while inside: nothing gets to them until they get out or
--the vehicle goes up, which kills them. A hidden ForceField stops anything that
--uses TakeDamage, damage that sets Health directly is undone, and the InVehicle
--attribute tells Random Arty, the gas and the Bloxians to pass them over.
local protected = {}

function kit.protect(human)
	local character = human.Parent
	if protected[human] or not character then return end
	local shield = Instance.new("ForceField")
	shield.Name = "VehicleArmor"
	shield.Visible = false
	shield.Parent = character
	character:SetAttribute("InVehicle",true)
	local kept = human.Health
	local guard = human.HealthChanged:Connect(function(health)
		if health >= kept then
			kept = health
		elseif health > 0 then
			human.Health = kept
		end
	end)
	protected[human] = {shield = shield,guard = guard}
end

function kit.unprotect(human)
	local entry = protected[human]
	if not entry then return end
	protected[human] = nil
	entry.guard:Disconnect()
	entry.shield:Destroy()
	if human.Parent then
		human.Parent:SetAttribute("InVehicle",nil)
	end
end

-- Who a hit belongs to and who may be hurt ---------------------------------

--A live character a part belongs to (not a vehicle that happens to have a Humanoid),
--other than one inside own.
function kit.personOf(own,part)
	local model = part:FindFirstAncestorOfClass("Model")
	local victim = model and model:FindFirstChildOfClass("Humanoid")
	if victim and victim.RootPart and not model:IsDescendantOf(own) then
		return victim
	end
	return nil
end

--The vehicle (tagged BloxianVehicle or MarineVehicle) a part belongs to, other than own.
function kit.vehicleOf(own,part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model ~= own and (model:HasTag("BloxianVehicle") or model:HasTag("MarineVehicle")) then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--Never own's crew or the attacker's own side, and an NPC spares the players it
--would not shoot. No attacker (a wreck going up): anyone.
function kit.canHurt(own,attacker,victim)
	local victimModel = victim.Parent
	if not victimModel or victim.Health <= 0 or victimModel:IsDescendantOf(own) then return false end
	if victim.SeatPart and victim.SeatPart:IsDescendantOf(own) then return false end
	if not attacker then return true end
	if attacker == victimModel then return false end
	local attackerSide = sides.sideOf(attacker)
	if attackerSide and attackerSide == sides.sideOf(victimModel) then return false end
	local victimPlayer = players:GetPlayerFromCharacter(victimModel)
	if not players:GetPlayerFromCharacter(attacker) and victimPlayer and sides.sparesPlayer(attacker,attackerSide,victimPlayer) then
		return false
	end
	return true
end

--Damage with kill credit for a player attacker; a kill bumps own's counter
--attribute (GunKills, Roadkills), which a Bloxian crew watches.
function kit.hurt(own,attacker,victim,damage,counter)
	local player = attacker and players:GetPlayerFromCharacter(attacker)
	if player then
		local creator = Instance.new("ObjectValue")
		creator.Name = "creator"
		creator.Value = player
		creator.Parent = victim
		debris:AddItem(creator,2)
	end
	victim:TakeDamage(damage)
	if counter and victim.Health <= 0 then
		own:SetAttribute(counter,(own:GetAttribute(counter) or 0) + 1)
	end
end

--A vehicle on the other side from the attacker: crewed by an enemy of his and no
--friend, or kept to another team. An empty one open to anyone is nobody's, so it
--is never wrecked by accident. No attacker (a wreck going up): any.
function kit.canHurtVehicle(own,attacker,car)
	local human = car:FindFirstChildOfClass("Humanoid")
	if not human or human.Health <= 0 then return false end
	if not attacker then return true end
	local enemyAboard = false
	for _,name in ipairs({"VehicleSeat","Seat"}) do
		local seat = car:FindFirstChild(name)
		local occupant = seat and seat.Occupant
		if occupant and occupant.Health > 0 then
			if not kit.canHurt(own,attacker,occupant) then
				return false
			end
			enemyAboard = true
		end
	end
	if enemyAboard then return true end
	local settings = car:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	local side = sides.sideOf(attacker)
	return team ~= nil and team.Value ~= "" and side ~= nil and team.Value ~= side
end

-- Going down ----------------------------------------------------------------

--Engulfed: how many of its parts burn and the biggest fire on one (studs; 30 is Roblox's limit).
local ENGULF_PARTS = 8
local ENGULF_MAX_FIRE = 25

--Sets the whole airframe alight: a fire on each visible part (the biggest
--ENGULF_PARTS of them, sized to the part) and black smoke off the largest.
function kit.engulf(model)
	local parts = {}
	for _,part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 and not part:FindFirstChild("EngulfFire") then
			parts[#parts+1] = part
		end
	end
	table.sort(parts,function(a,b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	for index = 1,math.min(#parts,ENGULF_PARTS) do
		local part = parts[index]
		local fire = Instance.new("Fire")
		fire.Name = "EngulfFire"
		fire.Size = math.clamp(math.max(part.Size.X,part.Size.Y,part.Size.Z)*0.4,4,ENGULF_MAX_FIRE)
		fire.Heat = 20
		fire.Color = Color3.fromRGB(255,120,30)
		fire.SecondaryColor = Color3.fromRGB(255,220,80)
		fire.Parent = part
		if index == 1 then
			local smoke = Instance.new("Smoke")
			smoke.Size = ENGULF_MAX_FIRE
			smoke.RiseVelocity = 12
			smoke.Opacity = 0.7
			smoke.Color = Color3.fromRGB(30,30,30)
			smoke.Parent = part
		end
	end
end

--The wreck left on the ground: its charred colour, how long the fires burn on
--it, how long it lies there in all, and how long it takes to fade away (seconds).
local WRECK_COLOR = Color3.fromRGB(45,40,36)
local WRECK_BURN = 6
local WRECK_TIME = 12
local WRECK_FADE = 3

--Lays the model down at `at` as a wreck: charred black, its fires burning out
--after WRECK_BURN, and the whole thing fading away after WRECK_TIME.
function kit.wreck(model,body,at,facing)
	model:SetAttribute("Wrecked",true)
	for _,tag in ipairs({sides.JET_TAG,sides.GUNSHIP_TAG}) do
		model:RemoveTag(tag)
	end
	local tilt = CFrame.Angles(math.rad(-6),0,math.rad(math.random(-20,20)))
	body.CFrame = CFrame.lookAt(at,at + facing) * CFrame.new(0,model:GetExtentsSize().Y*0.2,0) * tilt
	local visible = {}
	for _,item in ipairs(model:GetDescendants()) do
		if item:IsA("SurfaceAppearance") then
			item:Destroy()
		elseif item:IsA("BasePart") and item.Transparency < 1 then
			visible[#visible+1] = item
			item.Color = WRECK_COLOR
			item.Material = Enum.Material.Slate
			if item:IsA("MeshPart") then
				pcall(function()
					item.TextureID = ""
				end)
			end
		end
	end

	task.delay(WRECK_BURN,function()
		for _,item in ipairs(model:GetDescendants()) do
			if item:IsA("Fire") then
				item.Enabled = false
			end
		end
	end)
	task.delay(WRECK_TIME,function()
		if not model.Parent then return end
		for _,item in ipairs(model:GetDescendants()) do
			if item:IsA("Smoke") then
				item.Enabled = false
			end
		end
		local fade = TweenInfo.new(WRECK_FADE)
		for _,part in ipairs(visible) do
			if part.Parent then
				tweenService:Create(part,fade,{Transparency = 1}):Play()
			end
		end
		task.wait(WRECK_FADE)
		model:Destroy()
	end)
end

--The canopy: its size, how far above the torso it hangs, colour, and seconds to
--fade once down. He drifts outward at DRIFT_SPEED and is given up on after CHUTE_MAX_TIME.
local CHUTE_SIZE = Vector3.new(14,5,14)
local CHUTE_HEIGHT = 10
local CHUTE_COLOR = Color3.fromRGB(96,104,72)
local CHUTE_FADE = 1.5
local DRIFT_SPEED = 4
local CHUTE_MAX_TIME = 90

--Opens a canopy over character and lets him down at fallSpeed (studs/s),
--drifting along outward (a flat unit vector, or nil). ignore: what the landing
--check looks through (his aircraft). Returns once he is down.
function kit.parachute(character,fallSpeed,outward,ignore)
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	local human = character:FindFirstChildOfClass("Humanoid")
	if not root or not torso or not human or human.Health <= 0 then return end

	local canopy = Instance.new("Part")
	canopy.Name = "Parachute"
	canopy.Size = CHUTE_SIZE
	canopy.Color = CHUTE_COLOR
	canopy.Material = Enum.Material.Fabric
	canopy.CanCollide = false
	canopy.CanQuery = false
	canopy.CanTouch = false
	canopy.Massless = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = canopy
	canopy.CFrame = torso.CFrame * CFrame.new(0,CHUTE_HEIGHT,0)
	local weld = Instance.new("Weld")
	weld.Part0 = torso
	weld.Part1 = canopy
	weld.C0 = CFrame.new(0,CHUTE_HEIGHT,0)
	weld.Parent = canopy

	local harness = Instance.new("Attachment")
	harness.Name = "Harness"
	harness.Position = Vector3.new(0,1,0)
	harness.Parent = torso
	for _,corner in ipairs({Vector3.new(1,0,1),Vector3.new(-1,0,1),Vector3.new(1,0,-1),Vector3.new(-1,0,-1)}) do
		local rim = Instance.new("Attachment")
		rim.Position = Vector3.new(corner.X*CHUTE_SIZE.X*0.4,-CHUTE_SIZE.Y*0.2,corner.Z*CHUTE_SIZE.Z*0.4)
		rim.Parent = canopy
		local line = Instance.new("RopeConstraint")
		line.Attachment0 = harness
		line.Attachment1 = rim
		line.Length = CHUTE_HEIGHT + 2
		line.Visible = true
		line.Thickness = 0.05
		line.Color = BrickColor.new("Light stone grey")
		line.Parent = canopy
	end
	canopy.Parent = character

	local drag = Instance.new("LinearVelocity")
	drag.Name = "ParachuteDrag"
	drag.Attachment0 = harness
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.VectorVelocity = (outward or Vector3.zero)*DRIFT_SPEED - Vector3.new(0,fallSpeed,0)
	drag.MaxForce = root.AssemblyMass*workspace.Gravity*3
	drag.Parent = root

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {character,ignore}
	local falling = 0
	while character.Parent and human.Health > 0 and falling < CHUTE_MAX_TIME do
		if human.FloorMaterial ~= Enum.Material.Air or workspace:Raycast(root.Position,Vector3.new(0,-3.5,0),params) then
			break
		end
		falling += task.wait()
	end

	drag:Destroy()
	harness:Destroy()
	canopy.Anchored = true
	weld:Destroy()
	tweenService:Create(canopy,TweenInfo.new(CHUTE_FADE),{Transparency = 1}):Play()
	debris:AddItem(canopy,CHUTE_FADE)
end

-- Effects -------------------------------------------------------------------

--A blast's size and sound when Random Arty is not there to draw it.
local BLAST_RADIUS = 22
local BLAST_SOUND = "rbxassetid://73652976704676"

--Random Arty's shell impact when it is installed (ServerStorage.ArtilleryBlast),
--else a plain explosion and boom. scale: 1 is a shell's impact.
function kit.blastFx(position,scale)
	local artilleryBlast = serverStorage:FindFirstChild("ArtilleryBlast")
	if artilleryBlast then
		artilleryBlast:Fire(position,scale or 1)
		return
	end
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = BLAST_RADIUS*(scale or 1)
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace

	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = BLAST_SOUND
	sound.Volume = 2
	sound.RollOffMinDistance = 30
	sound.RollOffMaxDistance = 2000
	sound.Parent = holder
	sound:Play()
	debris:AddItem(holder,6)
end

return kit

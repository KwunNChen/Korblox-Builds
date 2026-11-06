--[[
	F-4 Phantom: air superiority, then close air support. Spawned from the
	Bloxian Spawner (Vehicles mode) or placed by hand, it flies itself: there is
	no crew but the pilot, who ejects when it is shot down.

	Its side is Settings.Team (blank counts as Friendly). It
		clears the air  first: every enemy AC-130, Phantom and Apache in the sky.
		                It dogfights them: lag pursuit on the way in, lead
		                pursuit for a shot, a pull up instead of overshooting.
		                Sidewinders (the small pylon missiles) from range, the
		                rotary cannon up close.
		defends         with flares and a hard break: across a missile coming
		                at it, into an enemy Phantom sitting on its tail.
		attacks         the ground only once the sky has been clear of enemy
		                aircraft for AIR_CLEAR_TIME: the enemy within
		                STATION_RADIUS of where it was put, else anywhere within
		                SEARCH_RADIUS of it, the ones closest to its own side's
		                troops first, never with a friend near:
		                Mavericks (the big pylon missiles) into vehicles, gun
		                runs on soldiers and players. It never fires a missile
		                at a person.
		patrols         a wide circle over that spot otherwise.

	Each missile is a part on the pylons (Armory): it disappears when fired and
	comes back after REARM_TIME.

	Who counts as an enemy follows the Bloxians: Hostile fights everyone,
	Friendly fights Bloxians of other teams but never players, and a Roblox
	team's name sides with that team's players.

	Aircraft carry these attributes, which any Phantom reads and writes:
		ShotDown        brings a plane down (the AC-130 and Phantom watch it).
		AirHealth       a plane's health against cannon rounds (AIR_HEALTH).
		Flares          flares left (FLARE_LOAD). A salvo goes when a missile
		                gets close, if the last was FLARE_INTERVAL ago or
		                more, and may pull the missile off.
		FlaresAt        server time of its last salvo.
		MissileInbound  how many missiles are homing on it right now.
	Lifetime (seconds), set by whoever sends it in (Bloxian recon calling for
	air cover), makes it leave after that long, unless it is shot down first.
	Its Status attribute says what it is doing, for the spawner tool's tracker:
	Patrol, Intercept, Dogfight, Defending, Break, Attack, Extend, Strafe,
	Egress or Down.
]]

local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local serverStorage = game:GetService("ServerStorage")
local tweenService = game:GetService("TweenService")

--Flight: cruise and combat speed (studs/s), how fast it turns (degrees/s) and
--climbs (studs/s) cruising and in combat, its patrol height above the ground
--and patrol circle radius (studs), the lowest it ever flies above the ground,
--and the most it banks into a turn (degrees).
local CRUISE_SPEED = 260
local COMBAT_SPEED = 400
local TURN_RATE = 55
local COMBAT_TURN_RATE = 110
local CLIMB_RATE = 120
local COMBAT_CLIMB_RATE = 220
local PATROL_HEIGHT = 650
local PATROL_RADIUS = 600
local MIN_HEIGHT = 100
local MAX_BANK = 80

--Fighting near the players: with FOLLOW_PLAYERS on it patrols, and looks for
--ground targets, round its own spot STATION_SPREAD_MIN to STATION_SPREAD_MAX
--studs off the middle of the live players (picked once, in a random direction)
--rather than where it was put, so fights spread out over the map. Against another jet it fights between DOGFIGHT_FLOOR and DOGFIGHT_CEILING
--above the ground (breaks included); after a helicopter it goes no higher than
--DOGFIGHT_CEILING, and an AC-130 it goes up to. Once it is more than
--DOGFIGHT_LEASH studs from the players with the enemy further out still, it
--heads back over them, which drags the fight back with it.
local FOLLOW_PLAYERS = true
local STATION_SPREAD_MIN = 800
local STATION_SPREAD_MAX = 2500
local DOGFIGHT_FLOOR = 700
local DOGFIGHT_CEILING = 1300
local DOGFIGHT_LEASH = 2500

--Dogfighting: inside LAG_RANGE it flies lead pursuit (nose ahead of the
--target, LEAD_TIME seconds of its flight) to get a shot; outside it, lag
--pursuit (aiming LAG_DISTANCE behind it) so it closes without overshooting.
--Closer than OVERSHOOT_RANGE with the target more than OVERSHOOT_ANGLE
--(degrees) off its nose, it pulls up YOYO_HEIGHT (a high yo-yo) instead of
--flying past.
local LAG_RANGE = 1200
local LEAD_TIME = 0.6
local LAG_DISTANCE = 250
local OVERSHOOT_RANGE = 300
local OVERSHOOT_ANGLE = 60
local YOYO_HEIGHT = 150

--Defending: it breaks when a missile is homing on it, or an enemy Phantom
--within TAIL_RANGE is behind it (more than TAIL_BEHIND degrees off its nose)
--with his own nose within TAIL_ANGLE degrees of it. A break is BREAK_TIME
--seconds of the hardest turn it has, BREAK_DIVE studs down, and it goes back
--on the attack for at least BREAK_COOLDOWN seconds before it breaks again.
local TAIL_RANGE = 900
local TAIL_ANGLE = 20
local TAIL_BEHIND = 120
local BREAK_TIME = 2.5
local BREAK_DIVE = 120
local BREAK_COOLDOWN = 3

--Sidewinders: how close and how far off the nose (degrees) before it fires,
--the closest it fires one, seconds between missiles, speed (studs/s), turn
--(degrees/s), how close counts as a hit, how long one flies before it is lost
--(seconds), and the damage one does to a helicopter.
local MISSILE_RANGE = 1800
local MISSILE_CONE = 35
local MISSILE_MIN_RANGE = 150
local MISSILE_COOLDOWN = 2.5
local MISSILE_SPEED = 900
local MISSILE_TURN = 160
local MISSILE_HIT = 25
local MISSILE_LIFE = 5
local AIR_HELI_DAMAGE = 2000

--Flares and how they fool missiles: the shared AirDefense module.

--Cannon against aircraft: range, how far off the lead point (degrees) it
--fires, how close a round must pass to hit (studs), and damage per round to a
--plane's AirHealth and to a helicopter (AirDefense's AIR_HEALTH is each
--plane's health).
local AIR_GUN_RANGE = 800
local AIR_GUN_CONE = 8
local AIR_HIT_RADIUS = 14
local AIR_ROUND_DAMAGE = 8
local AIR_ROUND_HELI_DAMAGE = 25

--How long the sky must have been clear of enemy aircraft (seconds) before it
--turns on the ground, and the seconds before a fired missile is back on its
--pylon.
local AIR_CLEAR_TIME = 10
local REARM_TIME = 25

--Ground attack: how far from its spot it looks for targets first (studs), how
--far from itself it looks when there are none there (the rest of the map, by
--default), how often it looks (seconds), how far a friend must be from the
--target for it to fire at all, and the seconds it pulls away after a run
--before turning back in.
local STATION_RADIUS = 900
local SEARCH_RADIUS = math.huge
local SCAN_INTERVAL = 0.5
local DANGER_CLOSE = 35
--A target its own side's Bloxian Special Recon reported (BloxianSpotted) within
--REPORT_TIME seconds is struck before anything else, wherever it is.
local REPORT_TIME = 30
local EGRESS_TIME = 4
--Too close to a ground target to line up (inside MIN_RUN_DISTANCE and off its
--nose) it flies straight out to RUN_START_DISTANCE, or for EXTEND_TIME
--seconds, and turns in for one clean run, instead of circling over him.
local MIN_RUN_DISTANCE = 600
local RUN_START_DISTANCE = 1100
local EXTEND_TIME = 6

--Mavericks, vehicles only: the height it runs in at, range, how far off the
--nose (degrees), seconds between them, speed (studs/s), damage to the vehicle
--it hits (any vehicle: one is enough for an Abrams) and to other enemy
--vehicles within MAVERICK_SPLASH studs. Missiles launch with the Javelin's
--sound.
local MAVERICK_HEIGHT = 250
local MAVERICK_RANGE = 2000
local MAVERICK_CONE = 60
local MAVERICK_COOLDOWN = 3
local MAVERICK_SPEED = 500
local MAVERICK_DAMAGE = 100000
local MISSILE_SOUND = "rbxassetid://112204190873336"
local MAVERICK_SPLASH = 15
local MAVERICK_SPLASH_DAMAGE = 400

--Gun runs with the nose cannon (an M61 rotary): the height it runs in at, the
--range it opens fire at and how far off the nose (degrees) it still reaches,
--rounds per second, how long a burst lasts and the gap before the next run
--(seconds), how wide the rounds scatter round the target (studs), and damage
--per round to people and to vehicles.
local ATTACK_HEIGHT = 150
local GUN_RANGE = 900
local GUN_CONE = 30
local GUN_RATE = 40
local BURST_TIME = 1.5
local RUN_COOLDOWN = 3
local GUN_SPREAD = 5
local ROUND_DAMAGE = 20
local ROUND_VEHICLE_DAMAGE = 30

--Where the gun sits under the nose (studs from the root), the tracer colour,
--and the gun's sound (a gatling firing loop, played while it fires).
local GUN_OFFSET = Vector3.new(0,-4,-32)
local TRACER_COLOR = Color3.fromRGB(255,170,60)
local GUN_SOUND = "rbxassetid://17705539789"

--Shot down: how fast it falls (studs/s) and rolls (radians/s).
local FALL_SPEED = 120
local FALL_SPIN = 2
--Engulfed: how many of its parts burn and the biggest fire on one (studs; 30
--is Roblox's limit), and how much bigger than a shell's impact the blast is
--when it hits the ground (Random Arty's ArtilleryBlast).
local ENGULF_PARTS = 30
local ENGULF_MAX_FIRE = 25
local CRASH_SCALE = 4

--The wreck left on the ground: its charred colour, how long the fires burn on
--it, how long it lies there in all, and how long it takes to fade away
--(seconds).
local WRECK_COLOR = Color3.fromRGB(45,40,36)
local WRECK_BURN = 6
local WRECK_TIME = 12
local WRECK_FADE = 3

--The pilot who ejects: a Bloxian from ServerStorage in the Pilot uniform with
--the FN FAL. Thrown up EJECT_UP studs/s, his canopy opens after CHUTE_DELAY
--seconds and he sinks at CHUTE_FALL_SPEED.
local SOLDIER_NAME = "BLOXIAN"
local PILOT_UNIT = "Pilot"
local PILOT_WEAPON = "Rifle"
local EJECT_UP = 40
local CHUTE_DELAY = 0.8
local CHUTE_FALL_SPEED = 25
local CHUTE_SIZE = Vector3.new(14,5,14)
local CHUTE_HEIGHT = 10
local CHUTE_COLOR = Color3.fromRGB(96,104,72)
local CHUTE_FADE = 1.5

--A missile's blast when Random Arty is not there to draw it (studs), and its sound.
local BLAST_RADIUS = 22
local BLAST_SOUND = "rbxassetid://73652976704676"

--Flyby: played from the jet when it passes within FLYBY_RANGE of a player, at
--most once every FLYBY_COOLDOWN seconds; how loud, and how far it carries.
local FLYBY_SOUND = "rbxassetid://106006741903011"
local FLYBY_RANGE = 400
local FLYBY_COOLDOWN = 8
local FLYBY_VOLUME = 2
local FLYBY_HEARING = 1500

local sides = require(script.Parent:WaitForChild("Sides"))
local airDefense = require(script.Parent:WaitForChild("AirDefense"))
local HOSTILE = sides.HOSTILE
local FRIENDLY = sides.FRIENDLY
local JET_TAG = sides.JET_TAG
local GUNSHIP_TAG = sides.GUNSHIP_TAG
local HELI_TAG = sides.HELI_TAG
local AIR_TAGS = sides.AIR_TAGS
local VEHICLE_TAGS = {"BloxianVehicle","MarineVehicle"}

local jet = script.Parent
local root = jet.PrimaryPart

--Every part rides on the root: welded here rather than in the file, then let go.
for _,part in ipairs(jet:GetDescendants()) do
	if part:IsA("BasePart") and part ~= root then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Anchored = false
	end
end
local settings = jet:FindFirstChild("Settings")
local teamValue = settings and settings:FindFirstChild("Team")

jet:AddTag(JET_TAG)

local lifetime = jet:GetAttribute("Lifetime")
if lifetime then
	task.delay(lifetime,function()
		if jet.Parent and not jet:GetAttribute("ShotDown") then
			jet:Destroy()
		end
	end)
end
jet:SetAttribute("AirHealth",airDefense.AIR_HEALTH[JET_TAG])
jet:SetAttribute("Flares",airDefense.FLARE_LOAD[JET_TAG])
jet:SetAttribute("Chaff",airDefense.CHAFF_LOAD[JET_TAG])
jet:SetAttribute("MissileInbound",0)

local function flat(v)
	return Vector3.new(v.X,0,v.Z)
end

--Whether a tank's smoke screen (a part tagged SmokeScreen, with a Radius
--attribute) lies between two points.
local function smokeBetween(from,to)
	local line = to - from
	local length = line:Dot(line)
	for _,cloud in ipairs(collectionService:GetTagged("SmokeScreen")) do
		local centre = cloud.Position
		local t = length > 0 and math.clamp((centre - from):Dot(line)/length,0,1) or 0
		if (from + line*t - centre).Magnitude < (cloud:GetAttribute("Radius") or 10) then
			return true
		end
	end
	return false
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = {jet}

local function groundY(position)
	local result = workspace:Raycast(Vector3.new(position.X,position.Y + 50,position.Z),Vector3.new(0,-5000,0),groundParams)
	return result and result.Position.Y or 0
end

---------------------------------------------------------------- sides

local function mySide()
	local value = teamValue and teamValue.Value or ""
	return value ~= "" and value or FRIENDLY
end

--"enemy", "friend" or nil (neither) for a character.
local function standing(model)
	return sides.standing(model,mySide())
end

--Every live soldier and player character, with its root.
local function people()
	local list = {}
	for _,player in ipairs(players:GetPlayers()) do
		local character = player.Character
		local human = character and character:FindFirstChildOfClass("Humanoid")
		if human and human.Health > 0 and human.RootPart then
			list[#list+1] = {model = character,human = human,root = human.RootPart}
		end
	end
	for model in pairs(_G.BloxianRadio or {}) do
		local human = model.Parent and model:FindFirstChildOfClass("Humanoid")
		if human and human.Health > 0 and human.RootPart and not players:GetPlayerFromCharacter(model) then
			list[#list+1] = {model = model,human = human,root = human.RootPart}
		end
	end
	return list
end

--"enemy", "friend" or nil for a vehicle: by its crew, else the team it is kept to.
local function vehicleStanding(car)
	return sides.vehicleStanding(car,mySide())
end

local function vehicleOf(instance)
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		for _,tag in ipairs(VEHICLE_TAGS) do
			if model:HasTag(tag) then return model end
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local airKind = sides.airKind

--An enemy AC-130, Phantom or Apache still flying.
local function enemyAircraft(craft)
	return craft ~= jet and sides.enemyAircraft(craft,mySide())
end

local hurtAircraft = airDefense.hurtAircraft

local velocityOf = airDefense.velocityOf

---------------------------------------------------------------- effects

--Random Arty's shell impact when it is installed (ServerStorage.ArtilleryBlast),
--else a plain explosion and boom.
--scale: 1 is a shell's impact.
local function blastFx(position,scale)
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

--Sets the whole airframe alight: a fire on each visible part (the biggest
--ENGULF_PARTS of them, sized to the part) and black smoke off the largest.
local function engulf(model)
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
		if index <= 3 then
			local smoke = Instance.new("Smoke")
			smoke.Size = ENGULF_MAX_FIRE
			smoke.RiseVelocity = 12
			smoke.Opacity = 0.7
			smoke.Color = Color3.fromRGB(30,30,30)
			smoke.Parent = part
		end
	end
end

--Lays the model down at `at` as a wreck: charred black, its fires burning out
--after WRECK_BURN, and the whole thing fading away after WRECK_TIME.
local function wreck(model,body,at,facing)
	model:SetAttribute("Wrecked",true)
	for _,tag in ipairs({"BloxianJet","BloxianGunship"}) do
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

local plainPart,addTrail = airDefense.plainPart,airDefense.addTrail

local function tracer(from,to)
	local length = (to - from).Magnitude
	if length < 1 then return end
	local part = plainPart("Tracer",Vector3.new(0.3,0.3,math.min(length,40)),TRACER_COLOR,Enum.Material.Neon)
	part.CFrame = CFrame.lookAt(to,from) * CFrame.new(0,0,-part.Size.Z/2)
	part.Parent = workspace
	debris:AddItem(part,0.06)
end

local function puff(at)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = workspace.Terrain
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(120,105,85))
	dust.Size = NumberSequence.new(1.5,5)
	dust.Transparency = NumberSequence.new(0.3,1)
	dust.Lifetime = NumberRange.new(0.5,0.9)
	dust.Speed = NumberRange.new(6,14)
	dust.SpreadAngle = Vector2.new(40,40)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Enabled = false
	dust.Parent = holder
	dust:Emit(4)
	debris:AddItem(holder,1)
end

---------------------------------------------------------------- the pilot

local function parachute(character)
	local body = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	local human = character:FindFirstChildOfClass("Humanoid")
	if not body or not torso or not human or human.Health <= 0 then return end

	local canopy = plainPart("Parachute",CHUTE_SIZE,CHUTE_COLOR,Enum.Material.Fabric)
	canopy.Anchored = false
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
	canopy.Parent = character

	local drag = Instance.new("LinearVelocity")
	drag.Name = "ParachuteDrag"
	drag.Attachment0 = harness
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.VectorVelocity = Vector3.new(0,-CHUTE_FALL_SPEED,0)
	drag.MaxForce = body.AssemblyMass*workspace.Gravity*3
	drag.Parent = body

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {character}
	local falling = 0
	while character.Parent and human.Health > 0 and falling < 90 do
		if human.FloorMaterial ~= Enum.Material.Air or workspace:Raycast(body.Position,Vector3.new(0,-3.5,0),params) then
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

local function setValue(holder,name,className,value)
	local item = holder:FindFirstChild(name)
	if not item then
		item = Instance.new(className)
		item.Name = name
		item.Parent = holder
	end
	item.Value = value
end

--Out of the jet as it goes down, on a parachute, to fight on the ground.
local function eject(at)
	local template = serverStorage:FindFirstChild(SOLDIER_NAME)
	if not template then return end
	local side = mySide()
	local pilot = template:Clone()
	local pilotSettings = pilot:FindFirstChild("Settings")
	if pilotSettings then
		setValue(pilotSettings,"Team","StringValue",side)
		setValue(pilotSettings,"AttackPlayers","BoolValue",side == HOSTILE)
		setValue(pilotSettings,"Unit","StringValue",PILOT_UNIT)
		setValue(pilotSettings,"Weapon","StringValue",PILOT_WEAPON)
		setValue(pilotSettings,"Role","StringValue","Rifleman")
		setValue(pilotSettings,"Respawn","BoolValue",false)
	end
	pilot:SetAttribute("Ejected",true)
	--A spawner's jet hands its owner down, so Clear all takes the pilot too.
	local owner = jet:GetAttribute("SpawnedBy")
	if owner then
		pilot:SetAttribute("SpawnedBy",owner)
		pilot:SetAttribute("VehicleCrew",true)
		pilot:AddTag("BloxianSpawned")
	end
	pilot:PivotTo(CFrame.new(at + Vector3.new(0,8,0)))
	pilot.Parent = workspace
	local body = pilot:FindFirstChild("HumanoidRootPart")
	if body then
		body.AssemblyLinearVelocity = Vector3.new(0,EJECT_UP,0)
	end
	task.delay(CHUTE_DELAY,parachute,pilot)
end

---------------------------------------------------------------- weapons

--The pylon parts whose names start with prefix, in the order they are fired.
local function pylonParts(prefix)
	local list = {}
	local armory = jet:FindFirstChild("Armory")
	for _,side in ipairs({"Left","Right"}) do
		local holder = armory and armory:FindFirstChild(side)
		if holder then
			for _,part in ipairs(holder:GetChildren()) do
				if part:IsA("BasePart") and part.Name:sub(1,#prefix) == prefix then
					list[#list+1] = part
				end
			end
		end
	end
	table.sort(list,function(a,b)
		return a.Name..a.Parent.Name < b.Name..b.Parent.Name
	end)
	return list
end
--Missile 1 / 2 are the Sidewinders, Missile Big the Mavericks.
local sidewinders = {}
local mavericks = {}
for _,part in ipairs(pylonParts("Missile")) do
	table.insert(part.Name == "Missile Big" and mavericks or sidewinders,part)
end

local function loaded(parts)
	for _,part in ipairs(parts) do
		if part.Transparency < 1 then return true end
	end
	return false
end

--Takes the next loaded part off the pylons: where the shot leaves from, or nil
--when they are all fired.
local function takeFrom(parts)
	for _,part in ipairs(parts) do
		if part.Transparency < 1 then
			part.Transparency = 1
			task.delay(REARM_TIME,function()
				if part.Parent then
					part.Transparency = 0
				end
			end)
			return part.Position
		end
	end
	return nil
end

--A homing missile from the pylons at target (a model). onHit(missile position)
--runs when it gets there. Against an aircraft the target may throw flares,
--which can pull it off.
local function launch(parts,target,speed,turnRate,onHit)
	local from = takeFrom(parts)
	if not from then return false end
	local missile = plainPart("Missile",Vector3.new(0.7,0.7,5),Color3.fromRGB(220,220,220),Enum.Material.Metal)
	missile.CFrame = CFrame.lookAt(from,from + root.CFrame.LookVector)
	addTrail(missile,Color3.fromRGB(230,230,230),1.2,0.6)
	missile.Parent = workspace
	local whoosh = Instance.new("Sound")
	whoosh.SoundId = MISSILE_SOUND
	whoosh.Volume = 2
	whoosh.RollOffMinDistance = 40
	whoosh.RollOffMaxDistance = 1500
	whoosh.Parent = missile
	whoosh:Play()

	local airborne = airKind(target) ~= nil
	target:SetAttribute("MissileInbound",(target:GetAttribute("MissileInbound") or 0) + 1)
	target:SetAttribute("ThreatAt",root.Position)
	if airborne then
		airDefense.velocityOf(target)
	end
	local chasing = nil --a flare it was pulled onto
	local lastSeen = nil --a ground target's last position before smoke hid it
	local blinded = false
	local flareChecked = false
	local forward = root.CFrame.LookVector
	local born = os.clock()

	local connection
	local function finish()
		connection:Disconnect()
		missile:Destroy()
		if target.Parent then
			target:SetAttribute("MissileInbound",math.max((target:GetAttribute("MissileInbound") or 1) - 1,0))
		end
	end
	connection = runService.Heartbeat:Connect(function(dt)
		local goal = nil
		if chasing then
			goal = chasing.Parent and chasing.Position
		elseif target.Parent and target.PrimaryPart and not target:GetAttribute("ShotDown") then
			goal = target.PrimaryPart.Position
			--Smoke between it and a vehicle: it flies on to where it last saw it.
			if not airborne then
				if smokeBetween(missile.Position,goal) then
					blinded = true
					goal = lastSeen or goal
				else
					blinded = false
					lastSeen = goal
				end
			end
		end
		if goal then
			local toGoal = goal - missile.Position
			if airborne and not chasing and not flareChecked and toGoal.Magnitude < airDefense.FLARE_RANGE then
				flareChecked = true
				chasing = airDefense.decoy(target,missile.Position)
			end
			--Through the flares: it goes off on one instead of the aircraft.
			if airborne and airDefense.touchedFlare(target,missile.Position) then
				blastFx(missile.Position)
				finish()
				return
			end
			if toGoal.Magnitude < MISSILE_HIT then
				local missed = blinded and (not target.PrimaryPart or (target.PrimaryPart.Position - missile.Position).Magnitude > MISSILE_HIT)
				if chasing or missed then
					blastFx(missile.Position)
				else
					onHit(missile.Position)
				end
				finish()
				return
			end
			local angle = math.acos(math.clamp(forward:Dot(toGoal.Unit),-1,1))
			local turn = math.min(math.rad(turnRate)*dt,angle)
			local axis = forward:Cross(toGoal.Unit)
			if angle > 1e-3 and axis.Magnitude > 1e-4 then
				forward = CFrame.fromAxisAngle(axis.Unit,turn):VectorToWorldSpace(forward)
			end
		end
		local position = missile.Position + forward*speed*dt
		missile.CFrame = CFrame.lookAt(position,position + forward)
		if os.clock() - born > MISSILE_LIFE then
			finish()
		end
	end)
	return true
end

local function fireSidewinder(target)
	return launch(sidewinders,target,MISSILE_SPEED,MISSILE_TURN,function(at)
		hurtAircraft(target,math.huge,AIR_HELI_DAMAGE)
		blastFx(at)
	end)
end

--Into an enemy vehicle only: no splash on people.
local function fireMaverick(car)
	return launch(mavericks,car,MAVERICK_SPEED,MISSILE_TURN,function(at)
		blastFx(at)
		local human = car:FindFirstChildOfClass("Humanoid")
		if human and human.Health > 0 then
			human:TakeDamage(MAVERICK_DAMAGE)
		end
		for _,tag in ipairs(VEHICLE_TAGS) do
			for _,other in ipairs(collectionService:GetTagged(tag)) do
				local part = other ~= car and other.PrimaryPart
				local otherHuman = part and other:FindFirstChildOfClass("Humanoid")
				if otherHuman and otherHuman.Health > 0 and (part.Position - at).Magnitude < MAVERICK_SPLASH
					and vehicleStanding(other) == "enemy" then
					otherHuman:TakeDamage(MAVERICK_SPLASH_DAMAGE)
				end
			end
		end
	end)
end

--The gun: rounds are rays from under the nose, each drawn as a tracer.
local gun = Instance.new("Attachment")
gun.Name = "Gun"
gun.Position = GUN_OFFSET
gun.Parent = root
local gunSound = Instance.new("Sound")
gunSound.Name = "GunFire"
gunSound.SoundId = GUN_SOUND
gunSound.Looped = true
gunSound.Volume = 2
gunSound.RollOffMinDistance = 60
gunSound.RollOffMaxDistance = 2500
gunSound.Parent = gun

local flyby = Instance.new("Sound")
flyby.Name = "Flyby"
flyby.SoundId = FLYBY_SOUND
flyby.Volume = FLYBY_VOLUME
flyby.RollOffMinDistance = 60
flyby.RollOffMaxDistance = FLYBY_HEARING
flyby.Parent = root
task.spawn(function()
	while jet.Parent and not jet:GetAttribute("ShotDown") do
		for _,player in ipairs(players:GetPlayers()) do
			local body = player.Character and player.Character.PrimaryPart
			if body and (body.Position - root.Position).Magnitude < FLYBY_RANGE then
				flyby:Play()
				task.wait(FLYBY_COOLDOWN)
				break
			end
		end
		task.wait(0.25)
	end
end)

local roundParams = RaycastParams.new()
roundParams.FilterType = Enum.RaycastFilterType.Exclude
roundParams.FilterDescendantsInstances = {jet}

--One round at a ground target, scattered round it. Only the enemy are hurt.
local function fireRound(targetPart)
	local offset = Vector3.new(math.random() - 0.5,0,math.random() - 0.5)*2*GUN_SPREAD
	local aim = targetPart.Position + offset
	local from = gun.WorldPosition
	local direction = (aim - from).Unit*(GUN_RANGE*1.6)
	local result = workspace:Raycast(from,direction,roundParams)
	local hitAt = result and result.Position or from + direction
	tracer(from,hitAt)
	if not result then return end
	puff(hitAt)

	local car = vehicleOf(result.Instance)
	if car then
		local human = car:FindFirstChildOfClass("Humanoid")
		if human and human.Health > 0 and vehicleStanding(car) == "enemy" then
			human:TakeDamage(ROUND_VEHICLE_DAMAGE)
		end
		return
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local human = model and model:FindFirstChildOfClass("Humanoid")
	if human and human.Health > 0 and standing(model) == "enemy" then
		human:TakeDamage(ROUND_DAMAGE)
	end
end

--One round at an aircraft, along the gun line toward aim: a hit if it passes
--within AIR_HIT_RADIUS of where the aircraft will be.
local function fireAirRound(craft,aim)
	local from = gun.WorldPosition
	local spread = CFrame.Angles((math.random() - 0.5)*0.02,(math.random() - 0.5)*0.02,0)
	local direction = (CFrame.lookAt(from,aim)*spread).LookVector
	local to = from + direction*AIR_GUN_RANGE
	tracer(from,to)
	local offset = aim - from
	local along = math.clamp(offset:Dot(direction),0,AIR_GUN_RANGE)
	if (from + direction*along - aim).Magnitude < AIR_HIT_RADIUS then
		hurtAircraft(craft,AIR_ROUND_DAMAGE,AIR_ROUND_HELI_DAMAGE)
	end
end

---------------------------------------------------------------- choosing targets

local position = root.Position
local heading = flat(root.CFrame.LookVector)
heading = heading.Magnitude > 0.01 and heading.Unit or Vector3.new(0,0,-1)
local home = Vector3.new(position.X,groundY(position),position.Z)
local station = home
local spreadAngle = math.random()*math.pi*2
local stationOffset = Vector3.new(math.cos(spreadAngle),0,math.sin(spreadAngle))
	*(STATION_SPREAD_MIN + math.random()*(STATION_SPREAD_MAX - STATION_SPREAD_MIN))

--Where it works from: the middle of the live players (FOLLOW_PLAYERS), else
--where it was put.
local function anchor()
	if not FOLLOW_PLAYERS then return home end
	local sum,count = Vector3.zero,0
	for _,player in ipairs(players:GetPlayers()) do
		local character = player.Character
		local human = character and character:FindFirstChildOfClass("Humanoid")
		if human and human.Health > 0 and human.RootPart then
			sum += human.RootPart.Position
			count += 1
		end
	end
	if count == 0 then return home end
	local centre = sum/count + stationOffset
	return Vector3.new(centre.X,groundY(centre),centre.Z)
end

local airTarget = nil
local groundTarget = nil --{part, car (nil for a person)}

--The nearest enemy aircraft anywhere: the sky comes first.
local function findAirTarget()
	local best,bestDist = nil,math.huge
	for _,tag in ipairs(AIR_TAGS) do
		for _,craft in ipairs(collectionService:GetTagged(tag)) do
			if craft:IsDescendantOf(workspace) and enemyAircraft(craft) then
				local dist = (craft.PrimaryPart.Position - position).Magnitude
				if dist < bestDist then
					best,bestDist = craft,dist
				end
			end
		end
	end
	return best
end

--An enemy Phantom close behind with its nose on this one, if any. One out in
--front, even pointing straight at it, is a head-on pass, not a threat.
local function onMyTail()
	for _,other in ipairs(collectionService:GetTagged(JET_TAG)) do
		if other ~= jet and enemyAircraft(other) then
			local offset = position - other.PrimaryPart.Position
			local behind = math.deg(math.acos(math.clamp(heading:Dot(flat(-offset).Unit),-1,1))) > TAIL_BEHIND
			if offset.Magnitude < TAIL_RANGE and flat(offset).Magnitude > 1 and behind then
				local aim = math.deg(math.acos(math.clamp(other.PrimaryPart.CFrame.LookVector:Dot(offset.Unit),-1,1)))
				if aim < TAIL_ANGLE then
					return other
				end
			end
		end
	end
	return nil
end

--The enemy to attack on the ground: closest to one of its own troops, else
--closest to it. Vehicles come first while it has a Maverick loaded.
local function findGroundTarget()
	local friends,soldiers,vehicles,reported = {},{},{},{}
	local spotted = _G.BloxianSpotted or {}
	local now = workspace:GetServerTimeNow()
	for _,entry in ipairs(people()) do
		local seat = entry.human.SeatPart
		--Nobody still in the air on a parachute (a pilot out of a wreck).
		local hanging = entry.model:FindFirstChild("Parachute") ~= nil
		if not (seat and vehicleOf(seat)) and not hanging then
			local view = standing(entry.model)
			if view == "friend" then
				friends[#friends+1] = entry.root.Position
			elseif view == "enemy" then
				soldiers[#soldiers+1] = {part = entry.root}
				local report = spotted[entry.root]
				if report and report.team == mySide() and now - report.at <= REPORT_TIME then
					reported[#reported+1] = {part = entry.root}
				end
			end
		end
	end
	local seen = {}
	for _,tag in ipairs(VEHICLE_TAGS) do
		for _,car in ipairs(collectionService:GetTagged(tag)) do
			local human = car:FindFirstChildOfClass("Humanoid")
			if not seen[car] and car:IsDescendantOf(workspace) and car.PrimaryPart and human and human.Health > 0
				and not car:GetAttribute("Aircraft") and not car:GetAttribute("Wrecked") then
				seen[car] = true
				local view = vehicleStanding(car)
				if view == "friend" then
					friends[#friends+1] = car.PrimaryPart.Position
				elseif view == "enemy" then
					vehicles[#vehicles+1] = {part = car.PrimaryPart,car = car}
					local report = spotted[car.PrimaryPart]
					if report and report.team == mySide() and now - report.at <= REPORT_TIME then
						reported[#reported+1] = {part = car.PrimaryPart,car = car}
					end
				end
			end
		end
	end

	--Within radius of center: the one closest to a friend, else closest to it.
	local function pick(list,center,radius)
		local best,bestScore = nil,math.huge
		for _,entry in ipairs(list) do
			local at = entry.part.Position
			if flat(at - center).Magnitude < radius then
				local nearestFriend = math.huge
				for _,friend in ipairs(friends) do
					nearestFriend = math.min(nearestFriend,(friend - at).Magnitude)
				end
				if nearestFriend > DANGER_CLOSE then
					local score = nearestFriend < math.huge and nearestFriend or (at - position).Magnitude
					if score < bestScore then
						best,bestScore = entry,score
					end
				end
			end
		end
		return best
	end
	--Its own patch first; with nothing there, anyone it can find.
	local function around(center,radius)
		return (loaded(mavericks) and pick(vehicles,center,radius)) or pick(soldiers,center,radius) or pick(vehicles,center,radius)
	end
	return pick(reported,position,math.huge) or around(station,STATION_RADIUS) or around(position,SEARCH_RADIUS)
end

---------------------------------------------------------------- flying

local bank = 0
local lastScan = -math.huge
local nextMissile = 0
local nextMaverick = 0
local nextRun = 0
local burstUntil = 0
local egressUntil = 0
local extendUntil = 0
local breakUntil = 0
local breakSign = 1
local beamDirection = nil --a missile's break: the way across its path
local roundsOwed = 0
local airSeenAt = -math.huge
local ground = station.Y
local lastGround = -math.huge
local downSince = nil
local spin = 0

local function setStatus(status)
	if jet:GetAttribute("Status") ~= status then
		jet:SetAttribute("Status",status)
	end
end
setStatus("Patrol")

--Degrees off the nose, flat, of a point.
local function offNose(point)
	local to = flat(point - position)
	if to.Magnitude < 1 then return 0 end
	return math.deg(math.acos(math.clamp(heading:Dot(to.Unit),-1,1)))
end

--Degrees off the nose in 3D, along the way it is flying.
local function offBore(point,travel)
	local to = point - position
	if to.Magnitude < 1 or travel.Magnitude < 1 then return 0 end
	return math.deg(math.acos(math.clamp(travel.Unit:Dot(to.Unit),-1,1)))
end

local travel = heading*CRUISE_SPEED

local connection
connection = runService.Heartbeat:Connect(function(dt)
	if not jet.Parent or not root.Parent then
		connection:Disconnect()
		return
	end
	local now = os.clock()

	if now - lastGround > 0.25 then
		lastGround = now
		ground = math.max(groundY(position),groundY(position + heading*300))
	end

	--Shot down: the pilot ejects, it noses over, rolls, and blows up on the ground.
	if jet:GetAttribute("ShotDown") then
		if not downSince then
			downSince = now
			engulf(jet)
			task.spawn(eject,position)
		end
		gunSound:Stop()
		setStatus("Down")
		spin += FALL_SPIN*dt
		position += heading*CRUISE_SPEED*0.6*dt - Vector3.new(0,FALL_SPEED*dt,0)
		root.CFrame = CFrame.lookAt(position,position + heading - Vector3.new(0,0.6,0)) * CFrame.Angles(0,0,spin)
		if position.Y <= groundY(position) + 4 or now - downSince > 20 then
			local at = Vector3.new(position.X,groundY(position),position.Z)
			blastFx(at,CRASH_SCALE)
			connection:Disconnect()
			wreck(jet,root,at,heading)
		end
		return
	end

	if now - lastScan > SCAN_INTERVAL then
		lastScan = now
		station = anchor()
		airTarget = findAirTarget()
		if airTarget then
			airSeenAt = now
		end
		groundTarget = now - airSeenAt > AIR_CLEAR_TIME and findGroundTarget() or nil
	end
	if airTarget and not enemyAircraft(airTarget) then
		airTarget = nil
	end

	--Breaking: a missile coming, or an enemy on its tail.
	if now >= breakUntil + BREAK_COOLDOWN then
		local inbound = (jet:GetAttribute("MissileInbound") or 0) > 0
		local chaser = onMyTail()
		if inbound or chaser then
			breakUntil = now + BREAK_TIME
			--Into the attacker, which turns him past; against a missile, square
			--across its path (beaming it, where chaff works best), the way that
			--needs the least turn.
			beamDirection = nil
			if chaser then
				breakSign = heading:Cross(flat(chaser.PrimaryPart.Position - position)).Y > 0 and 1 or -1
			else
				local threat = jet:GetAttribute("ThreatAt")
				local line = typeof(threat) == "Vector3" and flat(threat - position)
				if line and line.Magnitude > 1 then
					beamDirection = line.Unit:Cross(Vector3.yAxis)
					if beamDirection:Dot(heading) < 0 then
						beamDirection = -beamDirection
					end
				else
					breakSign = math.random(2) == 1 and 1 or -1
				end
			end
			setStatus(chaser and "Break" or "Defending")
		end
	end

	local goal,goalHeight,speed,turnRate,climbRate
	local firing = nil --what the gun is firing at: "air" or "ground"
	local airAim = nil
	if now < breakUntil then
		--The hardest turn it has, diving.
		goal = position + (beamDirection or CFrame.Angles(0,breakSign*math.rad(80),0):VectorToWorldSpace(heading))*500
		goalHeight,speed = position.Y - BREAK_DIVE,COMBAT_SPEED
		if airTarget and airKind(airTarget) == JET_TAG then
			goalHeight = math.max(goalHeight,math.min(position.Y,ground + DOGFIGHT_FLOOR))
		end
		turnRate,climbRate = COMBAT_TURN_RATE*1.2,COMBAT_CLIMB_RATE
	elseif airTarget then
		local at = airTarget.PrimaryPart.Position
		local velocity = velocityOf(airTarget)
		local dist = (at - position).Magnitude
		airSeenAt = now
		speed,turnRate,climbRate = COMBAT_SPEED,COMBAT_TURN_RATE,COMBAT_CLIMB_RATE
		if dist > MISSILE_RANGE*1.5 then
			goal,goalHeight = at,at.Y
			setStatus("Intercept")
		else
			setStatus("Dogfight")
			local lead = at + velocity*LEAD_TIME
			local behind = velocity.Magnitude > 1 and at - velocity.Unit*LAG_DISTANCE or at
			if dist < OVERSHOOT_RANGE and offNose(at) > OVERSHOOT_ANGLE then
				--High yo-yo: up and over instead of flying past him.
				goal,goalHeight = behind,at.Y + YOYO_HEIGHT
			elseif dist < LAG_RANGE then
				goal,goalHeight = lead,lead.Y
			else
				goal,goalHeight = behind,behind.Y
			end
		end
		local kind = airKind(airTarget)
		if kind == JET_TAG then
			goalHeight = math.clamp(goalHeight,ground + DOGFIGHT_FLOOR,ground + DOGFIGHT_CEILING)
		elseif kind ~= GUNSHIP_TAG then
			goalHeight = math.min(goalHeight,ground + DOGFIGHT_CEILING)
		end
		local fromPlayers = flat(position - station).Magnitude
		if fromPlayers > DOGFIGHT_LEASH and flat(at - station).Magnitude > fromPlayers then
			goal = station
		end
		if now >= nextMissile and dist > MISSILE_MIN_RANGE and dist < MISSILE_RANGE and offNose(at) < MISSILE_CONE then
			if fireSidewinder(airTarget) then
				nextMissile = now + MISSILE_COOLDOWN
			end
		end
		local gunAim = at + velocity*(dist/2000)
		if dist < AIR_GUN_RANGE and offBore(gunAim,travel) < AIR_GUN_CONE then
			firing,airAim = "air",gunAim
		end
	elseif now < burstUntil and groundTarget and groundTarget.part.Parent then
		--Mid-run: nose on him and the gun going while he is in its reach.
		local at = groundTarget.part.Position
		goal,goalHeight,speed = at,at.Y + ATTACK_HEIGHT,COMBAT_SPEED
		setStatus("Strafe")
		if (at - gun.WorldPosition).Magnitude < GUN_RANGE and offNose(at) < GUN_CONE then
			firing = "ground"
		end
	elseif now < egressUntil then
		goal,goalHeight,speed = position + heading*500,ground + PATROL_HEIGHT,COMBAT_SPEED
		setStatus("Egress")
	elseif now < extendUntil and groundTarget and groundTarget.part.Parent then
		--Out far enough for a straight run in.
		goal,goalHeight,speed = position + heading*500,ground + MAVERICK_HEIGHT,COMBAT_SPEED
		setStatus("Extend")
		if flat(groundTarget.part.Position - position).Magnitude > RUN_START_DISTANCE then
			extendUntil = 0
		end
	elseif groundTarget and groundTarget.part.Parent then
		local at = groundTarget.part.Position
		local car = groundTarget.car
		speed = COMBAT_SPEED
		setStatus("Attack")
		local cone = (car and loaded(mavericks)) and MAVERICK_CONE or GUN_CONE
		if flat(at - position).Magnitude < MIN_RUN_DISTANCE and offNose(at) > cone then
			extendUntil = now + EXTEND_TIME
			goal,goalHeight = position + heading*500,ground + MAVERICK_HEIGHT
		elseif car and loaded(mavericks) then
			goal,goalHeight = at,at.Y + MAVERICK_HEIGHT
			if now >= nextMaverick and (at - position).Magnitude < MAVERICK_RANGE and offNose(at) < MAVERICK_CONE then
				if fireMaverick(car) then
					nextMaverick = now + MAVERICK_COOLDOWN
					egressUntil = now + EGRESS_TIME
				end
			end
		elseif now >= nextRun then
			goal,goalHeight = at,at.Y + ATTACK_HEIGHT
			if (at - gun.WorldPosition).Magnitude < GUN_RANGE and offNose(at) < GUN_CONE then
				burstUntil = now + BURST_TIME
				egressUntil = burstUntil + EGRESS_TIME
				nextRun = burstUntil + RUN_COOLDOWN
				firing = "ground"
			end
		else
			goal,goalHeight = position + heading*500,ground + PATROL_HEIGHT
		end
	end
	if not goal then
		--Round the patrol circle, steering for a point a little ahead on it.
		local fromStation = flat(position - station)
		local around = math.atan2(fromStation.Z,fromStation.X) - 0.5
		goal = station + Vector3.new(math.cos(around),0,math.sin(around))*PATROL_RADIUS
		goalHeight,speed = ground + PATROL_HEIGHT,CRUISE_SPEED
		setStatus("Patrol")
	end
	turnRate = turnRate or (speed == COMBAT_SPEED and COMBAT_TURN_RATE*0.7 or TURN_RATE)
	climbRate = climbRate or CLIMB_RATE

	if firing then
		roundsOwed += GUN_RATE*dt
		while roundsOwed >= 1 do
			roundsOwed -= 1
			if firing == "air" then
				fireAirRound(airTarget,airAim)
			else
				fireRound(groundTarget.part)
			end
		end
		if not gunSound.IsPlaying then
			gunSound:Play()
		end
	else
		roundsOwed = 0
		if gunSound.IsPlaying then
			gunSound:Stop()
		end
	end

	--Turn toward the goal, at most turnRate.
	local want = flat(goal - position)
	local turn = 0
	if want.Magnitude > 1 then
		want = want.Unit
		local angle = math.acos(math.clamp(heading:Dot(want),-1,1))
		local sign = heading:Cross(want).Y > 0 and 1 or -1
		turn = math.min(angle,math.rad(turnRate)*dt)*sign
		heading = CFrame.Angles(0,turn,0):VectorToWorldSpace(heading).Unit
	end

	local height = math.max(goalHeight,ground + MIN_HEIGHT)
	local climb = math.clamp((height - position.Y)*2,-climbRate,climbRate)
	position += heading*speed*dt + Vector3.new(0,climb*dt,0)

	local goalBank = dt > 0 and math.clamp(turn/(math.rad(COMBAT_TURN_RATE)*dt),-1,1)*MAX_BANK or 0
	bank += (goalBank - bank)*math.min(dt*4,1)
	travel = heading*speed + Vector3.new(0,climb,0)
	root.CFrame = CFrame.lookAt(position,position + travel) * CFrame.Angles(0,0,math.rad(bank))
end)

--[[
	A spawnable AC-130. Spawned from the Bloxian Spawner's Vehicles mode, it
	takes station high over where it was put down and circles there (guns on its
	left, banked into the turn), flying itself.

	Its side is Settings.Team (blank counts as Hostile), copied to its Team
	attribute. Nobody calls it: every so often it picks the biggest group of
	enemies near its station (Bloxians of another team, and players not on its
	team), never one with a friend close by, sets Target and OnMission, flies its
	orbit over them and rains down a barrage through Random Arty's
	ArtilleryFireMission, from its Muzzle, with no warning. Random Arty bumps its
	Shots attribute for every shell and sets MissionOver when done; then it flies
	back to its station. The only sound before it is its arrival when it spawns.

	It is tagged BloxianGunship, and an enemy F-4 Phantom's missile sets ShotDown: it
	goes down burning and any barrage it is firing stops.
]]

local debris = game:GetService("Debris")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

--Height above the ground it circles (studs), orbit radius, airspeed (studs/s),
--how far it banks into the orbit (degrees) and how fast it rolls (degrees/s).
local ALTITUDE = 700
local ORBIT_RADIUS = 350
local SPEED = 110
local BANK = 20
local ROLL_RATE = 12

--How fast the orbit's centre slides to a new target or back to station (studs/s).
local RELOCATE_SPEED = 90

--Its own barrages: the first FIRST_BARRAGE seconds after it arrives, then every
--BARRAGE_INTERVAL seconds. It shells the spot with the most enemies within
--CLUSTER_RADIUS, out to BARRAGE_RANGE (flat) from its station, never one with a
--friend within DANGER_CLOSE. It flies over first, for up to OVERHEAD_WAIT seconds.
local FIRST_BARRAGE = 15
local BARRAGE_INTERVAL = NumberRange.new(30,50)
local BARRAGE_RANGE = 800
local CLUSTER_RADIUS = 25
local DANGER_CLOSE = 30
local OVERHEAD_WAIT = 12

--Shot down: how fast it falls (studs/s) and rolls (radians/s).
local FALL_SPEED = 90
local FALL_SPIN = 0.6
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

--The sound every player hears when it spawns (heard everywhere, not from the
--plane), and its volume.
local ARRIVAL_SOUND = "rbxassetid://8261242927"
local ARRIVAL_VOLUME = 1.1

--The flash at the muzzle for each shell: colour, size (studs) and seconds.
local FLASH_COLOR = Color3.fromRGB(255,200,120)
local FLASH_SIZE = 8
local FLASH_TIME = 0.08

--The gun's sound for each shell (the 40 mm), played from the muzzle.
local FIRE_SOUND = "rbxassetid://18754665604"

local HOSTILE = "Hostile"

local gunship = script.Parent
local root = gunship.PrimaryPart

--Every part rides on the root: welded here rather than in the file, then let go.
for _,part in ipairs(gunship:GetDescendants()) do
	if part:IsA("BasePart") and part ~= root then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Anchored = false
	end
end
local muzzle = root:FindFirstChild("Muzzle")
local fireSound = muzzle and muzzle:FindFirstChild("Fire")
if muzzle and not fireSound then
	fireSound = Instance.new("Sound")
	fireSound.Name = "Fire"
	fireSound.Parent = muzzle
end
if fireSound then
	fireSound.SoundId = FIRE_SOUND
end
local settings = gunship:FindFirstChild("Settings")
local teamValue = settings and settings:FindFirstChild("Team")

local function syncTeam()
	local team = teamValue and teamValue.Value or ""
	gunship:SetAttribute("Team",team ~= "" and team or HOSTILE)
end
syncTeam()
if teamValue then
	teamValue.Changed:Connect(syncTeam)
end
gunship:SetAttribute("OnMission",false)
gunship:AddTag("BloxianGunship")

--Everyone hears it come on station.
local arrival = Instance.new("Sound")
arrival.Name = "AC130Arrival"
arrival.SoundId = ARRIVAL_SOUND
arrival.Volume = ARRIVAL_VOLUME
arrival.Parent = workspace
arrival:Play()
debris:AddItem(arrival,15)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = {gunship}

--Station: the ground under where it was spawned.
local spawnAt = root.Position
local below = workspace:Raycast(spawnAt + Vector3.new(0,50,0),Vector3.new(0,-2000,0),groundParams)
local station = (below and below.Position or spawnAt) + Vector3.new(0,ALTITUDE,0)
local center = station
local rate = SPEED/ORBIT_RADIUS

--It circles with the centre always on its left, the side its guns are on.
local angle = math.random()*2*math.pi
local function orbitPoint(at)
	return center + Vector3.new(math.cos(at),0,math.sin(at))*ORBIT_RADIUS
end
local function orbitForward(at)
	return Vector3.new(math.sin(at),0,-math.cos(at))
end

local falling = false
local fallTime = 0
local bank = 0
local position = orbitPoint(angle)
local heading = orbitForward(angle)

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

local function place()
	root.CFrame = CFrame.lookAt(position,position + heading) * CFrame.Angles(0,0,math.rad(bank))
end
place()

--Where the orbit's centre is headed: over the target on a mission, else station.
local function goalCenter()
	local target = gunship:GetAttribute("Target")
	if gunship:GetAttribute("OnMission") and typeof(target) == "Vector3" then
		return Vector3.new(target.X,target.Y + ALTITUDE,target.Z)
	end
	return station
end

gunship:GetAttributeChangedSignal("Shots"):Connect(function()
	if not muzzle then return end
	--A copy per shell, so each one rings out instead of cutting off the last.
	if fireSound then
		local shot = fireSound:Clone()
		shot.Parent = muzzle
		shot:Play()
		debris:AddItem(shot,4)
	end
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.one*FLASH_SIZE
	flash.Material = Enum.Material.Neon
	flash.Color = FLASH_COLOR
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.CFrame = muzzle.WorldCFrame
	flash.Parent = gunship
	debris:AddItem(flash,FLASH_TIME)
end)

local connection
connection = runService.Heartbeat:Connect(function(dt)
	if not gunship.Parent or not root.Parent then
		connection:Disconnect()
		return
	end

	local artilleryBlast = game:GetService("ServerStorage"):FindFirstChild("ArtilleryBlast")
	if gunship:GetAttribute("ShotDown") and not falling then
		falling = true
		gunship:SetAttribute("OnMission",false)
		engulf(gunship)
	end
	if falling then
		fallTime += dt
		bank += FALL_SPIN*math.deg(dt)
		position += heading*SPEED*0.7*dt - Vector3.new(0,FALL_SPEED*dt,0)
		root.CFrame = CFrame.lookAt(position,position + heading - Vector3.new(0,0.5,0)) * CFrame.Angles(0,0,math.rad(bank))
		local hit = workspace:Raycast(position,Vector3.new(0,-30,0),groundParams)
		if hit or fallTime > 30 then
			--Random Arty's impact, CRASH_SCALE times over, else a plain explosion.
			local at = hit and hit.Position or position
			if artilleryBlast then
				artilleryBlast:Fire(at,CRASH_SCALE)
			else
				local explosion = Instance.new("Explosion")
				explosion.Position = at
				explosion.BlastRadius = 40
				explosion.BlastPressure = 0
				explosion.DestroyJointRadiusPercent = 0
				explosion.ExplosionType = Enum.ExplosionType.NoCraters
				explosion.Parent = workspace
			end
			connection:Disconnect()
			wreck(gunship,root,at,heading)
		end
		return
	end

	--Barrage done: back to station.
	if gunship:GetAttribute("OnMission") and gunship:GetAttribute("MissionOver") then
		gunship:SetAttribute("OnMission",false)
	end

	local toGoal = goalCenter() - center
	local step = RELOCATE_SPEED*dt
	center = toGoal.Magnitude <= step and goalCenter() or center + toGoal.Unit*step

	angle -= rate*dt
	position = orbitPoint(angle)
	heading = orbitForward(angle)
	bank += math.clamp(BANK - bank,-ROLL_RATE*dt,ROLL_RATE*dt)
	place()
end)

--Everyone alive on the ground, as {root, team}: players by their Roblox team
--and Bloxians by Settings.Team. A player on no team is only an enemy of a
--Hostile gunship; to any other he counts as a friend.
local function people()
	local list = {}
	for _,player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local human = character and character:FindFirstChildOfClass("Humanoid")
		if root and human and human.Health > 0 then
			local team = player.Team and not player.Neutral and player.Team.Name
			if not team then
				team = gunship:GetAttribute("Team") == HOSTILE and "" or gunship:GetAttribute("Team")
			end
			list[#list+1] = {root = root, team = team}
		end
	end
	for _,model in ipairs(CollectionService:GetTagged("Bloxian")) do
		local root = model:FindFirstChild("HumanoidRootPart")
		local human = model:FindFirstChildOfClass("Humanoid")
		local settings = model:FindFirstChild("Settings")
		local team = settings and settings:FindFirstChild("Team")
		if root and human and human.Health > 0 and model:IsDescendantOf(workspace) then
			list[#list+1] = {root = root, team = team and team.Value or ""}
		end
	end
	return list
end

--Where to shell: the enemy with the most other enemies around him, with no
--friend near. nil if there is nobody to shell.
local function pickTarget()
	local team = gunship:GetAttribute("Team")
	local enemies,friends = {},{}
	for _,person in ipairs(people()) do
		local flat = Vector3.new(person.root.Position.X - station.X,0,person.root.Position.Z - station.Z)
		if person.team == team then
			friends[#friends+1] = person.root
		elseif flat.Magnitude <= BARRAGE_RANGE then
			enemies[#enemies+1] = person.root
		end
	end

	local best,bestCount = nil,0
	for _,enemy in ipairs(enemies) do
		local safe = true
		for _,friend in ipairs(friends) do
			if (friend.Position - enemy.Position).Magnitude < DANGER_CLOSE then
				safe = false
				break
			end
		end
		if safe then
			local count = 0
			for _,other in ipairs(enemies) do
				if (other.Position - enemy.Position).Magnitude <= CLUSTER_RADIUS then
					count += 1
				end
			end
			if count > bestCount then
				best,bestCount = enemy,count
			end
		end
	end
	return best
end

local function airborne()
	return gunship.Parent ~= nil and root.Parent ~= nil and not falling and not gunship:GetAttribute("ShotDown")
end

task.spawn(function()
	task.wait(FIRST_BARRAGE)
	while airborne() do
		local mission = ServerStorage:FindFirstChild("ArtilleryFireMission")
		local target = mission and pickTarget()
		if not mission then
			warn("[AC130] ServerStorage.ArtilleryFireMission is missing, so the gunship cannot fire. Install or re-sync the current Random Arty package.")
			return
		end
		if target then
			gunship:SetAttribute("Target",target.Position)
			gunship:SetAttribute("MissionOver",false)
			gunship:SetAttribute("OnMission",true)
			local flyUntil = os.clock() + OVERHEAD_WAIT
			while airborne() and os.clock() < flyUntil and (goalCenter() - center).Magnitude > 30 do
				task.wait(0.5)
			end
			if not airborne() then return end

			local aim = target.Parent and target.Position or gunship:GetAttribute("Target")
			local called,ok = pcall(mission.Invoke,mission,aim,{gunship = gunship})
			if not called or not ok then
				gunship:SetAttribute("OnMission",false)
			end
			while airborne() and gunship:GetAttribute("OnMission") do
				task.wait(0.5)
			end
		end
		task.wait(BARRAGE_INTERVAL.Min + math.random()*(BARRAGE_INTERVAL.Max - BARRAGE_INTERVAL.Min))
	end
end)

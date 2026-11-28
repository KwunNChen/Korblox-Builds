------Respawn------
local marine = script.Parent.Parent.Parent
local myHead = marine.Head
local myHuman = marine.Humanoid

--The respawn clone is built from this, so it must be set first.
if not marine.PrimaryPart then
	marine.PrimaryPart = marine.Torso
end

--Only soldiers that can respawn pay for a spare copy.
local clone = marine.Settings.Respawn.Value and marine:Clone() or nil

--RandomizeAppearance waits for this, so the spare copy is never cloned with a look already on it.
marine:SetAttribute("BloxianCloned",true)

local modules = script.Parent.Parent.Modules
local actions = require(modules.ActionsModule)
local status = require(modules.Status)
local chatter = require(modules.ChatterModule)

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local myRoot = marine.HumanoidRootPart

--Bloxians pass through each other (no shoving, no climbing onto heads), but not players or the world.
local SOLDIER_GROUP = "Bloxian"
if not PhysicsService:IsCollisionGroupRegistered(SOLDIER_GROUP) then
	PhysicsService:RegisterCollisionGroup(SOLDIER_GROUP)
end
PhysicsService:CollisionGroupSetCollidable(SOLDIER_GROUP,SOLDIER_GROUP,false)
PhysicsService:CollisionGroupSetCollidable(SOLDIER_GROUP,"BloxianProne",false)
for _,part in ipairs(marine:GetChildren()) do
	if part:IsA("BasePart") then
		part.CollisionGroup = SOLDIER_GROUP
	end
end

--Leaning into where they walk is drawn by each client (Scripts.Client.BloxianLean).
--The first soldier in a server puts one copy of it, switched on, in ReplicatedStorage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
if not ReplicatedStorage:FindFirstChild("BloxianLean") then
	local leanScript = script.Parent.Parent.Client.BloxianLean:Clone()
	leanScript.Enabled = true
	leanScript.Parent = ReplicatedStorage
end

--Fall damage: landing faster than FALL_SAFE_SPEED (studs/s down; about an 18
--stud drop) hurts, FALL_LETHAL_SPEED (about 50 studs) or faster kills, evenly
--in between. A parachute lands far slower than either.
local FALL_SAFE_SPEED = 85
local FALL_LETHAL_SPEED = 140

--Sound variables
local runningSound = myHead.Running
local jumpingSound = myHead.Jumping
local hurtSound = myHead.Hurt
local diedSound = myHead.Died

--Footsteps and jumps: how loud (STEP_VOLUME, or by Settings.Unit), the distance
--they stay at full volume, and how far they carry.
local STEP_VOLUME = 0.2
local STEP_VOLUME_BY_UNIT = {Infantry = 0.4, ["Special Recon"] = 0.05}
local STEP_FULL_VOLUME_RANGE = 4
local STEP_HEARING = 40
local unitSetting = marine.Settings:FindFirstChild("Unit")
local stepVolume = unitSetting and STEP_VOLUME_BY_UNIT[unitSetting.Value] or STEP_VOLUME
for _,sound in ipairs({runningSound,jumpingSound,myHead:FindFirstChild("Landing")}) do
	sound.Volume = stepVolume
	sound.RollOffMinDistance = STEP_FULL_VOLUME_RANGE
	sound.RollOffMaxDistance = STEP_HEARING
end

--No "BLOXIAN" name (or health bar) over his head.
myHuman.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

--GettingUp is off (below), so a soldier knocked over by a blast would never stand again.
myHuman:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
myHuman:SetStateEnabled(Enum.HumanoidStateType.Flying,false)
myHuman:SetStateEnabled(Enum.HumanoidStateType.GettingUp,false)
myHuman:SetStateEnabled(Enum.HumanoidStateType.Physics,false)
myHuman:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false)
myHuman:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics,false)
myHuman:SetStateEnabled(Enum.HumanoidStateType.StrafingNoPhysics,false)
myHuman:SetStateEnabled(Enum.HumanoidStateType.Swimming,false)

--Limbs that collide with the world once ragdolled. HumanoidRootPart must stay
--off or it fights the Torso and the body jitters or sinks.
local ragdollCollide = {
	["Head"] = true,
	["Torso"] = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
}

--Seconds the ragdolled body lies there, whether or not he respawns, then how
--long it takes to fade out before it is removed.
local CORPSE_TIME = 15
local fadeInfo = TweenInfo.new(1)

--Seconds the hurt face stays up after the last hit.
local HURT_FACE_TIME = 1

myHuman.Running:Connect(function(speed)
	if speed>0 then
		runningSound:Play()
	else
		runningSound:Stop()
	end
end)

myHuman.Jumping:Connect(function()
	jumpingSound:Play()
end)

--Footsteps like players': SPH's walk sounds by floor material, one per step (as SPH_Player.Footsteps).
--Replaces the looped Running sound when SPH is in the place.
local WALK_SETS = {
	CorrodedMetal = "Metal", DiamondPlate = "Metal", Fabric = "Sand", Glacier = "Ground", Grass = "Grass",
	Ground = "Ground", LeafyGrass = "Grass", Metal = "Metal", Mud = "Mud", Neon = "Metal", Pebble = "Ground",
	Salt = "Ground", Sand = "Sand", Snow = "Sand", Wood = "Wood", WoodPlanks = "Wood",
}
local STEP_HEARD_FULL, STEP_HEARD_MAX = 10, 70
local sph = ReplicatedStorage:FindFirstChild("SPH_Assets")
local walkSounds = sph and sph:FindFirstChild("Sounds") and sph.Sounds:FindFirstChild("WalkSounds")

--SPH's ragdoll (joint limits, stiff-then-loose joints, no bounce) when the place has it: the body crumples
--where it stands, like a player corpse. Otherwise the model's own loose *Rag sockets.
local ragdollMod = sph and sph:FindFirstChild("Modules") and sph.Modules:FindFirstChild("RagdollMod")
ragdollMod = ragdollMod and require(ragdollMod)
if walkSounds and walkSounds:FindFirstChild("Concrete") then
	runningSound.Volume = 0
	local step = Instance.new("Sound")
	step.Name = "Footstep"
	step.RollOffMinDistance = STEP_HEARD_FULL
	step.RollOffMaxDistance = STEP_HEARD_MAX
	step.Parent = myRoot
	local loudness = stepVolume/0.4 --Infantry 1, Special Recon creeps
	task.spawn(function()
		while marine.Parent and myHuman.Health > 0 do
			local speed = myRoot.AssemblyLinearVelocity.Magnitude
			local floor = myHuman.FloorMaterial
			if speed > math.max(2,myHuman.WalkSpeed/2) and floor ~= Enum.Material.Air and floor ~= Enum.Material.Water then
				local set = walkSounds:FindFirstChild(WALK_SETS[floor.Name] or "Concrete") or walkSounds.Concrete
				local list = set:GetChildren()
				local pick = list[math.random(#list)]
				step.SoundId = pick.SoundId
				step.PlaybackSpeed = pick.PlaybackSpeed + math.random(-100,100)/1000
				step.Volume = math.min(0.4*speed/10,1)*loudness --players: 0.4 * speed/10
				step:Play()
				task.wait(0.5*10/speed)
			else
				task.wait(0.1)
			end
		end
	end)
end

local fallSpeed = 0
myHuman.StateChanged:Connect(function(_,new)
	if new == Enum.HumanoidStateType.Freefall then
		fallSpeed = 0
		task.spawn(function()
			while myHuman:GetState() == Enum.HumanoidStateType.Freefall do
				fallSpeed = math.max(fallSpeed,-myRoot.AssemblyLinearVelocity.Y)
				RunService.Heartbeat:Wait()
			end
		end)
	elseif new == Enum.HumanoidStateType.Landed and fallSpeed > FALL_SAFE_SPEED and myHuman.Health > 0 then
		local share = math.clamp((fallSpeed - FALL_SAFE_SPEED)/(FALL_LETHAL_SPEED - FALL_SAFE_SPEED),0,1)
		fallSpeed = 0
		--Soldier AI: nobody to fire back at.
		marine:SetAttribute("FellAt",workspace:GetServerTimeNow())
		myHuman:TakeDamage(myHuman.MaxHealth*share)
	end
end)

myHuman.Died:Connect(function()
	diedSound:Play()
	actions.yieldM4()
	actions.updateFace("Dead")
	chatter.died()

	--The body is ragdolled and its motors are off, so Animate has nothing left to drive.
	local animate = script.Parent:FindFirstChild("Animate")
	if animate then
		animate.Enabled = false
	end
	for _,track in ipairs(myHuman:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end

	--One traversal instead of two: ragdoll the joints and collect what needs
	--fading in the same pass.
	local fadeTargets = {}
	if ragdollMod then
		ragdollMod.LimitR6(marine)
	end
	for _,v in ipairs(marine:GetDescendants()) do
		if v:IsA("BallSocketConstraint") then
			v.Enabled = v.Enabled or not ragdollMod --SPH's new sockets are already on; the model's own stay off
		elseif v:IsA("Motor6D") then
			v.Enabled = false
		elseif v:IsA("BasePart") then
			v.CanCollide = ragdollCollide[v.Name] == true
			--A corpse must not keep firing Touched and answering raycasts.
			v.CanTouch = false
			v.CanQuery = false
			if v.Transparency < 1 then
				fadeTargets[#fadeTargets+1] = v
			end
		elseif v:IsA("Decal") then
			fadeTargets[#fadeTargets+1] = v
		end
	end

	--The respawn copy goes in on its own timer. This script puts it there, so
	--the faded body is kept, out of the way, until then.
	local parent = marine.Parent
	local respawnAt = clone and marine.Settings.Respawn.Value and os.clock() + marine.Settings.RespawnDelay.Value
	local respawned = false
	local function respawn()
		if respawnAt and not respawned then
			respawned = true
			clone.Parent = parent or workspace
		end
	end
	if respawnAt then
		task.delay(respawnAt - os.clock(),respawn)
	end

	task.wait(CORPSE_TIME)
	for _,v in ipairs(fadeTargets) do
		TweenService:Create(v,fadeInfo,{Transparency = 1}):Play()
	end
	task.wait(fadeInfo.Time + 0.05)

	for _,v in ipairs(marine:GetDescendants()) do
		if v:IsA("BasePart") then
			v.Anchored = true
			v.CanCollide = false
		end
	end
	if respawnAt and os.clock() < respawnAt then
		task.wait(respawnAt - os.clock())
	end
	respawn()
	marine:Destroy()
end)

local oldHealth = myHuman.Health
local soundSpeeds = {0.9,0.95,1,1.05,1.1}
local hurtToken = 0
--Seconds after a fall that a loss of health is put down to it, not to an enemy.
local FALL_HURT_TIME = 1
myHuman.HealthChanged:Connect(function(health)
	if health < oldHealth and health > 0 then
		status:set("tookDamage",true)
		status:set("lastDamaged",os.clock())
		if workspace:GetServerTimeNow() - (marine:GetAttribute("FellAt") or -math.huge) > FALL_HURT_TIME then
			status:set("lastHit",os.clock())
		end
		chatter.hit()

		if math.random(3) == 1 and not hurtSound.IsPlaying then
			hurtSound.PlaybackSpeed = soundSpeeds[math.random(#soundSpeeds)]
			hurtSound:Play()
		end

		actions.updateFace("Hurt")
		hurtToken += 1
		local token = hurtToken
		task.delay(HURT_FACE_TIME,function()
			if token == hurtToken then
				actions.updateFace(status:get("pendingMood") or "Idle",true)
			end
		end)
	end
	oldHealth = health
end)

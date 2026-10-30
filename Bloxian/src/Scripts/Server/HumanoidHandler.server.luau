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

--Sound variables
local runningSound = myHead.Running
local jumpingSound = myHead.Jumping
local hurtSound = myHead.Hurt
local diedSound = myHead.Died

--Footsteps and jumps: how loud, the distance they stay at full volume, and how far they carry.
local STEP_VOLUME = 0.2
local STEP_FULL_VOLUME_RANGE = 4
local STEP_HEARING = 40
for _,sound in ipairs({runningSound,jumpingSound,myHead:FindFirstChild("Landing")}) do
	sound.Volume = STEP_VOLUME
	sound.RollOffMinDistance = STEP_FULL_VOLUME_RANGE
	sound.RollOffMaxDistance = STEP_HEARING
end

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
	for _,v in ipairs(marine:GetDescendants()) do
		if v:IsA("BallSocketConstraint") then
			v.Enabled = true
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
myHuman.HealthChanged:Connect(function(health)
	if health < oldHealth and health > 0 then
		status:set("tookDamage",true)
		status:set("lastDamaged",os.clock())
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

local actions = {}

--Services
local debrisService = game:GetService("Debris")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")

--Required Modules
local modules = script.Parent
local status = require(modules.Status)
local speed = require(modules.SpeedModule)
local core = require(modules.CoreModule)
local chatter = require(modules.ChatterModule)
local weapon = require(modules.WeaponProfiles).current

local marine = modules.Parent.Parent
local myHuman = marine.Humanoid
local myRoot = marine.HumanoidRootPart
local m4 = marine.M4
local reloadSound = m4.Reload
local magazine = marine.Mag

--Seconds a reload may take before the soldier gives up waiting on the animation.
local RELOAD_TIMEOUT = 3

--Seconds to bring the rifle up or down.
local RAISE_TIME = 0.3

--Seconds between aim updates, and how far (a dot product) he turns before his
--facing is written again. Every write goes over the network to every player.
local AIM_STEP = 0.1
local AIM_TURN_DOT = 0.9995

--Seconds he keeps aiming at a target he can no longer see. After that he lets
--go, so he walks facing where he is going instead of staring through walls.
local AIM_LINGER = 1

local myHead = marine.Head
local myTorso = marine.Torso
local neck = myTorso.Neck
local lShoulder = myTorso["Left Shoulder"]
local rShoulder = myTorso["Right Shoulder"]
local lArmWeld = myTorso["Left Arm Weld"]
local rArmWeld = myTorso["Right Arm Weld"]
local lArm = marine["Left Arm"]
local rArm = marine["Right Arm"]
local m4Weld = m4["M4 Weld"]

--Motors--
local lHip = myTorso["Left Hip"]
local lHipOrg = lHip.C0
local rHip = myTorso["Right Hip"]
local rHipOrg = rHip.C0
local rootJoint = myRoot.RootJoint
local rootJointOrg = rootJoint.C0

--Align Orientations
local bodyRotate = myRoot.AlignOrientation

--How fast he swings round to aim. The model ships at 200, which snaps.
local AIM_TURN_SPEED = 40
bodyRotate.Responsiveness = AIM_TURN_SPEED

local yAxisAttach = Instance.new("Attachment")
yAxisAttach.Parent = workspace.Terrain
yAxisAttach.CFrame = myRoot.CFrame

bodyRotate.Attachment1 = yAxisAttach

--The attachments live in Terrain, so they outlive the soldier unless removed.
marine.Destroying:Connect(function()
	yAxisAttach:Destroy()
end)

local m4Hinge = m4.HingeConstraint
local m4HingeAttach0 = m4Hinge.Attachment0
local m4HingeAttach = m4.HingeAttach1
local torsoHingeAttach = myTorso.HingeAttach0
local torsoHingAttachOrgPos = torsoHingeAttach.Position
local headHinge = myHead.HingeConstraint

--Body poses: how far the torso sinks (studs), how far it pitches forward, and
--how far the head lifts (degrees).
local STANCES = {
	stand = {drop = 0, pitch = 0, neck = 0},
	prone = {drop = 2.4, pitch = 90, neck = 80},
}
local STANCE_TIME = 0.35
--Least seconds between going prone and getting up (either way; riding skips it),
--and his share of his usual walk speed while prone.
local STANCE_COOLDOWN = 3
local PRONE_SPEED = 0.6

--Where his eyes would be in each pose, off his root (prone: down and forward),
--for checking he can still see his target from it.
local EYE = {
	prone = Vector3.new(0,-2.2,-1.5),
}
local POSTURE_INTERVAL = 0.3

--Lying down with the ground or a ledge between his barrel and the target, he
--gets up and stays up this many seconds before trying prone again.
local PRONE_BLOCKED_WAIT = 10

--Prone, the rifle's pivot moves this far off the shoulder, in torso space (+Z is
--up when he lies face down, +Y toward his head), so the rifle clears the ground.
local PRONE_HINGE = Vector3.new(0,0.4,0.9)

local stance = "stand"
local pose = table.clone(STANCES.stand)
local aimTilt = 0

--Prone, the torso and head lie on the ground: in this group they do not push off it.
local PRONE_GROUP = "BloxianProne"
pcall(function()
	PhysicsService:RegisterCollisionGroup(PRONE_GROUP)
	PhysicsService:CollisionGroupSetCollidable(PRONE_GROUP,"Default",false)
end)
local proneParts = {}
local function collectProneParts()
	for _,part in ipairs({myTorso,myHead,lArm,rArm,m4}) do
		proneParts[part] = proneParts[part] or part.CollisionGroup
	end
	for _,part in ipairs(m4:GetDescendants()) do
		if part:IsA("BasePart") then
			proneParts[part] = proneParts[part] or part.CollisionGroup
		end
	end
end

--Where the rifle's pivot sits on the torso for the current pose and aim tilt.
local function hingeSpot(tilt)
	return torsoHingAttachOrgPos + Vector3.new(0,tilt/90,0) + PRONE_HINGE*(pose.pitch/90)
end

local function applyPose()
	torsoHingeAttach.Position = hingeSpot(aimTilt)
	--The rifle swings on a hinge at the chest; keep its axis level however he lies.
	m4HingeAttach0.WorldCFrame = CFrame.new(m4HingeAttach0.WorldPosition)*CFrame.fromEulerAnglesYXZ(0,math.rad(myRoot.Orientation.Y),0)
	local tilt = aimTilt*(1 - pose.pitch/90)
	rootJoint.C0 = rootJointOrg*CFrame.new(0,0,-pose.drop)*CFrame.fromEulerAnglesYXZ(math.rad(pose.pitch + tilt),0,0)
	rHip.C0 = rHipOrg*CFrame.fromEulerAnglesYXZ(0,0,math.rad(tilt))
	lHip.C0 = lHipOrg*CFrame.fromEulerAnglesYXZ(0,0,math.rad(-tilt))
end

local reloadAnimation = myHuman:LoadAnimation(marine.Reload)
reloadAnimation.Priority = Enum.AnimationPriority.Action

function actions.aim()

	local aimPos = Vector3.zero
	local lastSeen = os.clock()
	local written,facing = nil,nil

	status:set("weaponAimed",true)
	myHuman.AutoRotate = false
	bodyRotate.Enabled = true
	speed.set(10)

	while true do

		local target = status:get("currentTarget")

		if myHuman.Health <=0 or not target or not target.Parent then
			break
		elseif not status:get("m4Equipped") and not status:get("reloading") then
			break
		end

		local dist = math.max(core.checkDist(target,myTorso),1)
		if core.checkSight(target) then
			lastSeen = os.clock()
			if speed.get() == 16 and not status:get("closingIn") then
				speed.set(10)
			end
		elseif os.clock() - lastSeen > AIM_LINGER and not status:get("reloading") then
			break
		elseif speed.get() == 10 then
			--Nobody in sight: he runs, rifle up.
			speed.set(16)
		end

		aimPos = target.Position

		local tilt = math.round(math.clamp((myRoot.Position.Y - aimPos.Y)/(dist*0.04),-45,45))
		local toAim = aimPos - m4.Position
		local aimPitch = toAim.Magnitude > 0.1 and math.round(math.deg(math.asin(toAim.Unit.Y))) or 0
		local equipped = status:get("m4Equipped")

		local state = string.format("%d %d %d %s",tilt,aimPitch,math.round(pose.pitch),tostring(equipped))
		if state ~= written then
			written = state
			aimTilt = tilt
			applyPose()
			m4Hinge.TargetAngle = aimPitch
			headHinge.TargetAngle = aimPitch
			neck.C0 = CFrame.new(0,1,0) * CFrame.Angles(-1.5 + math.rad(aimPitch + pose.neck),equipped and math.rad(15) or 0,math.rad(180))
		end

		local flat = Vector3.new(toAim.X,0,toAim.Z)
		if flat.Magnitude > 0.1 and (not facing or facing:Dot(flat.Unit) < AIM_TURN_DOT) then
			facing = flat.Unit
			yAxisAttach.WorldCFrame = CFrame.lookAt(m4.Position,Vector3.new(aimPos.X,myRoot.Position.Y,aimPos.Z))
		end

		task.wait(AIM_STEP)
	end


	actions.resetHead()
	bodyRotate.Enabled = false
	speed.set(16)
	myHuman.AutoRotate = true

	--Rifle back to level: lying down it stays drawn, and would keep pointing
	--where the lost target was (into the ground below a perch).
	m4Hinge.TargetAngle = 0
	headHinge.TargetAngle = 0
	aimTilt = 0
	applyPose()

	status:set("weaponAimed",false)
end

function actions.reload()
	--Cover and the gun can both ask for a reload at once.
	if status:get("reloading") or myHuman.Health <= 0 then
		return
	end

	status:set("weaponAimed",false)
	reloadSound:Play()
	status:set("reloading",true)
	chatter.reload()

	actions.yieldM4()

	m4Weld.Part0 = nil
	m4.CFrame = lArm.CFrame * CFrame.new(0.5,-0.2,0) * CFrame.Angles(math.rad(-90),math.rad(0),math.rad(0))
	m4Weld.Part0 = lArm

	reloadAnimation:Play()
	reloadAnimation:AdjustSpeed(3/weapon.reloadTime)

	task.wait(0.2)

	--A gun model from GunModels brings its own magazine.
	local gunModel = m4:FindFirstChild("GunModel")
	local mag = gunModel and gunModel:FindFirstChild("Mag") or magazine
	local fakeMag = mag:Clone()
	for _,joint in ipairs(fakeMag:GetDescendants()) do
		if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
			joint:Destroy()
		end
	end
	fakeMag.Anchored = false
	fakeMag.Massless = false
	fakeMag.CanCollide = true
	fakeMag.CanQuery = false
	fakeMag.CanTouch = false
	fakeMag.Parent = workspace
	debrisService:AddItem(fakeMag,4)
	mag.Transparency = 1

	local deadline = os.clock() + RELOAD_TIMEOUT
	while reloadAnimation.IsPlaying and os.clock() < deadline and myHuman.Health > 0 do
		task.wait(0.05)
	end

	mag.Transparency = 0
	status:set("reloading",false)
	status:set("mag",weapon.magSize)
	if myHuman.Health > 0 then
		actions.drawM4()
	end
end

function actions.drawM4()
	actions.yieldKnife()
	if not status:get("m4Equipped") and not status:get("reloading") then
		status:beginAction()
		status:set("m4Equipped",true)
		status:set("m4Lowered",false)
		m4.Equip:Play()

		--M4 Setup
		m4Weld.Part0 = nil
		local poseShift = torsoHingeAttach.WorldPosition - myRoot.CFrame:PointToWorldSpace(torsoHingAttachOrgPos)
		m4.CFrame = CFrame.new(poseShift) * myRoot.CFrame * CFrame.new(0.65,-1.6,0) * CFrame.Angles(math.rad(-90),math.rad(0),math.rad(0))
		m4HingeAttach.WorldPosition = torsoHingeAttach.WorldPosition
		m4Hinge.Enabled = true

		--Right Arm Setup
		rShoulder.Part1 = nil
		rArmWeld.Part1 = nil --x 1.25
		rArmWeld.Enabled = false
		rArm.CFrame = m4.CFrame * CFrame.new(0.7,-0.4,1.5) * CFrame.Angles(math.rad(80),math.rad(0),math.rad(-10))
		rArmWeld.Part1 = rArm
		rArmWeld.Enabled = true

		--Left Arm Setup
		lShoulder.Part1 = nil
		lArmWeld.Part1 = nil
		lArm.CFrame = m4.CFrame * CFrame.new(-1,-0.3,0.8) * CFrame.Angles(math.rad(90),math.rad(-3),math.rad(28)) --x84
		lArmWeld.Part1 = lArm

		task.wait(RAISE_TIME)
		status:endAction()
	end
end



function actions.yieldM4()
	if status:get("m4Equipped") or status:get("m4Lowered") then

		status:set("m4Equipped",false)
		status:set("weaponAimed",false)
		status:set("m4Lowered",false)

		m4.Equip:Play()

		--Right Arm setup
		rArmWeld.Part1 = nil
		rShoulder.Part1 = rArm

		--Left Arm Setup
		lArmWeld.Part1 = nil
		lShoulder.Part1 = lArm

		--M4 Setup
		m4Weld.Part0 = nil
		m4Hinge.Enabled = false
		m4.CFrame = myTorso.CFrame * CFrame.new(0,0,0.5) * CFrame.Angles(math.rad(-90),math.rad(45),math.rad(-270))
		m4Weld.Part0 = myTorso
	end
end

function actions.lowerM4()
	if not status:get("m4Lowered") and status:get("m4Equipped") and not status:get("reloading") then

		status:beginAction()
		status:set("m4Equipped",false)
		status:set("m4Lowered",true)

		m4.Equip:Play()

		--M4 Setup
		m4Hinge.Enabled = false
		m4Weld.Part0 = nil
		m4.CFrame = myTorso.CFrame * CFrame.new(-0.5,-0.9,-1) * CFrame.Angles(math.rad(-75),math.rad(55),math.rad(75)) -- z 35 x 0
		m4Weld.Part0 = myTorso

		--Right Arm Setup
		rShoulder.Part1 = nil
		rArmWeld.Part1 = nil
		rArm.CFrame = myTorso.CFrame * CFrame.new(1.3,-0.2,-0.3) * CFrame.Angles(math.rad(30),math.rad(14),math.rad(-25))
		rArmWeld.Part1 = rArm

		--Left Arm Setup
		lShoulder.Part1 = nil
		lArmWeld.Part1 = nil
		lArm.CFrame = myTorso.CFrame * CFrame.new(-1.3,-0.1,-0.3) * CFrame.Angles(math.rad(40),math.rad(-3),math.rad(10)) --x84
		lArmWeld.Part1 = lArm

		task.wait(RAISE_TIME)
		status:endAction()
	end
end

--Low ready: rifle in both hands, muzzle down, a moment from the shoulder.
function actions.readyM4()
	if status:get("m4Lowered") or status:get("reloading") then return end
	actions.yieldKnife()
	if not status:get("m4Equipped") then
		actions.drawM4()
	end
	actions.lowerM4()
end

local knife = marine.Knife

--Drawing and putting away the rifle or knife: how loud, the distance it stays
--at full volume, and how far away it carries.
local EQUIP_VOLUME = 0.1
local EQUIP_FULL_VOLUME_RANGE = 4
local EQUIP_HEARING = 35
for _,sound in ipairs({m4.Equip,knife.Equip}) do
	sound.Volume = EQUIP_VOLUME
	sound.RollOffMinDistance = EQUIP_FULL_VOLUME_RANGE
	sound.RollOffMaxDistance = EQUIP_HEARING
end

function actions.drawKnife()
	if not status:get("knifeEquipped") then
		actions.yieldM4()
		knife.Equip:Play()
		status:set("knifeEquipped",true)
		knife.Weld.Part0 = nil
		knife.CFrame = rArm.CFrame * CFrame.new(0,-1,-1) * CFrame.Angles(math.rad(90),math.rad(180),math.rad(180))
		knife.Weld.Part0 = rArm
	end
end

function actions.yieldKnife()
	if status:get("knifeEquipped") then
		status:set("knifeEquipped",false)
		knife.Weld.Part0 = nil
		knife.CFrame = myTorso.CFrame * CFrame.new(-1,-1,0.5) * CFrame.Angles(math.rad(-65),0,math.rad(180))
		knife.Weld.Part0 = myTorso
	end
end

function actions.yieldWeapons()
	actions.yieldKnife()
	actions.yieldM4()
end

function actions.resetHead()
	tweenService:Create(neck,TweenInfo.new(0.5),{C0 = CFrame.new(0,1,0) * CFrame.Angles(math.rad(-90 + pose.neck),0,math.rad(180))}):Play()
end

local faces = myHead.Faces
function actions.updateFace(newStatus,recovered)
	local mood = status:get("mood")
	if mood == "Dead" or (mood == newStatus and not recovered) then
		return
	end

	--A hurt face holds until the hurt timer recovers it, later moods wait their turn.
	if mood == "Hurt" and not recovered and newStatus ~= "Dead" then
		status:set("pendingMood",newStatus)
		return
	end

	local newFace = faces:FindFirstChild("face"..newStatus)
	if newFace then
		local oldFace = status:get("currentFace")
		if typeof(oldFace) == "Instance" then
			oldFace.Parent = faces
		end
		newFace.Parent = myHead
		status:set("currentFace",newFace)
	end
	status:set("pendingMood",nil)
	status:set("mood",newStatus)
end


--Moves him into a pose from STANCES over STANCE_TIME.
local stanceToken = 0
local stanceChangedAt = -math.huge
function actions.setStance(name,force)
	if name == stance or not STANCES[name] then return end
	if not force and os.clock() - stanceChangedAt < STANCE_COOLDOWN then return end
	stanceChangedAt = os.clock()
	stance = name
	marine:SetAttribute("Stance",name)
	--Lying down he crawls: whatever sets his speed, he gets PRONE_SPEED of it.
	speed.setProne(name == "prone" and PRONE_SPEED or nil)
	--Torso, head, arms and rifle all lie on the ground prone.
	local prone = name == "prone"
	collectProneParts()
	for part,group in pairs(proneParts) do
		if part.Parent then
			part.CollisionGroup = prone and PRONE_GROUP or group
		end
	end

	stanceToken += 1
	local token = stanceToken
	local from,to = table.clone(pose),STANCES[name]
	task.spawn(function()
		local start = os.clock()
		while token == stanceToken and myHuman.Health > 0 do
			local alpha = math.min((os.clock() - start)/STANCE_TIME,1)
			for key,value in pairs(to) do
				pose[key] = from[key] + (value - from[key])*alpha
			end
			if not status:get("weaponAimed") then
				applyPose()
			end
			if alpha >= 1 then break end
			runService.Heartbeat:Wait()
		end
		if token == stanceToken and not status:get("weaponAimed") then
			actions.resetHead()
		end
	end)
end

--Prone, or still getting up from it.
function actions.isDown()
	return stance ~= "stand" or pose.pitch > 1
end

--Whether he would see target with his eyes at eye (a position).
local function seesFrom(eye,target)
	local hit,result = core.raycast(eye,target.Position - eye)
	return not hit or result.Instance:IsDescendantOf(target.Parent)
end

--Prone if he can still see his target from the ground, and his rifle can
--still shoot him from there, else standing.
local proneBlockedUntil = 0
local function keepSight(want)
	local target = status:get("currentTarget")
	if want ~= "prone" or not target or not target.Parent then
		return want
	end
	if os.clock() < proneBlockedUntil then
		return "stand"
	end
	if stance == "prone" and pose.pitch >= 89 and core.checkSight(target) and not core.checkShot(target) then
		proneBlockedUntil = os.clock() + PRONE_BLOCKED_WAIT
		return "stand"
	end
	if seesFrom(myRoot.CFrame:PointToWorldSpace(EYE.prone),target) then
		return "prone"
	end
	return "stand"
end

--Prone when caught in the open with no cover (status proneUntil), or when his
--team asks for it (status teamStance), if he can still see his target from
--there. Up whenever he moves, rides or holds a knife, once STANCE_COOLDOWN allows.
task.spawn(function()
	while myHuman.Health > 0 and marine.Parent do
		local want = "stand"
		if myHuman.Sit or myHuman.MoveDirection.Magnitude > 0.1 or status:get("knifeEquipped") then
			want = "stand"
		elseif (status:get("proneUntil") or 0) > os.clock() then
			want = keepSight("prone")
		elseif status:get("teamStance") then
			want = keepSight(status:get("teamStance"))
		end
		actions.setStance(want,myHuman.Sit)
		--Down and not aiming, keep the rifle's pivot level (the pose can leave it tipped).
		if stance ~= "stand" and not status:get("weaponAimed") then
			applyPose()
		end
		--Down, he always has his rifle in his hands.
		if stance ~= "stand" and not status:get("m4Equipped") and not status:get("reloading")
			and not status:get("launching") and not status:get("knifeEquipped") then
			actions.drawM4()
		end
		task.wait(POSTURE_INTERVAL)
	end
end)

return actions

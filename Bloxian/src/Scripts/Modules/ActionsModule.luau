local actions = {}

--Services
local debrisService = game:GetService("Debris")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--Required Modules
local modules = script.Parent
local status = require(modules.Status)
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

local xAxisAttach = Instance.new("Attachment")
xAxisAttach.Parent = workspace.Terrain
xAxisAttach.CFrame = myRoot.CFrame

local yAxisAttach = Instance.new("Attachment")
yAxisAttach.Parent = workspace.Terrain
yAxisAttach.CFrame = myRoot.CFrame

bodyRotate.Attachment1 = yAxisAttach

--The attachments live in Terrain, so they outlive the soldier unless removed.
marine.Destroying:Connect(function()
	xAxisAttach:Destroy()
	yAxisAttach:Destroy()
end)

local m4Hinge = m4.HingeConstraint
local m4HingeAttach0 = m4Hinge.Attachment0
local m4HingeAttach = m4.HingeAttach1
local torsoHingeAttach = myTorso.HingeAttach0
local torsoHingAttachOrgPos = torsoHingeAttach.Position
local headHinge = myHead.HingeConstraint

local reloadAnimation = myHuman:LoadAnimation(marine.Reload)
reloadAnimation.Priority = Enum.AnimationPriority.Action

function actions.aim()

	local aimPos = Vector3.zero
	local lastSeen = os.clock()

	status:set("weaponAimed",true)
	myHuman.AutoRotate = false
	bodyRotate.Enabled = true
	myHuman.WalkSpeed = 10

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
		elseif os.clock() - lastSeen > AIM_LINGER and not status:get("reloading") then
			break
		end

		aimPos = core.leadPoint(target,m4.Position,weapon.bulletSpeed)

		local tilt = (myRoot.Position.Y - aimPos.Y) / (dist*0.04)
		tilt = math.clamp(tilt,-45,45)
		rootJoint.C0 = rootJointOrg * CFrame.fromEulerAnglesYXZ(math.rad(tilt),0,0)
		lHip.C0 = lHipOrg * CFrame.fromEulerAnglesYXZ(0,0,math.rad(-tilt))
		rHip.C0 = rHipOrg * CFrame.fromEulerAnglesYXZ(0,0,math.rad(tilt))

		xAxisAttach.WorldCFrame = CFrame.lookAt(m4.Position,aimPos)
		local aimPitch = xAxisAttach.Orientation.X
		m4HingeAttach0.WorldCFrame = CFrame.new(m4HingeAttach0.WorldPosition) * CFrame.fromEulerAnglesYXZ(0,math.rad(myRoot.Orientation.Y),0)
		m4Hinge.TargetAngle = aimPitch
		headHinge.TargetAngle = aimPitch

		torsoHingeAttach.Position = torsoHingAttachOrgPos + Vector3.new(0,tilt/90,0)

		yAxisAttach.WorldCFrame = CFrame.lookAt(m4.Position,Vector3.new(
			aimPos.X,
			myRoot.Position.Y,
			aimPos.Z
			))

		if status:get("m4Equipped") then
			neck.C0 = CFrame.new(0,1,0) * CFrame.Angles(-1.5 + math.rad(aimPitch),math.rad(15),math.rad(180))
		else
			neck.C0 = CFrame.new(0,1,0) * CFrame.Angles(-1.5 + math.rad(aimPitch),0,math.rad(180))
		end

		runService.Heartbeat:Wait()
		runService.Heartbeat:Wait()
	end


	actions.resetHead()
	bodyRotate.Enabled = false
	myHuman.WalkSpeed = 16
	myHuman.AutoRotate = true

	rootJoint.C0 = rootJointOrg
	lHip.C0 = lHipOrg
	rHip.C0 = rHipOrg

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

		xAxisAttach.CFrame = myTorso.CFrame

		--M4 Setup
		m4Weld.Part0 = nil
		m4.CFrame = myRoot.CFrame * CFrame.new(0.65,-1.6,0) * CFrame.Angles(math.rad(-90),math.rad(0),math.rad(0))
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
		rArm.CFrame = myRoot.CFrame * CFrame.new(1.3,-0.2,-0.3) * CFrame.Angles(math.rad(30),math.rad(14),math.rad(-25))
		rArmWeld.Part1 = rArm

		--Left Arm Setup
		lShoulder.Part1 = nil
		lArmWeld.Part1 = nil
		lArm.CFrame = myRoot.CFrame * CFrame.new(-1.3,-0.1,-0.3) * CFrame.Angles(math.rad(40),math.rad(-3),math.rad(10)) --x84
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
	tweenService:Create(neck,TweenInfo.new(0.5),{C0 = CFrame.new(0,1,0) * CFrame.Angles(math.rad(-90),0,math.rad(180))}):Play()
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


return actions

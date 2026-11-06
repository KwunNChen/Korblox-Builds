--[[
	Runs on each client (RunContext Client): Bloxians lean into the way they
	walk, legs turned toward it when they strafe, as players do with the
	DirectionTilting script. Only this client sees it: it sets the hip and root
	joints' C0 locally, on top of whatever the server last set them to (aiming,
	prone), and puts the server's back when it lets go. Lying prone, seated,
	dead and far-off soldiers are left alone.

	It ships disabled inside every soldier. The first soldier to load copies it
	into ReplicatedStorage, switched on, so there is one copy per server.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

--Soldiers further than this from the camera are not leaned.
local LEAN_DISTANCE = 120

--Slower than this (studs/s) with the lean eased off, he is left alone.
local STILL_SPEED = 1
local STILL_LEAN = 0.01

--Soldiers further than this from the camera wear no gear or gun on this client
--(the server's copies are untouched), checked every GEAR_CHECK seconds.
local GEAR_DISTANCE = 200
local GEAR_CHECK = 1

--How far the legs turn toward a sideways step and the torso leans with it
--(degrees between them), and how fast both follow (lower = faster).
local RANGE_OF_MOTION = 40
local RANGE_OF_MOTION_TORSO = 80 - RANGE_OF_MOTION
local LERP_SPEED = 0.005

--How far he tilts into his momentum (per stud/s), and how fast the tilt follows.
local MOMENTUM_FACTOR = 0.02
local SMOOTH_SPEED = 5

local legRange = math.rad(RANGE_OF_MOTION)
local torsoRange = math.rad(RANGE_OF_MOTION_TORSO)
local shiftRange = RANGE_OF_MOTION / 140

local states = {}

--A joint this client is leaning: the server's C0, and what this client last wrote over it.
local function hold(joint)
	local held = {joint = joint, base = joint.C0}
	held.written = held.base
	held.changed = joint:GetPropertyChangedSignal("C0"):Connect(function()
		if joint.C0 ~= held.written then
			held.base = joint.C0
		end
	end)
	return held
end

local function release(model)
	local state = states[model]
	if not state then return end
	for _,held in ipairs(state.joints) do
		held.changed:Disconnect()
		if held.joint.Parent then
			held.joint.C0 = held.base
		end
	end
	states[model] = nil
end

local function set(held,offset)
	held.written = held.base*offset
	held.joint.C0 = held.written
end

local function sideways(amount,range,forward)
	return amount*(range - math.abs(forward)*range/2)
end

local function lean(model,dt)
	local human = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	local rootJoint = root and root:FindFirstChild("RootJoint")
	local rightHip = torso and torso:FindFirstChild("Right Hip")
	local leftHip = torso and torso:FindFirstChild("Left Hip")
	if not (human and rootJoint and rightHip and leftHip) or human.Health <= 0 or human.Sit
		or model:GetAttribute("Stance") == "prone" then
		release(model)
		return
	end

	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - root.Position).Magnitude > LEAN_DISTANCE then
		release(model)
		return
	end

	local state = states[model]
	local speed = root.AssemblyLinearVelocity.Magnitude
	if not state and speed < STILL_SPEED then
		return
	end
	if not state then
		state = {leg = 0, torso = 0, shift = 0, pitch = 0, roll = 0,
			joints = {hold(rootJoint),hold(rightHip),hold(leftHip)}}
		states[model] = state
	end

	local velocity = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
	local walk = velocity/math.max(human.WalkSpeed,1)
	local flip = walk.Z > 0.1 and -1 or 1
	local move = root.CFrame:VectorToObjectSpace(human.MoveDirection)

	local follow = 1 - LERP_SPEED^dt
	local smooth = math.min(dt*SMOOTH_SPEED,1)
	state.leg += (flip*sideways(walk.X,legRange,walk.Z) - state.leg)*follow
	state.torso += (flip*sideways(walk.X,torsoRange,walk.Z) - state.torso)*follow
	state.shift += (flip*sideways(walk.X,shiftRange,walk.Z) - state.shift)*follow
	state.pitch += (-move.Z*math.abs(velocity.Z)*MOMENTUM_FACTOR - state.pitch)*smooth
	state.roll += (-move.X*math.abs(velocity.X)*MOMENTUM_FACTOR - state.roll)*smooth

	if speed < STILL_SPEED and math.abs(state.leg) + math.abs(state.torso) + math.abs(state.shift)
		+ math.abs(state.pitch) + math.abs(state.roll) < STILL_LEAN then
		release(model)
		return
	end

	set(state.joints[1],CFrame.Angles(0,0,-state.torso)*CFrame.Angles(state.pitch,state.roll,0))
	local hip = CFrame.new(-state.shift,0,0)*CFrame.Angles(0,-state.leg,0)
	set(state.joints[2],hip)
	set(state.joints[3],hip)
end

--stripped[model][piece] = where the piece goes back.
local stripped = {}

local function strip(model)
	local pieces = stripped[model] or {}
	stripped[model] = pieces
	for _,part in ipairs(model:GetChildren()) do
		if part.Name:match("^Morph") then
			pieces[part] = model
			part.Parent = nil
		end
	end
	local m4 = model:FindFirstChild("M4")
	local gun = m4 and m4:FindFirstChild("GunModel")
	if gun then
		pieces[gun] = m4
		gun.Parent = nil
	end
end

local function dress(model)
	for piece,parent in pairs(stripped[model]) do
		piece.Parent = parent
	end
	stripped[model] = nil
end

task.spawn(function()
	while true do
		task.wait(GEAR_CHECK)
		local camera = workspace.CurrentCamera
		for _,model in ipairs(CollectionService:GetTagged("Bloxian")) do
			local root = model:FindFirstChild("HumanoidRootPart")
			if camera and root and (camera.CFrame.Position - root.Position).Magnitude > GEAR_DISTANCE then
				strip(model)
			elseif stripped[model] then
				dress(model)
			end
		end
		for model in pairs(stripped) do
			if not model.Parent then
				stripped[model] = nil
			end
		end
	end
end)

RunService.PreSimulation:Connect(function(dt)
	for _,model in ipairs(CollectionService:GetTagged("Bloxian")) do
		lean(model,dt)
	end
	for model in pairs(states) do
		if not model.Parent then
			release(model)
		end
	end
end)

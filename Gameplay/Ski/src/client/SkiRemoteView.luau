local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiPose = require(script.Parent:WaitForChild("SkiPose"))
local SkiEffects = require(script.Parent:WaitForChild("SkiEffects"))
local SkiSound = require(script.Parent:WaitForChild("SkiSound"))

local Attr = Shared.Attr
local State = Shared.State

local SkiRemoteView = {}

local viewers: { [Model]: any } = {}
local pending: { [Model]: boolean } = {}

local localPlayer = Players.LocalPlayer

local function currentCamera(): Camera?
	return workspace.CurrentCamera
end

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

local function teardown(character: Model)
	pending[character] = nil

	local viewer = viewers[character]
	if not viewer then
		return
	end
	viewers[character] = nil

	viewer.pose:destroy()
	viewer.effects:destroy()
	viewer.sound:destroy()
	Shared.setWalkAnimation(character, nil)

	log("stopped rendering %s", character.Name)
end

local function build(character: Model)
	if viewers[character] then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not character:FindFirstChild("SkiGear") or not character:FindFirstChild("Torso") or not root then
		pending[character] = true
		return
	end

	pending[character] = nil

	Shared.setWalkAnimation(character, Config.Animations.Walking)

	viewers[character] = {
		character = character,
		root = root :: BasePart,
		pose = SkiPose.new(character),
		effects = SkiEffects.new(character, false),
		sound = SkiSound.new(character),
		lean = 0,

		culled = false,
		detailed = false,
	}

	log("rendering %s", character.Name)
end

local function refresh(character: Model)
	if character:GetAttribute(Attr.Equipped) == true then
		build(character)
	else
		teardown(character)
	end
end

local function watchCharacter(character: Model)
	character:GetAttributeChangedSignal(Attr.Equipped):Connect(function()
		refresh(character)
	end)

	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			teardown(character)
		end
	end)

	refresh(character)
end

local function watchPlayer(player: Player)
	if player == localPlayer then
		return
	end

	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(teardown)

	if player.Character then
		watchCharacter(player.Character)
	end
end

local function readNumber(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

function SkiRemoteView.update(dt: number)
	local camera = currentCamera()

	for character in pending do
		if character.Parent and character:GetAttribute(Attr.Equipped) == true then
			build(character)
		else
			pending[character] = nil
		end
	end

	for character, viewer in viewers do
		if not character.Parent or not viewer.root.Parent then
			teardown(character)
			continue
		end

		local away = if camera then (camera.CFrame.Position - viewer.root.Position).Magnitude else 0

		if away > Config.RemoteCullDistance then
			if not viewer.culled then
				viewer.culled = true
				viewer.detailed = false
				viewer.pose:release()
				viewer.effects:setActive(false)
				viewer.sound:mute()
			end
			continue
		end

		viewer.culled = false
		viewer.detailed = away <= Config.RemotePoseDistance

		local state = character:GetAttribute(Attr.State) or State.Walking
		local speed = readNumber(character, Attr.Speed)
		local scrub = readNumber(character, Attr.Scrub)
		local onSnow = character:GetAttribute(Attr.OnSnow) == true

		local riding = state == State.Riding or state == State.Braking

		if state == State.Walking or not viewer.detailed then
			viewer.pose:release()
			viewer.lean = 0
		else
			local poseName = "Stance"
			if state == State.Airborne then
				poseName = "Air"
			elseif state == State.Braking then
				poseName = "Brake"
			elseif math.abs(viewer.lean) > 0.3 then
				poseName = "Carve"
			end

			viewer.lean = Shared.damp(viewer.lean, readNumber(character, Attr.Lean), Config.LeanSmoothing, dt)
			viewer.pose:setPose(poseName)
			viewer.pose:setLean(viewer.lean)
		end

		viewer.effects:update(dt, speed, scrub, onSnow, riding)
		viewer.sound:update(dt, speed, scrub, riding, onSnow)
	end
end

function SkiRemoteView.updatePoses(dt: number)
	for _, viewer in viewers do
		if viewer.detailed then
			viewer.pose:update(dt)
		end
	end
end

function SkiRemoteView.start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			teardown(player.Character)
		end
	end)
end

return SkiRemoteView

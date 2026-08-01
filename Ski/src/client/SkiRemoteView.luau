--[[
	SkiRemoteView
	Renders everyone ELSE's skiing.

	Their gear and their movement already replicate -- the gear is built on the
	server and the character position is ordinary character replication. What
	does not replicate is everything cosmetic: Motor6D C0 writes, particles and
	sounds made on a client are only ever seen by that client. So without this,
	another player skis past you standing bolt upright, silent, throwing no snow.

	No simulation happens here. Their client runs the physics and publishes five
	numbers, the server republishes those as character attributes, and this reads
	them and drives exactly the same SkiPose / SkiEffects / SkiSound that the
	local player uses. The rendering is identical; only where the numbers come
	from differs.
]]

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

-- Characters that should be rendered but whose gear hasn't turned up yet. See
-- build().
local pending: { [Model]: boolean } = {}

local localPlayer = Players.LocalPlayer

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

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

	log("stopped rendering %s", character.Name)
end

local function build(character: Model)
	if viewers[character] then
		return
	end

	--[[
		The gear has to exist first -- the pose hangs off its joints and the
		spray off its parts. It is server-built, so joining partway through a
		round can hand you the equipped flag before the model itself has
		streamed in.

		Queued rather than dropped. Give up here and that player stays unposed
		for as long as they keep the skis on, which is exactly the bug this file
		exists to fix.
	]]
	if not character:FindFirstChild("SkiGear") or not character:FindFirstChild("Torso") then
		pending[character] = true
		return
	end

	pending[character] = nil
	viewers[character] = {
		character = character,
		pose = SkiPose.new(character),
		-- Not local: this instance must never touch the camera.
		effects = SkiEffects.new(character, false),
		sound = SkiSound.new(character),
		lean = 0,
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
	-- Skipped, obviously: SkiController already drives this one directly, and
	-- two things posing the same character would fight every frame.
	if player == localPlayer then
		return
	end

	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(teardown)

	if player.Character then
		watchCharacter(player.Character)
	end
end

-- ============================================================
-- PER FRAME
-- ============================================================

local function readNumber(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

--[[
	Drives the effects and the sound. Poses are done separately -- see updatePoses.

	Attributes land about ten times a second, not every frame, so anything read
	here is a staircase. The sound smooths itself (SoundSmoothing) and particle
	rate is invisible in steps, but `lean` drives the carving overlay -- edge
	angle and body roll -- and stepping that is very visible. It gets damped on
	arrival, which is the same job LeanSmoothing does for the local player.
]]
function SkiRemoteView.update(dt: number)
	-- Anyone whose gear hadn't arrived yet. Two cheap FindFirstChilds, and only
	-- for characters actually waiting.
	for character in pending do
		if character.Parent and character:GetAttribute(Attr.Equipped) == true then
			build(character)
		else
			pending[character] = nil
		end
	end

	for character, viewer in viewers do
		if not character.Parent then
			teardown(character)
			continue
		end

		local state = character:GetAttribute(Attr.State) or State.Walking
		local speed = readNumber(character, Attr.Speed)
		local scrub = readNumber(character, Attr.Scrub)
		local onSnow = character:GetAttribute(Attr.OnSnow) == true

		local riding = state == State.Riding or state == State.Braking

		if state == State.Walking then
			-- Gear on, but standing about. Hand the joints back so their normal
			-- walk animation plays.
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

--[[
	Poses run in their own pass because they have to happen AFTER the engine's
	animation step -- the Animate script writes the same joints during the
	Character phase and would overwrite anything set before it. The controller
	binds this at RenderPriority.Character + 1 alongside its own.
]]
function SkiRemoteView.updatePoses(dt: number)
	for _, viewer in viewers do
		viewer.pose:update(dt)
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

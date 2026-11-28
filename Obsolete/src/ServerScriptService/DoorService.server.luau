--[[
	DoorService

	Runs every model tagged "BreachDoor" in Workspace (the double doors in the tower
	floors; template in ServerStorage.CityKit.Interior.BreachDoor).
	  G (Open/Close)  swings both leaves away from the player, quietly (E is SPH lean-right).
	  Hold F (Breach) kicks them open hard: bang, dust, and they stay open.
	  A shotgun pellet (SPH_Server) or an explosion with line of sight (ExplosionFX) breaches too:
	  they set the door's BreachAt attribute to where the hit came from.
	  An NPC that walks into a closed door pushes it open, so the AI can path
	  through (the leaves carry a PathfindingModifier with PassThrough).
	  LOCK_CHANCE of doors roll Locked: E only rattles the handle (and the prompt
	  then reads "Locked"); it has to be breached. NPCs can't push a locked door either.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local OPEN_ANGLE = math.rad(88)
local BREACH_ANGLE = math.rad(100)
local OPEN_TIME = 0.5
local BREACH_TIME = 0.12
local LOCK_CHANCE = 0.25
local LOCKED_SOUND = "rbxassetid://108817260659655" -- "Door Locked jiggle", Creator Store

local function setup(door)
	if not door:IsDescendantOf(workspace) or door:GetAttribute("DoorReady") then return end
	local leafL, leafR = door:FindFirstChild("LeafL"), door:FindFirstChild("LeafR")
	local promptPart = door:FindFirstChild("PromptPart")
	if not (leafL and leafR and promptPart) then return end
	door:SetAttribute("DoorReady", true)
	local width = door:GetAttribute("Width") or 6
	local pivot = door:GetPivot()
	local hingeL = pivot * CFrame.new(-width / 2, 0, 0)
	local hingeR = pivot * CFrame.new(width / 2, 0, 0)
	local closedL, closedR = leafL.CFrame, leafR.CFrame
	local openPrompt = promptPart:FindFirstChild("OpenPrompt")
	local breachPrompt = promptPart:FindFirstChild("BreachPrompt")
	local state = "closed"
	local locked = math.random() < LOCK_CHANCE
	door:SetAttribute("Locked", locked)
	local rattle = promptPart:FindFirstChild("Locked")
	if not rattle then
		rattle = Instance.new("Sound")
		rattle.Name = "Locked"
		rattle.SoundId = LOCKED_SOUND
		rattle.RollOffMaxDistance = 60
		rattle.Parent = promptPart
	end
	local angle = 0 -- current swing; positive swings the leaves toward the door's -Z side
	local busy = false

	local function place(a)
		leafL.CFrame = hingeL * CFrame.Angles(0, a, 0) * hingeL:Inverse() * closedL
		leafR.CFrame = hingeR * CFrame.Angles(0, -a, 0) * hingeR:Inverse() * closedR
	end

	local function swing(target, seconds)
		busy = true
		local from, t = angle, 0
		while t < seconds do
			t += RunService.Heartbeat:Wait()
			local k = math.clamp(t / seconds, 0, 1)
			k = 1 - (1 - k) * (1 - k)
			angle = from + (target - from) * k
			place(angle)
		end
		angle = target
		place(angle)
		busy = false
	end

	-- +1 when `position` is on the door's +Z side, so the leaves swing away from it
	local function awayFrom(position)
		return pivot:PointToObjectSpace(position).Z >= 0 and 1 or -1
	end

	local function open(position, quiet)
		if state ~= "closed" or busy then return end
		state = "open"
		if openPrompt then openPrompt.ActionText = "Close" end
		local creak = promptPart:FindFirstChild("Creak")
		if creak and not quiet then creak:Play() end
		swing(OPEN_ANGLE * awayFrom(position), OPEN_TIME)
	end

	local function close()
		if state ~= "open" or busy then return end
		swing(0, OPEN_TIME)
		state = "closed"
		if openPrompt then openPrompt.ActionText = "Open" end
	end

	if openPrompt then
		openPrompt.Triggered:Connect(function(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not root or door:GetAttribute("Lockdown") then return end -- sealed by a TowerBosses lockdown shutter
			if state == "closed" and locked then
				if not rattle.IsPlaying then rattle:Play() end
				openPrompt.ActionText = "Locked"
			elseif state == "closed" then
				open(root.Position)
			elseif state == "open" then
				close()
			end
		end)
	end

	local function breach(position)
		if state == "breached" or busy or door:GetAttribute("Lockdown") then return end
		local dir = state == "open" and math.sign(angle) or awayFrom(position)
		state = "breached"
		locked = false
		door:SetAttribute("Locked", false)
		if openPrompt then openPrompt.Enabled = false end
		breachPrompt.Enabled = false
		for _, name in {"Kick", "Splinter"} do
			local s = promptPart:FindFirstChild(name)
			if s then s:Play() end
		end
		local dust = promptPart:FindFirstChild("Dust")
		if dust then dust:Emit(30) end
		swing(BREACH_ANGLE * dir, BREACH_TIME)
	end

	if breachPrompt then
		breachPrompt.Triggered:Connect(function(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then breach(root.Position) end
		end)
		-- shotgun / blast breach; a disabled prompt (GET READY hold, already breached) means not breachable now
		door:GetAttributeChangedSignal("BreachAt"):Connect(function()
			local at = door:GetAttribute("BreachAt")
			if typeof(at) ~= "Vector3" then return end
			door:SetAttribute("BreachAt", nil)
			if breachPrompt.Enabled then breach(at) end
		end)
	end

	-- NPCs (no Player) open a closed door by walking into it
	local function onTouch(hit)
		if state ~= "closed" or busy or locked or door:GetAttribute("Lockdown") then return end
		local model = hit:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not Players:GetPlayerFromCharacter(model) then
			open(hit.Position, true)
		end
	end
	leafL.Touched:Connect(onTouch)
	leafR.Touched:Connect(onTouch)
end

CollectionService:GetInstanceAddedSignal("BreachDoor"):Connect(function(door)
	task.defer(setup, door)
end)
workspace.DescendantAdded:Connect(function(d)
	-- a floor cloned in from ServerStorage: its doors were tagged before they arrived
	if d:HasTag("BreachDoor") then task.defer(setup, d) end
end)
for _, door in CollectionService:GetTagged("BreachDoor") do
	task.defer(setup, door)
end

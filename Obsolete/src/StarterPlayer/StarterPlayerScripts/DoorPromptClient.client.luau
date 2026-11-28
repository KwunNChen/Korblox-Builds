-- Door Open / Breach prompts (Style Custom): the same small tag as Medical's Revive / Drag prompts
-- (see StarterCharacterScripts.MedicalClient). Breach sits just under Open; a line fills while you hold.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local DOOR_PROMPTS = { OpenPrompt = 0, BreachPrompt = 1, EnterPrompt = 0, ReadyPrompt = 0, DifficultyPrompt = 1, SabotagePrompt = 0, MaskPrompt = 0, RPGPrompt = 0 } -- row, top to bottom; Ready/Difficulty are the tavern table's, Sabotage the lockdown junction box, Mask/RPG the boss-floor pickups (TowerBosses)
local tags: { [ProximityPrompt]: () -> () } = {}

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	local row = DOOR_PROMPTS[prompt.Name]
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or row == nil then return end
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local key = if touch then "Tap"
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then prompt.GamepadKeyCode.Name:gsub("^Button", "")
		else prompt.KeyboardKeyCode.Name
	local gui = Instance.new("BillboardGui")
	gui.Name = "DoorPrompt"
	gui.Size = UDim2.fromOffset(84, 15)
	gui.SizeOffset = Vector2.new(0, -1.25 * row)
	gui.Adornee = prompt.Parent
	gui.AlwaysOnTop = true
	local label = Instance.new(if touch then "TextButton" else "TextLabel") :: any
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.55
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 12
	label.Font = Enum.Font.GothamMedium
	if touch then label.AutoButtonColor = false end
	label.Parent = gui
	local function refresh()
		label.Text = key .. "  " .. prompt.ActionText -- Open / Close flips while shown
	end
	refresh()
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(0, 0, 0, 2)
	bar.Parent = label
	local fill: Tween? = nil
	local conns = {
		prompt:GetPropertyChangedSignal("ActionText"):Connect(refresh),
		prompt.PromptButtonHoldBegan:Connect(function()
			fill = TweenService:Create(bar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 0, 2) })
			fill:Play()
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			if fill then fill:Cancel() end
			bar.Size = UDim2.new(0, 0, 0, 2)
		end),
	}
	if touch then
		table.insert(conns, label.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldBegin() end end))
		table.insert(conns, label.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldEnd() end end))
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tags[prompt] = function()
		for _, c in conns do c:Disconnect() end
		gui:Destroy()
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	local remove = tags[prompt]
	if remove then
		tags[prompt] = nil
		remove()
	end
end)

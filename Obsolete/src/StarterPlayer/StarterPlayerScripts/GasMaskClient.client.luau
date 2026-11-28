-- Gas mask (CBRN boss floors): the server puts it on as soon as you take one. While it's on: amber view, filter countdown,
-- and your own mask parts hidden in first person. Server side lives in ServerStorage.TowerBosses.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "GasMaskHUD", false, true, -1 -- under every other GUI (SPH ammo HUD is 0)

local view = Instance.new("Frame") -- everything that only shows with the mask on
view.Size, view.BackgroundTransparency, view.Visible = UDim2.fromScale(1, 1), 1, false
view.Parent = gui
local tint = Instance.new("Frame")
tint.Size, tint.BackgroundColor3, tint.BackgroundTransparency, tint.BorderSizePixel = UDim2.fromScale(1, 1), Color3.fromRGB(230, 150, 40), 0.9, 0
tint.Parent = view
local function edge(pos, size, rot)
	local f = Instance.new("Frame")
	f.Position, f.Size, f.BackgroundColor3, f.BorderSizePixel = pos, size, Color3.new(), 0
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.15), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	f.Parent = view
end
edge(UDim2.fromScale(0, 0), UDim2.fromScale(0.3, 1), 0)
edge(UDim2.fromScale(0.7, 0), UDim2.fromScale(0.3, 1), 180)
edge(UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.25), 90)
edge(UDim2.fromScale(0, 0.75), UDim2.fromScale(1, 0.25), -90)

local label = Instance.new("TextLabel")
label.AnchorPoint, label.Position, label.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -110), UDim2.fromOffset(320, 24)
label.BackgroundTransparency, label.FontFace, label.TextSize = 1, FONT, 18
label.TextColor3, label.TextStrokeTransparency = Color3.new(1, 1, 1), 0.4
label.Visible = false
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local on = char ~= nil and char:GetAttribute("GasMask") == true
	local has = player:GetAttribute("HasMask")
	local left = player:GetAttribute("MaskFilter") or 0
	view.Visible = on
	if on then
		label.Text = string.format("GAS MASK  ·  FILTER %ds", math.ceil(left))
		label.TextColor3 = if left < 8 then Color3.fromRGB(240, 90, 70) else Color3.new(1, 1, 1)
	elseif has and left <= 0 then
		label.Text = "FILTER SPENT"
		label.TextColor3 = Color3.fromRGB(200, 202, 208)
	end
	label.Visible = on or (has == true and left <= 0)
	-- the mask on the desk is gone for you once you've taken yours (squadmates still see theirs)
	local pickup = workspace:FindFirstChild("GasMaskPickup")
	if pickup then
		local taken = has == true
		for _, d in pickup:GetDescendants() do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = if taken then 1 else 0
			elseif d:IsA("Highlight") or d:IsA("ProximityPrompt") then d.Enabled = not taken end
		end
	end
	-- own mask parts would sit over the camera in first person
	if char then
		local head = char:FindFirstChild("Head")
		local close = head and (workspace.CurrentCamera.CFrame.Position - head.Position).Magnitude < 1.5
		for _, p in char:GetChildren() do
			if p:IsA("BasePart") and p:GetAttribute("PlayerMask") then p.LocalTransparencyModifier = if close then 1 else 0 end
		end
	end
end)

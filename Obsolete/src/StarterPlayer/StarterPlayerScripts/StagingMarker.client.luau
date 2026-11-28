-- Bobbing "STAGING" marker over the ready table (ReadyPoint), in the UI's HighwayGothic font.
-- Hides up close where the E/F prompts take over, and during a tower run.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local staging = workspace:WaitForChild("Staging")
local point = staging:WaitForChild("ReadyPoint") -- streams out during a run (the tower is ~3000 studs off) and back in as a new part

local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local GOLD = Color3.fromRGB(230, 185, 80)

local gui = Instance.new("BillboardGui")
gui.Name = "StagingMarker"
gui.Adornee = point
gui.AlwaysOnTop = true
gui.LightInfluence = 0
gui.MaxDistance = 140
gui.Size = UDim2.fromOffset(180, 74)
gui.StudsOffset = Vector3.new(0, 4.5, 0)
gui.ResetOnSpawn = false

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 30)
title.FontFace = FONT
title.Text = "STAGING"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 26
title.TextStrokeTransparency = 0.4
title.Parent = gui
local sub = title:Clone()
sub.Position = UDim2.fromOffset(0, 28)
sub.Size = UDim2.new(1, 0, 0, 16)
sub.Text = "READY UP HERE"
sub.TextColor3 = GOLD
sub.TextSize = 14
sub.Parent = gui
local arrow = sub:Clone()
arrow.Position = UDim2.fromOffset(0, 44)
arrow.Size = UDim2.new(1, 0, 0, 28)
arrow.Text = "\u{25BC}"
arrow.TextSize = 26
arrow.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { StudsOffset = Vector3.new(0, 5.3, 0) }):Play()

RunService.Heartbeat:Connect(function()
	if not point.Parent then
		point = staging:FindFirstChild("ReadyPoint") or point
		gui.Adornee = point
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	gui.Enabled = not (root and (root.Position - point.Position).Magnitude < 11) and not player:GetAttribute("InTowerRun")
end)

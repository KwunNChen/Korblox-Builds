-- Spectate: while TowerRun holds you out of the raid (RespawnWaves: killed in the run, or joined after it
-- started), a SPECTATE card sits above the Settings button (TowerMusic's SettingsUI, same look). Click it to
-- follow a teammate still in the run; Q / E (arrows, D-pad, NEXT on the card) switch; click again to stop.
-- Late joiners start spectating straight away. Gone once you have a character again.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local HIDE = { DeathScreen = true, MedicalBlackout = true, RespawnWaves = true } -- death overlays lifted while spectating
local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local WHITE, GREY = Color3.new(1, 1, 1), Color3.fromRGB(200, 202, 208)
local BOTTOM = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and 0.55 or 0.97 -- SettingsUI's

-- TowerMusic's shade / text / rule, so the card matches the Settings button
local function shade(parent, from)
	local f = Instance.new("Frame")
	f.Size, f.BackgroundColor3, f.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 0
	local g = Instance.new("UIGradient")
	local keys = {}
	for i = 0, 10 do
		local t = i / 10
		table.insert(keys, NumberSequenceKeypoint.new(t, from + (1 - from) * TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)))
	end
	g.Transparency = NumberSequence.new(keys)
	g.Parent = f
	f.Parent = parent
end
local function text(parent, str, x, y, w, h, max, colour)
	local l = Instance.new("TextLabel")
	l.AnchorPoint, l.Position, l.Size = Vector2.new(0, 0.5), UDim2.fromScale(x, y), UDim2.fromScale(w, h)
	l.BackgroundTransparency, l.FontFace, l.TextScaled = 1, FONT, true
	l.TextXAlignment, l.TextColor3, l.Text = Enum.TextXAlignment.Left, colour or WHITE, str
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize, c.MinTextSize = max, 8
	c.Parent = l
	l.Parent = parent
	return l
end
local function teamColour() return player.Team and player.Team.TeamColor.Color or WHITE end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.Enabled = "Spectate", false, 120, false -- above the death overlays (100 / 110)
local button = Instance.new("TextButton")
button.AnchorPoint, button.Size = Vector2.new(0, 1), UDim2.fromScale(0.2, 0.065)
button.BackgroundTransparency, button.Text, button.AutoButtonColor = 1, "", false
local bsize = Instance.new("UISizeConstraint")
bsize.MinSize, bsize.MaxSize = Vector2.new(190, 44), Vector2.new(340, 70)
bsize.Parent = button
button.Parent = gui
shade(button, 0.25)
local kicker = text(button, "", 0.07, 0.22, 0.8, 0.26, 13, GREY)
local title = text(button, "SPECTATE", 0.07, 0.56, 0.6, 0.4, 24)
local rule = Instance.new("Frame")
rule.AnchorPoint, rule.Position, rule.Size, rule.BorderSizePixel = Vector2.new(0, 0.5), UDim2.fromScale(0.07, 0.86), UDim2.new(0.5, 0, 0, 2), 0
local rg = Instance.new("UIGradient")
rg.Transparency = NumberSequence.new(0, 1)
rg.Parent = rule
rule.Parent = button
local nextB = Instance.new("TextButton") -- touch has no Q / E
nextB.AnchorPoint, nextB.Position, nextB.Size = Vector2.new(1, 0.5), UDim2.fromScale(0.97, 0.56), UDim2.fromScale(0.25, 0.6)
nextB.BackgroundTransparency, nextB.FontFace, nextB.TextScaled, nextB.TextColor3, nextB.Text = 1, FONT, true, GREY, "NEXT >"
local nc = Instance.new("UITextSizeConstraint")
nc.MaxTextSize = 16
nc.Parent = nextB
nextB.Parent = button
gui.Parent = player:WaitForChild("PlayerGui")

local function alive(p)
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0 and hum or nil
end
local function targets()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("InTowerRun") and alive(p) then table.insert(list, p) end
	end
	table.sort(list, function(a, b) return a.UserId < b.UserId end)
	return list
end

local watching: Player? = nil
local on = false -- spectating right now
local function step(dir)
	local list = targets()
	if #list == 0 then watching = nil return end
	local i = table.find(list, watching) or 0
	watching = list[(i - 1 + dir) % #list + 1]
end
local function setOn(v)
	if on == v then return end
	on = v
	for _, g in player.PlayerGui:GetChildren() do
		if HIDE[g.Name] and g:IsA("ScreenGui") then g.Enabled = not v end
	end
	if v then -- MedicalClient's downed look would otherwise sit on the teammate's view
		for _, e in Lighting:GetChildren() do
			if e.Name == "MedicalDowned" then (e :: any).Enabled = false end
		end
		local reverb = SoundService:GetAttribute("MedicalReverb")
		if reverb then SoundService.AmbientReverb = (Enum.ReverbType :: any)[reverb] end
		step(1)
	else
		watching = nil
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then camera.CameraSubject = hum end
	end
end
button.Activated:Connect(function() setOn(not on) end)
nextB.Activated:Connect(function() step(1) end)
local KEYS = { [Enum.KeyCode.Q] = -1, [Enum.KeyCode.Left] = -1, [Enum.KeyCode.DPadLeft] = -1,
	[Enum.KeyCode.E] = 1, [Enum.KeyCode.Right] = 1, [Enum.KeyCode.DPadRight] = 1 }
UserInputService.InputBegan:Connect(function(input, processed)
	if on and not processed and KEYS[input.KeyCode] then step(KEYS[input.KeyCode]) end
end)

RunService.RenderStepped:Connect(function()
	-- TowerRun sets RespawnWaves only while you're held out (cleared just before your respawn). Don't also check
	-- your own Health: the client can still read 100 on a body the server has killed.
	local held = player:GetAttribute("RespawnWaves") ~= nil
	if not held then
		setOn(false)
		gui.Enabled = false
		return
	end
	if not gui.Enabled and player.Character == nil then setOn(true) end -- joined mid-raid: nothing else to look at
	gui.Enabled = true
	-- above the Settings button; out of the way while its list is open
	local settings = player.PlayerGui:FindFirstChild("SettingsUI")
	local toggle = settings and settings:FindFirstChild("Toggle") :: GuiObject?
	local list = settings and settings:FindFirstChild("List") :: GuiObject?
	button.Position = UDim2.new(0, 0, BOTTOM, -((toggle and toggle.AbsoluteSize.Y or 44) + 6))
	button.Visible = not (list and list.Visible)
	rule.BackgroundColor3 = teamColour()

	local n = player:GetAttribute("RespawnWaves") or 0
	local wavesText = "RESPAWN IN " .. n .. (if n == 1 then " WAVE" else " WAVES")
	if not on then
		kicker.Text, title.Text, nextB.Visible = wavesText, "SPECTATE", false
		return
	end
	for _, g in player.PlayerGui:GetChildren() do -- overlays made after we started (the KIA card fades in late)
		if HIDE[g.Name] and g:IsA("ScreenGui") and g.Enabled then g.Enabled = false end
	end
	if not (watching and watching.Parent and watching:GetAttribute("InTowerRun") and alive(watching)) then step(1) end
	local hum = watching and alive(watching)
	if hum and camera.CameraSubject ~= hum then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = hum
	end
	kicker.Text = "SPECTATING  \u{00B7}  " .. wavesText
	title.Text = if watching then string.upper(watching.DisplayName) else "NO ONE STANDING"
	nextB.Visible = #targets() > 1
end)

-- Loops combat music while the player is in a tower run, plus a Settings panel to mute it.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local muted = false

-- "dont_6min_loop" at normal speed; Looped repeats it.
local music = Instance.new("Sound")
music.Name = "CombatMusic"
music.SoundId = "rbxassetid://104605857223443"
music.Volume = 0.65
music.Looped = true
music.Parent = SoundService

-- Van ride in (TowerRun sets Riding while the squad is seated): engine start, then the cab's road noise
-- until the teleport into the tower clears Riding.
local function sfx(id: number, volume: number, looped: boolean): Sound
	local x = Instance.new("Sound")
	x.SoundId = "rbxassetid://" .. id
	x.Volume = volume
	x.Looped = looped
	x.Parent = SoundService
	return x
end
local vanStart = sfx(104905476314384, 0.8, false) -- "engine_start"
local vanDrive = sfx(9112735838, 0.7, true) -- Pro Sound Effects: 1988 GMC Suburban, interior driving, loop
local function vanRide()
	if player:GetAttribute("Riding") then
		vanStart:Play()
		vanDrive.TimePosition = 0
		vanDrive.Volume = 0
		vanDrive:Play()
		game:GetService("TweenService"):Create(vanDrive, TweenInfo.new(2), { Volume = 0.7 }):Play() -- swells in under the start
	else
		vanStart:Stop()
		vanDrive:Stop()
	end
end
player:GetAttributeChangedSignal("Riding"):Connect(vanRide)

-- Only stop after being out of the run this long, so a teleport between floors never cuts it.
local OUT_GRACE = 3
local outSince = -math.huge -- not in a run at join, so no music

local function update()
	local inRun = player:GetAttribute("InTowerRun") == true and not player:GetAttribute("Riding") -- not during the van ride in
	if inRun then
		outSince = nil
	else
		outSince = outSince or os.clock()
	end
	local want = not muted and (inRun or os.clock() - outSince < OUT_GRACE)
	if want and not music.IsPlaying then
		if music.TimePosition > 0 then music:Resume() else music:Play() end
	elseif not want and music.IsPlaying then
		music:Pause()
	end
end
player:GetAttributeChangedSignal("InTowerRun"):Connect(update)
player:GetAttributeChangedSignal("Riding"):Connect(update)
-- Watchdog: anything that stops the sound mid-run (a load hitch on teleport) gets it resumed.
task.spawn(function()
	while true do
		task.wait(1)
		update()
	end
end)

-- Settings UI: the Spearhead team picker's look (Spearhead test place, StarterPlayerScripts.TeamSwitcher):
-- bottom-left card with a dark fade from the screen edge, HighwayGothic, team-colour rule; rows slide in above it.
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local WHITE = Color3.new(1, 1, 1)
local GREY = Color3.fromRGB(200, 202, 208)
local SLIDE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

local function play(obj, info, goal) local t = TweenService:Create(obj, info, goal); t:Play(); return t end

-- soft black fade from the left edge
local function shade(parent, from)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	local keys = {}
	for i = 0, 10 do
		local t = i / 10
		table.insert(keys, NumberSequenceKeypoint.new(t, from + (1 - from) * TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)))
	end
	g.Transparency = NumberSequence.new(keys)
	g.Parent = f
	f.Parent = parent
	return f
end

local function text(parent, str, x, y, w, h, max, colour)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0, 0.5)
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = colour or WHITE
	l.Text = str
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize, c.MinTextSize = max, 8
	c.Parent = l
	l.Parent = parent
	return l
end

local function rule(parent, x, y, w, colour)
	local r = Instance.new("Frame")
	r.AnchorPoint = Vector2.new(0, 0.5)
	r.Position = UDim2.fromScale(x, y)
	r.Size = UDim2.new(w, 0, 0, 2)
	r.BackgroundColor3 = colour
	r.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = r
	r.Parent = parent
	return r
end

local function teamColour()
	return player.Team and player.Team.TeamColor.Color or WHITE
end

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- mobile: the thumbstick owns the bottom-left corner, so sit above it
local BOTTOM = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and 0.55 or 0.97

local button = Instance.new("TextButton")
button.Name = "Toggle"
button.AnchorPoint = Vector2.new(0, 1)
button.Position = UDim2.fromScale(0, BOTTOM)
button.Size = UDim2.fromScale(0.2, 0.065)
button.BackgroundTransparency = 1
button.Text = ""
button.AutoButtonColor = false
local bsize = Instance.new("UISizeConstraint")
bsize.MinSize = Vector2.new(190, 44)
bsize.MaxSize = Vector2.new(340, 70)
bsize.Parent = button
button.Parent = gui

shade(button, 0.25)
local kicker = text(button, "SETTINGS", 0.07, 0.22, 0.8, 0.26, 13, GREY)
text(button, "OPTIONS", 0.07, 0.56, 0.86, 0.4, 24)
local crule = rule(button, 0.07, 0.86, 0.5, teamColour())
player:GetPropertyChangedSignal("Team"):Connect(function() crule.BackgroundColor3 = teamColour() end)

local list = Instance.new("Frame")
list.Name = "List"
list.AnchorPoint = Vector2.new(0, 1)
list.BackgroundTransparency = 1
list.Size = UDim2.fromScale(0.24, 0)
list.AutomaticSize = Enum.AutomaticSize.Y
list.Visible = false
local layout = Instance.new("UIListLayout")
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)
layout.Parent = list
local lsize = Instance.new("UISizeConstraint")
lsize.MinSize = Vector2.new(230, 0)
lsize.MaxSize = Vector2.new(400, math.huge)
lsize.Parent = list
list.Parent = gui

local function placeList()
	list.Position = UDim2.new(0, 0, BOTTOM, -button.AbsoluteSize.Y - 6)
end
button:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeList)
placeList()

-- One setting row: name / rule / state line. Clicking it toggles.
local function settingRow(name, order, stateText, onClick)
	local colour = teamColour()
	local r = Instance.new("CanvasGroup")
	r.Name = name
	r.LayoutOrder = order
	r.Size = UDim2.new(1, 0, 0, 50)
	r.BackgroundTransparency = 1
	r.GroupTransparency = 1
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 4.6
	ratio.DominantAxis = Enum.DominantAxis.Width
	ratio.Parent = r

	local inner = Instance.new("TextButton")
	inner.Size = UDim2.fromScale(1, 1)
	inner.Position = UDim2.fromScale(-0.06, 0)
	inner.BackgroundTransparency = 1
	inner.Text = ""
	inner.AutoButtonColor = false
	inner.Parent = r

	local sh = shade(inner, 0.2)
	text(inner, name, 0.06, 0.36, 0.88, 0.34, 26)
	local rl = rule(inner, 0.06, 0.58, 0.45, colour)
	local state = text(inner, stateText(), 0.06, 0.77, 0.88, 0.2, 14, colour:Lerp(WHITE, 0.45))

	inner.MouseEnter:Connect(function()
		play(rl, FAST, { Size = UDim2.new(0.62, 0, 0, 2) })
		play(sh, FAST, { BackgroundColor3 = colour:Lerp(Color3.new(0, 0, 0), 0.75) })
	end)
	inner.MouseLeave:Connect(function()
		play(rl, FAST, { Size = UDim2.new(0.45, 0, 0, 2) })
		play(sh, FAST, { BackgroundColor3 = Color3.new(0, 0, 0) })
	end)
	inner.Activated:Connect(function()
		onClick()
		state.Text = stateText()
	end)
	r.Parent = list
	return { r, inner }
end

local rows = {}
local open, busy = false, false

local function build()
	for _, c in list:GetChildren() do if c:IsA("CanvasGroup") then c:Destroy() end end
	return {
		settingRow("COMBAT MUSIC", 0, function()
			return (if muted then "OFF" else "ON") .. "  ·  CLICK TO " .. (if muted then "UNMUTE" else "MUTE")
		end, function()
			muted = not muted
			update()
		end),
	}
end

local function openList()
	open, busy = true, true
	rows = build()
	list.Visible = true
	kicker.Text = "CLOSE"
	for i, v in rows do
		task.delay((i - 1) * 0.05, function()
			play(v[1], SLIDE_IN, { GroupTransparency = 0 })
			play(v[2], SLIDE_IN, { Position = UDim2.fromScale(0, 0) })
		end)
	end
	task.delay(0.2, function() busy = false end)
end

local function close()
	if not open then return end
	open = false
	kicker.Text = "SETTINGS"
	for _, v in rows do
		play(v[1], SLIDE_OUT, { GroupTransparency = 1 })
		play(v[2], SLIDE_OUT, { Position = UDim2.fromScale(-0.06, 0) })
	end
	task.delay(0.2, function() if not open then list.Visible = false end end)
end

button.Activated:Connect(function()
	if busy then return end
	if open then close() else openList() end
end)
button.MouseEnter:Connect(function() play(crule, FAST, { Size = UDim2.new(0.66, 0, 0, 2) }) end)
button.MouseLeave:Connect(function() play(crule, FAST, { Size = UDim2.new(0.5, 0, 0, 2) }) end)
-- click anywhere else closes it (a click on a row is a processed input, so it doesn't count)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not open then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then close() end
end)

gui.Parent = player:WaitForChild("PlayerGui")
update()

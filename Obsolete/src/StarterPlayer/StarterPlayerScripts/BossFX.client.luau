-- Boss floor effects (server side: ServerStorage.TowerBosses).
--   TowerStatus.BossWarning    a red line that flashes under the floor header for a few seconds
--   TowerStatus.BossObjective  a line that stays there until cleared
--   Character.Spotted          the Signals Officer just radioed your position: red edge pulse
--   Player.Jam (0..1)          the EW Section's jammer: floor HUD, kill feed, chat and name tags drop out (health and status bars stay), static over the screen
--   TowerStatus.BossName       radio card top right (types BossTagline) and a low boom when a boss floor starts
--   TowerStatus.Radio          while a boss is up, the radio call types into that card instead (AdminConsole shows it otherwise)
--   TowerStatus.BossPhase = 2  the boss hit half health: boom again and a red edge pulse
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local status = game:GetService("ReplicatedStorage"):WaitForChild("TowerStatus")

local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local RED = Color3.fromRGB(230, 70, 60)
local JAMMED_GUIS = { TowerHUD = true, KillFeed = true } -- not SPH_UI: health, bleeding and other statuses stay readable

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "BossFX", false, true, 6

-- boss lines sit low in the centre, below the crosshair and above the hotbar
local function line(y, size, colour)
	local l = Instance.new("TextLabel")
	l.AnchorPoint, l.Position, l.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.74, y), UDim2.fromOffset(600, size + 6)
	l.BackgroundTransparency, l.FontFace, l.TextSize = 1, FONT, size
	l.TextColor3, l.TextStrokeTransparency, l.Text = colour, 0.35, ""
	l.Parent = gui
	return l
end
local objectiveLine = line(0, 16, Color3.fromRGB(235, 225, 200))
local warningLine = line(22, 19, RED)
warningLine.TextTransparency, warningLine.TextStrokeTransparency = 1, 1

-- warning: pops in, holds, fades
local warnSeq = 0
local function onWarning()
	local text = status:GetAttribute("BossWarning")
	if not text then return end
	warnSeq += 1
	local mine = warnSeq
	warningLine.Text = text
	warningLine.TextTransparency, warningLine.TextStrokeTransparency = 0, 0.35
	warningLine.TextSize = 23
	TweenService:Create(warningLine, TweenInfo.new(0.25), { TextSize = 19 }):Play()
	task.delay(5, function()
		if warnSeq ~= mine then return end
		TweenService:Create(warningLine, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end
status:GetAttributeChangedSignal("BossWarning"):Connect(onWarning)
local function onObjective() objectiveLine.Text = status:GetAttribute("BossObjective") or "" end
status:GetAttributeChangedSignal("BossObjective"):Connect(onObjective)
onObjective()

-- spotted: red edges pulse once per radio call
local edges = Instance.new("Frame")
edges.Size, edges.BackgroundTransparency = UDim2.fromScale(1, 1), 1
edges.Parent = gui
local edgeParts = {}
for _, spec in {
	{ UDim2.fromScale(0, 0), UDim2.fromScale(0.2, 1), 0 }, { UDim2.fromScale(0.8, 0), UDim2.fromScale(0.2, 1), 180 },
	{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.2), 90 }, { UDim2.fromScale(0, 0.8), UDim2.fromScale(1, 0.2), -90 },
} do
	local f = Instance.new("Frame")
	f.Position, f.Size, f.BackgroundColor3, f.BorderSizePixel, f.BackgroundTransparency = spec[1], spec[2], RED, 0, 1
	local g = Instance.new("UIGradient")
	g.Rotation = spec[3]
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	f.Parent = edges
	table.insert(edgeParts, f)
end
local spottedTag = line(46, 15, RED)
spottedTag.TextTransparency, spottedTag.TextStrokeTransparency = 1, 1
local function pulse()
	for _, f in edgeParts do
		f.BackgroundTransparency = 0.35
		TweenService:Create(f, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	end
	spottedTag.Text = "POSITION REPORTED"
	spottedTag.TextTransparency, spottedTag.TextStrokeTransparency = 0, 0.35
	TweenService:Create(spottedTag, TweenInfo.new(1.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end
local spotConn
local function hookChar(char)
	if spotConn then spotConn:Disconnect() end
	spotConn = char:GetAttributeChangedSignal("Spotted"):Connect(function()
		if char:GetAttribute("Spotted") then pulse() end
	end)
end
player.CharacterAdded:Connect(hookChar)
if player.Character then hookChar(player.Character) end

-- boss intro card: kicker / name / rule / tagline, punches in, holds, fades
local STING = "rbxassetid://180302005" -- the grenade boom, pitched down
local function sting(pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = STING, 0.9, pitch
	s.Parent = gui
	s:Play()
	game:GetService("Debris"):AddItem(s, 6)
end
-- radio card in the admin console's style: plum gradient from the Korblox banner, slides in top right,
-- types the tagline, holds, slides back out
local PLUM_TOP, PLUM_BOTTOM = Color3.fromRGB(92, 47, 90), Color3.fromRGB(50, 24, 48)
local ACCENT, TEXT, DIM = Color3.fromRGB(236, 190, 230), Color3.fromRGB(246, 234, 244), Color3.fromRGB(184, 146, 180)
local MONO = Enum.Font.Code
local BANNER = "rbxassetid://130752291688058"
local OUT, IN = UDim2.new(1, 320, 0, 70), UDim2.new(1, -16, 0, 70)
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end
local intro = make("Frame", {
	AnchorPoint = Vector2.new(1, 0), Position = OUT, Size = UDim2.fromOffset(300, 90),
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.03, BorderSizePixel = 0, Visible = false,
}, gui)
make("UIGradient", { Color = ColorSequence.new(PLUM_TOP, PLUM_BOTTOM), Rotation = 60 }, intro)
make("UIStroke", { Color = ACCENT, Transparency = 0.35 }, intro)
make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = RED, BorderSizePixel = 0 }, intro) -- red stripe: hostile
make("ImageLabel", {
	Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(54, 60), BackgroundTransparency = 1,
	Image = BANNER, ScaleType = Enum.ScaleType.Fit,
}, intro)
local dot = make("Frame", { Position = UDim2.fromOffset(70, 9), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = RED, BorderSizePixel = 0 }, intro)
local function label(x, y, h, size, colour, text)
	return make("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y), Size = UDim2.new(1, -(x + 8), 0, h),
		Font = MONO, TextSize = size, TextColor3 = colour, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Text = text or "",
	}, intro)
end
label(81, 5, 14, 12, RED, "HIGH-VALUE TARGET")
local iName = label(70, 20, 18, 16, TEXT)
local iTag = label(70, 40, 46, 12, DIM)
iTag.TextTruncate = Enum.TextTruncate.None

local introSeq = 0
-- slides the card in (if it isn't already), types tag under the name, holds, slides out; a newer call takes over
local function showCard(name, tag, colour)
	introSeq += 1
	local mine = introSeq
	iName.Text, iTag.Text, iTag.TextColor3 = name, tag, colour
	iTag.MaxVisibleGraphemes = 0
	if not intro.Visible then intro.Position, intro.Visible = OUT, true end
	TweenService:Create(intro, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { Position = IN }):Play()
	task.wait(0.35)
	for i = 1, #tag do -- typewriter
		if introSeq ~= mine then return end
		iTag.MaxVisibleGraphemes = i
		dot.Visible = i % 6 < 3
		task.wait(0.025)
	end
	dot.Visible = true
	task.wait(4.5)
	if introSeq ~= mine then return end
	local tw = TweenService:Create(intro, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = OUT })
	tw.Completed:Connect(function() if introSeq == mine then intro.Visible = false end end)
	tw:Play()
end
local function onBoss()
	local name = status:GetAttribute("BossName")
	if not name or player:GetAttribute("InTowerRun") ~= true then return end
	sting(0.55)
	showCard(name, status:GetAttribute("BossTagline") or "", DIM)
end
status:GetAttributeChangedSignal("BossName"):Connect(onBoss)
local lastRadio, lastRadioAt = nil, 0
status:GetAttributeChangedSignal("Radio"):Connect(function()
	local msg = status:GetAttribute("Radio")
	if not msg or not status:GetAttribute("BossName") or player:GetAttribute("InTowerRun") ~= true then return end
	if msg == lastRadio and os.clock() - lastRadioAt < 1 then return end -- nil-then-text fires twice under deferred signals
	lastRadio, lastRadioAt = msg, os.clock()
	local squelch = Instance.new("Sound")
	squelch.SoundId, squelch.Volume = "rbxassetid://9118026328", 0.6 -- ProSoundEffects "Radio Squelches 12"
	squelch.Parent = gui
	game:GetService("Debris"):AddItem(squelch, 3)
	squelch:Play()
	showCard(status:GetAttribute("BossName"), msg, TEXT)
end)

-- phase 2: the boss is hurt and changes up; boom and a red pulse at the screen edges
status:GetAttributeChangedSignal("BossPhase"):Connect(function()
	if status:GetAttribute("BossPhase") ~= 2 or player:GetAttribute("InTowerRun") ~= true then return end
	sting(0.8)
	for _, f in edgeParts do
		f.BackgroundTransparency = 0.25
		TweenService:Create(f, TweenInfo.new(1.6), { BackgroundTransparency = 1 }):Play()
	end
end)

-- jammer static: thin full-width lines of grey noise (random-keyed gradients) jittered ~20 times a second, plus tearing bars
local static = Instance.new("Frame")
static.Size, static.BackgroundTransparency, static.Visible = UDim2.fromScale(1, 1), 1, false
static.ZIndex = 0
static.Parent = gui
local ROWS = 140
local function noise()
	local keys = {}
	for i = 0, 19 do
		local v = math.random()
		table.insert(keys, ColorSequenceKeypoint.new(i / 19, Color3.new(v, v, v)))
	end
	return ColorSequence.new(keys)
end
local patterns = {}
for i = 1, 24 do patterns[i] = noise() end
local cells = {}
for y = 0, ROWS - 1 do
	local c = Instance.new("Frame")
	c.Position, c.Size = UDim2.fromScale(-0.5, y / ROWS), UDim2.new(2, 0, 1 / ROWS, 1)
	c.BorderSizePixel, c.BackgroundColor3 = 0, Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Parent = c
	c.Parent = static
	table.insert(cells, g)
end
local bars = {}
for i = 1, 2 do
	local b = Instance.new("Frame")
	b.Size, b.BorderSizePixel, b.BackgroundColor3 = UDim2.new(1, 0, 0, 3), 0, Color3.new(1, 1, 1)
	b.Parent = static
	table.insert(bars, b)
end
local noSignal = Instance.new("TextLabel")
noSignal.AnchorPoint, noSignal.Position, noSignal.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.74, 66), UDim2.fromOffset(300, 20) -- under the boss lines
noSignal.BackgroundTransparency, noSignal.FontFace, noSignal.TextSize = 1, FONT, 15
noSignal.TextColor3, noSignal.TextStrokeTransparency, noSignal.Text = Color3.fromRGB(220, 220, 220), 0.3, "SIGNAL JAMMED"
noSignal.Parent = static

local hidden = {} -- [ScreenGui] = was Enabled
local tags = {} -- [Humanoid] = old DisplayDistanceType
local TextChatService = game:GetService("TextChatService")
local chatWas = nil -- {window, input} Enabled before the jam, nil while not jammed
local function chatConfigs()
	return TextChatService:FindFirstChildOfClass("ChatWindowConfiguration"), TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
end
local function setJammed(on)
	local pg = player:FindFirstChild("PlayerGui")
	if on then
		for _, g in if pg then pg:GetChildren() else {} do
			if g:IsA("ScreenGui") and JAMMED_GUIS[g.Name] and hidden[g] == nil then
				hidden[g] = g.Enabled
				g.Enabled = false
			end
		end
		local win, bar = chatConfigs()
		if chatWas == nil and win and bar then
			chatWas = { win.Enabled, bar.Enabled }
			win.Enabled, bar.Enabled = false, false
		end
		for _, p in Players:GetPlayers() do
			local hum = p ~= player and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum and tags[hum] == nil then
				tags[hum] = hum.DisplayDistanceType
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end
	else
		for g, was in hidden do if g.Parent then g.Enabled = was end end
		for hum, was in tags do if hum.Parent then hum.DisplayDistanceType = was end end
		hidden, tags = {}, {}
		if chatWas then
			local win, bar = chatConfigs()
			if win and bar then win.Enabled, bar.Enabled = chatWas[1], chatWas[2] end
			chatWas = nil
		end
	end
end

local nextRoll = 0
RunService.RenderStepped:Connect(function()
	local jam = player:GetAttribute("Jam") or 0
	local on = jam > 0 and player:GetAttribute("InTowerRun") == true
	static.Visible = on
	setJammed(on) -- also catches GUIs and squadmates that appear mid-jam
	if not on or os.clock() < nextRoll then return end
	nextRoll = os.clock() + 0.05
	local base = 1 - 0.1 * jam -- light haze: even at full jam the lines are ~90% transparent
	for _, g in cells do
		g.Color = patterns[math.random(#patterns)]
		g.Offset = Vector2.new(math.random() - 0.5, 0)
		g.Parent.BackgroundTransparency = math.clamp(base + (math.random() - 0.5) * 0.06, 0, 1)
	end
	for _, b in bars do
		b.Position = UDim2.fromScale(0, math.random())
		b.BackgroundTransparency = 1 - 0.18 * jam * math.random()
	end
	noSignal.TextTransparency = if jam > 0.6 and os.clock() % 1 < 0.6 then 0.2 else 1
	noSignal.TextStrokeTransparency = noSignal.TextTransparency
end)

gui.Parent = player:WaitForChild("PlayerGui")

-- Shows ReplicatedStorage.TowerStatus (set by ServerScriptService.TowerRun) as a top-centre header
-- in the Settings card's look (StarterPlayerScripts.TowerMusic): dark fade, HighwayGothic, kicker / title / team rule / state line.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local status = game:GetService("ReplicatedStorage"):WaitForChild("TowerStatus")
local player = Players.LocalPlayer
local gui = script.Parent

local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local WHITE = Color3.new(1, 1, 1)
local GREY = Color3.fromRGB(200, 202, 208)
local FAIL = Color3.fromRGB(200, 40, 40)
local SLIDE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function fade(edge, mid) -- transparency: edge at both ends, mid in the centre, eased like the Settings shade
	local keys = {}
	for i = 0, 10 do
		local t = i / 10
		local d = math.abs(t - 0.5) * 2
		table.insert(keys, NumberSequenceKeypoint.new(t, mid + (edge - mid) * TweenService:GetValue(d, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)))
	end
	return NumberSequence.new(keys)
end

local function text(parent, y, h, max, colour)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.fromScale(0.9, h)
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextScaled = true
	l.TextColor3 = colour
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize, c.MinTextSize = max, 8
	c.Parent = l
	l.Parent = parent
	return l
end

local card = Instance.new("CanvasGroup")
card.Name = "Header"
card.AnchorPoint = Vector2.new(0.5, 0)
-- header Y: below the insertion letterbox bar (Insertion BAR = 0.11) while the cutscene runs
local function headerPos(lift: number): UDim2
	if player:GetAttribute("Cutscene") then return UDim2.new(0.5, 0, 0.11, 12 - lift) end
	return UDim2.new(0.5, 0, 0, 52 - lift)
end
card.Position = headerPos(0)
card.Size = UDim2.fromScale(0.34, 0.11)
card.BackgroundTransparency = 1
card.GroupTransparency = 1
card.Visible = false
local size = Instance.new("UISizeConstraint")
size.MinSize = Vector2.new(320, 74)
size.MaxSize = Vector2.new(560, 96)
size.Parent = card
card.Parent = gui

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BorderSizePixel = 0
local sg = Instance.new("UIGradient")
sg.Transparency = fade(1, 0.25)
sg.Parent = shade
shade.Parent = card

local kicker = text(card, 0.17, 0.2, 13, GREY)
local title = text(card, 0.45, 0.36, 28, WHITE)
local rule = Instance.new("Frame")
rule.AnchorPoint = Vector2.new(0.5, 0.5)
rule.Position = UDim2.fromScale(0.5, 0.69)
rule.Size = UDim2.new(0.5, 0, 0, 2)
rule.BorderSizePixel = 0
local rg = Instance.new("UIGradient")
rg.Transparency = fade(1, 0)
rg.Parent = rule
rule.Parent = card
local state = text(card, 0.85, 0.18, 14, GREY)

local function teamColour()
	return player.Team and player.Team.TeamColor.Color or WHITE
end

-- "HOSTILES REMAINING · 5   ·   1:23": the floor clock runs from TowerStatus.FloorStart (server time) while the fight is on
local function stateText(enemies)
	local s = "HOSTILES REMAINING  ·  " .. tostring(enemies)
	local t0 = status:GetAttribute("FloorStart")
	if t0 then
		local e = math.max(0, math.floor(workspace:GetServerTimeNow() - t0))
		s ..= string.format("   ·   %d:%02d", e // 60, e % 60)
	end
	return s
end

local shown = false
local function refresh()
	local banner = status:GetAttribute("Banner")
	local enemies = status:GetAttribute("Enemies")
	if banner then
		-- "FLOOR 3/20: GET READY 5" -> kicker "FLOOR 3/20", title "GET READY 5"
		local k, t = banner:match("^(.-):%s*(.+)$")
		if not k then
			if banner:match("^FLOOR") then k, t = banner, "CLEAR THE FLOOR" else k, t = "GARRISON TOWER", banner end
		end
		local colour = if banner == "RAID FAILED" then FAIL else teamColour()
		kicker.Text = k
		title.Text = t
		rule.BackgroundColor3 = colour
		state.Visible = enemies ~= nil and enemies > 0
		state.Text = stateText(enemies)
		state.TextColor3 = colour:Lerp(WHITE, 0.45)
	end
	if banner and not shown then
		shown = true
		card.Visible = true
		card.Position = headerPos(12)
		TweenService:Create(card, SLIDE_IN, { GroupTransparency = 0, Position = headerPos(0) }):Play()
	elseif not banner and shown then
		shown = false
		local tw = TweenService:Create(card, SLIDE_OUT, { GroupTransparency = 1, Position = headerPos(12) })
		tw.Completed:Connect(function() if not shown then card.Visible = false end end)
		tw:Play()
	end
end
status.AttributeChanged:Connect(refresh)
task.spawn(function() -- tick the floor clock between status changes
	while true do
		task.wait(0.5)
		if shown and state.Visible and status:GetAttribute("FloorStart") then state.Text = stateText(status:GetAttribute("Enemies")) end
	end
end)

-- Boss strip under the header while TowerStatus.BossName is set: name, and one pip per boss model still up (BossLeft).
local BOSS = Color3.fromRGB(215, 75, 65)
local bossCard = Instance.new("Frame")
bossCard.Name = "Boss"
bossCard.AnchorPoint = Vector2.new(0.5, 0)
bossCard.Position = UDim2.new(0.5, 0, 0, 6) -- top edge, above the floor header
bossCard.Size = UDim2.new(0.3, 0, 0, 46)
bossCard.BackgroundColor3 = Color3.new(0, 0, 0)
bossCard.BorderSizePixel = 0
bossCard.Visible = false
local bg = Instance.new("UIGradient")
bg.Transparency = fade(1, 0.3)
bg.Parent = bossCard
local bsize = Instance.new("UISizeConstraint")
bsize.MinSize = Vector2.new(280, 46)
bsize.MaxSize = Vector2.new(480, 46)
bsize.Parent = bossCard
bossCard.Parent = gui
local bossName = text(bossCard, 0.32, 0.5, 20, BOSS:Lerp(WHITE, 0.25))
local pips = Instance.new("Frame")
pips.AnchorPoint = Vector2.new(0.5, 0.5)
pips.Position = UDim2.fromScale(0.5, 0.78)
pips.Size = UDim2.new(0.6, 0, 0, 6)
pips.BackgroundTransparency = 1
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 4)
list.Parent = pips
pips.Parent = bossCard
local bossTotal = 0
local function refreshBoss()
	local name, left = status:GetAttribute("BossName"), status:GetAttribute("BossLeft")
	bossCard.Visible = name ~= nil
	if not name then bossTotal = 0 return end
	bossName.Text = if status:GetAttribute("BossPhase") == 2 then name .. "  ·  PHASE 2" else name
	bossTotal = math.max(bossTotal, left or 0)
	for _, c in pips:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	for i = 1, bossTotal do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 34, 1, 0)
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = if i <= (left or bossTotal) then BOSS else Color3.fromRGB(70, 70, 70)
		pip.LayoutOrder = i
		pip.Parent = pips
	end
end
status:GetAttributeChangedSignal("BossName"):Connect(refreshBoss)
status:GetAttributeChangedSignal("BossLeft"):Connect(refreshBoss)
status:GetAttributeChangedSignal("BossPhase"):Connect(refreshBoss)
refreshBoss()
player:GetAttributeChangedSignal("Cutscene"):Connect(function()
	if shown then TweenService:Create(card, SLIDE_IN, { Position = headerPos(0) }):Play() end
end)
player:GetPropertyChangedSignal("Team"):Connect(refresh)
refresh()

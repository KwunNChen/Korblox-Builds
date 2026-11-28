-- End-of-raid score card, in the Settings / tower header look (HighwayGothic, dark fade, kicker / title / rule).
-- ServerScriptService.TowerRun fires RaidReport to each squad member when a raid ends:
-- { result, difficulty, floors, total, time, lines = { { label, count, points } }, score, best = { floors, score }?, newBest,
--   squad = { { name, userId, kills, heads, deaths, revives, accuracy? } },
--   grade = "S".. "F", timing = { used, par, fastest?, avg? } (seconds of floor fighting, from TowerRun's splits) }
-- Lines tally in one by one, then the raid score counts up, then the personal best for that difficulty.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer

local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local WHITE, GREY, DIM = Color3.new(1, 1, 1), Color3.fromRGB(200, 202, 208), Color3.fromRGB(140, 142, 148)
local FAIL = Color3.fromRGB(200, 40, 40)
local Difficulties = require(game:GetService("ReplicatedStorage"):WaitForChild("TowerDifficulties"))
-- the difficulty's accent (Frontline's is the old gold)
local function accentOf(name)
	return (Difficulties[name or ""] or Difficulties[Difficulties.default]).accent
end
local LOSS = Color3.fromRGB(225, 110, 100)
local GRADE_COLOUR = { S = Color3.fromRGB(255, 205, 80), A = Color3.fromRGB(130, 220, 130), B = Color3.fromRGB(235, 235, 240),
	C = Color3.fromRGB(170, 172, 178), D = LOSS, F = LOSS }
local W, ROW_H, ROWS_TOP = 540, 32, 146
local SLIDE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local TICK = "rbxasset://sounds/clickfast.wav"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local AUTO_CLOSE = 40

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.IgnoreGuiInset, gui.Enabled = "RaidReport", false, 20, true, false
gui.Parent = player:WaitForChild("PlayerGui")

local function fade(edge, mid) -- same eased centre-opaque fade as the Settings shade
	local keys = {}
	for i = 0, 10 do
		local t = i / 10
		local d = math.abs(t - 0.5) * 2
		table.insert(keys, NumberSequenceKeypoint.new(t, mid + (edge - mid) * TweenService:GetValue(d, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)))
	end
	return NumberSequence.new(keys)
end

local function label(parent, x, y, w, h, size, colour, align)
	local l = Instance.new("TextLabel")
	l.Position, l.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
	l.BackgroundTransparency = 1
	l.FontFace, l.TextSize, l.TextColor3 = FONT, size, colour
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Text = ""
	l.Parent = parent
	return l
end

local function rule(parent, y, w, colour)
	local f = Instance.new("Frame")
	f.Position, f.Size = UDim2.fromOffset((W - w) / 2, y), UDim2.fromOffset(w, 2)
	f.BackgroundColor3, f.BorderSizePixel = colour, 0
	local g = Instance.new("UIGradient")
	g.Transparency = fade(1, 0)
	g.Parent = f
	f.Parent = parent
	return f
end

local function commas(n)
	local s = tostring(math.abs(math.round(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return (if n < 0 then "-" else "") .. out
end

local function clock(seconds)
	seconds = math.floor(seconds or 0)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function sound(id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = id, volume, pitch or 1
	s.Parent = gui
	s:Play()
	Debris:AddItem(s, 3)
end

-- counts lbl up to `to` over `seconds`, eased out; signed adds a + to gains
local function countUp(lbl, to, seconds, signed, ticking)
	local t0, lastTick = os.clock(), 0
	while lbl.Parent do
		local a = math.min((os.clock() - t0) / seconds, 1)
		local v = to * (1 - (1 - a) ^ 3)
		lbl.Text = (if signed and to >= 0 then "+" else "") .. commas(v)
		if ticking and os.clock() - lastTick > 0.05 and a < 1 then
			lastTick = os.clock()
			sound(TICK, 0.25, 0.9 + a * 0.6)
		end
		if a >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end

local current = 0
local viewConn

local function close(id)
	if current ~= id or not gui.Enabled then return end
	current += 1
	if viewConn then viewConn:Disconnect() viewConn = nil end
	for _, c in gui:GetChildren() do
		if c:IsA("CanvasGroup") then TweenService:Create(c, SLIDE_OUT, { GroupTransparency = 1 }):Play() end
		if c:IsA("Frame") then TweenService:Create(c, SLIDE_OUT, { BackgroundTransparency = 1 }):Play() end
	end
	task.wait(0.3)
	gui.Enabled = false
	gui:ClearAllChildren()
end

local function show(data)
	current += 1
	local id = current
	if viewConn then viewConn:Disconnect() end
	gui:ClearAllChildren()
	gui.Enabled = true
	local failed = data.result ~= "EXTRACTED"
	local accent = if failed then FAIL else WHITE
	local lines = data.lines or {}
	local rowsEnd = ROWS_TOP + #lines * ROW_H
	local squad = data.squad or {}
	local SQ_TOP, SQ_ROW = rowsEnd + 148, 26
	local squadH = if #squad > 0 then 30 + #squad * SQ_ROW + 12 else 0
	local H = rowsEnd + 190 + squadH

	local dim = Instance.new("Frame")
	dim.Size, dim.BackgroundColor3, dim.BackgroundTransparency, dim.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 1, 0
	dim.Parent = gui
	TweenService:Create(dim, TweenInfo.new(0.6), { BackgroundTransparency = 0.4 }):Play()

	local card = Instance.new("CanvasGroup")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.53)
	card.Size = UDim2.fromOffset(W, H)
	card.BackgroundTransparency, card.GroupTransparency = 1, 1
	card.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local cam = workspace.CurrentCamera
	local function fit() scale.Scale = math.clamp(cam.ViewportSize.Y / (H + 160), 0.5, 1.2) end
	fit()
	viewConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	local shade = Instance.new("Frame")
	shade.Size, shade.BackgroundColor3, shade.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 0
	local sg = Instance.new("UIGradient")
	sg.Transparency = fade(1, 0.1)
	sg.Parent = shade
	shade.Parent = card
	TweenService:Create(card, SLIDE_IN, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }):Play()

	label(card, 0, 22, W, 16, 14, accentOf(data.difficulty)).Text = "GARRISON TOWER  ·  " .. string.upper(data.difficulty or "")
	label(card, 0, 42, W, 44, 42, WHITE).Text = data.result
	rule(card, 94, 280, accent)
	label(card, 0, 106, W, 18, 15, accent:Lerp(WHITE, 0.45)).Text =
		string.format("%d OF %d FLOORS CLEARED  ·  %s", data.floors or 0, data.total or 0, clock(data.time))
	local timing = data.timing
	if timing and timing.fastest then
		label(card, 0, 126, W, 16, 13, DIM).Text = string.format("FLOOR TIME %s  /  PAR %s   ·   AVG %s   ·   FASTEST %s",
			clock(timing.used), clock(timing.par), clock(timing.avg), clock(timing.fastest))
	end

	task.wait(0.7)
	for i, line in lines do
		if current ~= id then return end
		local name, count, pts = line[1], line[2], line[3]
		local y = ROWS_TOP + (i - 1) * ROW_H
		local row = Instance.new("CanvasGroup")
		row.BackgroundTransparency, row.GroupTransparency = 1, 1
		row.Size, row.Position = UDim2.fromOffset(W, ROW_H), UDim2.fromOffset(-16, y)
		row.Parent = card
		label(row, 80, 0, 240, ROW_H, 19, WHITE, Enum.TextXAlignment.Left).Text = name
		label(row, 300, 0, 70, ROW_H, 17, DIM, Enum.TextXAlignment.Right).Text = "x" .. commas(count)
		local value = label(row, 340, 0, 120, ROW_H, 21, if pts < 0 then LOSS else WHITE, Enum.TextXAlignment.Right)
		value.Text = "+0"
		TweenService:Create(row, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { GroupTransparency = 0, Position = UDim2.fromOffset(0, y) }):Play()
		sound(TICK, 0.4, 1)
		task.spawn(countUp, value, pts, 0.4, true)
		task.wait(0.5)
	end
	if current ~= id then return end

	rule(card, rowsEnd + 10, 380, DIM)
	label(card, 80, rowsEnd + 22, 200, 48, 22, GREY, Enum.TextXAlignment.Left).Text = "RAID SCORE"
	local total = label(card, 240, rowsEnd + 18, 220, 52, 46, WHITE, Enum.TextXAlignment.Right)
	task.wait(0.3)
	countUp(total, data.score or 0, 1.4, false, true)
	if current ~= id then return end
	sound(PING, 0.6, if failed then 0.8 else 1)
	local pop = Instance.new("UIScale")
	pop.Scale = 1.15
	pop.Parent = total
	TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- run grade, top-left: stamps in after the score
	if data.grade then
		task.wait(0.35)
		if current ~= id then return end
		label(card, 26, 14, 90, 14, 12, DIM).Text = "GRADE"
		local g = label(card, 26, 28, 90, 70, 68, GRADE_COLOUR[data.grade] or WHITE)
		g.Text = data.grade
		local gs = Instance.new("UIScale")
		gs.Scale = 2.2
		gs.Parent = g
		TweenService:Create(gs, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		sound(PING, 0.7, if data.grade == "S" then 1.4 elseif data.grade == "F" or data.grade == "D" then 0.7 else 1.1)
	end
	-- the score is in: the RAID FAILED / EXTRACTED header (TowerHUD, drawn above this card) leaves
	local header = player.PlayerGui:FindFirstChild("TowerHUD") and player.PlayerGui.TowerHUD:FindFirstChild("Header")
	if header and header.Visible then
		local tw = TweenService:Create(header, SLIDE_OUT, { GroupTransparency = 1 })
		tw.Completed:Connect(function() header.Visible = false end)
		tw:Play()
	end

	task.wait(0.5)
	if current ~= id then return end
	local best = data.best
	local bestText = label(card, 0, rowsEnd + 82, W, 18, 15, GREY)
	bestText.Text = if best
		then string.format("PERSONAL BEST  ·  %s  ·  %d FLOOR%s  ·  %s", string.upper(data.difficulty or ""), best.floors, if best.floors == 1 then "" else "S", commas(best.score))
		else "NO PERSONAL BEST YET  ·  CLEAR A FLOOR TO SET ONE"
	if data.newBest then
		local badge = label(card, 0, rowsEnd + 106, W, 26, 24, accentOf(data.difficulty))
		badge.Text = "NEW PERSONAL BEST"
		local s = Instance.new("UIScale")
		s.Scale = 1.6
		s.Parent = badge
		TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		sound(PING, 0.8, 1.25)
		task.spawn(function() -- slow glow pulse while the card is up
			while badge.Parent and current == id do
				TweenService:Create(badge, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { TextTransparency = 0.35 }):Play()
				task.wait(0.8)
				TweenService:Create(badge, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
				task.wait(0.8)
			end
		end)
	end

	-- squad table: everyone in the raid, most kills first, your own row in the difficulty accent
	if #squad > 0 then
		rule(card, SQ_TOP - 6, 380, DIM)
		local cols = { { "KILLS", "kills" }, { "HEADSHOT %", "headPct" }, { "ACCURACY", "accuracy" }, { "DEATHS", "deaths" }, { "REVIVES", "revives" } }
		label(card, 50, SQ_TOP, 140, 24, 13, DIM, Enum.TextXAlignment.Left).Text = "SQUAD"
		for c, col in cols do label(card, 190 + (c - 1) * 68, SQ_TOP, 68, 24, 12, DIM, Enum.TextXAlignment.Right).Text = col[1] end
		for r, row in squad do
			local y = SQ_TOP + 28 + (r - 1) * SQ_ROW
			local colour = if row.userId == player.UserId then accentOf(data.difficulty) else WHITE
			local nameLbl = label(card, 50, y, 140, SQ_ROW, 17, colour, Enum.TextXAlignment.Left)
			nameLbl.Text, nameLbl.TextTruncate = row.name, Enum.TextTruncate.AtEnd
			for c, col in cols do
				local v = row[col[2]]
				if col[2] == "headPct" then v = if (row.kills or 0) > 0 then (row.heads or 0) / row.kills else nil end -- share of kills that were headshots
				label(card, 190 + (c - 1) * 68, y, 68, SQ_ROW, 17, colour, Enum.TextXAlignment.Right).Text =
					if col[2] == "accuracy" or col[2] == "headPct" then (if v then math.round(v * 100) .. "%" else "-") else commas(v or 0)
			end
		end
	end

	local button = Instance.new("TextButton")
	button.Position, button.Size = UDim2.fromOffset((W - 200) / 2, rowsEnd + 144 + squadH), UDim2.fromOffset(200, 34)
	button.BackgroundColor3, button.BackgroundTransparency, button.AutoButtonColor = Color3.new(), 0.3, true
	button.FontFace, button.TextSize, button.TextColor3, button.Text = FONT, 17, WHITE, "CONTINUE"
	button.Modal = true -- frees the mouse from first-person lock
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode, stroke.Color, stroke.Transparency = Enum.ApplyStrokeMode.Border, WHITE, 0.6
	stroke.Parent = button
	button.Parent = card
	button.Activated:Connect(function() close(id) end)
	task.delay(AUTO_CLOSE, close, id)
end

game:GetService("ReplicatedStorage"):WaitForChild("RaidReport").OnClientEvent:Connect(function(data)
	task.spawn(show, data)
end)

-- /PR: personal record card, top centre under the tower header. TowerRun sets PRDifficulty / PRFloors / PRScore on the player.
local prGui = Instance.new("ScreenGui")
prGui.Name, prGui.ResetOnSpawn, prGui.DisplayOrder = "PersonalRecord", false, 15
prGui.Parent = player.PlayerGui
local PR_W, PR_H = 420, 96
local pr = Instance.new("CanvasGroup")
pr.AnchorPoint, pr.Position, pr.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 140), UDim2.fromOffset(PR_W, PR_H)
pr.BackgroundTransparency, pr.GroupTransparency, pr.Visible = 1, 1, false
pr.Parent = prGui
do
	local shade = Instance.new("Frame")
	shade.Size, shade.BackgroundColor3, shade.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 0
	local g = Instance.new("UIGradient")
	g.Transparency = fade(1, 0.25)
	g.Parent = shade
	shade.Parent = pr
end
local prKicker = label(pr, 0, 10, PR_W, 14, 13, GREY)
prKicker.Text = "PERSONAL RECORD"
local prTitle = label(pr, 0, 26, PR_W, 34, 32, WHITE)
local prRule = Instance.new("Frame")
prRule.Position, prRule.Size, prRule.BorderSizePixel = UDim2.fromOffset((PR_W - 220) / 2, 64), UDim2.fromOffset(220, 2), 0
do
	local g = Instance.new("UIGradient")
	g.Transparency = fade(1, 0)
	g.Parent = prRule
end
prRule.Parent = pr
local prState = label(pr, 0, 72, PR_W, 16, 14, GREY)

local prShown = 0
local function showPR()
	prShown += 1
	local id = prShown
	local score, diff, floors = player:GetAttribute("PRScore"), player:GetAttribute("PRDifficulty"), player:GetAttribute("PRFloors")
	prRule.BackgroundColor3 = accentOf(diff)
	if score then
		prTitle.Text = commas(score)
		prState.Text = string.format("%s  ·  %d FLOOR%s CLEARED", string.upper(diff or ""), floors or 0, if floors == 1 then "" else "S")
	else
		prTitle.Text = "NO RECORD YET"
		prState.Text = "CLEAR A FLOOR IN A RAID TO SET ONE"
	end
	pr.Visible = true
	pr.Position = UDim2.new(0.5, 0, 0, 128)
	TweenService:Create(pr, SLIDE_IN, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 140) }):Play()
	sound(PING, 0.5, 1.1)
	task.delay(6, function()
		if prShown ~= id then return end
		local tw = TweenService:Create(pr, SLIDE_OUT, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0, 128) })
		tw.Completed:Connect(function() if prShown == id then pr.Visible = false end end)
		tw:Play()
	end)
end

local command = Instance.new("TextChatCommand")
command.Name = "PersonalRecord"
command.PrimaryAlias, command.SecondaryAlias = "/PR", "/pr"
command.Triggered:Connect(showPR)
command.Parent = game:GetService("TextChatService"):WaitForChild("TextChatCommands", 10) or game:GetService("TextChatService")


-- The right-side player list is off: standings live on the raid card's squad table and in /leaderboards.
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

-- /leaderboards: top 10 per difficulty from TowerRun's TowerLeaderboards, in the same card look, a tab per difficulty.
local lbGui = Instance.new("ScreenGui")
lbGui.Name, lbGui.ResetOnSpawn, lbGui.DisplayOrder, lbGui.IgnoreGuiInset, lbGui.Enabled = "Leaderboards", false, 18, true, false
lbGui.Parent = player.PlayerGui
local LB_W, LB_ROW, LB_TOP = 520, 28, 172
local LB_H = LB_TOP + 10 * LB_ROW + 70
local lbBoards, lbTab = nil, nil

local function closeBoards()
	lbGui.Enabled = false
	lbGui:ClearAllChildren()
end

local function drawBoard(body, name)
	body:ClearAllChildren()
	local rows = lbBoards and lbBoards[name]
	if not rows or #rows == 0 then
		label(body, 0, 0, LB_W, LB_ROW, 16, DIM).Text = if rows then "NO RECORDS YET" else "LEADERBOARD UNAVAILABLE"
		return
	end
	for i, r in rows do
		local y = (i - 1) * LB_ROW
		local c = if r.name == player.Name then accentOf(name) else WHITE
		label(body, 40, y, 40, LB_ROW, 18, DIM, Enum.TextXAlignment.Right).Text = tostring(i)
		local n = label(body, 100, y, 200, LB_ROW, 18, c, Enum.TextXAlignment.Left)
		n.Text, n.TextTruncate = r.name, Enum.TextTruncate.AtEnd
		label(body, 300, y, 80, LB_ROW, 17, GREY, Enum.TextXAlignment.Right).Text = tostring(r.floors)
		label(body, 380, y, 100, LB_ROW, 18, c, Enum.TextXAlignment.Right).Text = commas(r.score)
	end
end

local function openBoards()
	if lbGui.Enabled then closeBoards() return end -- the command toggles
	lbGui:ClearAllChildren()
	lbGui.Enabled = true
	local card = Instance.new("CanvasGroup")
	card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.53), UDim2.fromOffset(LB_W, LB_H)
	card.BackgroundTransparency, card.GroupTransparency = 1, 1
	card.Parent = lbGui
	local sc = Instance.new("UIScale")
	sc.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / (LB_H + 160), 0.5, 1.2)
	sc.Parent = card
	local shade = Instance.new("Frame")
	shade.Size, shade.BackgroundColor3, shade.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 0
	local sg = Instance.new("UIGradient")
	sg.Transparency = fade(1, 0.1)
	sg.Parent = shade
	shade.Parent = card
	TweenService:Create(card, SLIDE_IN, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }):Play()

	label(card, 0, 22, LB_W, 16, 14, GREY).Text = "GARRISON TOWER"
	label(card, 0, 42, LB_W, 44, 42, WHITE).Text = "LEADERBOARDS"
	local bar = rule(card, 94, 280, WHITE)
	label(card, 40, LB_TOP - 26, 40, 20, 12, DIM, Enum.TextXAlignment.Right).Text = "#"
	label(card, 100, LB_TOP - 26, 200, 20, 12, DIM, Enum.TextXAlignment.Left).Text = "OPERATOR"
	label(card, 300, LB_TOP - 26, 80, 20, 12, DIM, Enum.TextXAlignment.Right).Text = "FLOORS"
	label(card, 380, LB_TOP - 26, 100, 20, 12, DIM, Enum.TextXAlignment.Right).Text = "BEST SCORE"
	local body = Instance.new("Frame")
	body.BackgroundTransparency, body.Position, body.Size = 1, UDim2.fromOffset(0, LB_TOP), UDim2.fromOffset(LB_W, 10 * LB_ROW)
	body.Parent = card

	local tabs = {}
	local function select(name)
		lbTab = name
		bar.BackgroundColor3 = accentOf(name)
		for n, b in tabs do b.TextColor3 = if n == name then accentOf(n) else DIM end
		if lbBoards then
			drawBoard(body, name)
		else
			body:ClearAllChildren()
			label(body, 0, 0, LB_W, LB_ROW, 16, DIM).Text = "LOADING"
		end
	end
	local tw = LB_W / #Difficulties.order
	for i, name in Difficulties.order do
		local b = Instance.new("TextButton")
		b.Position, b.Size = UDim2.fromOffset((i - 1) * tw, 104), UDim2.fromOffset(tw, 28)
		b.BackgroundTransparency, b.FontFace, b.TextSize, b.Text = 1, FONT, 16, string.upper(name)
		b.Parent = card
		tabs[name] = b
		b.Activated:Connect(function() select(name) end)
	end

	local button = Instance.new("TextButton")
	button.Position, button.Size = UDim2.fromOffset((LB_W - 200) / 2, LB_H - 52), UDim2.fromOffset(200, 34)
	button.BackgroundColor3, button.BackgroundTransparency, button.AutoButtonColor = Color3.new(), 0.3, true
	button.FontFace, button.TextSize, button.TextColor3, button.Text = FONT, 17, WHITE, "CLOSE"
	button.Modal = true -- frees the mouse from first-person lock
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode, stroke.Color, stroke.Transparency = Enum.ApplyStrokeMode.Border, WHITE, 0.6
	stroke.Parent = button
	button.Parent = card
	button.Activated:Connect(closeBoards)

	local status = game:GetService("ReplicatedStorage"):FindFirstChild("TowerStatus")
	local current = status and status:GetAttribute("Difficulty")
	select(lbTab or (if current and Difficulties[current] then current else Difficulties.default))
	task.spawn(function()
		local ok, boards = pcall(function()
			return game:GetService("ReplicatedStorage"):WaitForChild("TowerLeaderboards", 10):InvokeServer()
		end)
		if not card.Parent then return end
		if ok and boards then lbBoards = boards end
		if lbBoards then select(lbTab) else drawBoard(body, lbTab) end
	end)
end

local lbCommand = Instance.new("TextChatCommand")
lbCommand.Name = "Leaderboards"
lbCommand.PrimaryAlias, lbCommand.SecondaryAlias = "/leaderboards", "/lb"
lbCommand.Triggered:Connect(openBoards)
lbCommand.Parent = game:GetService("TextChatService"):WaitForChild("TextChatCommands", 10) or game:GetService("TextChatService")

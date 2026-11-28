--[[
	Staging

	The raid board: while you stand in workspace.Staging.Zone (player attribute Staged, set by
	ServerScriptService.TowerRun) a card on the right lists the squad, each one's personal record and
	ready state, and the deploy countdown (kept right: on the left it covered the table's prompt tag) (ReplicatedStorage.TowerStatus attribute Deploy).
	Ready is toggled at the ReadyPrompt on the briefing table (staging compound); this script only flips its text for you.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local status = ReplicatedStorage:WaitForChild("TowerStatus")
local staging = workspace:WaitForChild("Staging")
staging:WaitForChild("ReadyPoint"):WaitForChild("ReadyPrompt")
local Difficulties = require(ReplicatedStorage:WaitForChild("TowerDifficulties"))

local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
local WHITE, GREY, DIM = Color3.new(1, 1, 1), Color3.fromRGB(200, 202, 208), Color3.fromRGB(140, 142, 148)
local READY = Color3.fromRGB(150, 210, 140)
local W, ROW_H, ROWS_TOP = 340, 26, 140
local TICK = "rbxasset://sounds/clickfast.wav"

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.IgnoreGuiInset = "Staging", false, 12, true
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

local card = Instance.new("CanvasGroup")
card.AnchorPoint = Vector2.new(1, 0.5)
card.Position = UDim2.new(1, 20, 0.5, 0)
card.Size = UDim2.fromOffset(W, ROWS_TOP + 40)
card.BackgroundTransparency, card.GroupTransparency = 1, 1
card.Visible = false
card.Parent = gui
local shade = Instance.new("Frame")
shade.Size, shade.BackgroundColor3, shade.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 0
local sg = Instance.new("UIGradient")
sg.Transparency = fade(1, 0.15)
sg.Parent = shade
shade.Parent = card

local kicker = label(card, 0, 18, W, 16, 14, GREY)
local title = label(card, 0, 38, W, 34, 32, WHITE)
local rule = Instance.new("Frame")
rule.Position, rule.Size = UDim2.fromOffset((W - 220) / 2, 80), UDim2.fromOffset(220, 2)
rule.BackgroundColor3, rule.BorderSizePixel = WHITE, 0
local rg = Instance.new("UIGradient")
rg.Transparency = fade(1, 0)
rg.Parent = rule
rule.Parent = card
local hint = label(card, 0, 92, W, 18, 15, GREY)
local details = label(card, 0, 112, W, 16, 13, DIM) -- the difficulty's rules

-- "5 WAVES  ·  RESPAWN IN 1 WAVE  ·  2 BANDAGES, 1 MEDKIT"
local function rules(d)
	local kit = {}
	for _, name in { "Bandage", "Medkit" } do
		local n = d.kit[name]
		if n then table.insert(kit, n .. " " .. string.upper(name) .. (if n == 1 then "" else "S")) end
	end
	return string.format("%d WAVES  \u{00B7}  RESPAWN IN %d WAVE%s  \u{00B7}  %s", d.floors, d.respawnWaves,
		if d.respawnWaves == 1 then "" else "S", table.concat(kit, ", "))
end
local function showDifficulty()
	local name = status:GetAttribute("Difficulty") or Difficulties.default
	local d = Difficulties[name]
	kicker.Text = "GARRISON TOWER  \u{00B7}  " .. string.upper(name)
	kicker.TextColor3, rule.BackgroundColor3 = d.accent, d.accent
	details.Text = rules(d)
end
status:GetAttributeChangedSignal("Difficulty"):Connect(showDifficulty)
showDifficulty()
local rows = Instance.new("Frame")
rows.BackgroundTransparency = 1
rows.Size, rows.Position = UDim2.fromOffset(W, 0), UDim2.fromOffset(0, ROWS_TOP)
rows.Parent = card

local shown = false
local fadeOut: Tween? = nil
local function show(on)
	if on == shown then return end
	shown = on
	if fadeOut then fadeOut:Cancel() fadeOut = nil end
	card.Visible = true
	local tw = TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		GroupTransparency = if on then 0 else 1,
		Position = UDim2.new(1, if on then -12 else 20, 0.5, 0),
	})
	if not on then
		-- a CanvasGroup can keep drawing its last frame at transparency 1; switching it off is certain
		fadeOut = tw
		tw.Completed:Connect(function(state) if state == Enum.PlaybackState.Completed and not shown then card.Visible = false end end)
	end
	tw:Play()
end

-- staged and not already deploying: the panel goes the moment the raid takes you
local function wanted()
	return player:GetAttribute("Staged") == true and not player:GetAttribute("InTowerRun")
end
for _, name in { "Staged", "InTowerRun" } do
	player:GetAttributeChangedSignal(name):Connect(function() show(wanted()) end)
end

local lastCount = nil
while true do
	task.wait(0.2)
	local staged = wanted()
	show(staged)
	-- looked up each tick: the ReadyPoint streams out during a run and comes back as a new instance
	local readyPrompt = staging:FindFirstChild("ReadyPoint") and staging.ReadyPoint:FindFirstChild("ReadyPrompt")
	if readyPrompt then readyPrompt.ActionText = if player:GetAttribute("Ready") then "Stand down" else "Ready up" end
	if not staged then lastCount = nil continue end

	local squad = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Staged") then table.insert(squad, p) end
	end
	table.sort(squad, function(a, b) return a.Name < b.Name end)
	local ready = 0
	for _, p in squad do if p:GetAttribute("Ready") then ready += 1 end end

	local count = status:GetAttribute("Deploy")
	if count then
		title.Text = "DEPLOYING IN " .. count
		hint.Text = if ready == #squad then "ALL READY" else string.format("%d OF %d READY  \u{00B7}  E AT THE TABLE", ready, #squad)
		if count ~= lastCount and count <= 5 then
			local s = Instance.new("Sound")
			s.SoundId, s.Volume, s.PlaybackSpeed = TICK, 0.4, if count == 0 then 1.4 else 1
			s.Parent = gui
			s:Play()
			Debris:AddItem(s, 2)
		end
	else
		title.Text = "STAGING"
		hint.Text = "TAVERN TABLE:  E READY  \u{00B7}  F DIFFICULTY"
	end
	lastCount = count

	rows:ClearAllChildren()
	for i, p in squad do
		local y = (i - 1) * ROW_H
		local isReady = p:GetAttribute("Ready") == true
		label(rows, 40, y, 170, ROW_H, 17, if p == player then WHITE else GREY, Enum.TextXAlignment.Left).Text = string.upper(p.DisplayName)
		local pr = p:GetAttribute("PRFloors")
		label(rows, 190, y, 60, ROW_H, 14, DIM, Enum.TextXAlignment.Right).Text = if pr then ("PR " .. pr .. "F") else ""
		label(rows, 250, y, 50, ROW_H, 15, if isReady then READY else DIM, Enum.TextXAlignment.Right).Text = if isReady then "READY" else "\u{2014}"
	end
	card.Size = UDim2.fromOffset(W, ROWS_TOP + #squad * ROW_H + 18)
end

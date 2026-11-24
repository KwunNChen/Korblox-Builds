--!strict
-- Lives inside the "Korblox Dark Magic" Tool. Shows the panel while equipped: pick a spell,
-- click characters to select them, then press the button to fire on all of them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tool = script.Parent :: Tool
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remote = ReplicatedStorage:WaitForChild("Dark Magic") :: RemoteEvent

local INK = Color3.fromRGB(232, 226, 210)
local MUTED = Color3.fromRGB(128, 124, 112)
local RULE = Color3.fromRGB(70, 68, 62)
local ACCENT = Color3.fromRGB(156, 92, 255)

-- Caster animations (R6, made with fwjelaa's animation method). Roblox only plays an animation in
-- games owned by whoever published it, so in another game: right-click each KeyframeSequence in
-- ServerStorage.DarkMagicAnimations > Save to Roblox (as that game's owner) and paste the new ids here.
-- Until then the spells still work, just without the caster's body animation.
local ANIM_IDS: { [string]: string } = {
	uniform = "127988240846267", -- DM_Uniform
	melt = "80748191261058", -- DM_Melt
	raise = "119474075521745", -- DM_Raise
	rip = "84106519181009", -- DM_SoulRip
	step = "103187897950830", -- DM_ShadowStep
	hex = "80748191261058", -- DM_Melt (hex shares the melt animation)
}
local KFS_NAME = {
	uniform = "DM_Uniform", melt = "DM_Melt", raise = "DM_Raise",
	rip = "DM_SoulRip", step = "DM_ShadowStep", hex = "DM_Melt",
}

local loaded: { [string]: AnimationTrack } = {}
local loadedFor: Animator? = nil
-- The track for an animation key on the current character, or nil if it has no id yet.
local function track(key: string): AnimationTrack?
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	if animator ~= loadedFor then -- new character: old tracks belong to the old Animator
		loaded, loadedFor = {}, animator
	end
	if loaded[key] then
		return loaded[key]
	end
	local id = ANIM_IDS[key] ~= "" and "rbxassetid://" .. ANIM_IDS[key] or nil
	if not id and game:GetService("RunService"):IsStudio() then
		-- unpublished test copies, Studio only (ReplicatedStorage.DarkMagicAnimations)
		local folder = ReplicatedStorage:FindFirstChild("DarkMagicAnimations")
		local kfs = folder and folder:FindFirstChild(KFS_NAME[key])
		if kfs then
			local ok, temp = pcall(function()
				return game:GetService("AnimationClipProvider"):RegisterAnimationClip(kfs)
			end)
			id = ok and temp or nil
		end
	end
	if not id then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, t = pcall(animator.LoadAnimation, animator, anim)
	if not ok then
		return nil
	end
	loaded[key] = t
	return t
end

-- A plain requisition slip: square corners, one thin accent edge, ruled fields.
local gui = Instance.new("ScreenGui")
gui.Name = "DarkMagicGui"
gui.ResetOnSpawn = false
gui.Enabled = false

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(1, 1)
frame.Position = UDim2.new(1, -20, 1, -20)
frame.Size = UDim2.fromOffset(236, 128)
frame.BackgroundColor3 = Color3.fromRGB(19, 19, 17)
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.Parent = gui

local edge = Instance.new("Frame")
edge.Size = UDim2.new(0, 2, 1, 0)
edge.BackgroundColor3 = ACCENT
edge.BorderSizePixel = 0
edge.Parent = frame

local function text(class: string, props: { [string]: any }): any
	local t = Instance.new(class) :: any
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		t[k] = v
	end
	t.Parent = frame
	return t
end

-- Mode tabs, one per spell.
local MODES = { "uniform", "melt", "raise", "rip", "step", "hex" }
local VERB = { uniform = "ISSUE", melt = "MELT", raise = "RAISE", rip = "RIP", step = "STEP", hex = "HEX" }
local HINT = {
	uniform = "Click people to select and give uniforms",
	melt = "Click people to select to turn to skeletons",
	raise = "Bodyguards/Attack people",
	rip = "Tear a poor man's soul out, and heal yourself",
	step = "Appear behind someone",
	hex = "2x damge on that person for 10 seconds",
}
local mode = "uniform"
local tabs: { [string]: TextButton } = {}
local tabRule = Instance.new("Frame")
tabRule.BorderSizePixel = 0
tabRule.BackgroundColor3 = ACCENT
tabRule.Size = UDim2.new(1, 0, 0, 2)
tabRule.Position = UDim2.new(0, 0, 1, 0)
local tabRow = Instance.new("Frame")
tabRow.BackgroundTransparency = 1
tabRow.Position = UDim2.fromOffset(16, 8)
tabRow.Size = UDim2.new(1, -32, 0, 24)
tabRow.Parent = frame
local tabList = Instance.new("UIListLayout")
tabList.FillDirection = Enum.FillDirection.Horizontal
tabList.Padding = UDim.new(0, 12)
tabList.SortOrder = Enum.SortOrder.LayoutOrder
tabList.Parent = tabRow
for i, name in MODES do
	local b = text("TextButton", {
		Text = name:upper(),
		Font = Enum.Font.Oswald,
		TextSize = 17,
		AutoButtonColor = false,
		LayoutOrder = i,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
	})
	b.Parent = tabRow
	tabs[name] = b
end

local function field(name: string, y: number, default: string): TextBox
	text("TextLabel", {
		Text = name,
		Font = Enum.Font.RobotoMono,
		TextSize = 12,
		TextColor3 = MUTED,
		Position = UDim2.fromOffset(16, y),
		Size = UDim2.fromOffset(52, 22),
	})
	local b = text("TextBox", {
		Text = default,
		PlaceholderText = "asset id",
		PlaceholderColor3 = RULE,
		ClearTextOnFocus = false,
		Font = Enum.Font.RobotoMono,
		TextSize = 14,
		TextColor3 = INK,
		Position = UDim2.fromOffset(68, y),
		Size = UDim2.new(1, -84, 0, 22),
	}) :: TextBox
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = default ~= "" and ACCENT or RULE
	line.Position = UDim2.new(0, 0, 1, 0)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Parent = b
	-- rule lights up once the field holds a usable id
	b:GetPropertyChangedSignal("Text"):Connect(function()
		line.BackgroundColor3 = b.Text:match("%d+") and ACCENT or RULE
	end)
	return b
end

-- default uniform, so the tool works straight away; either can be overwritten
local shirtBox = field("SHIRT", 44, "8391399172")
local pantsBox = field("PANTS", 72, "77314619818928")

local hint = text("TextLabel", {
	Text = "Click people to select. Blank keeps theirs.",
	Font = Enum.Font.SourceSans,
	TextSize = 14,
	TextColor3 = MUTED,
	Position = UDim2.fromOffset(16, 102),
	Size = UDim2.new(1, -32, 0, 16),
})

local issue = text("TextButton", {
	Text = "ISSUE",
	Font = Enum.Font.Oswald,
	TextSize = 16,
	TextColor3 = MUTED,
	TextXAlignment = Enum.TextXAlignment.Center,
	AutoButtonColor = false,
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(34, 33, 30),
	Position = UDim2.fromOffset(16, 128),
	Size = UDim2.new(1, -32, 0, 26),
}) :: TextButton
frame.Size = UDim2.fromOffset(300, 166)

gui.Parent = player:WaitForChild("PlayerGui")

local RANGE = 150 -- keep in step with the server's RANGE

-- pulls the first number out, so a pasted catalog URL works too
local function idOf(b: TextBox): number?
	return tonumber(b.Text:match("%d+"))
end

-- Same side as the server's isFriend: my own skeletons, or the same team (players, or NPCs' Team value).
local function isFriend(m: Model): boolean
	if m == player.Character or m:GetAttribute("NecroOwner") == player.UserId then
		return true
	end
	local team = player.Team
	if player.Neutral or not team then
		return false
	end
	local other = Players:GetPlayerFromCharacter(m)
	if other then
		return not other.Neutral and other.Team == team
	end
	local settings = m:FindFirstChild("Settings")
	local tag = (m:FindFirstChild("Team") or (settings and settings:FindFirstChild("Team"))) :: any
	return tag ~= nil and tag:IsA("StringValue") and tag.Value == team.Name
end

-- mirrors the server's checks, so only people the server will accept light up
local function legalTarget(part: Instance?): Model?
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	while part and part ~= workspace do
		local hum = part:IsA("Model") and part:FindFirstChildOfClass("Humanoid")
		if hum then
			local m = part :: Model
			if mode == "raise" then
				-- skeletons never fight your side; melt's leftover bones can be raised
				local torso = m:FindFirstChild("Torso") or m:FindFirstChildWhichIsA("BasePart")
				local corpse = m:GetAttribute("MeltCorpse") == true
				local ok = (hum.Health > 0 or corpse) and not isFriend(m)
				if ok and torso and torso:IsA("BasePart") and myRoot and (torso.Position - myRoot.Position).Magnitude <= RANGE then
					return m
				end
				return nil
			end
			if m == player.Character and (mode == "rip" or mode == "step" or mode == "hex") then
				return nil
			end
			local root = hum.RootPart
			if hum.Health > 0 and root and myRoot and (root.Position - myRoot.Position).Magnitude <= RANGE then
				return m
			end
			return nil
		end
		part = part.Parent
	end
	return nil
end

-- Highlights made on the client are only visible to this player.
local function makeHighlight(fill: number): Highlight
	local h = Instance.new("Highlight")
	h.FillColor, h.OutlineColor = ACCENT, ACCENT
	h.FillTransparency, h.OutlineTransparency = fill, 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	return h
end

local hoverHl = makeHighlight(1)
local selected: { [Model]: Highlight } = {}

local function refreshIssue()
	local n = 0
	for m in selected do
		n += 1
	end
	local verb = VERB[mode]
	issue.Text = n > 0 and (verb .. "  ·  " .. n) or (mode == "raise" and "RAISE  ·  GUARDS" or verb)
	local ready = n > 0 or mode == "raise" -- raise with nobody picked summons bodyguards
	issue.BackgroundColor3 = ready and ACCENT or Color3.fromRGB(34, 33, 30)
	issue.TextColor3 = ready and Color3.fromRGB(14, 12, 18) or MUTED
end

local function deselect(m: Model)
	local h = selected[m]
	if h then
		h:Destroy()
		selected[m] = nil
	end
end

local function clearAll()
	for m in selected do
		deselect(m)
	end
	hoverHl.Parent = nil
	refreshIssue()
end

local function setMode(m: string)
	mode = m
	for name, b in tabs do
		b.TextColor3 = name == m and INK or MUTED
	end
	tabRule.Parent = tabs[m]
	-- the clothing fields only matter for uniforms
	for _, b in { shirtBox, pantsBox } do
		b.TextEditable = m == "uniform"
		b.TextTransparency = m == "uniform" and 0 or 0.65
	end
	hint.Text = HINT[m]
	if m == "step" then -- you can only step behind one person
		local keep = next(selected)
		for s in selected do
			if s ~= keep then
				deselect(s)
			end
		end
	end
	refreshIssue()
end
for name, b in tabs do
	b.Activated:Connect(function()
		setMode(name)
	end)
end
setMode("uniform")

local hoverConn: RBXScriptConnection?

tool.Equipped:Connect(function()
	gui.Enabled = true
	hoverConn = game:GetService("RunService").RenderStepped:Connect(function()
		local m = legalTarget(mouse.Target)
		hoverHl.Parent = (m and not selected[m]) and m or nil
		-- drop selections that died, left or walked out of range
		for s in selected do
			if not legalTarget(s.PrimaryPart or s:FindFirstChildWhichIsA("BasePart")) then
				deselect(s)
				refreshIssue()
			end
		end
	end)
end)

tool.Unequipped:Connect(function()
	gui.Enabled = false
	for _, t in loaded do
		t:Stop(0.25)
	end
	if hoverConn then
		hoverConn:Disconnect()
		hoverConn = nil
	end
	clearAll()
end)

tool.Activated:Connect(function()
	local m = legalTarget(mouse.Target)
	if not m then
		return
	end
	if selected[m] then
		deselect(m)
	else
		if mode == "step" then
			for s in selected do
				deselect(s)
			end
		end
		local h = makeHighlight(0.55)
		h.Parent = m
		selected[m] = h
		hoverHl.Parent = nil
	end
	refreshIssue()
end)

-- the caster's body animation for the spell; the server times the effect to its release frame
local function castAnim(m: string)
	local t = track(m)
	if t then
		t:Play(0.1)
	end
end

issue.Activated:Connect(function()
	if mode == "raise" then
		castAnim("raise")
		local list = {}
		for m in selected do
			table.insert(list, m)
		end
		remote:FireServer("raise", list)
		clearAll()
		return
	end
	local s, p = idOf(shirtBox), idOf(pantsBox)
	if next(selected) == nil or (mode == "uniform" and not (s or p)) then
		return
	end
	castAnim(mode)
	for m in selected do
		remote:FireServer(mode, m, s, p)
	end
	clearAll()
end)

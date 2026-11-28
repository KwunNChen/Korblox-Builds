-- Admin console: "/admin <password>" in chat opens this terminal (the server fires AdminConsoleOpen).
-- Every line goes to ReplicatedStorage.AdminConsole (handled in ServerScriptService.TowerRun), which checks access
-- and returns the text to print. The command list for autofill/hints comes from the server ("?spec").
-- Tab autofills, Up/Down walk history, drag the title bar to move it, "close" or the x hides it.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("AdminConsole")
local openEvent = ReplicatedStorage:WaitForChild("AdminConsoleOpen")
local player = Players.LocalPlayer

-- plum taken from the banner: lighter top-left, darker bottom-right
local GRAD_TOP = Color3.fromRGB(92, 47, 90)
local GRAD_BOTTOM = Color3.fromRGB(50, 24, 48)
local BAR = Color3.fromRGB(38, 18, 37)
local FIELD = Color3.fromRGB(36, 17, 35)
local ACCENT = Color3.fromRGB(236, 190, 230)
local TEXT = Color3.fromRGB(246, 234, 244)
local DIM = Color3.fromRGB(184, 146, 180)
local RED = Color3.fromRGB(255, 130, 150)
local TweenService = game:GetService("TweenService")
local FONT = Enum.Font.Code -- monospace, so the autofill ghost lines up under the typed text
local HINT_LINES = 3
-- the Korblox banner (star over a white dragon on purple) shown in the welcome box
local BANNER_IMAGE = "rbxassetid://130752291688058"

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end

local gui = new("ScreenGui", { Name = "AdminConsole", ResetOnSpawn = false, DisplayOrder = 50, Enabled = false }, nil)
local panel = new("Frame", {
	Position = UDim2.fromOffset(24, 80), Size = UDim2.fromOffset(460, 330),
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.03, BorderSizePixel = 0,
}, gui)
local function plum(o) -- banner gradient (UIGradient multiplies a white background)
	o.BackgroundColor3 = Color3.new(1, 1, 1)
	new("UIGradient", { Color = ColorSequence.new(GRAD_TOP, GRAD_BOTTOM), Rotation = 60 }, o)
end
plum(panel)
new("UIStroke", { Color = ACCENT, Transparency = 0.35 }, panel)
-- frees the mouse in first person while the console is up, so it can be dragged and clicked
new("TextButton", { Modal = true, Text = "", BackgroundTransparency = 1, Size = UDim2.new() }, panel)

local bar = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = BAR, BorderSizePixel = 0, Active = true }, panel)
new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -40, 1, 0),
	Font = FONT, TextSize = 14, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "ADMIN CONSOLE  ·  Tab autofills",
}, bar)
local closeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(20, 20),
	BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = ACCENT, Text = "x",
}, bar)

local log = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 1, -(28 + 8 + 24 + HINT_LINES * 15 + 6)),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 3, ScrollBarImageColor3 = ACCENT,
}, panel)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, log)
new("UIPadding", { PaddingTop = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1) }, log) -- room for the welcome box border

local hints = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.new(0, 12, 1, -(8 + 24 + HINT_LINES * 15 + 2)),
	Size = UDim2.new(1, -24, 0, HINT_LINES * 15), Font = FONT, TextSize = 13, TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
	ClipsDescendants = true, RichText = true, Text = "",
}, panel)

local field = new("Frame", {
	Position = UDim2.new(0, 10, 1, -32), Size = UDim2.new(1, -20, 0, 24), BackgroundColor3 = FIELD, BorderSizePixel = 0,
}, panel)
new("UIStroke", { Color = ACCENT, Transparency = 0.6 }, field)
new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 14, 1, 0),
	Font = FONT, TextSize = 15, TextColor3 = ACCENT, Text = ">",
}, field)
local inputProps = {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -28, 1, 0),
	Font = FONT, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}
local ghost = new("TextLabel", inputProps, field)
ghost.TextColor3 = DIM
local prompt = new("TextBox", inputProps, field)
prompt.TextColor3 = TEXT
prompt.ClearTextOnFocus = false
prompt.PlaceholderText = "type a command"
prompt.PlaceholderColor3 = DIM

local order = 0
local function out(text, color)
	order += 1
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT, TextSize = 14, TextColor3 = color or TEXT, TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true, Text = text, LayoutOrder = order,
	}, log)
	for _, k in log:GetChildren() do
		if k:IsA("TextLabel") and k.LayoutOrder <= order - 200 then k:Destroy() end -- keep the last 200 lines
	end
	task.defer(function() log.CanvasPosition = Vector2.new(0, log.AbsoluteCanvasSize.Y) end)
end

-- autofill --------------------------------------------------------------------------------------------
local spec = nil -- { commands = { {name, args, desc} }, args = { [command] = { values } } }
local function esc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
local function usage(c)
	return '<font color="#ECBEE6">' .. esc(c.name .. (if c.args ~= "" then " " .. c.args else "")) .. "</font>  " .. esc(c.desc)
end
local function startsWith(s, pre) return s:lower():sub(1, #pre) == pre:lower() end

-- returns (completed text or nil, hint lines)
local function suggest(text)
	if not spec then return nil, { "loading commands..." } end
	local word, rest = text:match("^%s*(%S*)(.*)$")
	if word == "" then
		local names = {}
		for _, c in spec.commands do table.insert(names, c.name) end
		return nil, { "commands: " .. table.concat(names, "  "), "start typing one to see what it needs" }
	end
	if rest == "" then -- still typing the command name
		local lines, first = {}, nil
		for _, c in spec.commands do
			if startsWith(c.name, word) then
				first = first or c
				table.insert(lines, usage(c))
			end
		end
		if not first then return nil, { '<font color="#FF7896">no command starts with "' .. esc(word) .. '"</font>' } end
		return if word ~= "" then first.name else nil, lines
	end
	local cmd = nil
	for _, c in spec.commands do if c.name == word:lower() then cmd = c end end
	if not cmd then return nil, { '<font color="#FF7896">unknown command "' .. esc(word) .. '"</font>  (help lists them)' } end
	local values = spec.args[cmd.name]
	if not values then return nil, { usage(cmd), if cmd.args == "" then "takes nothing after it: press Enter" else "" } end
	local arg = rest:match("^%s+(%S*)$") or ""
	local fits = {}
	for _, v in values do if startsWith(v, arg) then table.insert(fits, v) end end
	local lines = { usage(cmd) }
	table.insert(lines, if #fits > 0 then "options: " .. esc(table.concat(fits, "  ")) else '<font color="#FF7896">no option starts with "' .. esc(arg) .. '"</font>')
	local done = if #fits > 0 and arg ~= "" then text:sub(1, #text - #arg) .. fits[1] else nil
	return done, lines
end

local completion = nil
local function refresh()
	local text = prompt.Text
	local lines
	completion, lines = suggest(text)
	ghost.Text = if completion and startsWith(completion, text) then text .. completion:sub(#text + 1) else ""
	if #lines > HINT_LINES then
		local more = #lines - (HINT_LINES - 1)
		lines = table.move(lines, 1, HINT_LINES - 1, 1, {})
		table.insert(lines, "+" .. more .. " more, keep typing")
	end
	hints.Text = table.concat(lines, "\n")
end

local function autofill()
	local text = prompt.Text:gsub("\t", "")
	local done = suggest(text)
	if not done then prompt.Text = text return end
	-- a finished command that takes a value gets its space, so the options show next
	local isCommand = not done:find("%s")
	if isCommand and spec and spec.args[done] then done ..= " " end
	prompt.Text = done
	prompt.CursorPosition = #done + 1
end

prompt:GetPropertyChangedSignal("Text"):Connect(function()
	if prompt.Text:find("\t") then autofill() return end -- Tab typed into the box
	refresh()
end)

-- running lines -----------------------------------------------------------------------------------------
local history, at = {}, 0
local function hide()
	gui.Enabled = false
	prompt:ReleaseFocus()
end
prompt.FocusLost:Connect(function(enter)
	if not enter or not gui.Enabled then return end
	local line = prompt.Text
	prompt.Text = ""
	if line:match("^%s*$") then prompt:CaptureFocus() return end
	if line ~= history[#history] then table.insert(history, line) end
	at = #history + 1
	out("> " .. line, DIM)
	if line:lower():match("^%s*close%s*$") or line:lower():match("^%s*exit%s*$") then hide() return end
	local ok, res = pcall(remote.InvokeServer, remote, line)
	if not ok then
		out("error: " .. tostring(res), RED)
	else
		res = tostring(res)
		local bad = res:match("^unknown") or res:match("^locked") or res:match("^no boss")
		out(res, if bad then RED else TEXT)
	end
	prompt:CaptureFocus()
end)
closeBtn.Activated:Connect(hide)

UserInputService.InputBegan:Connect(function(input)
	if not prompt:IsFocused() then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		task.defer(autofill)
	elseif #history > 0 and (input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down) then
		at = math.clamp(at + (if input.KeyCode == Enum.KeyCode.Up then -1 else 1), 1, #history + 1)
		prompt.Text = history[at] or ""
		prompt.CursorPosition = #prompt.Text + 1
	end
end)

-- dragging by the title bar -------------------------------------------------------------------------------
local dragFrom, panelFrom = nil, nil
bar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragFrom, panelFrom = input.Position, panel.Position
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if not dragFrom then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local d = input.Position - dragFrom
		panel.Position = UDim2.new(panelFrom.X.Scale, panelFrom.X.Offset + d.X, panelFrom.Y.Scale, panelFrom.Y.Offset + d.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragFrom = nil
	end
end)

openEvent.OnClientEvent:Connect(function()
	gui.Enabled = true
	if not spec then
		local ok, res = pcall(remote.InvokeServer, remote, "?spec")
		if ok and type(res) == "table" then spec = res end
	end
	refresh()
	task.defer(prompt.CaptureFocus, prompt) -- after the chat box lets go of focus
end)

out("Korblox Admin Console · help for commands · Tab autofills", DIM)

-- radio notification: slides in at the top right, types its message, then slides back out. Shown on console open
-- and whenever the server sets ReplicatedStorage.TowerStatus.Radio (TowerBosses), so it lives in its own always-on gui.
local radioGui = new("ScreenGui", { Name = "RadioNotify", ResetOnSpawn = false, DisplayOrder = 51 }, nil)
local radio = new("Frame", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 340, 0, 70), Size = UDim2.fromOffset(320, 100),
	BorderSizePixel = 0, BackgroundTransparency = 0.03,
}, radioGui)
plum(radio)
new("UIStroke", { Color = ACCENT, Transparency = 0.35 }, radio)
new("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, radio) -- left edge stripe
new("ImageLabel", {
	Position = UDim2.fromOffset(10, 7), Size = UDim2.fromOffset(62, 70), BackgroundTransparency = 1,
	Image = BANNER_IMAGE, ScaleType = Enum.ScaleType.Fit,
}, radio)
local dot = new("Frame", {
	Position = UDim2.fromOffset(82, 12), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = RED, BorderSizePixel = 0,
}, radio)
new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(95, 6), Size = UDim2.new(1, -100, 0, 18),
	Font = FONT, TextSize = 13, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "INCOMING TRANSMISSION",
}, radio)
new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(82, 24), Size = UDim2.new(1, -90, 0, 16),
	Font = FONT, TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "KORBLOX COMMAND // " .. (if game:GetService("RunService"):IsStudio() then "STUDIO" else game.JobId:sub(1, 8):upper()),
}, radio)
local radioMsg = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(82, 42), Size = UDim2.new(1, -90, 0, 54),
	Font = FONT, TextSize = 13, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = "",
}, radio)

local radioRun = 0
local function transmit(msg)
	radioRun += 1
	local run = radioRun
	radioMsg.Text = msg
	radioMsg.MaxVisibleGraphemes = 0
	local squelch = Instance.new("Sound")
	squelch.SoundId, squelch.Volume = "rbxassetid://9118026328", 0.6 -- ProSoundEffects "Radio Squelches 12"
	squelch.Parent = radioGui
	squelch.Ended:Once(function() squelch:Destroy() end)
	squelch:Play()
	TweenService:Create(radio, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { Position = UDim2.new(1, -16, 0, 70) }):Play()
	task.wait(0.35)
	for i = 1, #msg do -- typewriter
		if run ~= radioRun then return end
		radioMsg.MaxVisibleGraphemes = i
		dot.Visible = i % 6 < 3
		task.wait(0.025)
	end
	dot.Visible = true
	task.wait(4)
	if run ~= radioRun then return end
	TweenService:Create(radio, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(1, 340, 0, 70) }):Play()
end
openEvent.OnClientEvent:Connect(function()
	task.spawn(transmit, "Admin console online, " .. player.DisplayName .. ". Type help for commands.")
end)
gui.Parent = player:WaitForChild("PlayerGui")
radioGui.Parent = gui.Parent
local towerStatus = ReplicatedStorage:WaitForChild("TowerStatus")
local lastMsg, lastAt = nil, 0
towerStatus:GetAttributeChangedSignal("Radio"):Connect(function()
	local msg = towerStatus:GetAttribute("Radio")
	-- the server's nil-then-text reset fires twice under deferred signals, both reading the text
	if not msg or (msg == lastMsg and os.clock() - lastAt < 1) then return end
	if towerStatus:GetAttribute("BossName") and player:GetAttribute("InTowerRun") then return end -- BossFX types it into the boss card
	lastMsg, lastAt = msg, os.clock()
	task.spawn(transmit, msg)
end)

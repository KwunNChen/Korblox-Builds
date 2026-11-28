-- Client half of ServerScriptService.Medical: mirrors CanDie / Downed onto the humanoid (the client
-- owns its character's state), plays the Bandage animation and drives SPH's status bars.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local char = script.Parent
local hum = char:WaitForChild("Humanoid") :: Humanoid
local root = char:WaitForChild("HumanoidRootPart")
local DEAD = Enum.HumanoidStateType.Dead

local function syncDeath()
	local canDie = char:GetAttribute("CanDie") ~= false -- nil = Medical not running, die normally
	hum:SetStateEnabled(DEAD, canDie)
	if canDie and hum.Health <= 0 then hum:ChangeState(DEAD) end
end
char:GetAttributeChangedSignal("CanDie"):Connect(syncDeath)
hum.HealthChanged:Connect(function(h) if h <= 0 then syncDeath() end end)
syncDeath()

-- The default reset only zeroes Health here, which the blocked Dead state ignores: let the server kill
task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("MedicalReset")
	local reset = Instance.new("BindableEvent")
	reset.Event:Connect(function() remote:FireServer() end)
	reset.Parent = script
	for _ = 1, 20 do -- SetCore errors until the CoreScripts register it
		if pcall(game:GetService("StarterGui").SetCore, game:GetService("StarterGui"), "ResetButtonCallback", reset) then break end
		task.wait(0.5)
	end
end)

char:GetAttributeChangedSignal("Downed"):Connect(function()
	local downed = char:GetAttribute("Downed") == true
	hum.PlatformStand = downed
	if downed then
		-- the server ragdolls the joints; knock the body over backwards or it can balance on its legs
		root.AssemblyLinearVelocity += -root.CFrame.LookVector * 6
		root.AssemblyAngularVelocity = root.CFrame.RightVector * 8
	else
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)

-- Downed screen (your own only): colour drains, the view blurs and darkens, sound goes underwater and a
-- heartbeat slows as you bleed out. Dying while downed fades to black.
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local BLEEDOUT_TIME = 60 -- Medical's BLEEDOUT_TIME
-- this script stops with the old character before it can clean up, so each spawn clears the last one's
for _, e in Lighting:GetChildren() do
	if e.Name == "MedicalDowned" then e:Destroy() end
end
if SoundService:GetAttribute("MedicalReverb") == nil then SoundService:SetAttribute("MedicalReverb", SoundService.AmbientReverb.Name) end
local reverb = (Enum.ReverbType :: any)[SoundService:GetAttribute("MedicalReverb")]
SoundService.AmbientReverb = reverb
local grade = Instance.new("ColorCorrectionEffect")
grade.Name, grade.Enabled = "MedicalDowned", false
grade.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name, blur.Enabled, blur.Size = "MedicalDowned", false, 0
blur.Parent = Lighting
local heart = Instance.new("Sound")
heart.SoundId = "rbxassetid://176554627" -- "Slow Heartbeat", loops cleanly
heart.Looped, heart.Volume = true, 0.8
heart.Parent = script
local function downedFx()

-- Give up (Battlefield-style): while downed, hold Space / X / the on-screen tag to stop waiting for a
-- revive. The server kills you through MedicalReset; the kill still goes to whoever downed you.
local UserInputService = game:GetService("UserInputService")
local GIVE_UP_HOLD = 1.5
local GIVE_UP_KEYS = { [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonX] = true }
local giveUp = Instance.new("ScreenGui")
giveUp.Name, giveUp.Enabled = "MedicalGiveUp", false
local giveTag = Instance.new(if UserInputService.TouchEnabled then "TextButton" else "TextLabel") :: any
giveTag.AnchorPoint = Vector2.new(0.5, 1)
giveTag.Position = UDim2.new(0.5, 0, 1, -110)
giveTag.Size = UDim2.fromOffset(170, 24)
giveTag.BackgroundColor3, giveTag.BackgroundTransparency, giveTag.BorderSizePixel = Color3.new(), 0.55, 0
giveTag.TextColor3, giveTag.TextSize, giveTag.Font = Color3.new(1, 1, 1), 13, Enum.Font.GothamMedium
if UserInputService.TouchEnabled then giveTag.AutoButtonColor = false end
giveTag.Parent = giveUp
local giveFill = Instance.new("Frame")
giveFill.BorderSizePixel, giveFill.BackgroundColor3 = 0, Color3.new(1, 1, 1)
giveFill.AnchorPoint, giveFill.Position, giveFill.Size = Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(0, 0, 0, 2)
giveFill.Parent = giveTag
giveUp.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local heldSince: number? = nil
local function letGo()
	heldSince = nil
	giveFill.Size = UDim2.new(0, 0, 0, 2)
end
local function holdDown()
	if char:GetAttribute("Downed") and hum.Health > 0 then heldSince = os.clock() end
end
local function giveUpText()
	local last = UserInputService:GetLastInputType()
	giveTag.Text = if last.Name:find("Gamepad") then "Hold X to give up"
		elseif last == Enum.UserInputType.Touch then "Hold to give up"
		else "Hold SPACE to give up"
end
UserInputService.LastInputTypeChanged:Connect(giveUpText)
giveUpText()
UserInputService.InputBegan:Connect(function(input)
	if GIVE_UP_KEYS[input.KeyCode] and not UserInputService:GetFocusedTextBox() then holdDown() end
end)
UserInputService.InputEnded:Connect(function(input)
	if GIVE_UP_KEYS[input.KeyCode] then letGo() end
end)
giveTag.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then holdDown() end end)
giveTag.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then letGo() end end)
RunService.RenderStepped:Connect(function()
	if not heldSince then return end
	local t = (os.clock() - heldSince) / GIVE_UP_HOLD
	giveFill.Size = UDim2.new(math.min(t, 1), 0, 0, 2)
	if t >= 1 then
		heldSince = nil
		ReplicatedStorage:WaitForChild("MedicalReset"):FireServer()
	end
end)
char:GetAttributeChangedSignal("Downed"):Connect(function()
	giveUp.Enabled = char:GetAttribute("Downed") == true
	letGo()
end)
hum.Died:Connect(function() giveUp.Enabled = false end)
	local downed = char:GetAttribute("Downed") == true
	grade.Enabled, blur.Enabled = downed, downed
	SoundService.AmbientReverb = if downed then Enum.ReverbType.UnderWater else reverb
	if not downed then heart:Stop(); return end
	local t = 1 - math.clamp((char:GetAttribute("BleedOut") or BLEEDOUT_TIME) / BLEEDOUT_TIME, 0, 1) -- 0 just downed, 1 bled out
	local tw = TweenInfo.new(1, Enum.EasingStyle.Linear)
	TweenService:Create(grade, tw, { Saturation = -0.5 - 0.5 * t, Brightness = -0.35 * t, Contrast = 0.15,
		TintColor = Color3.new(1, 0.85 - 0.25 * t, 0.85 - 0.25 * t) }):Play()
	TweenService:Create(blur, tw, { Size = 3 + 9 * t }):Play()
	heart.PlaybackSpeed = 1.15 - 0.5 * t
	if not heart.IsPlaying then heart:Play() end
end
char:GetAttributeChangedSignal("Downed"):Connect(downedFx)
char:GetAttributeChangedSignal("BleedOut"):Connect(downedFx)
hum.Died:Connect(function()
	if not grade.Enabled then return end
	local gui = Instance.new("ScreenGui") -- ResetOnSpawn: gone on respawn
	gui.Name, gui.IgnoreGuiInset, gui.DisplayOrder = "MedicalBlackout", true, 100
	local black = Instance.new("Frame")
	black.Size, black.BackgroundColor3, black.BackgroundTransparency, black.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 1, 0
	black.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	TweenService:Create(black, TweenInfo.new(1.5), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(heart, TweenInfo.new(1.5), { Volume = 0 }):Play()
end)
downedFx()

-- You can't revive or carry yourself: hide your own prompts locally
root.ChildAdded:Connect(function(c)
	if c:IsA("ProximityPrompt") and (c.Name == "Revive" or c.Name == "Carry") then c.Enabled = false end
end)

-- Revive / Carry prompts (Style Custom on the server): a small tag above the body instead of Roblox's big
-- default button, so it doesn't cover a body you're aiming at. A line under it fills while you hold.
local ProximityPromptService = game:GetService("ProximityPromptService")
local tags: { [ProximityPrompt]: () -> () } = {}
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or (prompt.Name ~= "Revive" and prompt.Name ~= "Carry") then return end
	-- an enemy's body: no revive, and the server only lets you drag it
	local body = prompt.Parent and prompt.Parent.Parent
	local owner = body and Players:GetPlayerFromCharacter(body)
	local dummyTeam = body and body:GetAttribute("MedTeam") -- Studio test dummy (Medical's MedicalDummy)
	local enemy = if owner then owner.Team ~= Players.LocalPlayer.Team
		else dummyTeam ~= nil and dummyTeam ~= (Players.LocalPlayer.Team and Players.LocalPlayer.Team.Name)
	if enemy and prompt.Name == "Revive" then prompt.Enabled = false; return end
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local key = if touch then "Tap"
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then prompt.GamepadKeyCode.Name:gsub("^Button", "")
		else prompt.KeyboardKeyCode.Name
	local gui = Instance.new("BillboardGui")
	gui.Name = "MedicalPrompt"
	gui.Size = UDim2.fromOffset(84, 15)
	gui.StudsOffset = Vector3.new(0, if prompt.Name == "Revive" then 2.4 else 1.9, 0)
	gui.Adornee = prompt.Parent
	gui.AlwaysOnTop = true
	-- only touch gets a button: on PC a clickable tag would eat your shots
	local label = Instance.new(if touch then "TextButton" else "TextLabel") :: any
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.55
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 12
	label.Font = Enum.Font.GothamMedium
	label.Text = key .. "  " .. (if enemy then "Drag" else prompt.ActionText)
	if touch then label.AutoButtonColor = false end
	label.Parent = gui
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(0, 0, 0, 2)
	bar.Parent = label
	local fill: Tween? = nil
	local conns = {
		prompt.PromptButtonHoldBegan:Connect(function()
			fill = TweenService:Create(bar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 0, 2) })
			fill:Play()
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			if fill then fill:Cancel() end
			bar.Size = UDim2.new(0, 0, 0, 2)
		end),
	}
	if touch then
		table.insert(conns, label.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldBegin() end end))
		table.insert(conns, label.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldEnd() end end))
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tags[prompt] = function()
		for _, c in conns do c:Disconnect() end
		gui:Destroy()
	end
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	local remove = tags[prompt]
	if remove then
		tags[prompt] = nil
		remove()
	end
end)

-- No equipping while carrying: hide the hotbar, and put away anything that still gets out (SPH's equip
-- would move the arms onto its gun rig)
local StarterGui = game:GetService("StarterGui")
char:GetAttributeChangedSignal("Carrying"):Connect(function()
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, char:GetAttribute("Carrying") == nil)
end)
char.Destroying:Connect(function() pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, true) end)
char.ChildAdded:Connect(function(c)
	if c:IsA("Tool") and char:GetAttribute("Carrying") then task.defer(hum.UnequipTools, hum) end
end)

-- Dragging: the body still bumps into you, and its grip snaps back when it snags on a curb; neither may
-- shove you faster than you walk or pop you upward (you simulate yourself, so this is the place to cap it).
-- Before each physics step and again after it: a push inside the step then lasts one frame at most.
local function capDrag()
	if char:GetAttribute("TreatAnim") ~= "Drag" or not char:GetAttribute("Carrying") then return end
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local cap = hum.WalkSpeed * 1.1
	local y = if hum:GetState() == Enum.HumanoidStateType.Jumping then v.Y else math.min(v.Y, 4)
	if flat.Magnitude > cap or y ~= v.Y then
		root.AssemblyLinearVelocity = (if flat.Magnitude > cap then flat.Unit * cap else flat) + Vector3.new(0, y, 0)
	end
end
RunService.PreSimulation:Connect(capDrag)
RunService.PostSimulation:Connect(capDrag)

-- F while carrying or dragging someone puts them down
game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F and char:GetAttribute("Carrying") then
		ReplicatedStorage:WaitForChild("MedicalCarry"):FireServer()
	end
end)

-- Bandage / Medkit / Carry / Drag animations (R6), published to the game's group (35065811); they only play in that group's
-- games. Sources: ReplicatedStorage.MedicalAnimations. Re-upload and replace an id after editing one.
local ANIM_IDS: { [string]: string } = {
	Bandage_Arm = "81677527414384",
	Bandage_Leg = "70549438251652",
	Bandage_Torso = "117388350066150",
	Medkit_Arm = "116755742683037",
	Medkit_Leg = "123654790474513",
	Medkit_Torso = "106824786936431",
	Medkit_Other = "99482879070127",
	Carry = "122677292612504",
	Drag = "79002113942786",
}
local animator = hum:WaitForChild("Animator") :: Animator
local tracks: { [string]: AnimationTrack } = {}
local function track(name: string): AnimationTrack?
	if tracks[name] then return tracks[name] end
	local id = ANIM_IDS[name] and ANIM_IDS[name] ~= "" and "rbxassetid://" .. ANIM_IDS[name] or nil
	if not id and RunService:IsStudio() then
		local folder = ReplicatedStorage:FindFirstChild("MedicalAnimations")
		local kfs = folder and folder:FindFirstChild(name)
		if kfs then
			local ok, temp = pcall(function() return game:GetService("AnimationClipProvider"):RegisterAnimationClip(kfs) end)
			id = ok and temp or nil
		end
	end
	if not id then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, t = pcall(animator.LoadAnimation, animator, anim)
	if ok then tracks[name] = t end
	return tracks[name]
end
-- load now: a first-time load takes ~0.4 s and would put the wrap behind the server's pill timing
for name in ANIM_IDS do task.spawn(track, name) end
local playing: AnimationTrack? = nil
char:GetAttributeChangedSignal("TreatAnim"):Connect(function()
	if playing then playing:Stop(0.2) end
	local name = char:GetAttribute("TreatAnim")
	playing = name and track(name) or nil
	if playing then playing:Play(0.15) end
end)

-- Status bars: SPH's own BleedingUI / FractureUI (left edge, HighwayGothic), plus copies for the rest
local sph = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("SPH_UI", 15)
if not sph then return end
local function bar(template: string, name: string, y: number): Frame
	local f = sph:FindFirstChild(name) or sph:WaitForChild(template):Clone()
	f.Name = name
	f.Position = UDim2.fromScale(0, y)
	f.Visible = false
	f.Parent = sph
	return f
end
local rows = {
	down = bar("BleedingUI", "DownedUI", 0.47),
	bleed = bar("BleedingUI", "BleedingUI", 0.5),
	leg = bar("FractureUI", "FractureUI", 0.53),
	arm = bar("FractureUI", "ArmUI", 0.56),
	treat = bar("BleedingUI", "TreatingUI", 0.59),
}
local function show(row: string, text: string?)
	rows[row].Visible = text ~= nil
	if text then rows[row].TextLabel.Text = text end
end
-- medkit rows get a green cross (two bars) in place of the blood drop
local drop = rows.treat:FindFirstChildOfClass("ImageLabel") :: ImageLabel
local cross = rows.treat:FindFirstChild("MedkitCross") or Instance.new("Frame")
cross.Name, cross.BackgroundTransparency, cross.Visible = "MedkitCross", 1, false
cross.Position, cross.Size = drop.Position, drop.Size
if not cross:FindFirstChild("Bar") then
	Instance.new("UIAspectRatioConstraint").Parent = cross
	for _, size in { UDim2.fromScale(0.34, 0.9), UDim2.fromScale(0.9, 0.34) } do
		local b = Instance.new("Frame")
		b.Name, b.AnchorPoint, b.Position, b.Size = "Bar", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), size
		b.BackgroundColor3, b.BorderSizePixel = Color3.fromRGB(70, 200, 95), 0
		b.Parent = cross
	end
end
cross.Parent = rows.treat
local function medkitIcon(on: boolean)
	cross.Visible, drop.Visible = on, not on
end

local function refresh()
	local left = char:GetAttribute("BleedOut") or 0
	show("down", if char:GetAttribute("Downed") then ("Down %d:%02d"):format(left // 60, left % 60) else nil)
	show("bleed", if char:GetAttribute("Bleeding") then "Bleeding" else nil)
	show("leg", if char:GetAttribute("LegInjured") then "Leg wound" else nil)
	show("arm", if char:GetAttribute("ArmInjured") then "Arm wound" else nil)
	local who = char:GetAttribute("Treating")
	local tool = char:FindFirstChildOfClass("Tool")
	local verb = if tool and tool.Name == "Medkit" then "Treating" else "Bandaging"
	local carrying = char:GetAttribute("Carrying")
	if carrying then
		show("treat", (if char:GetAttribute("TreatAnim") == "Drag" then "Dragging " else "Carrying ") .. carrying .. "  [F] drop")
	else
		show("treat", if who then (if who == "yourself" then verb else verb .. " " .. who) else char:GetAttribute("TreatedBy"))
	end
	medkitIcon(not carrying and rows.treat.TextLabel.Text:find("^Treat") ~= nil) -- "Treating ..." / "Treated by ..."
end
char.AttributeChanged:Connect(refresh)
refresh()

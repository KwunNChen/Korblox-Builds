local respawnTime = game.Players.RespawnTime
local player = game.Players.LocalPlayer
local dead = false
local label = script.Parent
local main = script.Parent.Parent
local black = script.Parent.Parent.Blackout
local tweenService = game:GetService("TweenService")

local ending = false

-- house look (the Settings card / tower header): HighwayGothic, dark centre fade, kicker / title / red rule / state line
local FONT = Font.new("rbxasset://fonts/families/HighwayGothic.json")
label.FontFace = FONT
local card
local function fade(edge, mid)
	local keys = {}
	for i = 0, 10 do
		local t = i / 10
		local d = math.abs(t - 0.5) * 2
		table.insert(keys, NumberSequenceKeypoint.new(t, mid + (edge - mid) * tweenService:GetValue(d, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)))
	end
	return NumberSequence.new(keys)
end
local function text(parent, y, h, size, colour)
	local l = Instance.new("TextLabel")
	l.Position, l.Size = UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, h)
	l.BackgroundTransparency = 1
	l.FontFace, l.TextSize, l.TextColor3 = FONT, size, colour
	l.Parent = parent
	return l
end
local function wavesCard()
	if card then return card end
	card = Instance.new("CanvasGroup")
	card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.4), UDim2.fromOffset(460, 104)
	card.BackgroundTransparency, card.GroupTransparency = 1, 1
	local shade = Instance.new("Frame")
	shade.Size, shade.BackgroundColor3, shade.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(), 0
	local g = Instance.new("UIGradient")
	g.Transparency = fade(1, 0.2)
	g.Parent = shade
	shade.Parent = card
	text(card, 10, 14, 13, Color3.fromRGB(200, 202, 208)).Text = "KILLED IN ACTION"
	local title = text(card, 28, 36, 34, Color3.new(1, 1, 1))
	title.Name = "Title"
	local rule = Instance.new("Frame")
	rule.Position, rule.Size, rule.BorderSizePixel = UDim2.new(0.5, -120, 0, 70), UDim2.fromOffset(240, 2), 0
	rule.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
	local rg = Instance.new("UIGradient")
	rg.Transparency = fade(1, 0)
	rg.Parent = rule
	rule.Parent = card
	local state = text(card, 78, 16, 14, Color3.fromRGB(225, 150, 150))
	state.Name = "State"
	-- its own gui, above MedicalClient's death blackout (DisplayOrder 100); gone on respawn like the death screen
	local holder = Instance.new("ScreenGui")
	holder.Name, holder.IgnoreGuiInset, holder.DisplayOrder = "RespawnWaves", true, 110
	card.Parent = holder
	holder.Parent = player:WaitForChild("PlayerGui")
	tweenService:Create(card, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { GroupTransparency = 0 }):Play()
	return card
end

repeat task.wait() until player.Character

player.Character:WaitForChild("Humanoid")
player.Character.Humanoid.Died:Connect(function()
	dead = true
	local tInfo = TweenInfo.new(1,Enum.EasingStyle.Quint)
	tweenService:Create(main,tInfo,{BackgroundTransparency = 0,Position = UDim2.fromScale(0,0)}):Play()
	tweenService:Create(label,tInfo,{TextTransparency = 0}):Play()
end)

game:GetService("RunService").RenderStepped:Connect(function(dt)
	if dead then
		-- killed in a tower run: TowerRun holds the respawn for some cleared floors and sets this attribute on us only
		local waves = player:GetAttribute("RespawnWaves")
		if waves then
			label.Visible = false
			local c = wavesCard()
			c.Title.Text = "RESPAWN IN " .. waves .. (waves == 1 and " WAVE" or " WAVES")
			c.State.Text = "YOUR SQUAD MUST CLEAR " .. waves .. (waves == 1 and " MORE FLOOR" or " MORE FLOORS")
			return
		end
		respawnTime -= dt
		local finalString
		if respawnTime < 1 and not ending then
			ending = true
			local tInfo = TweenInfo.new(0.5)
			tweenService:Create(label,tInfo,{TextTransparency = 1,Position = UDim2.fromScale(0.5,0.15)}):Play()
			tweenService:Create(black,tInfo,{BackgroundTransparency = 0}):Play()
		end
		if respawnTime > 0.01 then
			local timeString = tostring(respawnTime)
			if respawnTime < 10 then
				timeString = "0"..timeString
			end
			finalString = string.sub(timeString,1,2).."."
			if #timeString >= 4 then
				finalString = finalString..string.sub(timeString,4,4)
			else
				finalString = finalString.."00"
			end
			if #timeString >= 5 then
				finalString = finalString..string.sub(timeString,5,5)
			else
				finalString = finalString.."0"
			end
		else
			finalString = "00.00"
		end
		label.Text = finalString
	end
end)
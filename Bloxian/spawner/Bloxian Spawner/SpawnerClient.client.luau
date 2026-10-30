--[[
	The Bloxian Spawner tool, player side: a panel to pick the unit, group,
	team, weapon and radioman, a marker where the group will land, clicks sent to
	the BloxianSpawner server script, and a tracker that pins a tag over every
	Bloxian in the world, through walls.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local CollectionService = game:GetService("CollectionService")

local tool = script.Parent
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local remote = ReplicatedStorage:WaitForChild("BloxianSpawnerRemote")

--Panel choices, in the order they are shown. The first is the default.
local OPTIONS = {
	{key = "unit", label = "Unit", values = {"Infantry","Sniper team","AT team"}},
	{key = "size", label = "Group", values = {1,4,9}, names = {"Soldier","Fire team","Squad"}},
	{key = "team", label = "Team", values = {"Hostile","Friendly"}},
	{key = "weapon", label = "Weapon", values = {"Random","Rifle","DMR","Carbine","LMG","Sniper"}},
	{key = "radio", label = "Radioman", values = {"Random","Leader","None"}, names = {"Random","Leader","None"}},
}

--Panel look, after the TREK HUD: see-through dark boxes with a light outline,
--white Gotham caps, grey for secondary text, Roboto Mono for numbers.
local BOX = Color3.fromRGB(15,15,15)
local BOX_TRANSPARENCY = 0.5
local CHIP_TRANSPARENCY = 0.35
local HOVER_TRANSPARENCY = 0.15
local OUTLINE = Color3.fromRGB(205,205,205)
local INK = Color3.fromRGB(255,255,255)
local INK_DIM = Color3.fromRGB(154,154,154)
local SELECTED = Color3.fromRGB(250,250,250)
local SELECTED_INK = Color3.fromRGB(15,15,15)
local DANGER = Color3.fromRGB(229,0,0)
local GOOD = Color3.fromRGB(79,254,120)

local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
local BOLD = Font.new(GOTHAM,Enum.FontWeight.Bold)
local MEDIUM = Font.new(GOTHAM,Enum.FontWeight.Medium)
local HEAVY = Font.new(GOTHAM,Enum.FontWeight.Heavy)
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json")

local IDLE_STATUS = "[CLICK] - SPAWN AT CURSOR"

--Marker colours for the teams that are not Roblox teams (those use their TeamColor),
--and how wide the marker is per group size.
local TEAM_COLORS = {Hostile = Color3.fromRGB(220,60,60), Friendly = Color3.fromRGB(70,140,255)}
local MARKER_WIDTH = {[1] = 4, [4] = 12, [9] = 20}
local PAIR_WIDTH = 8

--Rows that only apply to infantry; other units bring their own make-up.
local INFANTRY_ONLY = {size = true, weapon = true, radio = true}

--Seconds between tracker refreshes.
local TRACK_INTERVAL = 0.2

local TRACKED_TAG = "Bloxian"
local TRACKER_NAME = "BloxianTracker"
local TRACKING_ATTRIBUTE = "BloxianTracking"

local chosen = {}
for _,option in ipairs(OPTIONS) do
	chosen[option.key] = 1
end

local gui,statusLabel,trackButton,marker,renderConnection
local rows = {}
local trackers = {}
local trackConnections = {}
local trackRun = 0

local function value(key)
	for _,option in ipairs(OPTIONS) do
		if option.key == key then
			return option.values[chosen[key]]
		end
	end
end

--Hostile, Friendly, then every Roblox team in the game, read each time the tool comes out.
local function refreshTeams()
	local values = {"Hostile","Friendly"}
	for _,team in ipairs(Teams:GetTeams()) do
		if team.Name ~= "Hostile" and team.Name ~= "Friendly" then
			values[#values+1] = team.Name
		end
	end
	for _,option in ipairs(OPTIONS) do
		if option.key == "team" then
			local current = option.values[chosen.team]
			option.values = values
			chosen.team = table.find(values,current) or 1
		end
	end
end

local function teamColor(name)
	local team = Teams:FindFirstChild(name)
	if team and team:IsA("Team") then
		return team.TeamColor.Color
	end
	return TEAM_COLORS[name] or Color3.new(1,1,1)
end

local function make(className,props,parent)
	local item = Instance.new(className)
	for key,prop in pairs(props) do
		item[key] = prop
	end
	item.Parent = parent
	return item
end

local function padding(parent,x,y)
	return make("UIPadding",{
		PaddingLeft = UDim.new(0,x), PaddingRight = UDim.new(0,x),
		PaddingTop = UDim.new(0,y), PaddingBottom = UDim.new(0,y),
	},parent)
end

local function list(parent,direction,gap,wraps)
	return make("UIListLayout",{
		FillDirection = direction,
		Padding = UDim.new(0,gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = wraps or false,
	},parent)
end

local function outline(parent,thickness,transparency)
	return make("UIStroke",{
		Color = OUTLINE,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	},parent)
end

local function corner(parent,radius)
	return make("UICorner",{CornerRadius = UDim.new(0,radius)},parent)
end

local function text(parent,content,size,color,order,font)
	return make("TextLabel",{
		Size = UDim2.new(1,0,0,size + 6),
		BackgroundTransparency = 1,
		FontFace = font or MEDIUM,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = content,
		LayoutOrder = order,
	},parent)
end

local function flatButton(parent,content,order)
	local item = make("TextButton",{
		BackgroundColor3 = BOX,
		BackgroundTransparency = CHIP_TRANSPARENCY,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = BOLD,
		TextSize = 13,
		TextColor3 = INK,
		Text = string.upper(content),
		LayoutOrder = order,
	},parent)
	corner(item,4)
	outline(item,1,0.55)
	item.MouseEnter:Connect(function()
		if item:GetAttribute("Selected") ~= true then
			item.BackgroundTransparency = HOVER_TRANSPARENCY
		end
	end)
	item.MouseLeave:Connect(function()
		if item:GetAttribute("Selected") ~= true then
			item.BackgroundTransparency = CHIP_TRANSPARENCY
		end
	end)
	return item
end

local function refreshRows()
	local infantry = value("unit") == "Infantry"
	for key,row in pairs(rows) do
		if INFANTRY_ONLY[key] then
			row.Visible = infantry
		end
	end
end

local function setSelected(item,selected)
	item:SetAttribute("Selected",selected)
	item.BackgroundColor3 = selected and SELECTED or BOX
	item.BackgroundTransparency = selected and 0 or CHIP_TRANSPARENCY
	item.TextColor3 = selected and SELECTED_INK or INK
end

local function showStatus(message,color)
	if not statusLabel then
		return
	end
	local shown = string.upper(message)
	statusLabel.Text = shown
	statusLabel.TextColor3 = color or INK
	task.delay(2.5,function()
		if statusLabel and statusLabel.Text == shown then
			statusLabel.Text = IDLE_STATUS
			statusLabel.TextColor3 = INK_DIM
		end
	end)
end

--One labelled row of choices; the picked one is filled with the accent.
local function optionRow(parent,option,order)
	local row = make("Frame",{
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	},parent)
	list(row,Enum.FillDirection.Vertical,6)
	text(row,string.upper(option.label),12,INK_DIM,1,BOLD)

	local chips = make("Frame",{
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	},row)
	list(chips,Enum.FillDirection.Horizontal,4,true)

	local buttons = {}
	local names = option.names or option.values
	for index,name in ipairs(names) do
		local chip = flatButton(chips,tostring(name),index)
		chip.Size = UDim2.fromOffset(0,28)
		chip.AutomaticSize = Enum.AutomaticSize.X
		if option.key == "team" then
			padding(chip,12,0).PaddingLeft = UDim.new(0,26)
			make("Frame",{
				AnchorPoint = Vector2.new(0,0.5),
				Position = UDim2.new(0,-16,0.5,0),
				Size = UDim2.fromOffset(8,8),
				BackgroundColor3 = teamColor(option.values[index]),
				BorderSizePixel = 0,
			},chip)
		else
			padding(chip,12,0)
		end
		buttons[index] = chip
		chip.Activated:Connect(function()
			chosen[option.key] = index
			for other,button in ipairs(buttons) do
				setSelected(button,other == index)
			end
			refreshRows()
		end)
	end
	setSelected(buttons[chosen[option.key]],true)
	rows[option.key] = row
end

local function aliveTracked()
	local count = 0
	for _,tracker in pairs(trackers) do
		if tracker.Enabled then
			count += 1
		end
	end
	return count
end

local function refreshTrackButton()
	if not trackButton then
		return
	end
	local on = player:GetAttribute(TRACKING_ATTRIBUTE) == true
	setSelected(trackButton,on)
	trackButton.Text = on and ("TRACKING "..aliveTracked()) or "TRACK ALL"
end

-- Tracker ---------------------------------------------------------------------

local function untrack(model)
	local tracker = trackers[model]
	if tracker then
		tracker:Destroy()
		trackers[model] = nil
	end
end

local function track(model)
	if trackers[model] or not model:IsDescendantOf(workspace) then
		return
	end
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end

	local tracker = make("BillboardGui",{
		Name = TRACKER_NAME,
		Adornee = head,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = math.huge,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(150,48),
		StudsOffsetWorldSpace = Vector3.new(0,2.6,0),
	},nil)

	local box = make("Frame",{
		Name = "Box",
		Size = UDim2.fromScale(1,1),
		BackgroundColor3 = BOX,
		BackgroundTransparency = BOX_TRANSPARENCY,
		BorderSizePixel = 0,
	},tracker)
	corner(box,4)
	outline(box,1,0.4)
	make("Frame",{
		Name = "Swatch",
		Position = UDim2.fromOffset(8,8),
		Size = UDim2.fromOffset(8,8),
		BorderSizePixel = 0,
	},box)
	make("TextLabel",{
		Name = "Title",
		Position = UDim2.fromOffset(22,3),
		Size = UDim2.new(1,-28,0,18),
		BackgroundTransparency = 1,
		FontFace = BOLD,
		TextSize = 12,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	},box)
	make("TextLabel",{
		Name = "Detail",
		Position = UDim2.fromOffset(8,20),
		Size = UDim2.new(1,-16,0,16),
		BackgroundTransparency = 1,
		FontFace = MONO,
		TextSize = 12,
		TextColor3 = INK_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
	},box)
	local bar = make("Frame",{
		Name = "Health",
		Position = UDim2.new(0,8,1,-9),
		Size = UDim2.new(1,-16,0,3),
		BackgroundColor3 = Color3.fromRGB(60,60,60),
		BorderSizePixel = 0,
	},box)
	make("Frame",{
		Name = "Fill",
		Size = UDim2.fromScale(1,1),
		BorderSizePixel = 0,
	},bar)

	tracker.Parent = playerGui
	trackers[model] = tracker
end

local function refreshTracker(model,tracker)
	local human = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	local alive = human and head and human.Health > 0 and model:IsDescendantOf(workspace)
	tracker.Enabled = alive == true
	if not alive then
		return
	end

	local settings = model:FindFirstChild("Settings")
	local teamValue = settings and settings:FindFirstChild("Team")
	local teamName = teamValue and teamValue.Value or "?"
	local color = teamColor(teamName)

	local camera = workspace.CurrentCamera
	local distance = camera and math.floor((camera.CFrame.Position - head.Position).Magnitude) or 0

	local box = tracker.Box
	box.Swatch.BackgroundColor3 = color
	local unit = model:GetAttribute("Unit")
	local job = unit and unit ~= "Infantry" and unit or model:GetAttribute("Role") or "Rifleman"
	box.Title.Text = string.upper(teamName.." / "..job)
	box.Detail.Text = string.format("%-8s%5dM",string.upper(model:GetAttribute("Weapon") or "Rifle"),distance)
	box.Health.Fill.BackgroundColor3 = color
	box.Health.Fill.Size = UDim2.fromScale(math.clamp(human.Health/human.MaxHealth,0,1),1)
end

local function stopTracking()
	trackRun += 1
	for _,connection in ipairs(trackConnections) do
		connection:Disconnect()
	end
	table.clear(trackConnections)
	for model in pairs(trackers) do
		untrack(model)
	end
end

local function startTracking()
	stopTracking()
	for _,model in ipairs(CollectionService:GetTagged(TRACKED_TAG)) do
		track(model)
	end
	table.insert(trackConnections,CollectionService:GetInstanceAddedSignal(TRACKED_TAG):Connect(track))
	table.insert(trackConnections,CollectionService:GetInstanceRemovedSignal(TRACKED_TAG):Connect(untrack))

	local run = trackRun
	task.spawn(function()
		while run == trackRun and script.Parent do
			for model,tracker in pairs(trackers) do
				if model.Parent then
					refreshTracker(model,tracker)
				else
					untrack(model)
				end
			end
			refreshTrackButton()
			task.wait(TRACK_INTERVAL)
		end
	end)
end

local function setTracking(on)
	player:SetAttribute(TRACKING_ATTRIBUTE,on)
	if on then
		startTracking()
	else
		stopTracking()
	end
	refreshTrackButton()
end

-- Panel -----------------------------------------------------------------------

local function buildGui()
	gui = make("ScreenGui",{
		Name = "BloxianSpawnerGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	},nil)

	local panel = make("Frame",{
		AnchorPoint = Vector2.new(0,0.5),
		Position = UDim2.new(0,16,0.5,0),
		Size = UDim2.fromOffset(300,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = BOX,
		BackgroundTransparency = BOX_TRANSPARENCY,
		BorderSizePixel = 0,
	},gui)
	corner(panel,6)
	outline(panel,2)
	padding(panel,16,16)
	list(panel,Enum.FillDirection.Vertical,14)

	local header = make("Frame",{
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 0,
	},panel)
	list(header,Enum.FillDirection.Vertical,2)
	text(header,"/// BLOXIAN SPAWNER ///",18,INK,1,HEAVY)
	statusLabel = text(header,IDLE_STATUS,12,INK_DIM,2,MONO)

	table.clear(rows)
	for order,option in ipairs(OPTIONS) do
		optionRow(panel,option,order)
	end
	refreshRows()

	local actions = make("Frame",{
		Size = UDim2.new(1,0,0,36),
		BackgroundTransparency = 1,
		LayoutOrder = #OPTIONS + 1,
	},panel)
	list(actions,Enum.FillDirection.Horizontal,4)

	trackButton = flatButton(actions,"Track all",1)
	trackButton.Size = UDim2.new(0.6,-2,1,0)
	trackButton.Activated:Connect(function()
		setTracking(player:GetAttribute(TRACKING_ATTRIBUTE) ~= true)
	end)

	local clear = flatButton(actions,"Clear mine",2)
	clear.Size = UDim2.new(0.4,-2,1,0)
	clear.TextColor3 = DANGER
	clear.Activated:Connect(function()
		remote:FireServer("clear")
	end)

	refreshTrackButton()
	gui.Parent = playerGui
end

local function buildMarker()
	marker = Instance.new("Part")
	marker.Name = "BloxianSpawnMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.6
	marker.Parent = workspace.CurrentCamera
	mouse.TargetFilter = marker
end

tool.Equipped:Connect(function()
	refreshTeams()
	buildGui()
	buildMarker()
	renderConnection = RunService.RenderStepped:Connect(function()
		local width = value("unit") == "Infantry" and MARKER_WIDTH[value("size")] or PAIR_WIDTH
		marker.Size = Vector3.new(0.2,width,width)
		marker.Color = teamColor(value("team"))
		marker.CFrame = CFrame.new(mouse.Hit.Position) * CFrame.Angles(0,0,math.pi/2)
	end)
end)

tool.Unequipped:Connect(function()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if gui then
		gui:Destroy()
		gui,statusLabel,trackButton = nil,nil,nil
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
end)

tool.Activated:Connect(function()
	local options = {}
	for _,option in ipairs(OPTIONS) do
		options[option.key] = option.values[chosen[option.key]]
	end
	remote:FireServer("spawn",mouse.Hit.Position,workspace.CurrentCamera.CFrame.LookVector,options)
end)

remote.OnClientEvent:Connect(function(message)
	local failed = not string.find(message,"^Spawned") and not string.find(message,"^Cleared")
	showStatus(message,failed and DANGER or GOOD)
end)

--Tracking stays on through respawns; the last life's tags are left over in PlayerGui.
for _,leftover in ipairs(playerGui:GetChildren()) do
	if leftover.Name == TRACKER_NAME then
		leftover:Destroy()
	end
end
if player:GetAttribute(TRACKING_ATTRIBUTE) == true then
	startTracking()
end

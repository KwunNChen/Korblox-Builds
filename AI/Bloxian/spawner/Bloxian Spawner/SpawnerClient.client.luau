--[[
	The Bloxian Spawner tool, player side: a panel to pick the unit, group,
	team, weapon and radioman, a marker where the group will land, clicks sent to
	the BloxianSpawner server script, and a tracker that pins a tag over every
	Bloxian in the world, through walls.

	With the Vehicle Spawner's server script installed, the panel's Spawn row
	switches to vehicles: vehicle, team and crew, a footprint marker facing the
	way you look, and clicks sent to the VehicleSpawner server script instead.

	Its Kinetic Events tab calls artillery or an airstrike on the clicked spot,
	through the BloxianSpawner server script.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")

local tool = script.Parent
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local remote = ReplicatedStorage:WaitForChild("BloxianSpawnerRemote")
--Only there when the VehicleSpawner server script is installed.
local VEHICLE_REMOTE = "VehicleSpawnerRemote"
local vehicleRemote = ReplicatedStorage:FindFirstChild(VEHICLE_REMOTE)

--How far out a click can place a spawn (studs). The servers' MAX_SPAWN_DISTANCE
--has to be at least this.
local CLICK_RANGE = 5000

--Panel choices, in the order they are shown. The first is the default. tabs
--draws the row as tabs without a label; columns is chips per line (3 otherwise).
local OPTIONS = {
	{key = "branch", label = "Branch", values = {"Infantry","Special Operations"}, tabs = true},
	{key = "unit", label = "Unit", values = {"Infantry","Sniper team","AT team"}},
	{key = "sofSize", label = "Size", values = {"Recce","Fireteam"}, columns = 2},
	{key = "size", label = "Group", values = {1,4,9}, names = {"Soldier","Fire team","Squad"}},
	{key = "team", label = "Team", values = {"Hostile","Friendly"}, columns = 2},
	{key = "weapon", label = "Weapon", values = {"Random","Rifle","DMR","Carbine","LMG","Sniper"}},
	{key = "radio", label = "Radioman", values = {"Random","Leader","None"}, names = {"Random","Leader","None"}},
	--Each name is a preset in UniformModule.
	{key = "uniform", label = "Uniform", values = {"Bloxia","Korblox","KorbloxNaval"}, names = {"Bloxia","Korblox","Naval"}},
}

--Vehicles mode. The vehicle list comes from the server; send is the key the
--VehicleSpawner expects.
local VEHICLE_OPTIONS = {
	{key = "vehicle", label = "Vehicle", values = {}, columns = 2},
	{key = "vehicleTeam", send = "team", label = "Team", values = {"Any","Hostile","Friendly"}},
	{key = "crew", label = "Crew", values = {"None","Gunner","Full"}, names = {"Empty","Gunner only","Full crew"}},
}

--Kinetic Events mode. Side is whose airstrike it is; artillery hits everyone.
local KINETIC_OPTIONS = {
	{key = "kinetic", label = "Event", values = {"Artillery","Airstrike"}, columns = 2},
	{key = "kineticTeam", send = "team", label = "Side", values = {"Hostile","Friendly"}, columns = 2},
}

local KINETIC_MODE = "Kinetic Events"
local MODE_OPTION = {key = "mode", label = "Spawn", values = {"Soldiers",KINETIC_MODE}, tabs = true}

local ALL_OPTIONS = {MODE_OPTION}
for _,option in ipairs(OPTIONS) do
	table.insert(ALL_OPTIONS,option)
end
for _,option in ipairs(VEHICLE_OPTIONS) do
	table.insert(ALL_OPTIONS,option)
end
for _,option in ipairs(KINETIC_OPTIONS) do
	table.insert(ALL_OPTIONS,option)
end

--Panel look, after the TREK HUD: see-through dark boxes with a light outline,
--white Gotham caps, grey for secondary text, Roboto Mono for numbers.
local BOX = Color3.fromRGB(15,15,15)
local BOX_TRANSPARENCY = 0.5
local CHIP_TRANSPARENCY = 0.35
local CHIP_GAP = 4
--Panel size: width, the gap between rows, and the column of row labels beside the chips.
local PANEL_WIDTH = 400
local ROW_GAP = 8
local LABEL_WIDTH = 76
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

local IDLE_STATUS = "[CLICK] - AT CURSOR"

--Marker colours for the teams that are not Roblox teams (those use their TeamColor),
--and how wide the marker is per group size.
local TEAM_COLORS = {Any = Color3.fromRGB(230,230,230), Hostile = Color3.fromRGB(220,60,60), Friendly = Color3.fromRGB(70,140,255)}
local MARKER_WIDTH = {[1] = 4, [4] = 12, [9] = 20}
local PAIR_WIDTH = 8
--Ring width per kinetic event: Random Arty's shell scatter and the server's STRIKE_RADIUS, doubled.
local KINETIC_WIDTH = {Artillery = 180, Airstrike = 300}
local SOF_WIDTH = {Recce = 6, Fireteam = 12}
--Vehicle footprint when the server has not sent one.
local VEHICLE_FOOTPRINT = Vector2.new(8,16)

--Rows that only apply to infantry; other units bring their own make-up.
local INFANTRY_ONLY = {size = true, weapon = true, radio = true}
--Rows shown on one tab of the Branch row only.
local BRANCH_ONLY = {unit = "Infantry", size = "Infantry", weapon = "Infantry", radio = "Infantry", sofSize = "Special Operations"}

local TRACKING_ATTRIBUTE = "BloxianTracking"

local chosen = {}
for _,option in ipairs(ALL_OPTIONS) do
	chosen[option.key] = 1
end

local gui,statusLabel,trackButton,marker,renderConnection
local rows = {}

local function optionFor(key)
	for _,option in ipairs(ALL_OPTIONS) do
		if option.key == key then
			return option
		end
	end
end

local function value(key)
	local option = optionFor(key)
	return option.values[chosen[key]]
end

local function setValues(key,values)
	local option = optionFor(key)
	local current = option.values[chosen[key]]
	option.values = values
	chosen[key] = table.find(values,current) or 1
end

local function vehiclesOn()
	return vehicleRemote ~= nil and value("mode") == "Vehicles"
end

local function kineticOn()
	return value("mode") == KINETIC_MODE
end

--An aircraft always spawns with a full crew, so it has no crew choice.
local function aircraftChosen()
	local name = value("vehicle")
	return name ~= nil and vehicleRemote:GetAttribute("Aircraft_"..name:gsub("%W","_")) == true
end

--Read each time the tool comes out: Hostile, Friendly (and Any for vehicles),
--then every Roblox team in the game, and the server's vehicle list.
local function refreshChoices()
	local soldierTeams = {"Hostile","Friendly"}
	local vehicleTeams = {"Any","Hostile","Friendly"}
	for _,team in ipairs(Teams:GetTeams()) do
		if not table.find(vehicleTeams,team.Name) then
			soldierTeams[#soldierTeams+1] = team.Name
			vehicleTeams[#vehicleTeams+1] = team.Name
		end
	end
	setValues("team",soldierTeams)
	setValues("vehicleTeam",vehicleTeams)
	setValues("kineticTeam",soldierTeams)
	setValues("mode",vehicleRemote and {"Soldiers","Vehicles",KINETIC_MODE} or {"Soldiers",KINETIC_MODE})

	local vehicles = vehicleRemote and vehicleRemote:GetAttribute("Vehicles") or ""
	setValues("vehicle",vehicles ~= "" and string.split(vehicles,",") or {})
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
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = order,
	},parent)
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
	local vehicles = vehiclesOn()
	local kinetic = kineticOn()
	local infantry = value("unit") == "Infantry"
	local branch = value("branch")
	for _,option in ipairs(OPTIONS) do
		local row = rows[option.key]
		if row then
			local onTab = BRANCH_ONLY[option.key] == nil or BRANCH_ONLY[option.key] == branch
			row.Visible = not kinetic and (option.key == "uniform" or not vehicles and onTab and (infantry or not INFANTRY_ONLY[option.key]))
		end
	end
	for _,option in ipairs(VEHICLE_OPTIONS) do
		local row = rows[option.key]
		if row then
			row.Visible = vehicles and not (option.key == "crew" and aircraftChosen())
		end
	end
	for _,option in ipairs(KINETIC_OPTIONS) do
		local row = rows[option.key]
		if row then
			row.Visible = kinetic and (option.key == "kinetic" or value("kinetic") == "Airstrike")
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
	list(row,Enum.FillDirection.Horizontal,CHIP_GAP)
	if not option.tabs then
		text(row,string.upper(option.label),12,INK_DIM,1,BOLD).Size = UDim2.fromOffset(LABEL_WIDTH,28)
	end

	local buttons = {}
	local names = option.names or option.values

	--A straight grid: every chip in a row the same width.
	local columns = option.tabs and math.max(#names,1) or option.columns or 3
	local chips = make("Frame",{
		Size = UDim2.new(1,option.tabs and 0 or -LABEL_WIDTH - CHIP_GAP,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	},row)
	make("UIGridLayout",{
		CellSize = UDim2.new(1/columns,-CHIP_GAP*(columns - 1)/columns,0,option.tabs and 32 or 28),
		CellPadding = UDim2.fromOffset(CHIP_GAP,CHIP_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	},chips)

	if #names == 0 then
		text(chips,"NONE IN SERVERSTORAGE.BLOXIANVEHICLES",12,DANGER,1,MONO)
	end
	for index,name in ipairs(names) do
		local chip = flatButton(chips,tostring(name),index)
		if option.key == "team" or option.key == "vehicleTeam" or option.key == "kineticTeam" then
			padding(chip,8,0).PaddingLeft = UDim.new(0,22)
			make("Frame",{
				AnchorPoint = Vector2.new(0,0.5),
				Position = UDim2.new(0,-14,0.5,0),
				Size = UDim2.fromOffset(8,8),
				BackgroundColor3 = teamColor(option.values[index]),
				BorderSizePixel = 0,
			},chip)
		else
			padding(chip,6,0)
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
	if buttons[chosen[option.key]] then
		setSelected(buttons[chosen[option.key]],true)
	end
	rows[option.key] = row
end

local tracking

local function refreshTrackButton()
	if not trackButton then
		return
	end
	local on = player:GetAttribute(TRACKING_ATTRIBUTE) == true
	setSelected(trackButton,on)
	trackButton.Text = on and ("TRACKING "..tracking.alive()) or "TRACK ALL"
end

tracking = require(script.Parent:WaitForChild("Tracker"))({
	make = make, outline = outline, teamColor = teamColor,
	BOX = BOX, BOX_TRANSPARENCY = BOX_TRANSPARENCY, INK = INK, INK_DIM = INK_DIM, DANGER = DANGER,
	BOLD = BOLD, MONO = MONO,
},refreshTrackButton)

local function setTracking(on)
	player:SetAttribute(TRACKING_ATTRIBUTE,on)
	if on then
		tracking.start()
	else
		tracking.stop()
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
		Size = UDim2.fromOffset(PANEL_WIDTH,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = BOX,
		BackgroundTransparency = BOX_TRANSPARENCY,
		BorderSizePixel = 0,
	},gui)
	outline(panel,2)
	padding(panel,16,16)
	list(panel,Enum.FillDirection.Vertical,ROW_GAP)

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
	for order,option in ipairs(ALL_OPTIONS) do
		optionRow(panel,option,order)
	end
	refreshRows()

	local actions = make("Frame",{
		Size = UDim2.new(1,0,0,36),
		BackgroundTransparency = 1,
		LayoutOrder = #ALL_OPTIONS + 1,
	},panel)
	list(actions,Enum.FillDirection.Horizontal,4)

	trackButton = flatButton(actions,"Track all",1)
	trackButton.Size = UDim2.new(0.6,-2,1,0)
	trackButton.Activated:Connect(function()
		setTracking(player:GetAttribute(TRACKING_ATTRIBUTE) ~= true)
	end)

	local clear = flatButton(actions,"Clear all",2)
	clear.Size = UDim2.new(0.4,-2,1,0)
	clear.TextColor3 = DANGER
	clear.Activated:Connect(function()
		if vehiclesOn() then
			vehicleRemote:FireServer("clear")
		else
			remote:FireServer("clear")
		end
	end)

	refreshTrackButton()
	gui.Parent = playerGui
end

local function buildMarker()
	marker = Instance.new("Part")
	marker.Name = "BloxianSpawnMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Material = Enum.Material.SmoothPlastic
	marker.Transparency = 0.6
	marker.Parent = workspace.CurrentCamera
	mouse.TargetFilter = marker
end

local function lookDirection()
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flatLook = Vector3.new(look.X,0,look.Z)
	return flatLook.Magnitude > 0.01 and flatLook.Unit or Vector3.new(0,0,-1)
end

--Where the mouse points on the world, out to CLICK_RANGE, or nil for the sky.
local clickParams = RaycastParams.new()
clickParams.FilterType = Enum.RaycastFilterType.Exclude
local function clickPoint()
	clickParams.FilterDescendantsInstances = {marker,player.Character}
	local ray = mouse.UnitRay
	local result = workspace:Raycast(ray.Origin,ray.Direction*CLICK_RANGE,clickParams)
	return result and result.Position
end

--A disc the size of the group, or the vehicle's footprint facing the way you look.
local function placeMarker()
	local at = clickPoint()
	marker.Transparency = at and 0.6 or 1
	if not at then return end
	if kineticOn() then
		local event = value("kinetic")
		local width = KINETIC_WIDTH[event]
		marker.Shape = Enum.PartType.Cylinder
		marker.Size = Vector3.new(0.2,width,width)
		marker.Color = event == "Airstrike" and teamColor(value("kineticTeam")) or DANGER
		marker.CFrame = CFrame.new(at) * CFrame.Angles(0,0,math.pi/2)
	elseif vehiclesOn() then
		local name = value("vehicle")
		local size = name and vehicleRemote:GetAttribute("Size_"..name:gsub("%W","_"))
		if typeof(size) ~= "Vector2" then
			size = VEHICLE_FOOTPRINT
		end
		marker.Shape = Enum.PartType.Block
		marker.Size = Vector3.new(size.X,0.2,size.Y)
		marker.Color = teamColor(value("vehicleTeam"))
		marker.CFrame = CFrame.lookAt(at,at + lookDirection())
	else
		local width = value("branch") ~= "Infantry" and SOF_WIDTH[value("sofSize")]
			or value("unit") == "Infantry" and MARKER_WIDTH[value("size")] or PAIR_WIDTH
		marker.Shape = Enum.PartType.Cylinder
		marker.Size = Vector3.new(0.2,width,width)
		marker.Color = teamColor(value("team"))
		marker.CFrame = CFrame.new(at) * CFrame.Angles(0,0,math.pi/2)
	end
end

tool.Equipped:Connect(function()
	refreshChoices()
	buildGui()
	buildMarker()
	renderConnection = RunService.RenderStepped:Connect(placeMarker)
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
	if kineticOn() then
		local at = clickPoint()
		if at then
			remote:FireServer("kinetic",at,Vector3.zero,{event = value("kinetic"),team = value("kineticTeam")})
		else
			showStatus("Point at the ground",DANGER)
		end
		return
	end
	local vehicles = vehiclesOn()
	local OPTIONS = {}
	for _,option in ipairs(vehicles and VEHICLE_OPTIONS or OPTIONS) do
		options[option.send or option.key] = option.values[chosen[option.key]]
	end
	options.uniform = value("uniform")
	if not vehicles and options.branch ~= "Infantry" then
		options.unit = "Special Recon"
	end
	if vehicles and not options.vehicle then
		showStatus("No vehicles in ServerStorage.BloxianVehicles",DANGER)
		return
	end
	if vehicles and aircraftChosen() then
		options.crew = "Full"
	end
	local at = clickPoint()
	if not at then
		showStatus("Point at the ground",DANGER)
		return
	end
	local target = vehicles and vehicleRemote or remote
	target:FireServer("spawn",at,workspace.CurrentCamera.CFrame.LookVector,options)
end)

local function onReply(message)
	local failed = not string.find(message,"^Spawned") and not string.find(message,"^Cleared") and not string.find(message,"^Called")
	showStatus(message,failed and DANGER or GOOD)
end
remote.OnClientEvent:Connect(onReply)

--The vehicle server may start after this script, and its list can change while
--the tool is out (a vehicle added in Studio).
local function hookVehicles(found)
	vehicleRemote = found
	found.OnClientEvent:Connect(onReply)
	found:GetAttributeChangedSignal("Vehicles"):Connect(function()
		refreshChoices()
		if gui then
			gui:Destroy()
			buildGui()
		end
	end)
	if gui then
		refreshChoices()
		gui:Destroy()
		buildGui()
	end
end
if vehicleRemote then
	hookVehicles(vehicleRemote)
else
	task.spawn(function()
		hookVehicles(ReplicatedStorage:WaitForChild(VEHICLE_REMOTE,math.huge))
	end)
end

if player:GetAttribute(TRACKING_ATTRIBUTE) == true then
	tracking.start()
end

--[[
	The Bloxian Spawner tool, player side: a panel to pick the unit, group,
	team, weapon and radioman, a marker where the group will land, clicks sent to
	the BloxianSpawner server script, and a tracker that pins a tag over every
	Bloxian in the world, through walls.

	With the Vehicle Spawner's server script installed, the panel's Spawn row
	switches to vehicles: vehicle, team and crew, a footprint marker facing the
	way you look, and clicks sent to the VehicleSpawner server script instead.
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
	{key = "sofUnit", label = "Unit", values = {"Special Recon","Raiders"}, columns = 2},
	{key = "sofSize", label = "Size", values = {"Recce","Fireteam","ODA"}},
	{key = "size", label = "Group", values = {1,4,9}, names = {"Soldier","Fire team","Squad"}},
	{key = "team", label = "Team", values = {"Hostile","Friendly"}, columns = 2},
	{key = "weapon", label = "Weapon", values = {"Random","Rifle","DMR","Carbine","LMG","Sniper"}},
	{key = "radio", label = "Radioman", values = {"Random","Leader","None"}, names = {"Random","Leader","None"}},
	--Each name is a preset in UniformModule.
	{key = "uniform", label = "Uniform", values = {"Bloxia"}, columns = 1},
}

--Vehicles mode. The vehicle list comes from the server; send is the key the
--VehicleSpawner expects.
local VEHICLE_OPTIONS = {
	{key = "vehicle", label = "Vehicle", values = {}, columns = 2},
	{key = "vehicleTeam", send = "team", label = "Team", values = {"Any","Hostile","Friendly"}},
	{key = "crew", label = "Crew", values = {"None","Gunner","Full"}, names = {"Empty","Gunner only","Full crew"}},
}

local MODE_OPTION = {key = "mode", label = "Spawn", values = {"Soldiers","Vehicles"}, tabs = true}

local ALL_OPTIONS = {MODE_OPTION}
for _,option in ipairs(OPTIONS) do
	table.insert(ALL_OPTIONS,option)
end
for _,option in ipairs(VEHICLE_OPTIONS) do
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

local IDLE_STATUS = "[CLICK] - SPAWN AT CURSOR"

--Marker colours for the teams that are not Roblox teams (those use their TeamColor),
--and how wide the marker is per group size.
local TEAM_COLORS = {Any = Color3.fromRGB(230,230,230), Hostile = Color3.fromRGB(220,60,60), Friendly = Color3.fromRGB(70,140,255)}
local MARKER_WIDTH = {[1] = 4, [4] = 12, [9] = 20}
local PAIR_WIDTH = 8
local SOF_WIDTH = {Recce = 6, Fireteam = 12, ODA = 24}
--Vehicle footprint when the server has not sent one.
local VEHICLE_FOOTPRINT = Vector2.new(8,16)

--Rows that only apply to infantry; other units bring their own make-up.
local INFANTRY_ONLY = {size = true, weapon = true, radio = true}
--Rows shown on one tab of the Branch row only.
local BRANCH_ONLY = {unit = "Infantry", size = "Infantry", weapon = "Infantry", radio = "Infantry", sofUnit = "Special Operations", sofSize = "Special Operations"}

--Seconds between tracker refreshes.
local TRACK_INTERVAL = 0.2

--Soldiers, the aircraft (Phantoms, AC-130s, Apaches) and the land vehicles,
--and what an aircraft's tag is shown as (a land vehicle shows its name).
local TRACKED_TAGS = {"Bloxian","BloxianJet","BloxianGunship","BloxianAircraft","BloxianVehicle","MarineVehicle"}
local AIRCRAFT_NAMES = {BloxianJet = "F-4 Phantom",BloxianGunship = "AC-130",BloxianAircraft = "Apache"}
local VEHICLE_TAGS = {"BloxianVehicle","MarineVehicle"}
--How far above an aircraft's or a vehicle's root its tag floats (studs).
local AIRCRAFT_TAG_HEIGHT = 14
local VEHICLE_TAG_HEIGHT = 9
local TRACKER_NAME = "BloxianTracker"

--NATO unit-size mark for each echelon (the unit's SquadEchelon).
local ECHELON_MARKS = {["Fire team"] = "Ø", Squad = "●", Section = "●●", Platoon = "●●●", ["SOF Fireteam"] = "Ø", Recce = "Ø", ODA = "●●"}
--How far above the middle of a squad its tag floats (studs).
local SQUAD_TAG_HEIGHT = 35
local TRACKING_ATTRIBUTE = "BloxianTracking"

local chosen = {}
for _,option in ipairs(ALL_OPTIONS) do
	chosen[option.key] = 1
end

local gui,statusLabel,trackButton,marker,renderConnection
local rows = {}
local trackers = {}
local trackConnections = {}
local trackRun = 0

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
	local infantry = value("unit") == "Infantry"
	local branch = value("branch")
	for _,option in ipairs(OPTIONS) do
		local row = rows[option.key]
		if row then
			local onTab = BRANCH_ONLY[option.key] == nil or BRANCH_ONLY[option.key] == branch
			row.Visible = option.key == "uniform" or not vehicles and onTab and (infantry or not INFANTRY_ONLY[option.key])
		end
	end
	for _,option in ipairs(VEHICLE_OPTIONS) do
		local row = rows[option.key]
		if row then
			row.Visible = vehicles and not (option.key == "crew" and aircraftChosen())
		end
	end
	if rows.mode then
		rows.mode.Visible = vehicleRemote ~= nil
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
		if option.key == "team" or option.key == "vehicleTeam" then
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

local function aliveTracked()
	local count = 0
	for _,tracker in pairs(trackers) do
		if tracker.Enabled or tracker:GetAttribute("Alive") then
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

--What a machine is tracked as, and whether it flies. nil for a soldier.
local function machineName(model)
	for tag,name in pairs(AIRCRAFT_NAMES) do
		if model:HasTag(tag) then
			return name,true
		end
	end
	for _,tag in ipairs(VEHICLE_TAGS) do
		if model:HasTag(tag) then
			return model.Name,false
		end
	end
	return nil
end

--The most AirHealth each plane has been seen with, for its health bar.
local airHealthMax = setmetatable({},{__mode = "k"})

local function track(model)
	if trackers[model] or not model:IsDescendantOf(workspace) then
		return
	end
	local name,flies = machineName(model)
	local machine = name ~= nil
	--A model can arrive before its parts stream in, or lose them streaming out:
	--the refresh points the tag at whatever is there now.
	local anchor = if machine then model.PrimaryPart else model:FindFirstChild("Head")

	--Hidden until the first refresh has filled it in and found where it goes.
	local tracker = make("BillboardGui",{
		Name = TRACKER_NAME,
		Adornee = anchor,
		Enabled = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = math.huge,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(150,48),
		StudsOffsetWorldSpace = Vector3.new(0,if not machine then 2.6 elseif flies then AIRCRAFT_TAG_HEIGHT else VEHICLE_TAG_HEIGHT,0),
	},nil)

	local box = make("Frame",{
		Name = "Box",
		Size = UDim2.fromScale(1,1),
		BackgroundColor3 = BOX,
		BackgroundTransparency = BOX_TRANSPARENCY,
		BorderSizePixel = 0,
	},tracker)
	outline(box,1,0.4)
	make("Frame",{
		Name = "Swatch",
		Position = UDim2.fromOffset(8,8),
		Size = UDim2.fromOffset(8,8),
		BorderSizePixel = 0,
	},box)
	make("TextLabel",{
		Name = "Title",
		Text = "",
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
		Text = "",
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

--Who is in a vehicle's seats: how many, and the team of the first.
local function crewOf(model)
	local count,team = 0,nil
	for _,seatName in ipairs({"VehicleSeat","Seat"}) do
		local seat = model:FindFirstChild(seatName)
		local occupant = seat and seat.Occupant
		if occupant and occupant.Health > 0 then
			count += 1
			local crewSettings = occupant.Parent and occupant.Parent:FindFirstChild("Settings")
			local crewTeam = crewSettings and crewSettings:FindFirstChild("Team")
			local player = Players:GetPlayerFromCharacter(occupant.Parent)
			team = team or (crewTeam and crewTeam.Value ~= "" and crewTeam.Value) or (player and player.Team and player.Team.Name)
		end
	end
	return count,team
end

--An aircraft's or vehicle's tag: its team, what it is, what it is doing and how far off.
local function refreshMachine(model,tracker,kind,flies)
	local root = model.PrimaryPart
	local human = model:FindFirstChildOfClass("Humanoid")
	local down = model:GetAttribute("ShotDown") or model:GetAttribute("Wrecked") or (human and human.Health <= 0)
	tracker.Adornee = root
	tracker.Enabled = root ~= nil and model:IsDescendantOf(workspace)
	if not tracker.Enabled then
		return
	end

	local crew,crewTeam = crewOf(model)
	local settings = model:FindFirstChild("Settings")
	local teamValue = settings and settings:FindFirstChild("Team")
	local teamName = model:GetAttribute("Team") or crewTeam or (teamValue and teamValue.Value ~= "" and teamValue.Value)
		or (model:HasTag("BloxianJet") and "Friendly") or "Any"
	local color = down and DANGER or teamColor(teamName)

	local status = model:GetAttribute("Status")
	if down then
		status = flies and "Down" or "Wrecked"
	elseif not status then
		if model:GetAttribute("OnMission") then
			status = "Fire mission"
		elseif model:HasTag("BloxianGunship") then
			status = "On station"
		elseif flies and crew == 0 and human then
			status = "Empty"
		elseif flies then
			status = "Flying"
		else
			status = crew == 0 and "Empty" or ("Crew "..crew)
		end
	end

	local camera = workspace.CurrentCamera
	local distance = camera and math.floor((camera.CFrame.Position - root.Position).Magnitude) or 0

	local box = tracker.Box
	box.Swatch.BackgroundColor3 = color
	box.Title.Text = string.upper(teamName.." / "..kind)
	box.Detail.Text = string.format("%-10s%5dM",string.upper(status),distance)
	box.Health.Fill.BackgroundColor3 = color
	local airHealth = model:GetAttribute("AirHealth")
	if airHealth then
		airHealthMax[model] = math.max(airHealthMax[model] or 0,airHealth)
	end
	local health = if down then 0
		elseif human then human.Health/human.MaxHealth
		elseif airHealth then airHealth/math.max(airHealthMax[model],1)
		else 1
	box.Health.Fill.Size = UDim2.fromScale(math.clamp(health,0,1),1)
end

local function refreshTracker(model,tracker)
	local kind,flies = machineName(model)
	if kind then
		refreshMachine(model,tracker,kind,flies)
		return
	end
	--Soldiers have no tag of their own: their unit's tag, or their vehicle's, stands for them.
	local human = model:FindFirstChildOfClass("Humanoid")
	tracker:SetAttribute("Alive",human ~= nil and human.Health > 0 and model:IsDescendantOf(workspace))
	tracker.Enabled = false
end

--One tag per squad (by SquadId) high over the middle of its soldiers on foot:
--its NATO size mark above its name and strength. Anyone seated in a vehicle
--still counts toward the squad but is left out of where the tag sits.
--squadTags[id] = {gui, anchor (an invisible client-side part), heads}
local squadTags = {}

local function newSquadTag()
	local anchor = make("Part",{
		Name = "BloxianSquadAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2,0.2,0.2),
	},workspace.CurrentCamera)
	local tag = make("BillboardGui",{
		Name = TRACKER_NAME,
		Adornee = anchor,
		Enabled = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = math.huge,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(160,42),
		StudsOffsetWorldSpace = Vector3.new(0,SQUAD_TAG_HEIGHT,0),
	},nil)
	local box = make("Frame",{
		Name = "Box",
		Size = UDim2.fromScale(1,1),
		BackgroundColor3 = BOX,
		BackgroundTransparency = BOX_TRANSPARENCY,
		BorderSizePixel = 0,
	},tag)
	outline(box,1,0.4)
	make("TextLabel",{
		Name = "Mark",
		Position = UDim2.fromOffset(0,3),
		Size = UDim2.new(1,0,0,18),
		BackgroundTransparency = 1,
		FontFace = BOLD,
		TextSize = 16,
		Text = "",
	},box)
	make("TextLabel",{
		Name = "Label",
		Position = UDim2.fromOffset(0,21),
		Size = UDim2.new(1,0,0,16),
		BackgroundTransparency = 1,
		FontFace = MONO,
		TextSize = 12,
		Text = "",
	},box)
	tag.Parent = playerGui
	return {gui = tag, anchor = anchor, heads = {}}
end

local function dropSquadTag(id)
	local entry = squadTags[id]
	entry.gui:Destroy()
	entry.anchor:Destroy()
	squadTags[id] = nil
end

--Every frame: each tag's anchor to the middle of its squad's heads.
local function placeSquadTags()
	for _,entry in pairs(squadTags) do
		local sum,count = Vector3.zero,0
		for _,head in ipairs(entry.heads) do
			if head.Parent then
				sum += head.Position
				count += 1
			end
		end
		entry.gui.Enabled = count > 0
		if count > 0 then
			entry.anchor.CFrame = CFrame.new(sum/count)
		end
	end
end

--Every refresh: who is in each squad, and its mark, name and strength.
local function refreshSquads()
	local squads = {}
	for model,tracker in pairs(trackers) do
		local id = (tracker.Enabled or tracker:GetAttribute("Alive")) and model:GetAttribute("SquadName") and model:GetAttribute("SquadId")
		local human = id and model:FindFirstChildOfClass("Humanoid")
		local head = human and model:FindFirstChild("Head")
		if head then
			local squad = squads[id]
			if not squad then
				squad = {alive = 0,heads = {},model = model}
				squads[id] = squad
			end
			squad.alive += 1
			if not human.SeatPart then
				squad.heads[#squad.heads+1] = head
			end
		end
	end

	for id in pairs(squadTags) do
		if not squads[id] then
			dropSquadTag(id)
		end
	end

	for id,squad in pairs(squads) do
		local entry = squadTags[id] or newSquadTag()
		squadTags[id] = entry
		entry.heads = squad.heads

		local model = squad.model
		local echelon = model:GetAttribute("SquadEchelon") or "Squad"
		local settings = model:FindFirstChild("Settings")
		local teamValue = settings and settings:FindFirstChild("Team")
		local strength = math.floor(squad.alive/math.max(model:GetAttribute("SquadSize") or squad.alive,1)*100 + 0.5)
		local box = entry.gui.Box
		box.Mark.Text = ECHELON_MARKS[echelon] or ""
		box.Mark.TextColor3 = teamColor(teamValue and teamValue.Value or "?")
		local number = model:GetAttribute("SquadNumber")
		local name = string.upper(model:GetAttribute("SquadName"))
		box.Label.Text = echelon == "ODA" and string.format("ODA %s %d%%",name,strength)
			or string.format("%s %s%s %d%%",name,string.upper(echelon),number and " "..number or "",strength)
		box.Label.TextColor3 = model:GetAttribute("Demoralized") and DANGER or INK
	end
end

local function stopTracking()
	trackRun += 1
	for id in pairs(squadTags) do
		dropSquadTag(id)
	end
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
	for _,tag in ipairs(TRACKED_TAGS) do
		for _,model in ipairs(CollectionService:GetTagged(tag)) do
			track(model)
		end
		table.insert(trackConnections,CollectionService:GetInstanceAddedSignal(tag):Connect(track))
		table.insert(trackConnections,CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack))
	end
	table.insert(trackConnections,RunService.RenderStepped:Connect(placeSquadTags))

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
			refreshSquads()
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
	marker.Material = Enum.Material.Neon
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
	if vehiclesOn() then
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
	local vehicles = vehiclesOn()
	local options = {}
	for _,option in ipairs(vehicles and VEHICLE_OPTIONS or OPTIONS) do
		options[option.send or option.key] = option.values[chosen[option.key]]
	end
	options.uniform = value("uniform")
	if not vehicles and options.branch ~= "Infantry" then
		options.unit = options.sofUnit
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
	local failed = not string.find(message,"^Spawned") and not string.find(message,"^Cleared")
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

--Tracking stays on through respawns; the last life's tags are left over in PlayerGui.
for _,leftover in ipairs(playerGui:GetChildren()) do
	if leftover.Name == TRACKER_NAME then
		leftover:Destroy()
	end
end
if player:GetAttribute(TRACKING_ATTRIBUTE) == true then
	startTracking()
end

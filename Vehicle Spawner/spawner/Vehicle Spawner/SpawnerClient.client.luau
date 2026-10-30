--[[
	The Vehicle Spawner tool, player side: a panel to pick the vehicle, the team
	that may crew it and its crew, a footprint marker where it will land facing
	the way you look, and clicks sent to the VehicleSpawner server script.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")

local tool = script.Parent
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remote = ReplicatedStorage:WaitForChild("VehicleSpawnerRemote")

--Panel choices, in the order the buttons cycle through them. The first is the
--default. The vehicle list comes from the server.
local OPTIONS = {
	{key = "vehicle", label = "Vehicle", values = {}},
	{key = "team", label = "Team", values = {"Any","Hostile","Friendly"}},
	{key = "crew", label = "Crew", values = {"None","Driver","Full"}, names = {"Empty","Driver only","Full crew"}},
}

--Marker colours for the teams that are not Roblox teams (those use their TeamColor).
local TEAM_COLORS = {Any = Color3.fromRGB(230,230,230), Hostile = Color3.fromRGB(220,60,60), Friendly = Color3.fromRGB(70,140,255)}

local chosen = {}
for _,option in ipairs(OPTIONS) do
	chosen[option.key] = 1
end

local gui,statusLabel,marker,renderConnection
local buttons = {}

local function optionFor(key)
	for _,option in ipairs(OPTIONS) do
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

--Read each time the tool comes out: the server's vehicle list, and Any, Hostile,
--Friendly, then every Roblox team in the game.
local function refreshChoices()
	local list = remote:GetAttribute("Vehicles") or ""
	setValues("vehicle",list ~= "" and string.split(list,",") or {})

	local teams = {"Any","Hostile","Friendly"}
	for _,team in ipairs(Teams:GetTeams()) do
		if not table.find(teams,team.Name) then
			teams[#teams+1] = team.Name
		end
	end
	setValues("team",teams)
end

local function teamColor(name)
	local team = Teams:FindFirstChild(name)
	if team and team:IsA("Team") then
		return team.TeamColor.Color
	end
	return TEAM_COLORS[name] or Color3.new(1,1,1)
end

local function optionText(option)
	local index = chosen[option.key]
	local names = option.names or option.values
	return option.label..": "..tostring(names[index] or "none")
end

local function showStatus(message)
	if not statusLabel then
		return
	end
	statusLabel.Text = message
	local shown = message
	task.delay(2.5,function()
		if statusLabel and statusLabel.Text == shown then
			statusLabel.Text = ""
		end
	end)
end

local function button(parent,text,color,order)
	local item = Instance.new("TextButton")
	item.Size = UDim2.fromOffset(150,34)
	item.BackgroundColor3 = color
	item.BackgroundTransparency = 0.15
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.TextSize = 13
	item.TextColor3 = Color3.new(1,1,1)
	item.Text = text
	item.LayoutOrder = order
	item.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0,6)
	corner.Parent = item
	item.Parent = parent
	return item
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "VehicleSpawnerGui"
	gui.ResetOnSpawn = false

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5,1)
	panel.Position = UDim2.new(0.5,0,1,-90)
	panel.Size = UDim2.fromOffset(0,34)
	panel.AutomaticSize = Enum.AutomaticSize.X
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0,6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	for order,option in ipairs(OPTIONS) do
		local item = button(panel,optionText(option),Color3.fromRGB(30,32,38),order)
		buttons[option.key] = item
		item.Activated:Connect(function()
			if #option.values > 0 then
				chosen[option.key] = chosen[option.key] % #option.values + 1
			end
			item.Text = optionText(option)
		end)
	end

	local clear = button(panel,"Clear mine",Color3.fromRGB(150,40,40),#OPTIONS + 1)
	clear.Activated:Connect(function()
		remote:FireServer("clear")
	end)

	statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0.5,1)
	statusLabel.Position = UDim2.new(0.5,0,1,-130)
	statusLabel.Size = UDim2.fromOffset(400,24)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 16
	statusLabel.TextColor3 = Color3.new(1,1,1)
	statusLabel.TextStrokeTransparency = 0.5
	statusLabel.Text = #optionFor("vehicle").values > 0 and "Click the ground to spawn" or "No vehicles in ServerStorage.BloxianVehicles"
	statusLabel.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function buildMarker()
	marker = Instance.new("Part")
	marker.Name = "VehicleSpawnMarker"
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

tool.Equipped:Connect(function()
	refreshChoices()
	buildGui()
	buildMarker()
	renderConnection = RunService.RenderStepped:Connect(function()
		local name = value("vehicle")
		local size = name and remote:GetAttribute("Size_"..name:gsub("%W","_"))
		if typeof(size) ~= "Vector2" then
			size = Vector2.new(8,16)
		end
		local at = mouse.Hit.Position
		marker.Size = Vector3.new(size.X,0.2,size.Y)
		marker.Color = teamColor(value("team"))
		marker.CFrame = CFrame.lookAt(at,at + lookDirection())
	end)
end)

tool.Unequipped:Connect(function()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if gui then
		gui:Destroy()
		gui,statusLabel = nil,nil
		table.clear(buttons)
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
	if not options.vehicle then
		showStatus("No vehicles in ServerStorage.BloxianVehicles")
		return
	end
	remote:FireServer("spawn",mouse.Hit.Position,workspace.CurrentCamera.CFrame.LookVector,options)
end)

remote.OnClientEvent:Connect(showStatus)

--The list can change while the tool is out (a vehicle added in Studio).
remote:GetAttributeChangedSignal("Vehicles"):Connect(function()
	refreshChoices()
	local item = buttons.vehicle
	if item then
		item.Text = optionText(optionFor("vehicle"))
	end
end)

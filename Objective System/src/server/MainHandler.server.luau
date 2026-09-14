-- VARIABLES
local main = script.Parent.Parent
local system = main.System
local config = main.Settings
local points = main.Points

shared.defenders = {}
shared.raiders = {}
shared.neutral = {}

local defenderColour = config.DefendingTeams:GetAttribute('CategoryColour')
local raiderColour = config.RaidingTeams:GetAttribute('CategoryColour')

-- FUNCTIONS
local function setTeams()
	for i,team in pairs(config.DefendingTeams:GetChildren()) do
		if not team.Value then continue end
		shared.defenders[team.Value.Name] = team.Value
	end
	for i,team in pairs(config.RaidingTeams:GetChildren()) do
		if not team.Value then continue end
		shared.raiders[team.Value.Name] = team.Value
	end
	for i,team:ObjectValue in pairs(config.NeutralTeams:GetChildren()) do
		if not team.Value then continue end
		shared.neutral[team.Value.Name] = team.Value
	end
end

local function getPlrCategory(plr)
	if shared.defenders[plr.Team.Name] then
		return 'Defenders', shared.defenders[plr.Team.Name]
	elseif shared.raiders[plr.Team.Name] then
		return 'Raiders',shared.raiders[plr.Team.Name]
	elseif shared.neutral[plr.Team.Name] then
		return 'Neutral',shared.neutral[plr.Team.Name]
	end
end

local function victory(team)
	system.RaidOfficial.Value = false
	system.Remotes.Victory:FireAllClients(team)
	
	task.wait(5)
	
	for i, point in pairs(points:GetChildren()) do
		if point.Capital.Value then continue end
		
		point.Progress.Value = 0
		point.Owner.Value = 'None'
	end
	
	system.StatDefenders.Value = 0
	system.StatRaiders.Value = 0
end

local function cap(point)
	if point.Progress.Value == point.Progress.MaxValue then
		
		if system.StatDefenders.Value + (point.Value.Value) >= config.Objective.Value then 
			system.StatDefenders.Value = config.Objective.Value
			victory('Defenders')
		end
		
		system.StatDefenders.Value += (point.Value.Value)
	elseif point.Progress.Value == point.Progress.MinValue then
		
		if system.StatRaiders.Value + (point.Value.Value) >= config.Objective.Value then 
			system.StatRaiders.Value = config.Objective.Value
			victory('Raiders')
		end
		
		system.StatRaiders.Value += (point.Value.Value)
	end
end

local function getNumbersOnPoint(point)
	local r,d = 0,0
	
	for i,plr in pairs(game.Players:GetPlayers()) do
		if not plr.Character then continue end
		if not plr.Character:FindFirstChild('Humanoid') then continue end
		if not plr.Character:FindFirstChild('HumanoidRootPart') then continue end
		if plr.Character.Humanoid.Health <= 0 then continue end
		
		local radius
		
		if point.Parent:FindFirstChild('CaptureRadius') then
			radius = point.Parent:FindFirstChild('CaptureRadius').Value
		else
			if point.Size.X >=1 then
				radius = (point.Size.X) + 6
			elseif point.Size.Z >= 1 then
				radius = (point.Size.Z) + 6
			else
				radius = 16
			end
		end
		
		if (plr.Character.HumanoidRootPart.Position - point.Position).Magnitude <= radius then
			local category,team = getPlrCategory(plr)
			
			if category == 'Defenders' then
				d += 1
			elseif category == 'Raiders' then
				r += 1
			end
		end
		
	end
	
	return r,d
end

local function handlePoints()
	if not system.RaidOfficial.Value then return end
	
	for i,point in pairs(points:GetChildren()) do	
		if point.Capital.Value then continue end
		
		local r,d = getNumbersOnPoint(point.Point)

		if (r > d and point.Progress.Value > point.Progress.MinValue) then
			point.Progress.Value -= 1
			point.Contested.Value = false
		elseif (d > r and point.Progress.Value < point.Progress.MaxValue) then
			point.Progress.Value += 1
			point.Contested.Value = false
		elseif ((r ~= 0 and d ~= 0) and (r == d)) then
			point.Contested.Value = true
		else
			point.Contested.Value = false
		end
		
		if point.Progress.Value == point.Progress.MinValue then
			point.Owner.Value = 'Raiders'	
		elseif point.Progress.Value == point.Progress.MaxValue then
			point.Owner.Value = 'Defenders'
		else
			point.Owner.Value = 'None'
		end
	end
end

local function handleScores()
	if not system.RaidOfficial.Value then return end
	
	for i,point in pairs(points:GetChildren()) do
		cap(point)
	end
end

local function handlePointNotifications(point)
	if (point.Owner.Value ~= 'Raiders' and point.Owner.Value ~= 'Defenders') then return end
	
	local owner
	
	if point.Owner.Value == 'Raiders' then
		owner = 'RAIDERS'
	elseif point.Owner.Value == 'Defenders' then
		owner = 'DEFENDERS'
	end
	
	local message = {
		['Title'] = 'POINT CAPTURED',
		['Text'] = point.Name..' HAS BEEN TAKEN BY '..owner,
		['Icon'] = 'rbxassetid://6869139794', --radio icon
		['Duration'] = 3
	}
	system.Remotes.notif:FireAllClients('notif',message)
end

-- EXECUTION
setTeams()
for i,point in pairs(points:GetChildren()) do
	point.Owner:GetPropertyChangedSignal('Value'):Connect(function() handlePointNotifications(point) end)
end

task.spawn(function()
	while task.wait(.2) do
		handlePoints()
	end
end)

task.spawn(function()
	while task.wait(1) do
		handleScores()
	end
end)
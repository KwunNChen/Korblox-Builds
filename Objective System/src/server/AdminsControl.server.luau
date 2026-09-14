-- VARIABLES
local main = script.Parent.Parent
local system = main.System
local config = main.Settings
local points = main.Points

local plrs = game:GetService('Players')
local groups = game:GetService('GroupService')

shared.admins = {}

local defenderColour = config.DefendingTeams:GetAttribute('CategoryColour')
local raiderColour = config.RaidingTeams:GetAttribute('CategoryColour')
local admin = config.AdminControls
local user = admin.UserId

user.Value = game.PrivateServerOwnerId

local beginMessage = {
	['Title'] = 'RAID STARTED',
	['Text'] = 'The raid has begun.',
	['Icon'] = 'rbxassetid://6869139794', --radio icon
	['Duration'] = 5
}

local endMessage = {
	['Title'] = 'RAID ENDED',
	['Text'] = 'The raid has been stopped.',
	['Icon'] = 'rbxassetid://6869139794', --radio icon
	['Duration'] = 5
}

-- FUNCTIONS
local function begin()
	if not system.RaidOfficial.Value then
		for i,plr in pairs(plrs:GetPlayers()) do
			plr:LoadCharacter()
		end
		
		system.Remotes.notif:FireAllClients('notif',beginMessage)
		system.RaidOfficial.Value = true
	end
end

local function End()
	if system.RaidOfficial.Value then
		system.RaidOfficial.Value = false
		system.Ended.Value = true
		
		system.Remotes.notif:FireAllClients('notif',endMessage)
	end
end

local function score(score)
	if typeof(score) ~= 'number' then return end
	
	local message = {
		['Title'] = 'OBJECTIVE UPDATED',
		['Text'] = 'The objective has been set to: '..tostring(score),
		['Icon'] = 'rbxassetid://6869139794', --radio icon
		['Duration'] = 3
	}
	system.Remotes.notif:FireAllClients('notif',message)

	config.Objective.Value = score
end

local function setDefenderGroup(id)
	if typeof(id) ~= 'number' then return end

	local group = groups:GetGroupInfoAsync(id)
	system.DefenderGroup.Title.Value = group.Name
	system.DefenderGroup.Image.Value = group.EmblemUrl
	
	local message = {
		['Title'] = 'DEFENDER GROUP UPDATED',
		['Text'] = 'The defender group has been set to: '..tostring(group.Name),
		['Icon'] = group.EmblemUrl, --radio icon
		['Duration'] = 3
	}
	system.Remotes.notif:FireAllClients('notif',message)
end

local function setRaiderGroup(id)
	if typeof(id) ~= 'number' then return end

	local group = groups:GetGroupInfoAsync(id)
	system.RaiderGroup.Title.Value = group.Name
	system.RaiderGroup.Image.Value = group.EmblemUrl
		
	local message = {
		['Title'] = 'RAIDER GROUP UPDATED',
		['Text'] = 'The raider group has been set to: '..tostring(group.Name),
		['Icon'] = group.EmblemUrl, --radio icon
		['Duration'] = 3
	}
	system.Remotes.notif:FireAllClients('notif',message)
end

local function handleCommands(text) 
	-- if you're looking here, this system has 3 commands im not making a module based admin for this
	if text == '!begin' then
		begin()
	elseif text == '!end' then
		End()
	elseif string.sub(text,1,11) == '!defenderId' then
		local tbl = string.split(text, ' ')
		setDefenderGroup(tonumber(tbl[2]))
	elseif string.sub(text,1,9) == '!raiderId' then
		local tbl = string.split(text, ' ')
		setRaiderGroup(tonumber(tbl[2]))
	elseif string.sub(text,1,6) == '!score' then
		local tbl = string.split(text, ' ')
		score(tonumber(tbl[2]))
	end
end

local function plrAdded(plr:Player)
	for i,v in pairs(admin:GetChildren()) do
		if v.Name == 'GroupId' then
			if plr:GetRankInGroup(v.Value) >= v.RankId.Value then
				shared.admins[plr.Name] = true
				plr.Chatted:Connect(handleCommands)
				return
			end
		end
		if v.Name == 'UserId' then
			if plr.UserId == v.Value then
				shared.admins[plr.Name] = true
				plr.Chatted:Connect(handleCommands)
				return
			end
		end
	end
end

-- EXECUTION
plrs.PlayerAdded:Connect(plrAdded)
--[[
	Who is on which side, for the vehicles and aircraft. One copy of the rules,
	built into each package that needs it (a child named Sides).

	Sides are team names: a Roblox team's, or a Bloxian's Settings.Team. A
	Bloxian with a blank team is Hostile; a jet with a blank team flies for
	Friendly; an AC-130 with a blank Team attribute is Hostile.
]]

local players = game:GetService("Players")
local teams = game:GetService("Teams")

local sides = {}

sides.HOSTILE = "Hostile"
sides.FRIENDLY = "Friendly"
sides.JET_TAG = "BloxianJet"
sides.GUNSHIP_TAG = "BloxianGunship"
sides.HELI_TAG = "BloxianAircraft"
sides.AIR_TAGS = {sides.GUNSHIP_TAG,sides.JET_TAG,sides.HELI_TAG}

--Which kind of aircraft a model is (its tag), or nil.
function sides.airKind(craft)
	for _,tag in ipairs(sides.AIR_TAGS) do
		if craft:HasTag(tag) then return tag end
	end
	return nil
end

--A player's team name, or the Team value an NPC carries. nil for no side
--(a blank team, a Neutral player).
function sides.sideOf(model)
	local player = players:GetPlayerFromCharacter(model)
	if player then
		return not player.Neutral and player.Team and player.Team.Name or nil
	end
	local settings = model:FindFirstChild("Settings")
	local tag = model:FindFirstChild("Team") or (settings and settings:FindFirstChild("Team"))
	return tag and tag.Value ~= "" and tag.Value or nil
end

--Whether an NPC leaves this player alone: Hostile never does, one on a Roblox
--team's name fights other teams, and any other follows its AttackPlayers.
function sides.sparesPlayer(npcModel,npcSide,player)
	if npcSide == sides.HOSTILE then return false end
	local robloxTeam = npcSide and teams:FindFirstChild(npcSide)
	if robloxTeam and robloxTeam:IsA("Team") and player.Team and not player.Neutral then return false end
	local settings = npcModel:FindFirstChild("Settings")
	local attackPlayers = settings and settings:FindFirstChild("AttackPlayers")
	return attackPlayers ~= nil and not attackPlayers.Value
end

--A Bloxian's team (blank counts as Hostile), or nil for anything else.
function sides.npcSide(model)
	local settings = model:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	if not team or not team:IsA("StringValue") then return nil end
	return team.Value ~= "" and team.Value or sides.HOSTILE
end

--"enemy", "friend" or nil (neither) for a character, seen from side.
function sides.standing(model,side)
	local player = players:GetPlayerFromCharacter(model)
	if player then
		local team = teams:FindFirstChild(side)
		if team and team:IsA("Team") then
			return (not player.Neutral and player.Team == team) and "friend" or "enemy"
		end
		return side == sides.HOSTILE and "enemy" or "friend"
	end
	local other = sides.npcSide(model)
	if not other then return nil end
	return other == side and "friend" or "enemy"
end

--The live crew of a vehicle: whoever sits in its VehicleSeat and Seat.
function sides.crewOf(car)
	local crew = {}
	for _,name in ipairs({"VehicleSeat","Seat"}) do
		local seat = car:FindFirstChild(name)
		local occupant = seat and seat.Occupant
		if occupant and occupant.Health > 0 and occupant.Parent then
			crew[#crew+1] = occupant.Parent
		end
	end
	return crew
end

--"enemy", "friend" or nil for a vehicle seen from side: by its crew, else the
--team it is kept to.
function sides.vehicleStanding(car,side)
	local enemy = false
	for _,member in ipairs(sides.crewOf(car)) do
		local view = sides.standing(member,side)
		if view == "friend" then return "friend" end
		if view == "enemy" then enemy = true end
	end
	if enemy then return "enemy" end
	local settings = car:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	if team and team.Value ~= "" then
		return team.Value == side and "friend" or "enemy"
	end
	return nil
end

--A plane's side: an AC-130 by its Team attribute, a jet by its Settings.Team.
--nil for a helicopter, which goes by its crew.
function sides.craftSide(craft)
	local kind = sides.airKind(craft)
	if kind == sides.GUNSHIP_TAG then
		local team = craft:GetAttribute("Team")
		return type(team) == "string" and team ~= "" and team or sides.HOSTILE
	elseif kind == sides.JET_TAG then
		local settings = craft:FindFirstChild("Settings")
		local team = settings and settings:FindFirstChild("Team")
		return team and team.Value ~= "" and team.Value or sides.FRIENDLY
	end
	return nil
end

--An aircraft on the other side from side, still flying.
function sides.enemyAircraft(craft,side)
	if not craft.Parent or not craft.PrimaryPart or craft:GetAttribute("ShotDown") or craft:GetAttribute("Wrecked") then return false end
	local kind = sides.airKind(craft)
	if not kind then return false end
	if kind == sides.HELI_TAG then
		local human = craft:FindFirstChildOfClass("Humanoid")
		return human ~= nil and human.Health > 0 and sides.vehicleStanding(craft,side) == "enemy"
	end
	return sides.craftSide(craft) ~= side
end

return sides

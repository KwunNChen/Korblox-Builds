-- Checks the side rules in Shared/Sides.luau outside Studio.
-- Run from the AI folder:
--     lune run Shared/tests/sides.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

--No players and no Roblox teams: only Bloxians and aircraft.
local services = {
	Players = {GetPlayerFromCharacter = function() return nil end},
	Teams = {FindFirstChild = function() return nil end},
}
local game = {GetService = function(_,name) return services[name] end}
local sides = luau.load(fs.readFile("Shared/Sides.luau"),{debugName = "Sides",environment = {game = game}})()

local function soldier(team)
	local model = Instance.new("Model")
	local settings = Instance.new("Folder")
	settings.Name = "Settings"
	settings.Parent = model
	local value = Instance.new("StringValue")
	value.Name = "Team"
	value.Value = team
	value.Parent = settings
	return model
end

local function aircraft(tag,team)
	local model = if tag == sides.JET_TAG then soldier(team or "") else Instance.new("Model")
	model:AddTag(tag)
	local root = Instance.new("Part")
	root.Parent = model
	model.PrimaryPart = root
	if tag == sides.GUNSHIP_TAG and team then
		model:SetAttribute("Team",team)
	end
	return model
end

local failures = 0
local function check(name,got,want)
	if got ~= want then
		failures += 1
		print(string.format("FAIL %s: got %s, want %s",name,tostring(got),tostring(want)))
	end
end

check("blank Bloxian is Hostile",sides.npcSide(soldier("")),"Hostile")
check("Friendly Bloxian",sides.npcSide(soldier("Friendly")),"Friendly")
check("no Settings is no side",sides.npcSide(Instance.new("Model")),nil)
check("blank Bloxian has no sideOf",sides.sideOf(soldier("")),nil)
check("Hostile sees Hostile as friend",sides.standing(soldier(""),"Hostile"),"friend")
check("Friendly sees Hostile as enemy",sides.standing(soldier("Hostile"),"Friendly"),"enemy")

check("blank AC-130 is Hostile",sides.craftSide(aircraft(sides.GUNSHIP_TAG)),"Hostile")
check("Friendly AC-130",sides.craftSide(aircraft(sides.GUNSHIP_TAG,"Friendly")),"Friendly")
check("blank jet is Friendly",sides.craftSide(aircraft(sides.JET_TAG)),"Friendly")
check("Hostile jet",sides.craftSide(aircraft(sides.JET_TAG,"Hostile")),"Hostile")
check("helicopter goes by crew",sides.craftSide(aircraft(sides.HELI_TAG)),nil)

local folder = Instance.new("Folder")
local gunship = aircraft(sides.GUNSHIP_TAG,"Hostile")
gunship.Parent = folder
check("Hostile AC-130 is Friendly's enemy",sides.enemyAircraft(gunship,"Friendly"),true)
check("Hostile AC-130 is not Hostile's enemy",sides.enemyAircraft(gunship,"Hostile"),false)
gunship:SetAttribute("ShotDown",true)
check("shot-down AC-130 is nobody's enemy",sides.enemyAircraft(gunship,"Friendly"),false)

if failures > 0 then
	error(failures.." side rule(s) broken")
end
print("sides: all checks pass")

--[[
	What the enemy is fighting with, so a soldier can fight him the right way:
		close   a shotgun (more than one pellet a shot) or a melee weapon:
		        kept at a distance
		long    a scoped gun that isn't automatic (a sniper): rushed with fewer
		        friends, and peeked at only briefly
		auto    an automatic: hidden from longer, waiting out the bursts
	Anything else (a rifle, nothing in his hands) is nil.

	A player's held Tool is read from the TREK gun config it uses
	(ReplicatedStorage.TREK_SERVICES.GunConfigs, by the tool's TConfigToUse
	attribute or its name), else guessed from the tool's name. A Bloxian's is
	his Weapon attribute.
]]

local threat = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = script.Parent
local status = require(modules.Status)
local chatter = require(modules.ChatterModule)
local log = require(modules.Troubleshoot).log

--An automatic firing at least this many rounds a minute counts as one.
local AUTO_RPM = 500

--Words in a tool's name that give it away when it has no TREK config.
local NAME_WORDS = {
	close = {"shotgun","knife","bayonet","sword","machete","spas","870"},
	long = {"sniper","m24","m40","awp","svd","kar98","scoped"},
	auto = {"lmg","m60","m249","minigun","machine gun","smg"},
}

--A Bloxian's Weapon attribute.
local BLOXIAN_WEAPONS = {Sniper = "long", LMG = "auto", Shotgun = "close"}

--Chance he calls out what the enemy has the first time he sees it.
local CALLOUT_CHANCE = 0.6

local CALLOUTS = {close = "enemyShotgun", long = "enemySniper", auto = "enemyMG"}

--Each tool's kind, worked out once (false: nothing special).
local known = setmetatable({},{__mode = "k"})

local function configMode(tool)
	local services = ReplicatedStorage:FindFirstChild("TREK_SERVICES")
	local configs = services and services:FindFirstChild("GunConfigs")
	local module = configs and configs:FindFirstChild(tool:GetAttribute("TConfigToUse") or tool.Name,true)
	if not module or not module:IsA("ModuleScript") then return nil end
	local ok,config = pcall(require,module)
	return ok and type(config) == "table" and type(config[1]) == "table" and config[1] or nil
end

local function kindOf(tool)
	local mode = configMode(tool)
	if mode then
		if (mode.RaysPerShot or 1) > 1 or mode.BulletType == "Melee" then return "close" end
		if mode.CanZoom and mode.Scope and mode.GunType ~= 1 then return "long" end
		if mode.GunType == 1 and (mode.RoundsPerMinute or 0) >= AUTO_RPM then return "auto" end
		return false
	end
	local name = string.lower(tool.Name)
	for kind,words in pairs(NAME_WORDS) do
		for _,word in ipairs(words) do
			if string.find(name,word,1,true) then return kind end
		end
	end
	return false
end

--"close", "long", "auto" or nil for what target's owner is holding.
function threat.of(target)
	local character = target and target.Parent
	if not character then return nil end
	local bloxian = character:GetAttribute("Weapon")
	if bloxian then
		return BLOXIAN_WEAPONS[bloxian]
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return nil end
	if known[tool] == nil then
		known[tool] = kindOf(tool)
	end
	return known[tool] or nil
end

--What his current target is holding.
function threat.current()
	return threat.of(status:get("currentTarget"))
end

--Calls out a new enemy weapon. Called from the target loop.
local calledFor = setmetatable({},{__mode = "k"})
function threat.update()
	local target = status:get("currentTarget")
	local kind = target and threat.of(target)
	local character = target and target.Parent
	if not kind or calledFor[character] == kind then return end
	calledFor[character] = kind
	log("threat","enemy has a "..kind.." weapon")
	chatter.callout(CALLOUTS[kind],nil,CALLOUT_CHANCE)
end

return threat

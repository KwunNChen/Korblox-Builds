-- Checks the shared vehicle rules (Shared/VehicleKit with Shared/Sides), outside Studio:
-- who a vehicle may hurt, kill counters, and crew armour.
-- Run from the AI folder:
--     lune run Shared/tests/vehicle.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local noop = function() end

local playerOf = {}
local services = {
	Players = {GetPlayerFromCharacter = function(_,model) return playerOf[model] end},
	Teams = {FindFirstChild = noop},
	Debris = {AddItem = noop},
	ServerStorage = {FindFirstChild = noop},
	TweenService = {},
}
local game = {GetService = function(_,name) return services[name] end}

local function load(file,children)
	return luau.load(fs.readFile("Shared/"..file),{
		debugName = file,
		environment = {
			game = game,
			Color3 = roblox.Color3,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			script = {Parent = {WaitForChild = function(_,name) return children[name] end}},
			require = function(module) return module end,
			Instance = {new = function()
				return {Destroy = function(self) self.destroyed = true end}
			end},
		},
	})()
end

local sides = load("Sides.luau",{})
local kit = load("VehicleKit.luau",{Sides = sides})

--A model with a Settings.Team, under parent (a vehicle, or the world).
local function model(team,parent)
	local attributes = {}
	local m = {Parent = parent}
	--AttackPlayers as the spawner sets it: on for Hostile only.
	local settings = {Team = {Value = team}, AttackPlayers = {Value = team == "Hostile"}, FindFirstChild = function(self,name) return rawget(self,name) end}
	function m:FindFirstChild(name) return name == "Settings" and settings or nil end
	function m:GetAttribute(name) return attributes[name] end
	function m:SetAttribute(name,value) attributes[name] = value end
	function m:IsDescendantOf(other)
		local at = self.Parent
		while at do
			if at == other then return true end
			at = at.Parent
		end
		return false
	end
	return m
end

local function human(owner)
	local h = {Parent = owner, Health = 100}
	function h:TakeDamage(amount) self.Health = math.max(self.Health - amount,0) end
	return h
end

local tank = model("Hostile")
local hostile,friendly = model("Hostile"),model("Friendly")
local crewman = model("Friendly",tank)

assert(not kit.canHurt(tank,hostile,human(model("Hostile"))),"vehicle: hurt its own side")
assert(kit.canHurt(tank,hostile,human(friendly)),"vehicle: spared an enemy")
assert(not kit.canHurt(tank,hostile,human(crewman)),"vehicle: hurt its own crew")
assert(kit.canHurt(tank,nil,human(friendly)),"vehicle: a wreck going up spared someone")
assert(not kit.canHurt(tank,hostile,human(hostile)),"vehicle: the attacker hurt himself")

--A Friendly NPC (AttackPlayers off) spares a player; a Hostile one does not.
local player = {Team = nil, Neutral = true}
local playerModel = model("")
playerOf[playerModel] = player
assert(not kit.canHurt(tank,friendly,human(playerModel)),"vehicle: a Friendly crew hurt a player")
assert(kit.canHurt(tank,hostile,human(playerModel)),"vehicle: a Hostile crew spared a player")

--A kill bumps the counter; a wound does not.
local victim = human(friendly)
kit.hurt(tank,hostile,victim,40,"Roadkills")
assert(tank:GetAttribute("Roadkills") == nil,"vehicle: a wound counted as a kill")
kit.hurt(tank,hostile,victim,100,"Roadkills")
assert(tank:GetAttribute("Roadkills") == 1,"vehicle: a kill was not counted")

--Crew armour: direct Health damage is undone while seated, healing is kept, death
--still lands, and getting out takes the armour off.
local guard
local seated = human(model("Friendly"))
seated.HealthChanged = {Connect = function(_,callback)
	guard = callback
	return {Disconnect = function() guard = nil end}
end}
local function setHealth(value)
	seated.Health = value
	if guard then guard(value) end
end
kit.protect(seated)
assert(seated.Parent:GetAttribute("InVehicle") == true,"armour: InVehicle not set")
setHealth(60)
assert(seated.Health == 100,"armour: damage got through")
setHealth(0)
assert(seated.Health == 0,"armour: a wrecked vehicle's crew survived")
kit.unprotect(seated)
assert(seated.Parent:GetAttribute("InVehicle") == nil and guard == nil,"armour: still on after getting out")

print("vehicle: all checks pass")

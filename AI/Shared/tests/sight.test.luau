-- Checks soldiers' rays (CoreModule's core.cast, used for sight, shots and cover)
-- pass through what a body walks through, but never through a body, and blank teams.
-- Run from the AI folder:
--     lune run Shared/tests/sight.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3

local noop = function() end

local function part(name,canCollide,parent)
	return {Name = name, CanCollide = canCollide, Parent = parent, IsA = function() return false end}
end
local function holder(withHumanoid)
	return {FindFirstChild = function(_,name) return withHumanoid and name == "Humanoid" and {} or nil end,
		IsA = function() return false end}
end

--Parts along the ray in order; Raycast returns the first one not filtered out.
local along = {}
local casts = 0
local workspaceStub = {}
function workspaceStub:Raycast(_,_,params)
	casts += 1
	for _,hit in ipairs(along) do
		if not table.find(params.FilterDescendantsInstances,hit) then
			return {Instance = hit, Position = Vector3.zero}
		end
	end
	return nil
end

local function params()
	local p = {FilterDescendantsInstances = {"marine"}}
	function p:AddToFilter(instance)
		local list = table.clone(self.FilterDescendantsInstances)
		list[#list+1] = instance
		self.FilterDescendantsInstances = list
	end
	return p
end

local function value(v) return {Value = v} end
local team = value("Friendly")
local settings = {DetectionRange = value(100), Team = team, AttackPlayers = value(false)}
function settings:FindFirstChild(name) return rawget(self,name) end
local marine = {HumanoidRootPart = {Position = Vector3.zero}, Head = {Position = Vector3.zero},
	M4 = {Barrel = {}}, Settings = settings, AddTag = noop, FindFirstChildOfClass = noop}

local core = luau.load(fs.readFile("Bloxian/src/Scripts/Modules/CoreModule.luau"),{
	debugName = "CoreModule",
	environment = {
		workspace = workspaceStub,
		Vector3 = Vector3,
		RaycastParams = {new = params},
		game = {GetService = function(_,name)
			if name == "Players" then return {GetPlayerFromCharacter = noop} end
			local signal = {Connect = noop}
			return {FindFirstChild = noop, GetTagged = function() return {} end,
				GetInstanceAddedSignal = function() return signal end, GetInstanceRemovedSignal = function() return signal end}
		end},
		script = {Parent = {Parent = {Parent = marine}, Status = {get = noop}, WeaponProfiles = {current = {range = 100}}}},
		require = function(module) return module end,
	},
})()

local open = holder(false)
local leaf = part("Leaf",false,open)
local zone = part("CapturePoint",false,open)
local wall = part("Wall",true,open)
local limb = part("Left Leg",false,holder(true))

local p = params()
along = {leaf,zone,wall}
local hit = core.cast(Vector3.zero,Vector3.xAxis,p)
assert(hit and hit.Instance == wall,"sight: a leaf or a capture zone stopped the ray")
assert(#p.FilterDescendantsInstances == 1,"sight: the ray's filter was left changed")

along = {leaf,limb,wall}
hit = core.cast(Vector3.zero,Vector3.xAxis,p)
assert(hit and hit.Instance == limb,"sight: a ray passed through a body's non-solid limb")

along = {leaf,leaf,leaf,leaf,leaf,leaf}
casts = 0
core.cast(Vector3.zero,Vector3.xAxis,p)
assert(casts <= 5,"sight: a thicket made the ray loop "..casts.." times")

--Blank teams: a blank soldier and a Hostile one are on the same side.
local function soldier(teamName)
	local s = {Team = value(teamName)}
	function s:FindFirstChild(name) return rawget(self,name) end
	local model = {Name = "Bloxian", Settings = s}
	function model:FindFirstChild(name) return rawget(self,name) end
	return model
end
team.Value = ""
assert(core.isAlly(soldier("Hostile")),"teams: a blank soldier fought a Hostile one")
assert(not core.isAlly(soldier("Friendly")),"teams: a blank soldier sided with Friendly")
team.Value = "Friendly"
assert(core.isAlly(soldier("Friendly")),"teams: Friendly did not side with Friendly")

--Someone past his sight range is not seen, and costs no ray.
casts = 0
assert(not core.checkSight({Position = Vector3.new(500,0,0), Parent = {}}),"sight: saw past his range")
assert(casts == 0,"sight: cast a ray at someone out of range")

print("sight: all checks pass")

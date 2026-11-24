-- Checks a squad leader's plan moves on and never sticks, outside Studio:
-- react, then bound with the teams swapping, then fight; break when losing, rally after.
-- Run from the AI folder:
--     lune run Shared/tests/squad.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3,CFrame = roblox.Vector3,roblox.CFrame

local noop = function() end
--Any module function not listed does nothing and returns nothing.
local function stub(fields)
	return setmetatable(fields or {},{__index = function() return noop end})
end

local clock = 1000
local enemies = {}
local status = stub({})
local flags = {}
function status:get(name)
	if name == "potentialTargets" then return enemies end
	return flags[name]
end
function status:set(name,value)
	flags[name] = value
end

local function body(position)
	local model = {}
	local attributes = {}
	function model:GetAttribute(name) return attributes[name] end
	function model:SetAttribute(name,value) attributes[name] = value end
	local root = {Parent = model, Position = position, CFrame = CFrame.new(position), AssemblyLinearVelocity = Vector3.zero}
	model.HumanoidRootPart = root
	model.Humanoid = {Health = 100, MaxHealth = 100, Parent = model, WalkSpeed = 16}
	model.Settings = {Team = {Value = "Hostile"}, FindFirstChild = noop}
	return model,{root = root, human = model.Humanoid, team = model.Settings.Team, rank = 0}
end

local radio = {}
local marine,leaderEntry = body(Vector3.zero)
radio[marine] = leaderEntry
for i = 1,2 do
	local mate,entry = body(Vector3.new(i*5,0,0))
	radio[mate] = entry
end

local modules = {
	CoreModule = stub({checkDist = function(a,b) return (a.Position - b.Position).Magnitude end, isAlly = function() return false end}),
	Status = status,
	MovementModule = stub(),
	TacticsModule = stub({findCoverNear = function() return {} end}),
	ChatterModule = stub(),
	RadioModule = stub(),
	SpecialTeamModule = stub({detached = function() return false end}),
	SofModule = stub({kindOf = noop, kind = false, recon = false}),
	Troubleshoot = stub(),
	SpeedModule = stub(),
	Parent = {Parent = marine},
}

local squad = luau.load(fs.readFile("Bloxian/src/Scripts/Modules/SquadModule.luau"),{
	debugName = "SquadModule",
	environment = {
		_G = {BloxianRadio = radio},
		Vector3 = Vector3,
		CFrame = CFrame,
		os = {clock = function() return clock end},
		--No pincer, no coin flips.
		math = setmetatable({random = function() return 0.9 end},{__index = math}),
		script = {Parent = modules},
		require = function(module) return module end,
		task = {spawn = noop, wait = noop, delay = noop},
	},
})()
leaderEntry.rank = 1

local target = {Position = Vector3.new(0,0,-100), Parent = {}}
flags.currentTarget = target
enemies = {target}

local function tick(seconds)
	clock += seconds
	squad.update()
	return leaderEntry.plan
end

assert(tick(0).kind == "react","squad: contact did not start Battle Drill 1")
assert(tick(1).kind == "react","squad: left react before the squad was in cover")
local plan = tick(1)
assert(plan.kind == "bound","squad: no advance after react, got "..tostring(plan.kind))

--No team ever reports in (no cover anywhere): the leader still swaps them on his timeout.
local moving = plan.moving
local swapped = false
for _ = 1,10 do
	if tick(1).moving ~= moving then swapped = true break end
end
assert(swapped,"squad: the bounding teams never swapped")

--Bounding runs out: the squad fights rather than bounding forever.
for _ = 1,60 do
	if tick(1).kind ~= "bound" then break end
end
assert(leaderEntry.plan.kind == "fight","squad: bounding never ended, got "..leaderEntry.plan.kind)

--Outnumbered: break contact; enemy gone: rally, then back to nothing.
enemies = {target,target,target,target,target}
assert(tick(13).kind == "break","squad: outnumbered and still fighting")
flags.currentTarget = nil
assert(tick(1).kind == "rally","squad: no rally after breaking contact")
assert(tick(16) == nil,"squad: rally never ended")

print("squad: all checks pass")

-- Checks a soldier walks back out of a building with no path out, outside Studio.
-- Run from the AI folder:
--     lune run Shared/tests/nav.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3

local clock = 0
local loop
local roof,wall = false,false
local pathWorks = false
local moves = {}

local root = {Position = Vector3.zero}
function root:CanSetNetworkOwnership() return false end
local human = {Health = 100, FloorMaterial = "Grass", Parent = true}
function human:MoveTo(point) moves[#moves+1] = point end

local path = {Status = "NoPath"}
function path:ComputeAsync() self.Status = pathWorks and "Success" or "NoPath" end
function path:GetWaypoints() return {{Position = root.Position},{Position = Vector3.new(0,0,100)}} end

local status = {get = function() return nil end}
local core = {raycast = function(_,dir)
	if dir.Y > 0 then return roof end
	return wall
end}
local modules = {
	CoreModule = core,
	Status = status,
	Troubleshoot = {log = function() end, visualizePath = function() end},
}
modules.Parent = {Parent = {Parent = true, Humanoid = human, HumanoidRootPart = root}}

local movement = luau.load(fs.readFile("Bloxian/src/Scripts/Modules/MovementModule.luau"),{
	debugName = "MovementModule",
	environment = {
		_G = {},
		Vector3 = Vector3,
		os = {clock = function() return clock end},
		game = {GetService = function() return {CreatePath = function() return path end} end},
		script = {Parent = modules},
		require = function(module) return module end,
		task = {
			spawn = function(callback)
				if loop then
					callback()
				else
					loop = coroutine.create(callback)
				end
			end,
			wait = coroutine.yield,
		},
		Enum = {
			Material = {Air = "Air"},
			PathStatus = {Success = "Success"},
			PathWaypointAction = {Jump = "Jump", Walk = "Walk"},
		},
	},
})()

local function tick(position)
	clock += 0.05
	if position then root.Position = position end
	assert(coroutine.resume(loop))
end

--In through a door, then every path from inside fails.
pathWorks = true
movement.navigate(Vector3.new(0,0,60))
for z = 0,40,4 do
	roof = z > 20
	tick(Vector3.new(0,0,z))
end

wall,pathWorks = true,false
for _ = 1,20 do tick() end
assert(not movement.failed(),"he gave up instead of walking back")

--He walks his trail, nearest crumb first, and never heads further in.
local before = #moves
for z = 40,0,-4 do
	for _ = 1,3 do tick(Vector3.new(0,0,z)) end
end
assert(#moves > before,"he never moved")
local furthest = math.huge
for i = before+1,#moves do
	assert(moves[i].Z <= furthest + 0.01,"he turned back in")
	furthest = moves[i].Z
end
assert(furthest <= 8,"he did not make it back out: stopped at "..furthest)

--An outdoors goal with no path does not send him backward.
roof = false
for x = 0,40,4 do tick(Vector3.new(x,0,0)) end
movement.navigate(Vector3.new(500,0,0))
clock += 5
for _ = 1,10 do tick() end
assert(movement.failed(),"outdoors he should stand, not retrace")

--Indoors he knows the way out; outdoors he has nothing to do.
assert(not movement.getOut(),"sent outside while outside")
roof = true
assert(movement.getOut(),"no way outside from indoors")
print("nav: all checks pass")

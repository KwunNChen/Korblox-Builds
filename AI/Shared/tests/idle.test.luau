-- Checks a soldier doing nothing in a fight is caught, and one fighting is not, outside Studio.
-- Run from the AI folder:
--     lune run Shared/tests/idle.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3

local function fresh()
	return luau.load(fs.readFile("Bloxian/src/Scripts/Modules/IdleModule.luau"),{debugName = "IdleModule"})()
end

local here = Vector3.zero

--Standing still and silent: caught after 8 s, then the clock starts over.
local idle = fresh()
local caught = nil
for t = 0,20,0.5 do
	if idle.check(true,t,here,0) and not caught then caught = t end
end
assert(caught == 8,"idle: caught at "..tostring(caught))
assert(not idle.check(true,20.5,here,0),"idle: the clock did not start over")

--Firing every few seconds is fighting.
idle = fresh()
for t = 0,30,0.5 do
	assert(not idle.check(true,t,here,math.floor(t/5)),"idle: a soldier shooting was moved on")
end

--Walking is doing something; shuffling on the spot is not.
idle = fresh()
for t = 0,30,0.5 do
	assert(not idle.check(true,t,Vector3.new(t,0,0),0),"idle: a soldier walking was moved on")
end
idle = fresh()
caught = false
for t = 0,10,0.5 do
	caught = idle.check(true,t,Vector3.new(t%2,0,0),0) or caught
end
assert(caught,"idle: shuffling on the spot was taken for moving")

--Out of a fight the clock never runs.
idle = fresh()
for t = 0,30,0.5 do
	assert(not idle.check(false,t,here,0),"idle: moved on out of a fight")
end
assert(not idle.check(true,30.5,here,0),"idle: the clock ran while he was not fighting")
print("idle: all checks pass")

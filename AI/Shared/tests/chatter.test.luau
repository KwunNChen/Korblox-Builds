-- Checks the special operations lines (ChatterSof) cover every call and reply the
-- line soldiers' set has, pool for pool, so no spec ops soldier ever falls back to
-- a missing pool. Run from the AI folder:
--     lune run Shared/tests/chatter.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function load(name)
	return luau.load(fs.readFile("Bloxian/src/Scripts/Modules/"..name..".luau"),{debugName = name})()
end
local line,sof = load("ChatterLines"),load("ChatterSof")

local function nonEmptyStrings(list,where)
	assert(type(list) == "table" and #list > 0,"chatter: spec ops has no lines for "..where)
	for _,text in ipairs(list) do
		assert(type(text) == "string","chatter: spec ops line is not plain text in "..where)
	end
end

for _,section in ipairs({"calls","replies"}) do
	for kind,group in pairs(line[section]) do
		local mine = sof[section][kind]
		local where = section.."."..kind
		assert(mine ~= nil,"chatter: spec ops is missing "..where)
		if group[1] ~= nil then
			nonEmptyStrings(mine,where)
		else
			for pool in pairs(group) do
				nonEmptyStrings(mine[pool],where.."."..pool)
			end
		end
	end
end
assert(#sof.solo == 0,"chatter: spec ops mutters to himself")

print("chatter: all checks pass")

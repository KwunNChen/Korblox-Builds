-- Compiles every .luau file under the given folders and lists the ones that fail.
-- Run from the AI folder:
--     lune run Shared/tools/check.luau Bloxian/src
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failed = 0
local function walk(path)
	if fs.isDir(path) then
		for _,name in ipairs(fs.readDir(path)) do
			walk(path.."/"..name)
		end
	elseif path:match("%.luau$") then
		local ok,err = pcall(luau.compile,fs.readFile(path))
		if not ok then
			failed += 1
			print(path..": "..tostring(err))
		end
	end
end

for _,root in ipairs(process.args) do
	walk(root)
end
if failed > 0 then
	process.exit(1)
end
print("all compile")

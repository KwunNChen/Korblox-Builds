--Installs KorbloxAI.rbxm into an empty DataModel and checks what landed where.
--Run from this folder: lune run test-install.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local game = Instance.new("DataModel")
local starterPlayer = game:GetService("StarterPlayer")
Instance.new("StarterPlayerScripts").Parent = starterPlayer
local storage = game:GetService("ServerStorage")
local sss = game:GetService("ServerScriptService")

local function install()
	local package = roblox.deserializeModel(fs.readFile("KorbloxAI.rbxm"))[1]
	package.Parent = game:GetService("Workspace")
	local module = package:FindFirstChild("KorbloxInstall")
	local env = setmetatable({game = game, script = module},{__index = _G})
	env.print = function() end
	luau.load(module.Source,{environment = env})()()
	assert(game:GetService("Workspace"):FindFirstChild("KorbloxAI") == nil,"package left behind")
end

--A place that already has a Common folder keeps what else is in it.
local common = Instance.new("Folder")
common.Name = "Common"
common.Parent = sss
local mine = Instance.new("ModuleScript")
mine.Name = "Mine"
mine.Parent = common

install()
install()

local function need(root,path)
	local node = root
	for _,name in ipairs(path) do
		node = assert(node:FindFirstChild(name),table.concat(path,"/").." missing")
	end
	return node
end
--Everything the live-sync project lists has to install too.
local function walk(node,instance,path)
	for name,child in pairs(node) do
		if name:sub(1,1) ~= "$" then
			local found = assert(instance:FindFirstChild(name),path.."/"..name.." missing")
			walk(child,found,path.."/"..name)
		end
	end
end
local tree = serde.decode("json",fs.readFile("../../default.project.json")).tree
for service,node in pairs(tree) do
	if service:sub(1,1) ~= "$" then
		walk(node,game:GetService(service),service)
	end
end

need(sss,{"Common","CharacterCache"})
need(sss,{"Common","SpeedService"})
need(sss,{"Common","Mine"})
need(sss,{"Artillery","ImpactService"})
need(sss,{"BloxianSpawner","SpawnerKit"})
assert(#sss:GetChildren() == 4,"extra items in ServerScriptService")
print("install ok")

-- Distributes the packaged folders into the services the system expects,
-- then deletes itself. Runs once, on first server start after insertion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local package = script.Parent

local function ensureFolder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Merges rather than replaces: ServerScriptService.Common may already hold
-- another system's modules, and a name clash means the game already has its
-- own copy of that file.
local function moveChildren(source: Instance?, target: Instance)
	if not source then
		return
	end

	for _, child in source:GetChildren() do
		if target:FindFirstChild(child.Name) then
			warn(string.format(
				"[Snowstorm] %s already exists in %s -- keeping the existing one.",
				child.Name,
				target:GetFullName()
			))
			child:Destroy()
		else
			child.Parent = target
		end
	end
end

local function createStateHolder()
	if ReplicatedStorage:FindFirstChild("WeatherState") then
		return
	end

	local stateHolder = Instance.new("Configuration")
	stateHolder.Name = "WeatherState"
	stateHolder:SetAttribute("Intensity", 0)
	stateHolder:SetAttribute("Phase", "Clear")
	stateHolder:SetAttribute("WindX", 0)
	stateHolder:SetAttribute("WindZ", 0)
	stateHolder:SetAttribute("InstantCue", 0)
	stateHolder.Parent = ReplicatedStorage
end

-- Order matters. The packaged server scripts start running the moment the model
-- lands in ServerScriptService, and they block on WaitForChild until these
-- pieces exist, so shared code and state have to be published first.
createStateHolder()
moveChildren(package:FindFirstChild("Shared"), ensureFolder(ReplicatedStorage, "Weather"))
moveChildren(package:FindFirstChild("ServerCommon"), ensureFolder(ServerScriptService, "Common"))
moveChildren(
	package:FindFirstChild("Client"),
	ensureFolder(StarterPlayer:WaitForChild("StarterPlayerScripts"), "Weather")
)
moveChildren(package:FindFirstChild("Server"), ensureFolder(ServerScriptService, "Weather"))

print("[Snowstorm] Installed. Restart the playtest to run from the installed copy.")

package:Destroy()

--The server checks and helpers the Bloxian and Vehicle spawners share.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Teams = game:GetService("Teams")

--How far below a click ground is looked for (studs).
local GROUND_BELOW = 40

local kit = {}

function kit.finite(vector)
	return vector == vector and vector.Magnitude < 1e6
end

--Hostile, Friendly or a team in Teams.
function kit.validTeam(name)
	if name == "Hostile" or name == "Friendly" then
		return true
	end
	local team = Teams:FindFirstChild(name)
	return team ~= nil and team:IsA("Team")
end

function kit.holdsTool(player,toolName)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	return (backpack and backpack:FindFirstChild(toolName))
		or (character and character:FindFirstChild(toolName))
end

--Ground at position, looked for from headroom above it, seeing through players
--and everything tagged ignoreTag.
function kit.groundAt(position,ignoreTag,headroom)
	local ignore = CollectionService:GetTagged(ignoreTag)
	for _,player in ipairs(Players:GetPlayers()) do
		if player.Character then
			ignore[#ignore+1] = player.Character
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(position + Vector3.new(0,headroom,0),Vector3.new(0,-(headroom + GROUND_BELOW),0),params)
	return result and result.Position
end

function kit.setValue(settings,name,className,value)
	local holder = settings:FindFirstChild(name)
	if not holder then
		holder = Instance.new(className)
		holder.Name = name
		holder.Parent = settings
	end
	holder.Value = value
end

return kit

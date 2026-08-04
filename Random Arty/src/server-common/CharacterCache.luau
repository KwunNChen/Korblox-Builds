-- Cached HumanoidRootPart and Humanoid lookups, shared by the server systems.

local CharacterCache = {}

export type Entry = {
	character: Model,
	root: BasePart,
	humanoid: Humanoid,
}

local cache = setmetatable({}, { __mode = "k" })

function CharacterCache.get(player: Player): Entry?
	local character = player.Character
	if not character then
		return nil
	end

	local entry = cache[player]
	if entry and entry.character == character then
		return entry
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end

	entry = { character = character, root = root :: BasePart, humanoid = humanoid }
	cache[player] = entry
	return entry
end

function CharacterCache.getAlive(player: Player): Entry?
	local entry = CharacterCache.get(player)
	if entry and entry.humanoid.Health > 0 then
		return entry
	end
	return nil
end

return CharacterCache

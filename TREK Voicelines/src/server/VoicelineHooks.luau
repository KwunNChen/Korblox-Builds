--!strict
-- Adapters from TREK (and plain Roblox) events onto VoicelineService.request.
--
-- Nothing in here modifies TREK. Reload is a second listener on a RemoteEvent
-- TREK already owns, and everything else reads state TREK writes anyway.

local Players = game:GetService("Players")

local ServerScriptService = game:GetService("ServerScriptService")
local Service = require(ServerScriptService:WaitForChild("TREKVoicelines")
	:WaitForChild("VoicelineService"))

local Config = require(game:GetService("ReplicatedStorage")
	:WaitForChild("TREKVoicelines"):WaitForChild("VoicelineConfig"))

local Hooks = {}

-- Per-tool ammo bookkeeping, so LowAmmo can be judged against a real magazine
-- size rather than a guess.
type AmmoWatch = { capacity: number, last: number }

local function magCapacity(tool: Instance, mode: any): number?
	local funcs = (shared :: any).S and (shared :: any).S.trekServerFuncs
	if not funcs or not funcs.checkForModule then
		return nil
	end

	local ok, reqmod = pcall(funcs.checkForModule, tool)
	if not ok or type(reqmod) ~= "table" then
		return nil
	end

	local entry = reqmod[mode] or reqmod[tonumber(mode) :: any]
	if type(entry) == "table" and type(entry.MagCapacity) == "number" then
		return entry.MagCapacity
	end

	return nil
end

-- Watch one weapon's magazines. Fires LowAmmo on the shot that crosses the
-- threshold, which is race-free -- unlike reading ammo during a reload, where
-- TREK's own handler refills the magazine on the same event we are listening to.
local function watchTool(character: Model, tool: Instance)
	local ammo = tool:FindFirstChild("TAmmo")
	if not ammo then
		return
	end

	for _, modeFolder in ipairs(ammo:GetChildren()) do
		local counter = modeFolder:FindFirstChild("Ammo")
		if not counter or not counter:IsA("NumberValue") then
			continue
		end

		local watch: AmmoWatch = {
			capacity = magCapacity(tool, modeFolder.Name) or math.max(counter.Value, 1),
			last = counter.Value,
		}

		counter:GetPropertyChangedSignal("Value"):Connect(function()
			local value = counter.Value

			-- Capacity fallback: if we never got a real MagCapacity, the
			-- largest value we have ever seen is the best stand-in.
			if value > watch.capacity then
				watch.capacity = value
			end

			local dropped = value < watch.last
			watch.last = value

			if not dropped or watch.capacity <= 0 then
				return
			end

			if value > 0 and value / watch.capacity <= Config.LowAmmoFraction then
				Service.request(character, "LowAmmo")
			end
		end)
	end
end

-- Humanoids already bound, so the player path and the workspace scan can both
-- reach the same character without connecting twice.
local bound: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Bind one humanoid. `player` is nil for anything that is not a player's
	character -- an NPC, a dummy, an admin-spawned clone.

	Non-players get Hurt/Death of their own and, more to the point, can credit a
	Kill: whatever damaged them is read off the same WeaponTag TREK writes, so
	attribution does not depend on the victim being a player.
]]
local function onCharacter(player: Player?, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or bound[humanoid] then
		return
	end
	bound[humanoid] = true

	Service.reset(character)

	local lastHealth = humanoid.Health

	humanoid.HealthChanged:Connect(function(health: number)
		local delta = lastHealth - health
		lastHealth = health

		-- HealthChanged also fires on heals and on the respawn reset.
		if delta <= 0 then
			return
		end

		-- Death has its own line; a dying hit must not also say "ow".
		if health <= 0 then
			return
		end

		if delta < Config.HurtDamageThreshold then
			return
		end

		Service.request(character, "Hurt")
	end)

	humanoid.Died:Connect(function()
		-- TREK tags the victim's Humanoid with the killer for one second
		-- (LeaderBoardModule.tagPlr). Same tag its own kill feed reads.
		local tag = humanoid:FindFirstChild("WeaponTag")
		local killer = (tag and tag:IsA("ObjectValue")) and tag.Value or nil

		if Config.Debug then
			warn(string.format(
				"[TREKVoicelines] death: %s (player=%s) weaponTag=%s",
				character.Name,
				tostring(player and player.Name or "no"),
				tostring(killer and (killer :: any).Name or "none")
			))
		end

		Service.request(character, "Death")

		if not killer or not killer:IsA("Player") or killer == player then
			return
		end

		local killerCharacter = killer.Character
		if killerCharacter then
			Service.request(killerCharacter, "Kill")
		end
	end)

	-- Only players reload, so the ammo watcher is theirs alone.
	if not player then
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			watchTool(character, child)
		end
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			watchTool(character, child)
		end
	end)
end

-- Anything with a Humanoid that turns up in Workspace: NPCs, dummies, clones.
-- Workspace.ChildAdded rather than DescendantAdded on purpose -- characters are
-- parented to Workspace directly, and DescendantAdded fires for every bullet,
-- shell and effect part in a firefight.
local function tryBindModel(instance: Instance)
	if not Config.IncludeNPCs or not instance:IsA("Model") then
		return
	end

	task.spawn(function()
		local humanoid = instance:FindFirstChildOfClass("Humanoid")
			or instance:WaitForChild("Humanoid", 5)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end

		-- A player's own character arrives here too; resolve the owner so it is
		-- treated as a player, not an NPC.
		onCharacter(Players:GetPlayerFromCharacter(instance), instance)
	end)
end

local function onPlayer(player: Player)
	if player.Character then
		onCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
end

-- Characters whose reload was announced at the start, so the matching end-of-
-- reload signal can be ignored. Weak keys: a character that goes away takes its
-- entry with it.
local reloadAnnounced: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Longer than any sane ReloadSpeed. Only guards against a stamp left behind by a
-- reload that was interrupted (death mid-reload), so it never suppresses a real one.
local RELOAD_STAMP_TTL = 30

function Hooks.start()
	-- TREK's own handlers are on these same RemoteEvents; a RemoteEvent takes any
	-- number of listeners, so these add to them rather than replacing them. No
	-- TREK script is touched.
	local remotes = (shared :: any).S.TREK_Remotes

	-- Reload START. Gun fires GFX('Reload') at the top of reloadTypeOne, before
	-- the ReloadSpeed wait -- so this is the moment the player is actually
	-- vulnerable and "reloading!" is worth shouting. The Reload remote below is
	-- the wrong moment: Gun only fires it after the wait has finished, which on
	-- the KT-60 is six seconds late.
	remotes:WaitForChild("GFX").OnServerEvent:Connect(function(player: Player, kind: any)
		if kind ~= "Reload" then
			return
		end

		local character = player.Character
		if not character then
			return
		end

		reloadAnnounced[character] = os.clock()
		Service.request(character, "Reload")
	end)

	-- Reload END. Only used when no start signal arrived, which means a
	-- ReloadType 2 recharge weapon -- those trickle rounds in and never send
	-- GFX('Reload'), so finishing is the only moment there is to announce.
	remotes:WaitForChild("Reload").OnServerEvent:Connect(function(player: Player)
		local character = player.Character
		if not character then
			return
		end

		local announced = reloadAnnounced[character]
		reloadAnnounced[character] = nil

		if announced and os.clock() - announced < RELOAD_STAMP_TTL then
			return
		end

		Service.request(character, "Reload")
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end

	-- NPCs, dummies and admin-spawned clones. Guarded by `bound`, so a player
	-- character picked up here is not connected a second time.
	if Config.IncludeNPCs then
		workspace.ChildAdded:Connect(tryBindModel)
		for _, child in ipairs(workspace:GetChildren()) do
			tryBindModel(child)
		end
	end
end

return Hooks

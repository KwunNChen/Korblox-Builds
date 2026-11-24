-- Kills every enemy (boss squad too) and skips the rest of the wave.
local function wipe()
	wipeWave = true
	for _, m in CollectionService:GetTagged(ENEMY_TAG) do
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = 0 end
	end
end

local ADMIN_PASSWORD = "<REDACTED>"
-- matches a boss id case-insensitively and queues it; returns (id or nil, "A, B, C")
local function queueBoss(want)
	local names = {}
	for id in Bosses do
		table.insert(names, id)
		if want and id:lower() == want:lower() then
			forcedBoss = id
			return id, ""
		end
	end
	return nil, table.concat(names, ", ")
end
-- Admin console (StarterPlayerScripts.AdminConsole): "/admin <password>" in chat opens it (a TextChatCommand, so
-- the line never reaches chat and nobody sees the password). The client sends each typed line, the server runs it
-- and returns the text to print. Only players who opened it with the password can run commands.
local consoleAuthed, consoleFails = {}, {}
-- the console's autofill and hints read this list ("?spec"); args = what the command takes after its name
local CONSOLE_COMMANDS = {
	{ name = "help", args = "", desc = "list commands" },
	{ name = "wipe", args = "", desc = "kill every enemy, skip the rest of the wave" },
	{ name = "boss", args = "<name | clear>", desc = "next floor fights that boss (this floor during GET READY)" },
	{ name = "map", args = "<name | clear>", desc = "next floor built uses that map (no run: rebuilds floor 1 now)" },
	{ name = "status", args = "", desc = "run state, queued boss and map" },
	{ name = "close", args = "", desc = "hide the console (/admin <password> reopens it)" },
}
local helpLines = {}
for _, c in CONSOLE_COMMANDS do
	table.insert(helpLines, string.format("%-20s %s", c.name .. (if c.args ~= "" then " " .. c.args else ""), c.desc))
end
local CONSOLE_HELP = table.concat(helpLines, "\n")
local consoleRemote = Instance.new("RemoteFunction")
consoleRemote.Name = "AdminConsole"
consoleRemote.Parent = ReplicatedStorage
consoleRemote.OnServerInvoke = function(p, line)
	if type(line) ~= "string" or #line > 200 then return "bad input" end
	local cmd, arg = line:lower():match("^%s*(%S+)%s*(%S*)")
	if not cmd then return "" end
	if not consoleAuthed[p] then return "locked: open the console with /admin <password>" end
	if cmd == "?spec" then
		local bosses = {}
		for id in Bosses do table.insert(bosses, id) end
		table.sort(bosses)
		table.insert(bosses, "clear")
		local maps = {}
		for _, f in floorsFolder:GetChildren() do table.insert(maps, f.Name) end
		table.sort(maps)
		table.insert(maps, "clear")
		return { commands = CONSOLE_COMMANDS, args = { boss = bosses, map = maps } } -- args: command -> values it takes
	end
	if cmd == "help" then return CONSOLE_HELP end
	if cmd == "wipe" then
		wipe()
		print("TowerRun: console wipe by " .. p.Name)
		return "wave wiped"
	elseif cmd == "boss" then
		if arg == "clear" then forcedBoss = nil return "queued boss cleared" end
		local id, names = queueBoss(if arg ~= "" then arg else nil)
		if id then
			print("TowerRun: " .. p.Name .. " queued boss " .. id .. " for the next floor")
			return id .. " queued for the next floor"
		end
		return (if arg ~= "" then "no boss '" .. arg .. "'. " else "") .. "bosses: " .. names
	elseif cmd == "map" then
		if arg == "clear" then forcedMap = nil return "queued map cleared" end
		local names, found = {}, nil
		for _, f in floorsFolder:GetChildren() do
			table.insert(names, f.Name)
			if f.Name:lower() == arg then found = f.Name end
		end
		table.sort(names)
		if not found then
			return (if arg ~= "" then "no map '" .. arg .. "'. " else "") .. "maps: " .. table.concat(names, ", ")
		end
		forcedMap = found
		print("TowerRun: " .. p.Name .. " queued map " .. found)
		if not running then
			-- floor 1 is already waiting in the lobby: swap it now so the next run starts on this map
			local old = floors[1]
			floors[1] = nil
			task.spawn(function()
				if old then scrap(built(old)) end
				if not running and not floors[1] then buildFloor(1) end
			end)
			return "floor 1 rebuilding as " .. found
		end
		if floors[floorN + 1] then return found .. " queued: floor " .. (floorN + 1) .. " is already built, so it'll be floor " .. (floorN + 2) end
		return found .. " queued for the next floor"
	elseif cmd == "status" then
		return (if running then "run active, floor " .. floorN else "no run") .. "\nqueued boss: " .. (forcedBoss or "none")
			.. "\nqueued map: " .. (forcedMap or "none")
	end
	return "unknown command '" .. cmd .. "' (type help)"
end
local consoleOpen = Instance.new("RemoteEvent")
consoleOpen.Name = "AdminConsoleOpen" -- server -> client: show the console
consoleOpen.Parent = ReplicatedStorage
do
	local TextChatService = game:GetService("TextChatService")
	local folder = TextChatService:FindFirstChild("TextChatCommands") or Instance.new("Folder")
	folder.Name = "TextChatCommands"
	folder.Parent = TextChatService
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "AdminConsole"
	cmd.PrimaryAlias = "/admin"
	cmd.Parent = folder
	cmd.Triggered:Connect(function(source, text)
		local p = Players:GetPlayerByUserId(source.UserId)
		if not p then return end
		if (consoleFails[p] or 0) >= 5 then return end -- too many wrong passwords this session
		if text:match("^%S+%s+(%S+)%s*$") == ADMIN_PASSWORD then
			consoleAuthed[p] = true
			consoleOpen:FireClient(p)
		else
			consoleFails[p] = (consoleFails[p] or 0) + 1
			warn("TowerRun: wrong /admin password from " .. p.Name)
		end
	end)
end

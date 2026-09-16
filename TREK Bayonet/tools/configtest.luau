--[[
	Headless checks on the weapon config's bayonet block.

		lune run tools/configtest.luau

	Run after editing BayonetWeaponMode or the merged weapon module.

	Every assertion below corresponds to a line in TREK or in TREK Custom Bullets
	that reads a field WITHOUT a nil check and throws, or silently does something
	worse. They are not style preferences -- each one is a crash or a corrupted
	value that would otherwise be found by a player.
]]

local process = require("@lune/process")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector3, Color3 = roblox.Vector3, roblox.Color3

-- Enough of the Roblox globals for a weapon config to load.
local env = {
	workspace = { Gravity = 196.2 },
	Vector3 = Vector3,
	Color3 = Color3,
	CFrame = roblox.CFrame,
	math = math,
	table = table,
	string = string,
	ipairs = ipairs,
	pairs = pairs,
	print = print,
	tostring = tostring,
	tonumber = tonumber,
	typeof = typeof,
	type = type,
}
env._G = env

local function load(path: string)
	return luau.load(luau.compile(fs.readFile(path)), { environment = env })()
end

local failures = 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		print("  pass  " .. name)
	else
		failures += 1
		print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
	end
end

local INDEX = 2

--[[
	Read without a nil check by TREK's own modules, at damage time:

		TREKDamageModule:14   if distance < config.fallOffStart
		TREKDamageModule:57   result *= config.headShotMultiplier
		TREKGibsModule:126    if rnd > mod.limbRemovalChance

	A missing one does not degrade the bayonet -- it throws mid-swing, after the
	damage path has already started.
]]
local REQUIRED_NUMBERS = {
	"Damage",
	"headShotMultiplier",
	"ArmourDamage",
	"limbRemovalChance",
	"fallOffStart",
	"fallOffEnd",
	"RoundsPerMinute",
}

local function checkBlock(label: string, block: any)
	print("")
	print(label)

	if type(block) ~= "table" then
		check("the [" .. INDEX .. "] block exists", false, "got " .. typeof(block))
		return
	end

	check("BulletType is exactly \"Bayonet\"", block.BulletType == "Bayonet",
		"got " .. tostring(block.BulletType) .. " -- a name the handler cannot resolve "
			.. "aborts EVERY weapon in the place")

	for _, field in ipairs(REQUIRED_NUMBERS) do
		check(field .. " is a number", type(block[field]) == "number",
			"got " .. tostring(block[field]))
	end

	-- shoot() does `tool.LocalTAmmo[mode].Ammo.Value -= 1` unconditionally, and
	-- createAmmoStore skips any block with a falsy MagCapacity -- so omitting it
	-- means the store has no entry and every swing errors.
	check("MagCapacity is truthy", block.MagCapacity and true or false,
		"a melee mode still goes through the ammo path")
	check("MagCapacity is infinite", block.MagCapacity == math.huge,
		"anything finite runs dry and diverts the swing into Reload")
	check("MagCapacity is a number, not 'INF'", type(block.MagCapacity) == "number",
		"the client assigns it to a DoubleConstrainedValue, which rejects strings")
	check("ReservedAmmo is a number, not 'INF'", type(block.ReservedAmmo) == "number",
		"same reason")

	-- ReservedAmmo = math.huge misses TREK's 'INF' early return in handleReload,
	-- where inf - inf = NaN is then written into the ammo values.
	check("CanReload is false", block.CanReload == false,
		"reloading this mode writes NaN into its ammo")

	-- useSharedClip would point the decrement at mode 1's magazine, so swinging
	-- would eat rifle rounds.
	check("useSharedClip is false", block.useSharedClip == false,
		"swinging would drain the rifle's clip")

	check("RoundsPerMinute is above zero", (tonumber(block.RoundsPerMinute) or 0) > 0,
		"the server refuses the swing and divides nothing")

	--[[
		Fields VANILLA TREK dereferences for every mode at LOAD:

			Gun.client.luau:130
			modeStuff[name].fastCastBehavior.CosmeticBulletTemplate =
				shared.S.TREK_EffectsStorage.ProjectileTypes[tabl.ProjectileName]

		Indexing that Instance with nil throws, and it happens while the handler
		is still setting up -- so the whole WEAPON stops working, not just this
		mode. A bayonet fires no projectiles and Custom Bullets never reads any
		of this, which is exactly why it got dropped once and bricked the KR-61.

		They stay so that a half-finished install degrades instead of breaking.
	]]
	for _, field in ipairs({ "ProjectileName", "RayType" }) do
		check(field .. " exists (vanilla dereferences it at load)", block[field] ~= nil,
			"nil here breaks the entire weapon under the vanilla handler")
	end
	check("ProjectileAcceleration exists (vanilla assigns it at load)",
		typeof(block.ProjectileAcceleration) == "Vector3",
		"got " .. typeof(block.ProjectileAcceleration))
end

print("paste-in snippet: src/package/BayonetWeaponMode.luau")
local snippet = load("src/package/BayonetWeaponMode.luau")
checkBlock("  [" .. INDEX .. "] in the snippet", snippet[INDEX])

print("")
print("merged weapon module: weapon/KR-61 Bonecrusher (with bayonet).luau")
local weapon = load("weapon/KR-61 Bonecrusher (with bayonet).luau")
checkBlock("  [" .. INDEX .. "] in the KR-61", weapon[INDEX])

print("")
print("  the rest of the weapon")
do
	-- Every mode needs a name the handler can resolve, not just ours. A leftover
	-- numeric BulletType from vanilla TREK is the likeliest way to take the
	-- whole handler down.
	for key, block in pairs(weapon) do
		if type(block) == "table" then
			check(
				string.format("[%s] BulletType is a name, not a number", tostring(key)),
				type(block.BulletType) == "string",
				"got " .. typeof(block.BulletType) .. " " .. tostring(block.BulletType)
			)
		end
	end

	-- The mode has to be reachable by incrementing from 1, or V never gets to it.
	local reachable = true
	for i = 1, INDEX do
		if type(weapon[i]) ~= "table" then
			reachable = false
		end
	end
	check("every index from 1 to " .. INDEX .. " is filled, so V can reach it", reachable,
		"switchModes walks by increment and stops at the first gap")
end

--[[
	Every Config field the code READS must be one the config DEFINES.

	This exists because BayonetConfig was rewritten during the fire-mode rework
	and MissAnnounceAfter was dropped while BayonetService still read it. The
	result was

		BayonetService:783: attempt to compare nil < number

	at startup -- the service died before creating its remote, so the bayonet was
	simply absent, with one line in a log full of unrelated TREK asset warnings.

	A static scan catches it in a second and needs no Roblox at all.
]]
print("")
print("config fields: read vs defined")
do
	local defined = {}
	for field in fs.readFile("src/shared/BayonetConfig.luau"):gmatch("[\n]Config%.([A-Za-z]+)%s*=") do
		defined[field] = true
	end

	local readers = {
		"src/BayonetService.server.luau",
		"src/Bayonet.luau",
	}

	local missing = {}
	for _, path in ipairs(readers) do
		local source = fs.readFile(path)
		for field in source:gmatch("Config%.([A-Za-z]+)") do
			-- Skip the ones that only appear inside prose, by requiring the read
			-- to look like a value use rather than a word in a sentence.
			if not defined[field] and not missing[field] then
				missing[field] = path
			end
		end
	end

	local count = 0
	for field, path in pairs(missing) do
		count += 1
		check("Config." .. field .. " is defined", false, "read by " .. path)
	end
	if count == 0 then
		check("every Config field read by the code is defined", true)
	end
end

print("")
if failures == 0 then
	print("all config checks passed")
else
	print(failures .. " FAILED")
	process.exit(1)
end

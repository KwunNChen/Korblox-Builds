--[[
	TREK BAYONET -- INSTALL CHECKER AND FIXER

	NOT a lune script. Paste it into the Studio COMMAND BAR.

	Run it in EDIT MODE to check what is placed in the saved game, or during a
	PLAYTEST to check what TREK actually built. Both are worth doing: several
	things live in one and not the other.

	Set FIX = true to create the pieces it can create safely (2Barrel, 2Fire).
	It never touches TREK, never deletes a weapon config, and never writes into
	ReplicatedStorage.TREK_SERVICES -- see the note on that below.

	Every check corresponds to something that has actually gone wrong, and to a
	failure mode that is silent or misleading in game.
]]

local FIX = false

--[[
	The weapon to check. Both are place-specific and neither can be guessed:

	  * The installer's instance name may carry a TRAILING SPACE. It does in the
	    place this was written for ("Installer "), which is invisible in the
	    Explorer and breaks every FindFirstChild that assumes otherwise. This
	    script matches on the prefix instead so either spelling works.

	  * The weapon's name is matched exactly, because looser matching has twice
	    written configuration into the wrong module -- once by taking the last
	    name match in Workspace, once by matching a known Idle animation id that
	    the KT-60 happens to share.
]]
local WEAPON_NAME = 'KR-61 "Bonecrusher"'

local BAYONET_MODE = 2

local passes, failures, notes = 0, 0, 0

local function pass(what: string)
	passes += 1
	print("  ok    " .. what)
end

local function fail(what: string, why: string)
	failures += 1
	print("  FAIL  " .. what .. "  --  " .. why)
end

local function note(what: string)
	notes += 1
	print("  note  " .. what)
end

print("")
print("=== TREK BAYONET INSTALL CHECK ===")

--------------------------------------------------------------------------------
print("")
print("the installer")
--------------------------------------------------------------------------------

local installer
for _, c in ipairs(workspace:GetChildren()) do
	if c.Name:sub(1, 9) == "Installer" then
		installer = c
	end
end

if installer then
	pass("found " .. installer:GetFullName())
	if installer.Name ~= "Installer" then
		note("its name is " .. string.format("%q", installer.Name)
			.. " -- if you use the Rojo project, that exact string must appear in "
			.. "default.project.json under Workspace")
	end
else
	fail("Workspace installer", "no child of Workspace whose name starts with 'Installer'")
end

local plugins = installer and installer:FindFirstChild("Plugins")
if plugins then
	pass("Plugins folder")
else
	fail("Plugins folder", "TREK plugins live here; without it the pack cannot be merged")
end

--------------------------------------------------------------------------------
print("")
print("TREK Custom Bullets")
--------------------------------------------------------------------------------

--[[
	Looked for in TWO places on purpose.

	In EDIT MODE the pack sits in the plugin, waiting to be merged. During a
	PLAYTEST the installer has copied it into the live TREK_SERVICES. Checking
	only one of them gives a confident answer that is wrong half the time.
]]
local function findModules(): Instance?
	local live = game:GetService("ReplicatedStorage"):FindFirstChild("TREK_SERVICES")
	live = live and live:FindFirstChild("TREK_Modules")
	if live and live:FindFirstChild("BulletTypes") then
		return live
	end

	if plugins then
		for _, d in ipairs(plugins:GetDescendants()) do
			if d.Name == "TREK_Modules" and d:FindFirstChild("BulletTypes") then
				return d
			end
		end
	end

	return live
end

local modules = findModules()
if modules then
	pass("TREK_Modules at " .. modules:GetFullName())
else
	fail("TREK_Modules", "neither the plugin nor the live services carry one")
end

local bulletTypes = modules and modules:FindFirstChild("BulletTypes")
if bulletTypes then
	local names = {}
	for _, m in ipairs(bulletTypes:GetChildren()) do
		table.insert(names, m.Name)
	end
	table.sort(names)
	pass("BulletTypes: " .. table.concat(names, ", "))

	if bulletTypes:FindFirstChild("Bayonet") then
		pass("Bayonet bullet type is beside the others")
	else
		fail("Bayonet bullet type", "it must sit next to Hitscan/Projectile/Melee, or "
			.. "BulletType = 'Bayonet' resolves to nil and aborts the WHOLE gun handler")
	end
else
	fail("BulletTypes folder", "Custom Bullets is not installed")
end

if modules and modules:FindFirstChild("BulletModule") then
	pass("BulletModule")
else
	fail("BulletModule", "the handler requires this to resolve any BulletType at all")
end

--------------------------------------------------------------------------------
print("")
print("the gun handler")
--------------------------------------------------------------------------------

local handlers = game:GetService("ServerStorage"):FindFirstChild("TREKToolHandlers")
local gun = handlers and handlers:FindFirstChild("Gun")

if gun and gun:IsA("LuaSourceContainer") then
	pass("ServerStorage.TREKToolHandlers.Gun exists")
	if gun.Source:find("bulletTypes%[config") then
		pass("it is the Custom Bullets handler")
	else
		fail("Gun handler version", "this is the vanilla handler -- it ignores BulletType "
			.. "names, so the bayonet mode will fire bullets instead of swinging")
	end
else
	fail("ServerStorage.TREKToolHandlers.Gun", "this is PLACE CONTENT that the installer "
		.. "does not recreate. Without it no script handles the Tool and guns stop equipping")
end

--------------------------------------------------------------------------------
print("")
print("the bayonet package")
--------------------------------------------------------------------------------

local pkg = game:GetService("ReplicatedStorage"):FindFirstChild("TREKBayonet")
if pkg then
	pass("ReplicatedStorage.TREKBayonet")
	for _, n in ipairs({ "BayonetConfig", "BayonetGeometry" }) do
		if pkg:FindFirstChild(n) then
			pass("  " .. n)
		else
			fail("  " .. n, "missing from the package folder")
		end
	end
	if pkg:FindFirstChild("BayonetStab") then
		pass("  BayonetStab remote (the service has run)")
	else
		note("  BayonetStab remote absent -- expected in edit mode; in a playtest it "
			.. "means BayonetService did not finish")
	end
else
	fail("ReplicatedStorage.TREKBayonet", "the shared half of the package is not installed")
end

local svc = game:GetService("ServerScriptService"):FindFirstChild("TREKBayonet")
if svc and svc:FindFirstChild("BayonetService") then
	pass("ServerScriptService.TREKBayonet.BayonetService")
else
	fail("BayonetService", "the server half is not installed; nothing will take damage")
end

--[[
	That folder used to be pure legacy. It is not any more: WeaponPosePriority
	lives there, and without it every weapon sprint pose blends 50/50 with
	TREK's global Run -- both sit at Movement priority -- and the weapon reads
	as dropped while sprinting. So check the CONTENTS, not the folder.
]]
local starter = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local clientFolder = starter and starter:FindFirstChild("TREKBayonet")

if clientFolder and clientFolder:FindFirstChild("WeaponPosePriority") then
	pass("StarterPlayerScripts.TREKBayonet.WeaponPosePriority")
else
	fail("WeaponPosePriority", "weapon sprint poses are authored at Movement, the same "
		.. "priority as TREK's Run, so the two average together and the weapon looks "
		.. "dropped while sprinting")
end

if clientFolder and clientFolder:FindFirstChild("BayonetController") then
	fail("stale BayonetController", "left over from the old G-key build. "
		.. "It errors every spawn. Delete it -- the client half is a bullet type now")
end

--------------------------------------------------------------------------------
print("")
print("the weapon: " .. WEAPON_NAME)
--------------------------------------------------------------------------------

local gunConfigs
if installer then
	gunConfigs = installer:FindFirstChild("GunConfigs")
end
if not gunConfigs then
	local live = game:GetService("ReplicatedStorage"):FindFirstChild("TREK_SERVICES")
	gunConfigs = live and live:FindFirstChild("GunConfigs")
end

local weapon = gunConfigs and gunConfigs:FindFirstChild(WEAPON_NAME)

if not weapon then
	fail("weapon config", "no module named " .. WEAPON_NAME
		.. (gunConfigs and (" in " .. gunConfigs:GetFullName()) or " (no GunConfigs found)"))
	if gunConfigs then
		print("        weapons present:")
		for _, c in ipairs(gunConfigs:GetChildren()) do
			print("          " .. c.Name)
		end
	end
else
	pass("config module at " .. weapon:GetFullName())

	local ok, conf = pcall(require, weapon)
	if not ok or type(conf) ~= "table" then
		fail("config loads", tostring(conf))
	else
		local block = conf[BAYONET_MODE]
		if not block then
			fail("[" .. BAYONET_MODE .. "] block", "paste BayonetWeaponMode in, then RESTART "
				.. "the playtest -- SetUpGuns caches weapon modules at server start")
		else
			pass("[" .. BAYONET_MODE .. "] block present")

			if block.BulletType == "Bayonet" then
				pass("  BulletType = 'Bayonet'")
			else
				fail("  BulletType", "is " .. tostring(block.BulletType) .. ", must be 'Bayonet'")
			end

			if block.MagCapacity == math.huge then
				pass("  MagCapacity = math.huge")
			else
				fail("  MagCapacity", "must be math.huge -- shoot() decrements ammo "
					.. "unconditionally, so anything else eventually blocks the swing")
			end

			if block.CanReload == false then
				pass("  CanReload = false")
			else
				fail("  CanReload", "must be false, or reloading writes NaN into the ammo")
			end

			for _, field in ipairs({ "Damage", "headShotMultiplier", "ArmourDamage",
				"limbRemovalChance", "fallOffStart", "fallOffEnd", "RoundsPerMinute",
				"ProjectileName", "RayType" }) do
				if block[field] == nil then
					fail("  " .. field, "read without a nil check by TREK; missing throws at "
						.. "damage or load time")
				end
			end
		end

		-- Every mode of every weapon, because one bad name kills the handler.
		for key, modeBlock in pairs(conf) do
			if type(modeBlock) == "table" and type(modeBlock.BulletType) ~= "string" then
				fail("[" .. tostring(key) .. "] BulletType",
					"is " .. typeof(modeBlock.BulletType) .. ", must be a NAME like 'Hitscan'. "
						.. "A number resolves to nil and aborts the handler for EVERY weapon")
			end
		end
	end

	-- Animations live on the config module, keyed by mode prefix.
	local animFolder = weapon:FindFirstChild("Animations")
	if animFolder then
		for _, n in ipairs({ tostring(BAYONET_MODE) .. "Recoil", tostring(BAYONET_MODE) .. "Idle" }) do
			local a = animFolder:FindFirstChild(n)
			if a and a:IsA("Animation") and a.AnimationId ~= "" then
				pass("  " .. n .. " = " .. a.AnimationId)
			else
				note("  " .. n .. " missing -- the swing works, it just plays the rifle's pose. "
					.. "See tools/WeaponAnimations.luau")
			end
		end
	else
		fail("  Animations folder", "the weapon module has none")
	end
end

--------------------------------------------------------------------------------
print("")
print("the weapon Tool")
--------------------------------------------------------------------------------

local tool
for _, place in ipairs({ workspace, game:GetService("ServerStorage"),
	game:GetService("ReplicatedStorage"), game:GetService("StarterPack") }) do
	for _, d in ipairs(place:GetDescendants()) do
		if d:IsA("Tool") and d.Name == WEAPON_NAME then
			tool = tool or d
		end
	end
end

if not tool then
	fail("Tool", "no Tool named " .. WEAPON_NAME .. " found to check")
else
	pass("Tool at " .. tool:GetFullName())

	if tool:FindFirstChild("Bayonet", true) then
		pass("  a Bayonet part is inside it (this IS the hitbox)")
	else
		fail("  Bayonet part", "nothing named 'Bayonet' anywhere in the Tool, so the "
			.. "server refuses every swing")
	end

	local barrelName = tostring(BAYONET_MODE) .. "Barrel"
	local barrel = tool:FindFirstChild(barrelName)

	if barrel then
		local emitters = 0
		for _, d in ipairs(barrel:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		if emitters == 0 then
			pass("  " .. barrelName .. " with no ParticleEmitters")
		else
			fail("  " .. barrelName, emitters .. " ParticleEmitter(s) on it -- every swing "
				.. "will muzzle flash")
		end
	elseif FIX then
		local anchor = tool:FindFirstChild("Barrel") or tool:FindFirstChild("Handle")
			or tool:FindFirstChildWhichIsA("BasePart")
		if anchor then
			local part = Instance.new("Part")
			part.Name = barrelName
			part.Size = Vector3.new(0.2, 0.2, 0.2)
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
			part.CFrame = anchor.CFrame
			part.Parent = tool

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = anchor
			weld.Parent = part

			pass("  created " .. barrelName .. ", welded to " .. anchor.Name)
		else
			fail("  " .. barrelName, "no part in the Tool to weld a new one to")
		end
	else
		fail("  " .. barrelName, "without it the swing borrows the rifle's muzzle and "
			.. "fires a muzzle flash. Set FIX = true to create one")
	end
end

if weapon and not weapon:FindFirstChild(tostring(BAYONET_MODE) .. "Fire") then
	if FIX then
		local s = Instance.new("Sound")
		s.Name = tostring(BAYONET_MODE) .. "Fire"
		s.Parent = weapon
		pass("  created a silent " .. s.Name .. " (give it a stab SoundId when you have one)")
	else
		note("  no " .. tostring(BAYONET_MODE) .. "Fire sound -- other players hear the "
			.. "rifle's gunshot on a swing. Set FIX = true to add a silent one")
	end
end

--------------------------------------------------------------------------------
print("")
print(string.format("=== %d ok, %d failed, %d notes ===", passes, failures, notes))
if failures == 0 then
	print("nothing blocking. If the swing still does nothing, set BayonetConfig.Debug = true")
	print("and swing once -- every outcome reports itself.")
else
	print("fix the FAIL lines above, SAVE, then restart the playtest.")
end

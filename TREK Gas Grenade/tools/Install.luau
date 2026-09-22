--[[
	INSTALL

	Command-bar script. Paste it into Studio with TREKGasGrenade.rbxm sitting in
	ServerStorage, in EDIT mode, not a playtest.

	It moves everything out of the staging folder into the real services, and --
	the part that matters -- deletes any previous install at each destination
	first.

	This exists because installing by hand stopped being safe. The package now
	lands in five places, and it has grown by one destination in most builds.
	Moving the new folders in alongside the old ones leaves two folders with the
	same name, Roblox runs both, and the stale copy fails on a module it has
	never heard of:

		ServerScriptService.TREKGasGrenade has no child "GasExposure"

	which looks like a broken package rather than a half-finished install. The
	only reliable fix is to replace wholesale rather than merge, so that is what
	this does.

	Safe to run repeatedly. Running it on an already-correct install just
	replaces everything with itself.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local STAGING_NAME = "TREKGasGrenade"

local problems = 0

local function say(...)
	print("[GasInstall]", ...)
end

local function fail(...)
	problems += 1
	warn("[GasInstall]", ...)
end

--[[
	Find the staging folder specifically, not the models folder.

	Both are called TREKGasGrenade and both live in ServerStorage. The staging
	one is the only one carrying a "ReplicatedStorage" signpost child, which is
	what tells them apart -- and getting this wrong would move the grenade
	meshes into ReplicatedStorage and leave the real package untouched.
]]
local function findStaging(): Folder?
	for _, child in ipairs(ServerStorage:GetChildren()) do
		if child.Name == STAGING_NAME and child:FindFirstChild("ReplicatedStorage") then
			return child :: Folder
		end
	end
	return nil
end

--[[
	Where the weapon configs live.

	Searched for rather than assumed. In a saved place they hang off the
	Installer script in Workspace; the installer relocates them at runtime, and
	people do move them. Whatever holds the existing weapons is the right
	parent, so the grenade config lands beside them.
]]
local function findGunConfigs(): Instance?
	for _, root in ipairs({ workspace, ServerStorage, ReplicatedStorage, Lighting }) do
		local found = root:FindFirstChild("GunConfigs", true)
		if found then
			return found
		end
	end
	return nil
end

--[[
	Replace, never merge.

	Every same-named child at the destination is destroyed before the new one
	arrives. Merging is exactly what produced the two-folder state this script
	exists to clean up.
]]
local function install(item: Instance, destination: Instance): boolean
	local removed = 0

	for _, existing in ipairs(destination:GetChildren()) do
		if existing.Name == item.Name and existing ~= item then
			existing:Destroy()
			removed += 1
		end
	end

	item.Parent = destination

	say(string.format(
		"  %-16s -> %s%s",
		item.Name,
		destination:GetFullName(),
		removed > 0 and string.format("   (replaced %d)", removed) or ""
	))

	return true
end

-- ---------------------------------------------------------------------------

say("================================================")

local staging = findStaging()

if not staging then
	fail(
		"No staging folder found. Drag TREKGasGrenade.rbxm into ServerStorage first. "
			.. "(The staging folder is the one containing a ReplicatedStorage signpost, "
			.. "not the folder holding your grenade models.)"
	)
	return
end

say("staging folder:", staging:GetFullName())

--[[
	The destinations, in the order the README lists them.

	`merge` marks the one case where the destination folder is TREK's own and
	must be kept -- only the Throwable inside it is ours to replace. Everything
	else is a folder this package owns end to end.
]]
local PLAN = {
	{ signpost = "ReplicatedStorage", item = "TREKGasGrenade", into = ReplicatedStorage },
	{ signpost = "ServerScriptService", item = "TREKGasGrenade", into = ServerScriptService },
	{ signpost = "ServerStorage", item = "Throwable", inside = "TREKToolHandlers", merge = true },
	{ signpost = "GunConfigs", item = "Gas Grenade", into = nil },
	{ signpost = "StarterPlayerScripts", item = "TREKGasGrenade", into = StarterPlayer:FindFirstChild("StarterPlayerScripts") },
}

for _, step in ipairs(PLAN) do
	local signpost = staging:FindFirstChild(step.signpost)

	if not signpost then
		fail(string.format("staging folder has no %q signpost -- is this an older .rbxm?", step.signpost))
		continue
	end

	local source = signpost:FindFirstChild(step.item)
		or (step.inside and signpost:FindFirstChild(step.inside) and signpost[step.inside]:FindFirstChild(step.item))

	if not source then
		fail(string.format("%s has no %q to install", signpost:GetFullName(), step.item))
		continue
	end

	local destination = step.into

	if step.merge then
		--[[
			TREK's own handler folder. It is place content the installer does not
			recreate, so it must be found rather than made -- creating a second
			one would leave the real Gun handler somewhere TREK stops looking,
			and every gun in the place would stop equipping.
		]]
		destination = ServerStorage:FindFirstChild(step.inside)

		if not destination then
			fail(
				string.format(
					"ServerStorage has no %s folder. That is TREK's, not this package's -- "
						.. "install TREK 4 before installing the grenade.",
					step.inside
				)
			)
			continue
		end
	elseif step.signpost == "GunConfigs" then
		destination = findGunConfigs()

		if not destination then
			fail("Could not find a GunConfigs folder anywhere. Install TREK 4 first.")
			continue
		end
	end

	if not destination then
		fail(string.format("no destination for %q", step.item))
		continue
	end

	install(source, destination)
end

-- ---------------------------------------------------------------------------

--[[
	The README is staging-only and should not survive into the place, and the
	wrapper is empty once everything has moved out.
]]
local readme = staging:FindFirstChild("README")
if readme then
	readme:Destroy()
end

local leftovers = {}
for _, child in ipairs(staging:GetChildren()) do
	for _, inner in ipairs(child:GetChildren()) do
		table.insert(leftovers, child.Name .. "/" .. inner.Name)
	end
end

if #leftovers > 0 then
	fail("staging folder still holds: " .. table.concat(leftovers, ", ") .. " -- left in place, move them by hand")
else
	staging:Destroy()
	say("staging folder removed")
end

say("================================================")

if problems > 0 then
	warn(string.format("[GasInstall] finished with %d problem(s) -- see above", problems))
else
	say("Install complete. Now put your grenade models in ServerStorage.TREKGasGrenade")
	say("and run tools/PrepareGrenadeRig, then press Play.")
end

--[[
	GasGrenade -- GunConfigs shim

	This module is what TREK's core sees. It is installed into GunConfigs, and
	its name must match the Tool's name exactly.

	Two facts about TREK make this file necessary rather than merely tidy:

	  - A tool with no entry in GunConfigs is ignored completely. `checkForGun`
	    looks the tool up by name, and if it finds nothing it never reads
	    ToolType, never clones a handler, never builds an ammo store. The gate is
	    membership in that folder, whether or not the tool is a gun.

	  - Several core paths resolve a tool's config by `tool.Name` and ignore the
	    TConfigToUse attribute -- the Explosion remote handler in
	    TREKServerGeneral is the one that bites. Naming this module after the
	    tool is the only arrangement every lookup agrees on.

	THIS MODULE MUST NEVER THROW AT REQUIRE TIME. TREK requires it from inside
	`checkForGun`, on the server, while a character is being assembled. An error
	here does not fail gracefully -- it aborts the handler install and the tool
	silently does nothing for the rest of the round. Hence the pcall and the
	hardcoded fallbacks: a missing package folder costs you the tuned numbers,
	not the grenade.

	The real configuration lives in ReplicatedStorage.TREKGasGrenade.GasConfig.
	Tune it there, not here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Mirrors of GasConfig, used only if the package cannot be reached in time.
local FALLBACK_TOOL_TYPE = "Throwable"
local FALLBACK_MAG_CAPACITY = 1

local function loadPackageConfig()
	local package = ReplicatedStorage:FindFirstChild("TREKGasGrenade")
	if not package then
		return nil
	end

	local module = package:FindFirstChild("GasConfig")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end

	local ok, result = pcall(require, module)
	if not ok or typeof(result) ~= "table" then
		return nil
	end

	return result
end

local config = loadPackageConfig()

if not config then
	warn("[GasGrenade] TREKGasGrenade.GasConfig unreachable; falling back to built-in defaults.")
end

return {
	ToolType = (config and config.ToolType) or FALLBACK_TOOL_TYPE,

	--[[
		TREK builds the TAmmo store from any mode table carrying MagCapacity, so
		declaring one mode here is what gives the grenade a count and a working
		reload path on the server.

		ReservedAmmo is NOT optional. createAmmoStore assigns it straight into a
		DoubleConstrainedValue's MaxValue and Value with no nil check, so leaving
		it out throws inside checkForGun -- while a character is mid-spawn, which
		is about the worst place in TREK to raise an error.

		The other fields are the minimum the shared paths read without a nil
		check. Nothing fires rays, so the ballistics values are inert -- they
		exist so a stray core lookup finds a number rather than nil.
	]]
	[1] = {
		MagCapacity = (config and config.MagCapacity) or FALLBACK_MAG_CAPACITY,
		ReservedAmmo = (config and config.ReservedAmmo) or 0,
		ReloadSpeed = 1.2,
		ReloadType = 1,
		useSharedClip = false,

		Damage = 0,
		ArmourDamage = 0,
		headShotMultiplier = 1,
		fallOffStart = math.huge,
		fallOffEnd = math.huge,

		--[[
			Explicitly false. If this were true, TREK's Explosion remote would
			accept a client-sent position and run a blast using this config --
			a free one-shot explosion for anyone who can fire a remote.
		]]
		explosiveRays = false,
		explosionsIgnoreWalls = false,
		explosionName = "Invisible",

		CanSuppress = false,
		ExtraSuppression = false,
		limbRemovalChance = 0,
	},
}

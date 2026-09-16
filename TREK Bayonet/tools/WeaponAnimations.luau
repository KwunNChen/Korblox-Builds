--[[
	Creates the bayonet fire mode's animation instances on a weapon.

	NOT a lune script. Paste it into the Studio COMMAND BAR in EDIT MODE.

	--------------------------------------------------------------------------
	WHY THIS EXISTS
	--------------------------------------------------------------------------

	TREK Custom Bullets picks animations by mode prefix:

		determineAnim:  animations[tostring(currentMode) .. anim] or animations[anim]

	So an Animation named "2Recoil" plays on a bayonet swing while "Recoil"
	still plays when the rifle fires. The lookup is by NAME, and the instances
	live inside the weapon's config module, which is place content -- it is not
	in this repo and not synced by Rojo.

	That makes the ids easy to lose. Keeping them here means the animation setup
	is reproducible rather than something that was done once by hand at midnight
	and never written down.

	--------------------------------------------------------------------------
	AFTER RUNNING IT
	--------------------------------------------------------------------------

	Save the place and RESTART the playtest. Two caches make a mid-session
	change invisible: SetUpGuns caches every weapon module at server start, and
	the Gun handler's loadAnimations is guarded by `if animsLoaded then return
	end`, so it reads the Animations folder once per tool script and never again.
]]

local ANIMATIONS = {
	-- The stab itself. Plays on every swing, driven by shoot() -> determineAnim.
	["2Recoil"] = 130508149089530,

	-- The held pose for bayonet mode: the coil, the moment before the thrust.
	--
	-- Third id for this pose. The first two came out wrong because the gun was
	-- not attached to the editing rig at all, so neither had an AnimPart track
	-- -- and with TREK's identity toolAnim joint, no track means the whole
	-- weapon parks at the torso origin. It reads as "upside down" but nothing
	-- was rotated; the gun simply had no pose to sit in.
	["2Idle"] = 84114589119244,

	--[[
		The sprinting pose, and deliberately the SAME asset as the idle.

		Verified by reading the published sequence: its tracks are AnimPart,
		Bolt, HumanoidRootPart, Left Arm, Right Arm and Torso -- no legs. An
		animation only overrides the joints it keyframes, so the legs stay on
		whatever the Animate script is running and you get the bayonet stance
		on top of a normal run.

		Had it carried leg poses they would freeze mid-stride, and the fix would
		be tools/StripLegTracks.luau followed by a republish.
	]]
	["2SprintHold"] = 84114589119244,
}

--[[
	The weapon is found by PATH, because nothing else about it is unique.

	Two heuristics were tried and both wrote the animations into the wrong
	module, silently:

	  * last ModuleScript in Workspace whose name contains "KR" and "61" --
	    fine while exactly one copy exists, wrong the moment there are two.

	  * the module carrying a known Idle animation id -- except TREK weapons
	    SHARE animation ids. The KT-60 has the same Idle as the KR-61, so this
	    configured the KT-60 instead.

	Both failures look identical in game: the bayonet mode plays the rifle's
	idle and nothing is logged anywhere.

	The installer's GunConfigs folder holds one module per weapon, named exactly
	as the weapon is. That name, in that folder, is the only unique handle.
	Mind the trailing space in "Installer " -- it is part of the instance name.
]]
local INSTALLER = "Installer "
local WEAPON_NAME = 'KR-61 "Bonecrusher"'

local gunConfigs = workspace:FindFirstChild(INSTALLER)
gunConfigs = gunConfigs and gunConfigs:FindFirstChild("GunConfigs")

if not gunConfigs then
	warn("no " .. INSTALLER .. "GunConfigs in Workspace")
	return
end

local weapon = gunConfigs:FindFirstChild(WEAPON_NAME)

if not weapon then
	warn("no weapon named " .. WEAPON_NAME .. " -- the names present are:")
	for _, c in ipairs(gunConfigs:GetChildren()) do
		warn("   " .. c.Name)
	end
	return
end

print("weapon module: " .. weapon:GetFullName())

local folder = weapon:FindFirstChild("Animations")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Animations"
	folder.Parent = weapon
	print("created an Animations folder")
end

for name, id in pairs(ANIMATIONS) do
	local existing = folder:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = "rbxassetid://" .. id
	anim.Parent = folder

	print(string.format("  %s -> %s", name, anim.AnimationId))
end

--[[
	Verify rather than assume. These instances have gone missing once already --
	an undo in another panel removes them just as happily as it removes a
	keyframe -- and the failure is silent: the weapon plays the rifle's idle and
	nothing is logged.
]]
print("verifying:")
for name in pairs(ANIMATIONS) do
	local a = folder:FindFirstChild(name)
	print(string.format("  %-12s %s", name, a and a.AnimationId or "MISSING"))
end

print("done -- SAVE the place, then restart the playtest. Do not undo after this.")

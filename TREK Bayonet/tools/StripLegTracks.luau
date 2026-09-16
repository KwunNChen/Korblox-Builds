--[[
	STRIP LEG TRACKS

	NOT a lune script. Paste it into the Studio COMMAND BAR in EDIT MODE.

	Downloads a published animation, deletes the leg poses from it, and drops the
	result where the Clip Editor's Load menu reads from. Load it, check it,
	publish it, and use the new id as 2SprintHold.

	--------------------------------------------------------------------------
	WHY THIS MAKES THE LEGS RUN
	--------------------------------------------------------------------------

	An animation only overrides the joints it actually keyframes. Roblox's own
	Animate script drives walking and running; a weapon animation layered on top
	replaces only the limbs it has poses for.

	So an upper-body-only animation gives you the bayonet stance on the torso and
	arms while the legs keep running normally. Keep the leg poses in and they
	freeze mid-stride instead -- the animation is pinning them.

	The torso pose is KEPT. Legs hang off the torso, so they still swing with it
	physically -- what matters is that their own joints are left unanimated.
]]

local SOURCE_ID = 84114589119244

-- R6 names. Add "Head" here too if you want the head free to look around.
local STRIP = {
	["Left Leg"] = true,
	["Right Leg"] = true,
}

local OUTPUT_NAME = "BayonetSprint"

--------------------------------------------------------------------------------

print("")
print("=== STRIP LEG TRACKS ===")
print("source asset: " .. SOURCE_ID)

--[[
	The rig must be SELECTED. There is no fallback scan on purpose.

	Scanning for "a model with a Torso and a Humanoid" picked the wrong rig
	three separate times in this project -- it takes whichever match comes last,
	which is a respawn dummy as often as the rig you are working on. Silently
	acting on the wrong one is worse than refusing.
]]
local rig = game:GetService("Selection"):Get()[1]

if not rig or not rig:IsA("Model") or not rig:FindFirstChild("Torso") then
	warn("SELECT YOUR R6 RIG IN THE EXPLORER FIRST.")
	warn("  selected right now: " .. (rig and (rig:GetFullName() .. "  (" .. rig.ClassName .. ")")
		or "nothing"))
	warn("  it must be a Model with a Torso child.")
	return
end

print("rig: " .. rig:GetFullName())

local ok, objs = pcall(function()
	return game:GetObjects("rbxassetid://" .. SOURCE_ID)
end)

if not ok or not objs[1] then
	warn("could not download " .. SOURCE_ID .. ": " .. tostring(objs))
	warn("  if this says permission, the animation belongs to another account or")
	warn("  group and Studio will not hand it over for editing.")
	return
end

print("downloaded " .. SOURCE_ID .. " as a " .. objs[1].ClassName)

local sequence = objs[1]
if not sequence:IsA("KeyframeSequence") then
	warn("asset " .. SOURCE_ID .. " came back as a " .. sequence.ClassName .. ", not a KeyframeSequence")
	return
end

local removed, kept = 0, {}
for _, keyframe in ipairs(sequence:GetChildren()) do
	for _, pose in ipairs(keyframe:GetDescendants()) do
		if pose:IsA("Pose") then
			if STRIP[pose.Name] then
				--[[
					Destroying a Pose removes its CHILDREN too, and in the R6
					hierarchy the limbs hang off the Torso. Legs are leaves, so
					this is safe -- but never add "Torso" to STRIP, or you take
					the arms and head with it.
				]]
				pose:Destroy()
				removed += 1
			else
				kept[pose.Name] = true
			end
		end
	end
end

local names = {}
for name in pairs(kept) do
	table.insert(names, name)
end
table.sort(names)

--[[
	Saves live in ServerStorage.RBX_ANIMSAVES.<rig name> in this Studio version,
	NOT in Rig > AnimSaves. If your Load menu comes up empty, that is the first
	thing to check -- the other location exists in some versions and an empty
	menu usually means the sequence went to the one the editor is not reading.
]]
local root = game:GetService("ServerStorage"):FindFirstChild("RBX_ANIMSAVES")
if not root then
	root = Instance.new("Folder")
	root.Name = "RBX_ANIMSAVES"
	root.Parent = game:GetService("ServerStorage")
end

local saves = root:FindFirstChild(rig.Name)
if not saves then
	saves = Instance.new("Folder")
	saves.Name = rig.Name
	saves.Parent = root
end

local existing = saves:FindFirstChild(OUTPUT_NAME)
if existing then
	existing:Destroy()
end

sequence.Name = OUTPUT_NAME
sequence.Parent = saves

if removed == 0 then
	warn("removed NOTHING -- this animation has no poses named "
		.. table.concat((function()
			local t = {}
			for name in pairs(STRIP) do table.insert(t, name) end
			table.sort(t)
			return t
		end)(), " or "))
	warn("  the tracks it does have are listed below; adjust STRIP to match.")
end

print(string.format("removed %d leg pose(s)", removed))
print("tracks left: " .. table.concat(names, ", "))
print("saved as " .. sequence:GetFullName())
print("")
print("next: Clip Editor -> ... -> Load -> " .. OUTPUT_NAME .. ", check it, Publish to Roblox,")
print("then put the new id into tools/WeaponAnimations.luau as 2SprintHold.")

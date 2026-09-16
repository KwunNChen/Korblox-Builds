--[[
	STRIP HEAD TRACK

	NOT a lune script. Select your R6 rig in the Explorer, then paste this whole
	file into the Studio COMMAND BAR in EDIT MODE.

	Adapted from TREK Bayonet's tools/StripLegTracks.luau. Same machinery,
	already pointed at the climb animation and set to remove the neck.

	--------------------------------------------------------------------------
	WHAT IT IS FOR
	--------------------------------------------------------------------------

	A borrowed animation brings its own head movement. A ladder climb has the
	head craning up at the rungs, which on a mantle reads as staring at the sky
	while hauling yourself over a wall -- and the head is the first thing anyone
	looks at, so one bad neck track spoils an otherwise usable pose.

	An animation only drives the joints it actually keyframes, so deleting the
	Head poses leaves the head to sit naturally while everything else plays.

	There is a runtime alternative: ParkourConfig.KeepHeadLevel does the same job
	every frame without republishing anything. This is the tidier fix of the two,
	not the necessary one.

	--------------------------------------------------------------------------
	AFTERWARDS
	--------------------------------------------------------------------------

	Clip Editor -> ... -> Load -> MantlePull, check it, Publish to Roblox, then
	put the new id into ParkourConfig.Animations.MantlePull -- in the file on
	disk, not the Studio copy, or the next rojo sync overwrites it.

	If it says "removed NOTHING", this animation has no Head pose and the head
	movement you are seeing comes from somewhere else. Use KeepHeadLevel instead.
]]

local SOURCE_ID = 120398727612630 -- tempclimb's active climb
local STRIP = { ["Head"] = true }
local OUTPUT_NAME = "MantlePull"

--------------------------------------------------------------------------------

print("")
print("=== STRIP HEAD TRACK ===")
print("source asset: " .. SOURCE_ID)

--[[
	The rig must be SELECTED. There is no fallback scan on purpose -- scanning
	for "a model with a Torso" picks a respawn dummy as often as the rig you are
	working on, and silently acting on the wrong one is worse than refusing.
]]
local rig = game:GetService("Selection"):Get()[1]

if not rig or not rig:IsA("Model") or not rig:FindFirstChild("Torso") then
	warn("SELECT YOUR R6 RIG IN THE EXPLORER FIRST.")
	warn("  selected right now: " .. (rig and (rig:GetFullName() .. "  (" .. rig.ClassName .. ")") or "nothing"))
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
	warn("  group and Studio will not hand it over for editing. Use")
	warn("  ParkourConfig.KeepHeadLevel instead -- it needs no ownership.")
	return
end

local sequence = objs[1]
print("downloaded " .. SOURCE_ID .. " as a " .. sequence.ClassName)

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
					Destroying a Pose takes its CHILDREN with it. On R6 the Head
					hangs off the Torso and is itself a leaf, so removing it is
					safe -- but never put "Torso" in STRIP, or the arms and head
					go with it.
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
	NOT in Rig > AnimSaves. Both are written here, because which one the Clip
	Editor reads varies by version and an empty Load menu is almost always this.
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

local function place(into: Instance)
	local existing = into:FindFirstChild(OUTPUT_NAME)
	if existing then
		existing:Destroy()
	end
	local copy = sequence:Clone()
	copy.Name = OUTPUT_NAME
	copy.Parent = into
	print("saved as " .. copy:GetFullName())
end

place(saves)

local inRig = rig:FindFirstChild("AnimSaves")
if not inRig then
	inRig = Instance.new("Folder")
	inRig.Name = "AnimSaves"
	inRig.Parent = rig
end
place(inRig)

if removed == 0 then
	warn("removed NOTHING -- this animation has no pose named Head.")
	warn("  the tracks it does have are listed below.")
	warn("  the head movement is coming from somewhere else; use KeepHeadLevel.")
end

print(string.format("removed %d head pose(s)", removed))
print("tracks left: " .. table.concat(names, ", "))
print("")
print("next: Clip Editor -> ... -> Load -> " .. OUTPUT_NAME .. ", check it, Publish to Roblox,")
print("then put the new id into ParkourConfig.Animations.MantlePull")

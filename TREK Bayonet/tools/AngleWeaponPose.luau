--[[
	ANGLE THE WEAPON IN A POSE

	NOT a lune script. Paste into the Studio COMMAND BAR in EDIT MODE, with your
	R6 rig SELECTED.

	Downloads a published animation, pitches the weapon up (or down) by a fixed
	angle, and saves the result where the Clip Editor's Load menu reads from.
	Load it, look at it, publish it, and use the new id.

	Written for making a sprint pose out of an idle pose: same stance, barrel
	carried higher.

	--------------------------------------------------------------------------
	WHAT IT ROTATES, AND WHAT IT DOES NOT
	--------------------------------------------------------------------------

	Only the AnimPart track -- the weapon itself. The arms are left alone.

	At small angles that reads fine, because the hands stay visually on the
	weapon. Past roughly 20 degrees they start to come off it, and at that point
	the honest fix is the Clip Editor: rotate the gun, then move the arms to
	follow. No script can pose hands convincingly.

	The rotation is applied in the WEAPON'S OWN frame (post-multiplied), so it
	pivots the barrel about where the gun already is rather than swinging the
	whole weapon around the torso. That keeps the grip roughly in place and
	lifts the muzzle, which is the thing being asked for.
]]

local SOURCE_ID = 84114589119244

-- Degrees. Positive lifts the muzzle, negative drops it.
local ANGLE = 15

local OUTPUT_NAME = "BayonetSprint_Angled"

-- The weapon's root track. Everything else on the gun hangs off it, so
-- rotating this one carries the whole rifle.
local TRACK = "AnimPart"

--------------------------------------------------------------------------------

print("")
print("=== ANGLE WEAPON POSE ===")
print(string.format("source %d, %+d degrees on %s", SOURCE_ID, ANGLE, TRACK))

local rig = game:GetService("Selection"):Get()[1]
if not rig or not rig:IsA("Model") or not rig:FindFirstChild("Torso") then
	warn("SELECT YOUR R6 RIG IN THE EXPLORER FIRST.")
	warn("  selected right now: "
		.. (rig and (rig:GetFullName() .. "  (" .. rig.ClassName .. ")") or "nothing"))
	return
end
print("rig: " .. rig:GetFullName())

local ok, objs = pcall(function()
	return game:GetObjects("rbxassetid://" .. SOURCE_ID)
end)

if not ok or not objs[1] then
	warn("could not download " .. SOURCE_ID .. ": " .. tostring(objs))
	return
end

local sequence = objs[1]
if not sequence:IsA("KeyframeSequence") then
	warn("came back as a " .. sequence.ClassName .. ", not a KeyframeSequence")
	return
end

--[[
	The barrel runs along the weapon's own -Z, and a rotation about its local X
	maps -Z toward +Y. So post-multiplying by Angles(ANGLE, 0, 0) pitches the
	muzzle up by exactly that many degrees.
]]
local lift = CFrame.Angles(math.rad(ANGLE), 0, 0)

local touched = 0
for _, keyframe in ipairs(sequence:GetChildren()) do
	for _, pose in ipairs(keyframe:GetDescendants()) do
		if pose:IsA("Pose") and pose.Name == TRACK then
			pose.CFrame = pose.CFrame * lift
			touched += 1
		end
	end
end

if touched == 0 then
	warn("no " .. TRACK .. " pose found -- this animation does not move the weapon,")
	warn("  so there is nothing here to angle. Check the track names.")
	return
end

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

print(string.format("rotated %d %s pose(s) by %+d degrees", touched, TRACK, ANGLE))
print("saved as " .. sequence:GetFullName())
print("")
print("next: Clip Editor -> ... -> Load -> " .. OUTPUT_NAME)
print("      check the hands still look attached, then Publish to Roblox,")
print("      and put the new id into tools/WeaponAnimations.luau as 2SprintHold.")

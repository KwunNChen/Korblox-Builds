--[[
	HOLSTER TUNER

	NOT a lune script. Paste it into the Studio COMMAND BAR during a PLAYTEST,
	with the weapon UNEQUIPPED so the holster exists.

	Run it once as-is: it MEASURES the holster and prints where it currently
	sits, in the same numbers you would edit. Nothing moves.

	Then set APPLY = true, change the numbers, and run it again to move it.

	The first version of this shipped pre-filled with the values already in use,
	so running it re-applied the same transform and looked completely dead.
]]

local APPLY = false

local X, Y, Z = 0.95, 0.1, 0.5
local LEAN = -12
local PITCH, YAW, ROLL = 90, 0, -90

--------------------------------------------------------------------------------

local player = game:GetService("Players"):GetPlayers()[1]
local character = player and player.Character

print("")
print("=== HOLSTER TUNER ===")
print("player:    " .. (player and player.Name or "NONE -- are you in a playtest?"))
print("character: " .. (character and character:GetFullName() or "NONE"))

if not character then
	print("stop: no character. Run this during a playtest, not in edit mode.")
	return
end

local holster = character:FindFirstChild("HolsteredWeapon")
local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")

print("holster:   " .. (holster and holster:GetFullName() or "NONE -- unequip the weapon first"))
print("torso:     " .. (torso and torso.Name or "NONE"))

if not holster or not torso then
	return
end

local root = holster.PrimaryPart or holster:FindFirstChild("AnimPart")
if not root then
	print("stop: the holster has no AnimPart to measure from")
	return
end

--[[
	Where it is now, decomposed into the same six numbers this script takes.

	ToObjectSpace gives the holster's transform in the torso's frame, and
	ToOrientation pulls that apart into the X/Y/Z angles CFrame.Angles expects.
	The LEAN is not separable from them -- it is folded into the orientation --
	so what prints is the COMBINED rotation.
]]
local current = torso.CFrame:ToObjectSpace(root.CFrame)
local rx, ry, rz = current:ToOrientation()

print("")
print("CURRENT, in the torso's frame (+X right, +Y up, +Z behind):")
print(string.format("   position   %.2f, %.2f, %.2f", current.X, current.Y, current.Z))
print(string.format("   rotation   pitch %.0f   yaw %.0f   roll %.0f  (degrees)",
	math.deg(rx), math.deg(ry), math.deg(rz)))

local muzzleNow = current * CFrame.new(0, 0, -3)
local stockNow = current * CFrame.new(0, 0, 3)
print(string.format("   muzzle     %.1f, %.1f, %.1f", muzzleNow.X, muzzleNow.Y, muzzleNow.Z))
print(string.format("   stock      %.1f, %.1f, %.1f", stockNow.X, stockNow.Y, stockNow.Z))

if not APPLY then
	print("")
	print("APPLY is false, so nothing moved. Set APPLY = true and change the")
	print("numbers at the top to try a new position.")
	return
end

local offset = CFrame.new(X, Y, Z)
	* CFrame.Angles(0, 0, math.rad(LEAN))
	* CFrame.Angles(math.rad(PITCH), math.rad(YAW), math.rad(ROLL))

--[[
	The weld has to come off before the pivot and go back on after.

	A WeldConstraint locks its two parts at the transform they had when it
	activated, so pivoting a welded model either does nothing at all or drags
	the torso along with it.
]]
for _, d in ipairs(root:GetChildren()) do
	if d:IsA("WeldConstraint") then
		d:Destroy()
	end
end

holster:PivotTo(torso.CFrame * offset)

local weld = Instance.new("WeldConstraint")
weld.Part0 = root
weld.Part1 = torso
weld.Parent = root

local muzzle = offset * CFrame.new(0, 0, -3)
local stock = offset * CFrame.new(0, 0, 3)

print("")
print("APPLIED:")
print(string.format("   muzzle %.1f, %.1f, %.1f   stock %.1f, %.1f, %.1f   %s",
	muzzle.X, muzzle.Y, muzzle.Z, stock.X, stock.Y, stock.Z,
	((muzzle.X > 0) == (stock.X > 0)) and "same side" or "crosses the spine"))
print("")
print("paste into HolsterService's STYLES table when it looks right:")
print(string.format("    MyStyle = CFrame.new(%g, %g, %g)", X, Y, Z))
print(string.format("        * CFrame.Angles(0, 0, math.rad(%g))", LEAN))
print(string.format("        * CFrame.Angles(math.rad(%g), math.rad(%g), math.rad(%g)),",
	PITCH, YAW, ROLL))

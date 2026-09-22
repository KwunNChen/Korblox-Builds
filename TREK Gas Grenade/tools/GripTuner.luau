--[[
	GRIP TUNER

	NOT a lune script. Paste it into the Studio COMMAND BAR during a PLAYTEST,
	with the grenade EQUIPPED so the grip joint exists.

	Run it once as-is: it MEASURES the grip and prints where the grenade
	currently sits, in the same six numbers you would edit. Nothing moves.

	Then set APPLY = true, change the numbers, and run it again. The grenade
	moves immediately, in the live playtest, with no rebuild and no re-import --
	so finding the right orientation is a few seconds of trying rather than a
	round trip through Rojo each time.

	When it looks right, the script prints the exact GasConfig.GripOffset line to
	paste. Nothing it does survives the playtest; only that line is permanent.
]]

local APPLY = false

-- Studs, in the hand's own frame. Negative Y is toward the fingers.
local X, Y, Z = 0, -1, 0

-- Degrees. YAW spins the grenade in the palm; PITCH and ROLL tip it out.
local PITCH, YAW, ROLL = 0, 90, 0

--------------------------------------------------------------------------------

local GRIP_NAME = "GasGrenadeGrip"
local TOOL_NAME = "Gas Grenade"

local player = game:GetService("Players"):GetPlayers()[1]
local character = player and player.Character

print("")
print("=== GRIP TUNER ===")
print("player:    " .. (player and player.Name or "NONE -- are you in a playtest?"))
print("character: " .. (character and character:GetFullName() or "NONE"))

if not character then
	print("stop: no character. Run this during a playtest, not in edit mode.")
	return
end

local humanoid = character:FindFirstChildOfClass("Humanoid")
local isR6 = humanoid and humanoid.RigType == Enum.HumanoidRigType.R6
local handName = isR6 and "Right Arm" or "RightHand"
local hand = character:FindFirstChild(handName)

print("rig:       " .. (humanoid and humanoid.RigType.Name or "?"))
print("hand:      " .. (hand and hand:GetFullName() or "NONE -- " .. handName .. " is missing"))

if not hand then
	return
end

local grip = hand:FindFirstChild(GRIP_NAME)
print("grip:      " .. (grip and grip:GetFullName() or "NONE -- equip the grenade first"))

if not grip or not grip:IsA("Motor6D") then
	print("stop: no grip joint. Equip the " .. TOOL_NAME .. " and run this again.")
	return
end

print("holding:   " .. (grip.Part1 and grip.Part1:GetFullName() or "NOTHING -- joint points nowhere"))

--[[
	Where it is now, in the same six numbers this script takes.

	C0 is already expressed in the hand's frame, so unlike the holster tuner
	there is nothing to convert -- the offset is read straight off the joint.
	ToOrientation pulls the rotation apart into the X/Y/Z angles CFrame.Angles
	expects, in that order.
]]
local current = grip.C0
local cx, cy, cz = current.Position.X, current.Position.Y, current.Position.Z
local rx, ry, rz = current:ToOrientation()

print("")
print("CURRENT:")
print(string.format("  X, Y, Z            = %.3f, %.3f, %.3f", cx, cy, cz))
print(string.format("  PITCH, YAW, ROLL   = %.1f, %.1f, %.1f", math.deg(rx), math.deg(ry), math.deg(rz)))

if not APPLY then
	print("")
	print("APPLY is false, so nothing moved.")
	print("Set APPLY = true, edit the six numbers at the top, and run again.")
	return
end

local offset = CFrame.new(X, Y, Z)
	* CFrame.Angles(math.rad(PITCH), math.rad(YAW), math.rad(ROLL))

grip.C0 = offset

print("")
print("APPLIED:")
print(string.format("  X, Y, Z            = %.3f, %.3f, %.3f", X, Y, Z))
print(string.format("  PITCH, YAW, ROLL   = %.1f, %.1f, %.1f", PITCH, YAW, ROLL))

-- The line to keep, in the exact shape GasConfig holds.
print("")
print("Paste into GasConfig.GripOffset:")
print("")
print(string.format(
	"    %s = { X = %g, Y = %g, Z = %g, Pitch = %g, Yaw = %g, Roll = %g },",
	isR6 and "R6" or "R15", X, Y, Z, PITCH, YAW, ROLL
))
print("")
print("Re-equipping the grenade resets this to whatever GasConfig says, so put")
print("the line in the config before you stop the playtest.")

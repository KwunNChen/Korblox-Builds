--!strict
--[[
	What a mantle costs you, and giving it back.

	Three levers, all of them TREK's own, none of them modified:

	  UsingAbility   a BoolValue TREK ships on every character and never reads.
	                 We claim it so any other system can tell you are busy.
	  CanSprint      the veto TREK's vehicle seats use. While false, TREK's own
	                 controls.sprint() refuses to turn sprinting back on.
	  the weapon     unequipped, which is both the cost and the mechanism -- see
	                 below.

	--------------------------------------------------------------------------
	WHY UNEQUIPPING IS NOT ONLY FLAVOUR
	--------------------------------------------------------------------------

	TREK's HeadAndArmsController rewrites HumanoidRootPart.CFrame every frame
	while a weapon with TurnToTarget is out, forcing the yaw to the mouse and
	flattening pitch and roll. A pull-up that rotates the body cannot play over
	the top of that.

	Unequipping is the supported way to stop it: TREK's gun handler calls
	HeadArmsModule:Stop() from its own onUnEquip. We deliberately do NOT call
	:Pause() instead -- that module is a per-client singleton with no reference
	counting, and the gun handler calls :Continue() from three places we do not
	control, any of which would lift our pause out from under us mid-climb.

	It also means that with TREK Bayonet's HolsterService installed, the rifle
	visibly slings across the player's back for the duration, which is the right
	picture anyway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local package = ReplicatedStorage:WaitForChild("TREKParkour")
local Shared = require(package:WaitForChild("ParkourShared"))

local ParkourLockout = {}

export type Cost = {
	holster: boolean,
	blockSprint: boolean,
}

--[[
	What a move costs is per-move, not per-package. A mantle takes everything; a
	vault is supposed to be seamless and takes nothing but the flag. Taking the
	cost as an argument rather than reading the config here is what stops a vault
	quietly killing your sprint.

	Returns the tool that was taken away, so it can be given back to the same
	hand later. nil means there was nothing to take.
]]
function ParkourLockout.apply(character: Model, humanoid: Humanoid, cost: Cost): Tool?
	Shared.setUsingAbility(character, true)

	if cost.blockSprint then
		local canSprint = Shared.boolValue(character, "CanSprint")
		if canSprint then
			canSprint.Value = false
		end

		--[[
			CanSprint alone only stops sprint being turned back ON. If the
			player is sprinting right now, TREK is still acting on it, so the
			intent flag has to be cleared too. Clearing SprintEnabled is what
			TREK's own gun handler does when you fire.
		]]
		local sprintEnabled = Shared.boolValue(character, "SprintEnabled")
		if sprintEnabled then
			sprintEnabled.Value = false
		end
	end

	if not cost.holster then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		humanoid:UnequipTools()
	end
	return tool
end

function ParkourLockout.release(character: Model, humanoid: Humanoid?, tool: Tool?)
	Shared.setUsingAbility(character, false)

	local canSprint = Shared.boolValue(character, "CanSprint")
	if canSprint then
		--[[
			Only give sprint back if they are not sitting in something.

			TREK's seat handler owns CanSprint while seated and restores it on
			exit. Writing true here for a player who got seated mid-move would
			unlock sprinting inside a vehicle, and TREK would have no idea why.
		]]
		if humanoid and not humanoid.SeatPart then
			canSprint.Value = true
		end
	end

	-- Only to someone alive enough to hold it, and only if it still exists.
	if tool and tool.Parent and humanoid and humanoid.Health > 0 and humanoid.Parent then
		pcall(function()
			humanoid:EquipTool(tool :: Tool)
		end)
	end
end

return ParkourLockout

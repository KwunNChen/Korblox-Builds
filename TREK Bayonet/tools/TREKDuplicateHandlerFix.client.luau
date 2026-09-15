--[[
	TREK DUPLICATE HANDLER GUARD

	LocalScript. Put it in StarterPlayerScripts. Not part of the bayonet -- it
	lives here because this is where it got written.

	--------------------------------------------------------------------------
	THE SYMPTOM
	--------------------------------------------------------------------------

	Sprint sometimes does nothing. No error, no message.

	--------------------------------------------------------------------------
	WHY
	--------------------------------------------------------------------------

	MovementHandler connects UserInputService.InputBegan, and on the sprint key
	calls controls.sprint(), whose operative line is a TOGGLE:

		controls.sprintstate.Value = not controls.sprintstate.Value

	Run that script twice and one keypress flips SprintEnabled on and straight
	back off. Sprint is dead, silently, because nothing errored -- a toggle is
	the one primitive that fails invisibly under duplication.

	The startup log shows it happening:

		14:42:48.915  one life movement handler loaded
		14:42:50.458  one life movement handler loaded      <- second copy
		14:42:50.432  Studio install                        <- right before it

	It is intermittent because the duplicate sometimes dies during setup before
	it reaches the Connect. Its siblings do exactly that in the same log:

		ForceClientInstall.StarterCharacterScripts.CameraFix:6:
			attempt to index nil with 'WaitForChild'

	One surviving connection means sprint works. Two means it does not.

	--------------------------------------------------------------------------
	WHICH COPY IS THE REAL ONE
	--------------------------------------------------------------------------

	The character's. TREK's own Gun handler says so:

		Gun.client.luau:141
		local controls = require(chr:WaitForChild('OneLifeScripts')
			:WaitForChild('ControlsModule'))

	It expects OneLifeScripts as a child of the CHARACTER. So a MovementHandler
	running from PlayerGui -- which is where ForceClientInstall puts its copies
	-- is the stray, and it is also the copy whose siblings are erroring.

	This disables strays before they run and leaves the character's copy alone.
	If nothing is duplicated it does nothing and says nothing.

	--------------------------------------------------------------------------
	CONFIDENCE
	--------------------------------------------------------------------------

	The double-load is certain: it is in the log twice. The claim that the
	PlayerGui copy is the duplicate is inference from Gun.client's expectation
	plus the fact that the erroring siblings are all ForceClientInstall copies.
	This script names every script it disables, so the log will show whether the
	inference was right.
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Scripts that must run exactly once per life. ControlsModule is deliberately
-- absent: it is a ModuleScript, so extra copies are inert until required, and
-- each MovementHandler requires its own sibling by design.
local SINGLETONS = {
	MovementHandler = true,
	UIHandler = true,
	TeamIndicator = true,
}

local disabled = 0

--[[
	Disable a stray copy, if that is what it is.

	Called from DescendantAdded, which fires the moment the instance is parented
	-- before a LocalScript gets its first resumption. Setting Disabled here
	stops it rather than racing it.
]]
local function consider(inst: Instance)
	if not inst:IsA("LocalScript") then
		return
	end
	if not SINGLETONS[inst.Name] then
		return
	end

	-- The character's copy is the legitimate one. Anything else under the
	-- player -- PlayerGui, Backpack, PlayerScripts -- is a stray install.
	local chr = player.Character
	if chr and inst:IsDescendantOf(chr) then
		return
	end

	inst.Disabled = true
	disabled += 1
	warn(string.format(
		"[TREKDupFix] disabled a stray %s at %s (not under the character)",
		inst.Name, inst:GetFullName()
	))
end

local function sweep(root: Instance?)
	if not root then
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		consider(d)
	end
end

-- Anything already in place, then anything that arrives later. The second
-- install pass is the one that matters and it lands after the first.
sweep(player)
player.DescendantAdded:Connect(consider)

player.CharacterAdded:Connect(function()
	-- A fresh life gets a fresh set of strays.
	task.wait(1)
	sweep(player)
end)

task.delay(8, function()
	if disabled == 0 then
		warn("[TREKDupFix] nothing to disable -- no stray handlers found outside the character")
	else
		warn(string.format("[TREKDupFix] disabled %d stray handler(s) this life", disabled))
	end
end)

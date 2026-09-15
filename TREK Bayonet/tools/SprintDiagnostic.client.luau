--[[
	TEMPORARY DIAGNOSTIC -- delete when you have your answer.

	Put this in a LocalScript in StarterPlayerScripts. Play, then press your
	sprint key (F) ONCE and read Output.

	--------------------------------------------------------------------------
	THE HYPOTHESIS
	--------------------------------------------------------------------------

	TREK's MovementHandler connects UserInputService.InputBegan and, on the
	sprint key, calls controls.sprint(), whose effective line is:

		controls.sprintstate.Value = not controls.sprintstate.Value

	A TOGGLE. If MovementHandler is running twice -- and the startup log shows
	"one life movement handler loaded" printed twice, once after "Studio install"
	-- then one keypress toggles SprintEnabled twice: on, then immediately off.
	Sprint does nothing, with no error to show for it.

	It is intermittent because the second copy sometimes dies during setup before
	it reaches the Connect. The log shows its siblings doing exactly that:

		ForceClientInstall.StarterCharacterScripts.CameraFix:6:
			attempt to index nil with 'WaitForChild'

	When the duplicate dies early, one connection survives and sprint works.
	When it survives, sprint is dead.

	--------------------------------------------------------------------------
	READING THE OUTPUT
	--------------------------------------------------------------------------

	Press F once.

		TWO "[SPRINT] SprintEnabled ->" lines   = confirmed, duplicate handlers
		ONE line                                = something else, tell me

	The copy count printed at startup tells you where the duplicates live.
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local WATCHED = { "MovementHandler", "ControlsModule", "UIHandler" }

local function report(root: Instance?, label: string)
	if not root then
		return
	end
	for _, name in ipairs(WATCHED) do
		local hits = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name and d:IsA("LuaSourceContainer") then
				table.insert(hits, d:GetFullName())
			end
		end
		if #hits > 0 then
			warn(("[SPRINT] %s: %d x %s"):format(label, #hits, name))
			for _, full in ipairs(hits) do
				warn("           " .. full)
			end
		end
	end
end

local function watch(chr: Model)
	report(player, "in Player")
	report(chr, "in Character")

	local cfg = chr:WaitForChild("TREK_PlrConfig", 15)
	if not cfg then
		warn("[SPRINT] no TREK_PlrConfig on the character -- cannot watch")
		return
	end

	local enabled = cfg:WaitForChild("SprintEnabled", 10) :: BoolValue
	local sprinting = cfg:WaitForChild("Sprinting", 10) :: BoolValue
	local canSprint = cfg:WaitForChild("CanSprint", 10) :: BoolValue

	warn(("[SPRINT] watching. CanSprint=%s SprintEnabled=%s Sprinting=%s")
		:format(tostring(canSprint.Value), tostring(enabled.Value), tostring(sprinting.Value)))

	-- Count changes inside a short window. Two toggles from one keypress land
	-- within a frame or two of each other, which is what makes this decisive.
	local burst, lastAt = 0, 0

	enabled:GetPropertyChangedSignal("Value"):Connect(function()
		local now = os.clock()
		burst = if now - lastAt < 0.25 then burst + 1 else 1
		lastAt = now

		warn(("[SPRINT] SprintEnabled -> %-5s  (%d change%s in this press)%s")
			:format(
				tostring(enabled.Value),
				burst,
				burst == 1 and "" or "s",
				burst > 1 and "   <-- DOUBLE TOGGLE, duplicate handler confirmed" or ""
			))
	end)

	sprinting:GetPropertyChangedSignal("Value"):Connect(function()
		warn("[SPRINT] Sprinting   -> " .. tostring(sprinting.Value)
			.. "   WalkSpeed=" .. tostring(chr:FindFirstChildOfClass("Humanoid")
				and (chr:FindFirstChildOfClass("Humanoid") :: Humanoid).WalkSpeed or "?"))
	end)

	canSprint:GetPropertyChangedSignal("Value"):Connect(function()
		warn("[SPRINT] CanSprint   -> " .. tostring(canSprint.Value)
			.. (canSprint.Value and "" or "   <-- sprint is BLOCKED while this is false"))
	end)
end

if player.Character then
	task.spawn(watch, player.Character)
end
player.CharacterAdded:Connect(watch)

warn("[SPRINT] diagnostic armed -- press the sprint key ONCE and read the lines above")

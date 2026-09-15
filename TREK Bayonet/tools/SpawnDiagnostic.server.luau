--[[
	TEMPORARY DIAGNOSTIC -- delete when you have your answer.

	Paste into a Script in ServerScriptService, play, and respawn ten or so
	times (reset with Esc). Watch Output.

	WHAT IT IS TESTING
	------------------

	TREK's chrAdded (TREKServerGeneral, ~line 230) runs on CharacterAdded and
	opens with:

		local function chrAdded(chr, plr)
			createMotor(chr)                          -- line 1
			chr.ChildAdded:Connect(checkForGun)       -- line 2
			...
			repeat wait() until chr:FindFirstChild('Humanoid')   -- line 5 (!)

	and createMotor's first act is an UNGUARDED index:

		if chr.Humanoid.RigType == Enum.HumanoidRigType.R6 then
			M6D.Parent = chr.Torso

	The wait-for-Humanoid guard is FOUR LINES TOO LATE. If the character model
	replicates before its Humanoid does, chr.Humanoid throws, chrAdded aborts on
	its very first line, and two things never happen:

	  1. no 'toolAnim' Motor6D is created, so updateMotor later hits
	         if not chr.Torso:FindFirstChild('toolAnim') then return end
	     and silently gives up -- the gun is never jointed to the torso;

	  2. chr.ChildAdded:Connect(checkForGun) never runs, so when the tool
	     arrives nothing clones the ToolType handler and nothing calls
	     createAmmoStore -- the gun has no script and no ammo.

	Which is a gun that is sometimes there and sometimes completely dead,
	depending on replication timing. Exactly the symptom.

	READING THE OUTPUT
	------------------

	A healthy spawn:
		[SPAWN] X | at CharacterAdded: Humanoid=true Torso=true
		[SPAWN] X | after 5s: toolAnim=true Part1=...AnimPart tool=KR-61 ... handler=true TAmmo=true

	A broken spawn:
		[SPAWN] X | at CharacterAdded: Humanoid=false Torso=false
		[SPAWN] X | after 5s: toolAnim=false Part1=nil ... handler=false TAmmo=false

	Also search Output for:
		Humanoid is not a valid member of Model
	If that line appears on a bad spawn, the diagnosis is confirmed outright.
]]

local Players = game:GetService("Players")

local function watch(plr: Player)
	plr.CharacterAdded:Connect(function(chr)
		-- Read immediately: this is roughly the state TREK's own handler sees.
		local hum = chr:FindFirstChild("Humanoid")
		local torso = chr:FindFirstChild("Torso")

		warn(string.format(
			"[SPAWN] %s | at CharacterAdded: Humanoid=%s Torso=%s",
			plr.Name, tostring(hum ~= nil), tostring(torso ~= nil)
		))

		-- Then read the outcome once everything has had time to settle.
		task.delay(5, function()
			if not chr.Parent then
				return
			end

			local t = chr:FindFirstChild("Torso")
			local motor = t and t:FindFirstChild("toolAnim")
			local tool = chr:FindFirstChildOfClass("Tool")
				or (plr:FindFirstChild("Backpack") and plr.Backpack:FindFirstChildOfClass("Tool"))

			warn(string.format(
				"[SPAWN] %s | after 5s: toolAnim=%s Part1=%s tool=%s handler=%s TAmmo=%s",
				plr.Name,
				tostring(motor ~= nil),
				motor and motor.Part1 and motor.Part1.Name or "nil",
				tool and tool.Name or "NONE",
				tostring(tool ~= nil and tool:FindFirstChild("Gun") ~= nil),
				tostring(tool ~= nil and tool:FindFirstChild("TAmmo") ~= nil)
			))
		end)
	end)
end

for _, p in ipairs(Players:GetPlayers()) do
	watch(p)
end
Players.PlayerAdded:Connect(watch)

warn("[SPAWN] diagnostic armed -- respawn a few times and compare good vs bad spawns")

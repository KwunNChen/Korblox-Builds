-- Bootstrap. Waits for TREK to finish installing, then wires the hooks up.
--
-- The TREK_INSTALLED gate is the same one every TREK server script waits on --
-- shared.S does not exist until the installer has populated it.

repeat
	task.wait()
until game:GetService("ReplicatedStorage"):WaitForChild("TREK_INSTALLED").Value

local Config = require(game:GetService("ReplicatedStorage")
	:WaitForChild("TREKVoicelines"):WaitForChild("VoicelineConfig"))

-- Name any unusable entry once, at startup. Roblox's own message for these is
-- "Failed to load sound rbxassetid://" with no indication of which list it came
-- from, and the line simply plays as silence.
for _, bad in ipairs(Config.findBadEntries()) do
	warn(string.format(
		"[TREKVoicelines] %s sound #%d is not a usable asset: %q -- it is being skipped",
		bad.event, bad.index, bad.raw
	))
end

-- Events still waiting on ids. Not a fault, but silence you did not ask for is
-- worth saying out loud once rather than leaving you to wonder.
--
-- soundsFor, not playableSounds(cfg.Sounds): an event that borrows a voice via
-- SharesWith has no Sounds list of its own, so reading the field directly hands
-- ipairs a nil and kills this script before the hooks are ever connected.
local waiting = {}
for event in pairs(Config.Events) do
	if #Config.soundsFor(event) == 0 then
		table.insert(waiting, event)
	end
end

if #waiting > 0 then
	table.sort(waiting)
	warn("[TREKVoicelines] no clips yet, so these stay silent: " .. table.concat(waiting, ", "))
end

local Hooks = require(script.Parent:WaitForChild("VoicelineHooks"))

Hooks.start()

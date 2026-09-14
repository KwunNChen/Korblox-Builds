--!strict
-- Warms the audio cache so the first use of each clip is not a silent miss.
--
-- This has to run on the CLIENT. VoicelineService builds the Sound on the server
-- and parents it to the speaker's head, so the instance replicates but the audio
-- data does not -- every listener fetches the asset themselves. Preloading on the
-- server would warm the server's cache, which nobody listens through.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TREKVoicelines")
	:WaitForChild("VoicelineConfig"))

-- One probe per unique id. The same clip listed under several events, or twice
-- under one, is fetched once.
--
-- Dedupe on the NORMALISED url, not the raw config entry: 3526632933 and
-- "rbxassetid://3526632933" are the same asset written two ways.
local seen: { [string]: boolean } = {}
local probes: { Sound } = {}

for _, cfg in pairs(Config.Events) do
	-- playableSounds drops placeholders and malformed entries, so the preloader
	-- never asks Roblox for an asset that cannot exist. Fetching "rbxassetid://"
	-- is what produced "Request asset was not found" with nothing to trace it to.
	for _, url in ipairs(Config.playableSounds(cfg.Sounds or {})) do
		if not seen[url] then
			seen[url] = true

			local probe = Instance.new("Sound")
			probe.SoundId = url
			probe.Parent = script

			table.insert(probes, probe)
		end
	end
end

if #probes == 0 then
	return
end

-- Backgrounded: PreloadAsync yields, and with a large library it yields for a
-- while. Nothing else waits on this -- an unwarmed clip still plays, just later.
task.spawn(function()
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(probes)
	end)

	if not ok then
		warn("[TREKVoicelines] preload failed: " .. tostring(err))
	end

	-- The cache is keyed by asset id and outlives the instances, so the probes
	-- have done their job and can go.
	for _, probe in ipairs(probes) do
		probe:Destroy()
	end
end)

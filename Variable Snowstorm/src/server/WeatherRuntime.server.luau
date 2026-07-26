--[[
	WeatherRuntime
	Thin entry point. All the logic lives in WeatherService (a ModuleScript) so
	other server code can require it and hook into the storm without this script
	having to know about them.

	Gameplay effects go in the hooks below -- they are intentionally empty for now.
]]

local WeatherService = require(script.Parent:WaitForChild("WeatherService"))

WeatherService.start()

-- ============================================================
-- Gameplay hooks -- nothing wired up yet
-- ============================================================
--
-- Everything below is a working example, commented out. Uncomment and fill in
-- when you want the storm to actually do something to players.
--
-- Note that the shelter check here is the SERVER's own raycast. Never trust a
-- client's report of whether it is indoors -- that is trivially exploitable.
--
--[[

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Weather.WeatherConfig)

local COLD_THRESHOLD = 0.6   -- intensity above which exposure hurts
local DAMAGE_PER_TICK = 2

task.spawn(function()
	while true do
		task.wait(Config.ServerShelterInterval)

		local intensity = WeatherService.getIntensity()
		if intensity < COLD_THRESHOLD then
			continue
		end

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				continue
			end

			local sheltered = WeatherService.isPlayerSheltered(player)
			if not sheltered then
				humanoid:TakeDamage(DAMAGE_PER_TICK * intensity)
			end
		end
	end
end)

WeatherService.PhaseChanged:Connect(function(phase)
	print("[Weather] phase ->", phase)
end)

]]

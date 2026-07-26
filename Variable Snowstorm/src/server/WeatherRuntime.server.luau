-- Entry point plus the storm's gameplay effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Weather"):WaitForChild("WeatherConfig"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))
local SpeedService = require(ServerScriptService:WaitForChild("Common"):WaitForChild("SpeedService"))

local STORM_MODIFIER = "Storm"
local DEBUG_ATTRIBUTE = "DebugStartIntensity"

WeatherService.start()

-- Live debug knob on ReplicatedStorage.Weather. 0-1 forces that intensity,
-- negative resumes the cycle. WeatherConfig.DebugStartIntensity seeds it; set
-- the attribute at runtime to change it without a re-sync. The print confirms
-- the change actually reached the server.
local weatherFolder = ReplicatedStorage:WaitForChild("Weather")

local function applyDebugIntensity(value: unknown)
	if typeof(value) ~= "number" or value < 0 then
		WeatherService.setOverride(nil)
		print("[Weather] debug override cleared -- cycle resumed")
	else
		local intensity = math.clamp(value, 0, 1)
		WeatherService.setOverride(intensity, true)
		print(string.format("[Weather] debug override -> intensity %.2f", intensity))
	end
end

-- Seeded before connecting so a normal boot does not log a spurious clear.
weatherFolder:SetAttribute(DEBUG_ATTRIBUTE, Config.DebugStartIntensity)

weatherFolder:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
	applyDebugIntensity(weatherFolder:GetAttribute(DEBUG_ATTRIBUTE))
end)

if Config.DebugStartIntensity >= 0 then
	applyDebugIntensity(Config.DebugStartIntensity)
end

local function updatePlayerSpeed(player: Player, intensity: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if intensity <= 0 or WeatherService.isPlayerSheltered(player) then
		SpeedService.clearModifier(humanoid, STORM_MODIFIER)
		return
	end

	local multiplier = 1 + (Config.StormSpeedMultiplier - 1) * intensity
	SpeedService.setModifier(humanoid, STORM_MODIFIER, { mul = multiplier })
end

if Config.EnableStormSlowdown then
	task.spawn(function()
		local wasClear = true

		while true do
			task.wait(Config.StormSlowdownInterval)

			local intensity = WeatherService.getIntensity()

			-- Skip the whole sweep in clear weather once everyone is released.
			if intensity <= 0 and wasClear then
				continue
			end
			wasClear = intensity <= 0

			for _, player in Players:GetPlayers() do
				local ok, err = pcall(updatePlayerSpeed, player, intensity)
				if not ok then
					warn("[WeatherRuntime] slowdown failed for", player.Name, err)
				end
			end
		end
	end)
end

-- Cold damage
--[[

local COLD_THRESHOLD = 0.6
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

			if not WeatherService.isPlayerSheltered(player) then
				humanoid:TakeDamage(DAMAGE_PER_TICK * intensity)
			end
		end
	end
end)

]]

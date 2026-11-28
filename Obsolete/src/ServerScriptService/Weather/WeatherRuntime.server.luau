-- Entry point. Tower Assault copy: no lightning, no storm slowdown (Spearhead owns WalkSpeed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Weather"):WaitForChild("WeatherConfig"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))

local DEBUG_ATTRIBUTE = "DebugStartIntensity"

WeatherService.start()

-- Live knob on ReplicatedStorage.Weather. 0-1 forces that intensity, negative resumes the cycle.
local weatherFolder = ReplicatedStorage:WaitForChild("Weather")

local function applyDebugIntensity(value: any)
	if typeof(value) ~= "number" or value < 0 then
		WeatherService.setOverride(nil)
	else
		WeatherService.setOverride(math.clamp(value, 0, 1), true)
	end
end

weatherFolder:SetAttribute(DEBUG_ATTRIBUTE, Config.DebugStartIntensity)
weatherFolder:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
	applyDebugIntensity(weatherFolder:GetAttribute(DEBUG_ATTRIBUTE))
end)

if Config.DebugStartIntensity >= 0 then
	applyDebugIntensity(Config.DebugStartIntensity)
end

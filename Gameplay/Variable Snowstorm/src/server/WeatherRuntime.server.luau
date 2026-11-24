-- Entry point plus the storm's gameplay effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Weather"):WaitForChild("WeatherConfig"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))
local ThunderService = require(script.Parent:WaitForChild("ThunderService"))
local Common = ServerScriptService:WaitForChild("Common")
local SpeedService = require(Common:WaitForChild("SpeedService"))
local CharacterCache = require(Common:WaitForChild("CharacterCache"))

local STORM_MODIFIER = "Storm"
local DEBUG_ATTRIBUTE = "DebugStartIntensity"
local DEBUG_THUNDER_ATTRIBUTE = "DebugThunder"
local WIND_FORCE_NAME = "StormWindForce"

-- Raise to replicate the drift force less often, lower for finer steps.
local FORCE_EPSILON = 8

WeatherService.start()
ThunderService.start()

-- Live debug knob on ReplicatedStorage.Weather. 0-1 forces that intensity,
-- negative resumes the cycle.
local weatherFolder = ReplicatedStorage:WaitForChild("Weather")

local function applyDebugIntensity(value: any)
	if typeof(value) ~= "number" or value < 0 then
		WeatherService.setOverride(nil)
		print("[Weather] debug override cleared -- cycle resumed")
	else
		local intensity = math.clamp(value, 0, 1)
		WeatherService.setOverride(intensity, true)
		print(string.format("[Weather] debug override -> intensity %.2f", intensity))
	end
end

weatherFolder:SetAttribute(DEBUG_ATTRIBUTE, Config.DebugStartIntensity)

weatherFolder:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
	applyDebugIntensity(weatherFolder:GetAttribute(DEBUG_ATTRIBUTE))
end)

if Config.DebugStartIntensity >= 0 then
	applyDebugIntensity(Config.DebugStartIntensity)
end

-- Set true to open a thunderstorm window immediately. Resets itself.
weatherFolder:SetAttribute(DEBUG_THUNDER_ATTRIBUTE, false)

weatherFolder:GetAttributeChangedSignal(DEBUG_THUNDER_ATTRIBUTE):Connect(function()
	if weatherFolder:GetAttribute(DEBUG_THUNDER_ATTRIBUTE) ~= true then
		return
	end

	weatherFolder:SetAttribute(DEBUG_THUNDER_ATTRIBUTE, false)

	if not Config.EnableThunderstorm then
		warn("[Weather] DebugThunder ignored -- EnableThunderstorm is false.")
		return
	end
	if ThunderService.isActive() then
		print("[Weather] thunderstorm already running")
		return
	end

	ThunderService.triggerNow()
	print(
		string.format(
			"[Weather] thunderstorm -> %.0fs warning, then %.0fs of strikes",
			Config.ThunderWarningLead,
			Config.ThunderDuration
		)
	)
end)

-- +1 moving with the wind, -1 straight into it, 0 crosswind or standing still.
local function windAlignment(humanoid: Humanoid, wind: Vector3): number
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 or wind.Magnitude < 0.1 then
		return 0
	end
	return wind.Unit:Dot(move.Unit)
end

local forceCache = setmetatable({}, { __mode = "k" }) :: { [BasePart]: VectorForce }

local function getWindForce(root: BasePart): VectorForce
	local existing = forceCache[root]
	if existing and existing.Parent == root then
		return existing
	end

	local found = root:FindFirstChild(WIND_FORCE_NAME)
	if found then
		forceCache[root] = found :: VectorForce
		return found :: VectorForce
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "StormWindAttachment"
	attachment.Parent = root

	local force = Instance.new("VectorForce")
	force.Name = WIND_FORCE_NAME
	force.Attachment0 = attachment
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.zero
	force.Enabled = false
	force.Parent = root

	forceCache[root] = force
	return force
end

local function updateAirborneDrift(root: BasePart, humanoid: Humanoid, wind: Vector3, windAlpha: number, exposed: boolean)
	local force = getWindForce(root)

	local state = humanoid:GetState()
	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping

	-- Unit of a zero vector is NaN, and a NaN force breaks the assembly.
	if not (airborne and exposed) or wind.Magnitude < 0.1 then
		force.Enabled = false
		return
	end

	local target = wind.Unit * (Config.WindAirborneAccel * windAlpha * root.AssemblyMass)

	if (target - force.Force).Magnitude > FORCE_EPSILON then
		force.Force = target
	end
	force.Enabled = true
end

local function updatePlayerSpeed(player: Player, intensity: number, wind: Vector3, sheltered: boolean)
	local entry = CharacterCache.getAlive(player)
	if not entry then
		return
	end

	local humanoid = entry.humanoid
	local exposed = intensity > 0 and not sheltered
	local windAlpha = math.clamp(wind.Magnitude / Config.WindStormSpeed, 0, 1)

	if Config.EnableWindAirborneDrift then
		updateAirborneDrift(entry.root, humanoid, wind, windAlpha, exposed)
	end

	if not exposed then
		SpeedService.clearModifier(humanoid, STORM_MODIFIER)
		return
	end

	local base = 1 + (Config.StormSpeedMultiplier - 1) * intensity
	local swing = Config.WindDirectionalSwing * windAlpha
	local multiplier = base + windAlignment(humanoid, wind) * swing

	SpeedService.setModifier(humanoid, STORM_MODIFIER, {
		mul = multiplier,
		jumpMul = 1 + (Config.StormJumpMultiplier - 1) * intensity,
	})
end

local function sweepPlayer(player: Player, intensity: number, wind: Vector3, recheckShelter: boolean, shelterCache: { [Player]: boolean })
	if recheckShelter or shelterCache[player] == nil then
		shelterCache[player] = WeatherService.isPlayerSheltered(player)
	end
	updatePlayerSpeed(player, intensity, wind, shelterCache[player])
end

if Config.EnableStormSlowdown then
	task.spawn(function()
		local wasClear = true
		local sinceShelter = math.huge

		local shelterCache = setmetatable({}, { __mode = "k" })

		while true do
			sinceShelter += task.wait(Config.StormDirectionInterval)

			local intensity = WeatherService.getIntensity()

			if intensity <= 0 and wasClear then
				continue
			end
			wasClear = intensity <= 0

			local recheckShelter = sinceShelter >= Config.StormSlowdownInterval
			if recheckShelter then
				sinceShelter = 0
			end

			local wind = WeatherService.getWind()

			for _, player in Players:GetPlayers() do
				local ok, err = pcall(sweepPlayer, player, intensity, wind, recheckShelter, shelterCache)
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

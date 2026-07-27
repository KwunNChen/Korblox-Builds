-- Entry point plus the storm's gameplay effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Weather"):WaitForChild("WeatherConfig"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))
local SpeedService = require(ServerScriptService:WaitForChild("Common"):WaitForChild("SpeedService"))

local STORM_MODIFIER = "Storm"
local DEBUG_ATTRIBUTE = "DebugStartIntensity"
local WIND_FORCE_NAME = "StormWindForce"

-- Raise to replicate the drift force less often, lower for finer steps.
local FORCE_EPSILON = 8

WeatherService.start()

-- Live debug knob on ReplicatedStorage.Weather. 0-1 forces that intensity,
-- negative resumes the cycle. WeatherConfig.DebugStartIntensity seeds it; set
-- the attribute at runtime to change it without a re-sync. The print confirms
-- the change actually reached the server.
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

-- Seeded before connecting so a normal boot does not log a spurious clear.
weatherFolder:SetAttribute(DEBUG_ATTRIBUTE, Config.DebugStartIntensity)

weatherFolder:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
	applyDebugIntensity(weatherFolder:GetAttribute(DEBUG_ATTRIBUTE))
end)

if Config.DebugStartIntensity >= 0 then
	applyDebugIntensity(Config.DebugStartIntensity)
end

-- +1 moving with the wind, -1 straight into it, 0 crosswind or standing still.
local function windAlignment(humanoid: Humanoid, wind: Vector3): number
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 or wind.Magnitude < 0.1 then
		return 0
	end
	return wind.Unit:Dot(move.Unit)
end

-- Built on demand and left parented to the character, so it dies with them.
local function getWindForce(character: Model): VectorForce?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local existing = root:FindFirstChild(WIND_FORCE_NAME)
	if existing then
		return existing :: VectorForce
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

	return force
end

local function updateAirborneDrift(character: Model, humanoid: Humanoid, wind: Vector3, windAlpha: number, exposed: boolean)
	local force = getWindForce(character)
	if not force then
		return
	end

	local state = humanoid:GetState()
	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping

	-- Unit of a zero vector is NaN, and a NaN force breaks the whole assembly.
	if not (airborne and exposed) or wind.Magnitude < 0.1 then
		force.Enabled = false
		return
	end

	local root = force.Parent :: BasePart
	local target = wind.Unit * (Config.WindAirborneAccel * windAlpha * root.AssemblyMass)

	if (target - force.Force).Magnitude > FORCE_EPSILON then
		force.Force = target
	end
	force.Enabled = true
end

local function updatePlayerSpeed(player: Player, intensity: number, wind: Vector3, sheltered: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local exposed = intensity > 0 and not sheltered
	local windAlpha = math.clamp(wind.Magnitude / Config.WindStormSpeed, 0, 1)

	if Config.EnableWindAirborneDrift then
		updateAirborneDrift(character, humanoid, wind, windAlpha, exposed)
	end

	if not exposed then
		SpeedService.clearModifier(humanoid, STORM_MODIFIER)
		return
	end

	-- Swing rides live wind speed rather than intensity, so gusts pulse the
	-- penalty instead of holding it flat for the whole phase.
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

		-- Heading changes far faster than shelter does, so the cheap arithmetic
		-- runs every tick while the raycast stays on its own slower clock.
		local shelterCache = setmetatable({}, { __mode = "k" })

		while true do
			sinceShelter += task.wait(Config.StormDirectionInterval)

			local intensity = WeatherService.getIntensity()

			-- Skip the whole sweep in clear weather once everyone is released.
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiPhysics = {}

local UP = Vector3.yAxis

export type Ground = {
	normal: Vector3,
	friction: number,
}

export type Input = {
	steer: number,
	braking: boolean,
	tucking: boolean,
}

export type State = {
	velocity: Vector3,
	heading: Vector3,
	up: Vector3,
}

function SkiPhysics.slopePull(normal: Vector3, gravity: number): Vector3
	return Shared.projectOnPlane(Vector3.new(0, -gravity, 0), normal) * Config.SlopeAccelGain
end

function SkiPhysics.turnRateAt(speed: number): number
	return Config.TurnRate / (1 + speed * Config.TurnSpeedFalloff)
end

local function rotateAround(vector: Vector3, axis: Vector3, angle: number): Vector3
	local cos, sin = math.cos(angle), math.sin(angle)
	return vector * cos + axis:Cross(vector) * sin + axis * (axis:Dot(vector) * (1 - cos))
end

function SkiPhysics.groundStep(state: State, input: Input, ground: Ground, gravity: number, dt: number): State
	local normal = ground.normal

	local forward = Shared.safeUnit(Shared.projectOnPlane(state.heading, normal), state.heading)

	local velocity = state.velocity
	local planarSpeed = Shared.projectOnPlane(velocity, normal).Magnitude

	if input.steer ~= 0 then
		local rate = SkiPhysics.turnRateAt(planarSpeed)
		forward = Shared.safeUnit(rotateAround(forward, normal, -input.steer * rate * dt), forward)
	end

	local lateral = Shared.safeUnit(normal:Cross(forward), Vector3.xAxis)

	local vForward = velocity:Dot(forward)
	local vLateral = velocity:Dot(lateral)

	local pull = SkiPhysics.slopePull(normal, gravity)
	vForward += pull:Dot(forward) * dt
	vLateral += pull:Dot(lateral) * dt

	local lateralDrag = input.braking and Config.BrakeLateralDrag or Config.LateralDrag
	local keptLateral = vLateral * math.exp(-lateralDrag * dt)
	local scrubbed = math.abs(vLateral - keptLateral)
	vLateral = keptLateral

	local forwardSign = if vForward < 0 then -1 else 1
	vForward += scrubbed * Config.CarveRecovery * forwardSign

	vForward *= math.exp(-Config.ForwardDrag * dt)

	local airDrag = Config.AirDrag * (input.tucking and Config.TuckDragMultiplier or 1)
	vForward -= forwardSign * airDrag * vForward * vForward * dt

	local speed = math.sqrt(vForward * vForward + vLateral * vLateral)
	if speed > 1e-4 then
		local decel = ground.friction * gravity * math.max(normal:Dot(UP), 0) * dt
		local scale = math.max(speed - decel, 0) / speed
		vForward *= scale
		vLateral *= scale
	end

	if input.braking then
		speed = math.sqrt(vForward * vForward + vLateral * vLateral)
		if speed <= Config.BrakeHoldSpeed then
			vForward, vLateral = 0, 0
		else
			local braked = math.max(speed - Config.BrakeDecel * dt, 0)
			local scale = braked / speed
			vForward *= scale
			vLateral *= scale
		end
	end

	local newVelocity = forward * vForward + lateral * vLateral
	if newVelocity.Magnitude > Config.MaxSpeed then
		newVelocity = newVelocity.Unit * Config.MaxSpeed
	end

	return {
		velocity = newVelocity,
		heading = forward,
		up = normal,
	}
end

function SkiPhysics.hoverAccel(heightError: number, closingSpeed: number): number
	return heightError * Config.HoverStiffness - closingSpeed * Config.HoverDamping
end

function SkiPhysics.airStep(state: State, input: Input, gravity: number, dt: number): State
	local velocity = state.velocity

	velocity += Vector3.new(0, -gravity * dt, 0)

	local speed = velocity.Magnitude
	if speed > 1e-4 then
		local airDrag = Config.AirDrag * (input.tucking and Config.TuckDragMultiplier or 1)
		velocity -= velocity.Unit * (airDrag * speed * speed * dt)
	end

	local heading = state.heading
	local up = state.up

	if input.steer ~= 0 then
		local yaw = -input.steer * Config.AirYawRate * dt
		heading = Shared.safeUnit(rotateAround(heading, UP, yaw), heading)
		up = Shared.safeUnit(rotateAround(up, UP, yaw), up)

		local lateral = Shared.safeUnit(UP:Cross(heading), Vector3.xAxis)
		velocity += lateral * (input.steer * Config.AirDriftAccel * dt)
	end

	if velocity.Magnitude > Config.MaxSpeed then
		velocity = velocity.Unit * Config.MaxSpeed
	end

	return { velocity = velocity, heading = heading, up = up }
end

export type Landing = {
	crashed: boolean,
	speedKeep: number,
	errorDegrees: number,
}

function SkiPhysics.landingQuality(heading: Vector3, skiUp: Vector3, velocity: Vector3, normal: Vector3): Landing
	local impact = -velocity:Dot(normal)
	if impact > Config.CrashImpactSpeed then
		return { crashed = true, speedKeep = Config.CrashSpeedKeep, errorDegrees = 180 }
	end

	local travel = Shared.projectOnPlane(velocity, normal)
	local flatHeading = Shared.projectOnPlane(heading, normal)

	local misalignment = 0
	if travel.Magnitude > 1 and flatHeading.Magnitude > 1e-4 then
		local dot = math.clamp(travel.Unit:Dot(flatHeading.Unit), -1, 1)
		misalignment = math.deg(math.acos(dot))
	end

	local tilt = math.deg(math.acos(math.clamp(skiUp:Dot(normal), -1, 1)))

	local errorDegrees = math.max(misalignment, tilt)

	if errorDegrees >= Config.LandingCrashAngle then
		return { crashed = true, speedKeep = Config.CrashSpeedKeep, errorDegrees = errorDegrees }
	end

	if errorDegrees <= Config.LandingCleanAngle then
		return { crashed = false, speedKeep = 1, errorDegrees = errorDegrees }
	end

	local t = (errorDegrees - Config.LandingCleanAngle) / (Config.LandingCrashAngle - Config.LandingCleanAngle)
	return {
		crashed = false,
		speedKeep = Shared.lerp(1, Config.LandingWorstKeep, t),
		errorDegrees = errorDegrees,
	}
end

return table.freeze(SkiPhysics)

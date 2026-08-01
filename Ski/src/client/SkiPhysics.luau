--[[
	SkiPhysics
	The velocity and orientation math, with no Instances in sight. Everything
	here takes numbers and vectors and returns numbers and vectors, so the feel
	can be reasoned about (and tested) without a character attached.

	Two things worth knowing before you tune anything:

	1. Drag is applied as exp(-k * dt), not (1 - k * dt). The exponential form is
	   exact at any timestep, so a player at 30 fps gets the same curve as one at
	   240. The naive form quietly changes the feel with framerate and explodes
	   outright if k * dt ever exceeds 1.

	2. The downhill pull is just gravity with its ground-normal component
	   removed. Flat ground yields zero automatically, steep ground yields a lot,
	   and there is no slope-angle special case anywhere in this file.
]]

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
	steer: number, -- -1 (left) to 1 (right)
	pitch: number, -- -1 (nose down) to 1 (nose up), airborne only
	braking: boolean,
	tucking: boolean,
}

export type State = {
	velocity: Vector3,
	heading: Vector3, -- unit, the direction the ski tips point
	up: Vector3, -- unit, the ground normal when riding, free to tumble in the air
}

-- Gravity's component in the ground plane. This is the entire "downhill" idea.
function SkiPhysics.slopePull(normal: Vector3, gravity: number): Vector3
	return Shared.projectOnPlane(Vector3.new(0, -gravity, 0), normal) * Config.SlopeAccelGain
end

-- Turning tightens up as you speed up. Most of why going fast feels committing
-- rather than merely quick.
function SkiPhysics.turnRateAt(speed: number): number
	return Config.TurnRate / (1 + speed * Config.TurnSpeedFalloff)
end

-- Rotate `vector` around `axis` by `angle` radians (Rodrigues). Used to swing
-- the heading around the ground normal, so steering stays in the slope plane
-- instead of drifting off it on steep ground.
local function rotateAround(vector: Vector3, axis: Vector3, angle: number): Vector3
	local cos, sin = math.cos(angle), math.sin(angle)
	return vector * cos + axis:Cross(vector) * sin + axis * (axis:Dot(vector) * (1 - cos))
end

-- ============================================================
-- GROUNDED
-- ============================================================

function SkiPhysics.groundStep(state: State, input: Input, ground: Ground, gravity: number, dt: number): State
	local normal = ground.normal

	-- Keep the heading in the slope plane. On a steep pitch a heading left over
	-- from flatter ground points into the hill; projecting fixes it every frame.
	local forward = Shared.safeUnit(Shared.projectOnPlane(state.heading, normal), state.heading)

	local velocity = state.velocity
	local planarSpeed = Shared.projectOnPlane(velocity, normal).Magnitude

	-- Steer, then rebuild the axes so everything below is in the new frame.
	if input.steer ~= 0 then
		local rate = SkiPhysics.turnRateAt(planarSpeed)
		forward = Shared.safeUnit(rotateAround(forward, normal, -input.steer * rate * dt), forward)
	end

	local lateral = Shared.safeUnit(normal:Cross(forward), Vector3.xAxis)

	local vForward = velocity:Dot(forward)
	local vLateral = velocity:Dot(lateral)

	-- Gravity along the slope, split into the two axes.
	local pull = SkiPhysics.slopePull(normal, gravity)
	vForward += pull:Dot(forward) * dt
	vLateral += pull:Dot(lateral) * dt

	-- Edge grip. Whatever sideways speed the edges scrub off, a fraction comes
	-- back as forward speed -- that is carving, and it is why a clean turn costs
	-- less than a sloppy one.
	local lateralDrag = input.braking and Config.BrakeLateralDrag or Config.LateralDrag
	local keptLateral = vLateral * math.exp(-lateralDrag * dt)
	local scrubbed = math.abs(vLateral - keptLateral)
	vLateral = keptLateral

	local forwardSign = if vForward < 0 then -1 else 1
	vForward += scrubbed * Config.CarveRecovery * forwardSign

	-- Along-ski drag: a small linear term plus the quadratic one that actually
	-- sets terminal speed. Tucking cuts the quadratic term only, which is why it
	-- pays off at speed and does almost nothing when you're slow.
	vForward *= math.exp(-Config.ForwardDrag * dt)

	local airDrag = Config.AirDrag * (input.tucking and Config.TuckDragMultiplier or 1)
	vForward -= forwardSign * airDrag * vForward * vForward * dt

	-- Coulomb friction from the snow, applied to the whole planar velocity so it
	-- does not care which way you happen to be pointing. Scales with cos(slope),
	-- so it bites hardest on the flat -- which is what you want.
	local speed = math.sqrt(vForward * vForward + vLateral * vLateral)
	if speed > 1e-4 then
		local decel = ground.friction * gravity * math.max(normal:Dot(UP), 0) * dt
		local scale = math.max(speed - decel, 0) / speed
		vForward *= scale
		vLateral *= scale
	end

	-- Snowplow. Has to out-pull the slope or braking won't hold on steep ground.
	if input.braking then
		speed = math.sqrt(vForward * vForward + vLateral * vLateral)
		if speed <= Config.BrakeHoldSpeed then
			-- Pin rather than let the slope ooze you downhill forever.
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

--[[
	Spring that holds the root at HoverHeight. A spring rather than a hard snap,
	because snapping reads as teleporting over every bump.

	`closingSpeed` MUST be the rate of change of height above the ground, not the
	world-space vertical velocity. They are the same thing on flat ground and
	wildly different on a slope: skiing downhill has a large negative Y velocity
	while the height above the snow never changes. Feed it Y velocity and the
	damping term reads every descent as a fall and shoves you upward, which
	shows up as the skis mysteriously braking on exactly the terrain they should
	be accelerating on.
]]
function SkiPhysics.hoverAccel(heightError: number, closingSpeed: number): number
	return heightError * Config.HoverStiffness - closingSpeed * Config.HoverDamping
end

-- ============================================================
-- AIRBORNE
-- ============================================================

function SkiPhysics.airStep(state: State, input: Input, gravity: number, dt: number): State
	local velocity = state.velocity

	velocity += Vector3.new(0, -gravity * dt, 0)

	-- Quadratic drag on the whole velocity, not just forward -- in the air there
	-- is no "forward" to privilege.
	local speed = velocity.Magnitude
	if speed > 1e-4 then
		local airDrag = Config.AirDrag * (input.tucking and Config.TuckDragMultiplier or 1)
		velocity -= velocity.Unit * (airDrag * speed * speed * dt)
	end

	local heading = state.heading
	local up = state.up

	-- Yaw is spins, and it turns the whole rig -- rotating the heading without
	-- the up vector would leave you facing sideways but still flat, which reads
	-- as a glitch rather than a spin.
	if input.steer ~= 0 then
		local yaw = -input.steer * Config.AirYawRate * dt
		heading = Shared.safeUnit(rotateAround(heading, UP, yaw), heading)
		up = Shared.safeUnit(rotateAround(up, UP, yaw), up)

		-- A small sideways nudge so you can adjust a line, not rewrite it.
		local lateral = Shared.safeUnit(UP:Cross(heading), Vector3.xAxis)
		velocity += lateral * (input.steer * Config.AirDriftAccel * dt)
	end

	-- Pitch is flips, taken about the axis running through the skis. The
	-- controller feeds 0 for now -- turning that on is what starts tricks.
	if input.pitch ~= 0 then
		local pitch = input.pitch * Config.AirPitchRate * dt
		local axis = Shared.safeUnit(heading:Cross(up), Vector3.xAxis)
		heading = Shared.safeUnit(rotateAround(heading, axis, pitch), heading)
		up = Shared.safeUnit(rotateAround(up, axis, pitch), up)
	end

	if velocity.Magnitude > Config.MaxSpeed then
		velocity = velocity.Unit * Config.MaxSpeed
	end

	return { velocity = velocity, heading = heading, up = up }
end

-- ============================================================
-- LANDING
-- ============================================================

export type Landing = {
	crashed: boolean,
	speedKeep: number,
	errorDegrees: number,
}

--[[
	Two ways to land badly, and we take whichever is worse:

	  * sideways -- the skis point somewhere other than where you're travelling
	  * flat-footed -- the skis aren't parallel to the ground you're hitting

	Plus a straight impact check, because dropping onto a perfectly aligned
	surface from 300 studs up should still hurt.
]]
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

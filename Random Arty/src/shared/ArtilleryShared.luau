-- Helpers shared by the server and client artillery code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("ArtilleryConfig"))

local ArtilleryShared = {}

ArtilleryShared.Attr = table.freeze({
	BarrageActive = "BarrageActive",
	WarningActive = "WarningActive",
	ShellsLeft = "ShellsLeft",
	SecondsToFirstImpact = "SecondsToFirstImpact",
})

function ArtilleryShared.getStateHolder(): Instance
	return ReplicatedStorage:WaitForChild("ArtilleryState")
end

-- Nil if it is missing; callers disable themselves rather than yield forever.
function ArtilleryShared.getShellEvent(): RemoteEvent?
	return ReplicatedStorage:WaitForChild("ArtilleryShell", 10) :: RemoteEvent?
end

function ArtilleryShared.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Framerate-independent smoothing. `smoothing` is a time constant in seconds.
function ArtilleryShared.damp(current: number, target: number, smoothing: number, dt: number): number
	if smoothing <= 0 then
		return target
	end
	return target + (current - target) * math.exp(-dt / smoothing)
end

function ArtilleryShared.rollRange(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

--[[
	Normalizes an asset slot into something the engine will load, or "" if the
	slot was never filled in.

	Two completely different kinds of value are valid here:

	  rbxasset://textures/particles/smoke_main.dds   an ENGINE path. Ships with
	                                                 Studio, contains NO digits,
	                                                 and is already final.
	  rbxassetid://13623094740                       an UPLOADED asset id.
	  13623094740                                    the same, bare.

	Engine paths have to be passed straight through. Running one through the
	digit match below finds nothing, returns "", and the caller then silently
	leaves the property unset -- which for a ParticleEmitter means falling back
	to Roblox's default white sparkle. That failure is invisible in Output and
	looks exactly like "the texture I set is being ignored", because it is.

	Six digits is the floor for uploaded ids because every real one clears it,
	while placeholder text like "PUT ID HERE" does not.
]]
function ArtilleryShared.assetId(value: any): string
	if type(value) ~= "string" or value == "" then
		return ""
	end

	--[[
		An engine path, passed straight through -- but ONLY if it is a real path.

		"rbxasset://6286534083" is the trap: the engine-path prefix with an
		UPLOADED id after it, which is what you get by copying the shape of the
		default and pasting an id into it. rbxasset:// resolves a file that ships
		with Studio, so a number there names nothing and the texture renders
		blank with no error. Digits after the prefix always mean an upload, so
		rewrite it rather than handing back something that cannot load.
	]]
	local enginePath = value:match("^rbxasset://(.+)$")
	if enginePath and not enginePath:match("^%d+$") then
		return value
	end

	local digits = value:match("(%d+)")
	if not digits or #digits < 6 then
		return ""
	end
	return "rbxassetid://" .. digits
end

--[[
	TRAJECTORY

	Both sides run this, so a shell is described over the network by nothing but
	its impact point, its launch point and its timing. No positions are streamed.

	Given a launch point S, an impact point P and a flight time T, solve for the
	launch velocity that lands exactly on P:

		P = S + v*T + 0.5*a*T^2       ->      v = (P - S - 0.5*a*T^2) / T

	The shell then accelerates downward for the whole flight, so it comes in
	visibly faster than it went out. That acceleration is the entire reason this
	is real projectile motion rather than a Bezier -- a curve travelled at
	constant speed reads as floaty no matter how nice its shape is.

	ShellGravity is a look knob, not physics. It has nothing to do with
	workspace.Gravity and does not need to match it; the shell is drawn, never
	simulated.
]]

local function accel(): Vector3
	return Vector3.new(0, -Config.ShellGravity, 0)
end

function ArtilleryShared.solveVelocity(launch: Vector3, impact: Vector3, flightTime: number): Vector3
	local a = accel()
	return (impact - launch - a * (0.5 * flightTime * flightTime)) / flightTime
end

function ArtilleryShared.positionAt(launch: Vector3, velocity: Vector3, elapsed: number): Vector3
	return launch + velocity * elapsed + accel() * (0.5 * elapsed * elapsed)
end

-- Where a shell aimed at `impact` starts from, given the barrage's heading.
-- Heading is in degrees; every shell in one barrage shares it, give or take
-- BatteryHeadingSpread, which is what puts the trails roughly parallel.
function ArtilleryShared.launchPoint(impact: Vector3, headingDegrees: number, distance: number, height: number): Vector3
	local radians = math.rad(headingDegrees)
	return impact + Vector3.new(math.cos(radians) * distance, height, math.sin(radians) * distance)
end

return table.freeze(ArtilleryShared)

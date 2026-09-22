--!strict
--[[
	A short speed boost for landing a vault.

	--------------------------------------------------------------------------
	WHY THIS IS NOT ONE LINE
	--------------------------------------------------------------------------

	Setting Humanoid.WalkSpeed does not stick. TREK's MovementHandler runs a
	`while true ... task.wait(.1)` loop that flips Sprinting, and every flip
	writes WalkSpeed; ControlsModule writes it again on every crouch toggle. A
	boost applied once is gone inside a tenth of a second, and worse, it is gone
	INTERMITTENTLY -- it survives if you happen not to change state, which reads
	as "the boost sometimes doesn't work".

	So the boost re-asserts every frame. That wins, because a frame is shorter
	than TREK's poll.

	--------------------------------------------------------------------------
	AND WHY IT GIVES UP
	--------------------------------------------------------------------------

	Winning every frame means we would also overwrite TREK's LEGITIMATE writes --
	the crouch that should slow you to 6, the sprint that should take you to 24.
	Holding a boost through those would be a bug wearing a feature's clothes.

	So the three TREK flags are snapshotted when the boost starts and checked
	each frame. Any change and the boost stands down immediately and hands
	WalkSpeed back. You lose the rest of your boost by crouching; that is the
	correct trade, and it is one the player caused.

	The multiplier is applied to whatever WalkSpeed was at the moment the vault
	landed, not to a constant. That matters if another package is already
	slowing the player -- Variable Snowstorm's storm, say -- because the boost
	then scales their value rather than replacing it, and restores it on exit.
]]

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local package = ReplicatedStorage:WaitForChild("TREKParkour")
local Config = require(package:WaitForChild("ParkourConfig"))
local Shared = require(package:WaitForChild("ParkourShared"))

local ParkourBoost = {}

local BIND_NAME = "TREKParkourBoost"

-- The flags TREK writes WalkSpeed in response to. If any of them moves, the
-- write that follows is TREK's business and not ours to contest.
local WATCHED = { "Sprinting", "SprintEnabled", "Crouching" }

-- Same epsilon Ski's SpeedService uses -- writing a property to the value it
-- already holds is not free, and this runs every frame.
local WRITE_EPSILON = 0.05

type Boost = {
	humanoid: Humanoid,
	character: Model,
	base: number,
	target: number,
	expires: number,
	flags: { [string]: boolean },
}

local boost: Boost? = nil

local function readFlags(character: Model): { [string]: boolean }
	local snapshot = {}
	for _, name in WATCHED do
		local value = Shared.boolValue(character, name)
		snapshot[name] = value ~= nil and value.Value or false
	end
	return snapshot
end

local function flagsMoved(current: Boost): boolean
	for _, name in WATCHED do
		local value = Shared.boolValue(current.character, name)
		local now = value ~= nil and value.Value or false
		if now ~= current.flags[name] then
			return true
		end
	end
	return false
end

--[[
	Give WalkSpeed back. Safe to call twice, and safe on a dead character.

	The restore is deliberately unconditional rather than "only if it still
	holds our value": we have been overwriting every frame, so our value is what
	it holds, and there is nothing else it could be.
]]
function ParkourBoost.cancel(reason: string?)
	local current = boost
	if not current then
		return
	end
	boost = nil

	pcall(RunService.UnbindFromRenderStep, RunService, BIND_NAME)

	if current.humanoid.Parent and current.humanoid.Health > 0 then
		current.humanoid.WalkSpeed = current.base
	end

	if reason then
		Shared.log("boost ended (%s)", reason)
	end
end

function ParkourBoost.apply(character: Model, humanoid: Humanoid)
	if not Config.EnableVaultBoost or Config.VaultBoostMultiplier <= 1 then
		return
	end

	ParkourBoost.cancel()

	local base = humanoid.WalkSpeed
	if base <= 0 then
		return
	end

	local current: Boost = {
		humanoid = humanoid,
		character = character,
		base = base,
		target = base * Config.VaultBoostMultiplier,
		expires = os.clock() + Config.VaultBoostDuration,
		flags = readFlags(character),
	}
	boost = current

	--[[
		Character priority + 1, the same slot the motion uses, so the write lands
		after the Humanoid has had its turn for the frame.
	]]
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value + 1, function()
		if not boost then
			return
		end

		if not humanoid.Parent or humanoid.Health <= 0 or not character.Parent then
			ParkourBoost.cancel()
			return
		end

		if os.clock() >= current.expires then
			ParkourBoost.cancel("expired")
			return
		end

		-- Crouched, sprinted, or stopped sprinting -- TREK owns the speed again.
		if flagsMoved(current) then
			ParkourBoost.cancel("state changed")
			return
		end

		if math.abs(humanoid.WalkSpeed - current.target) > WRITE_EPSILON then
			humanoid.WalkSpeed = current.target
		end
	end)

	Shared.log("boost -- %.1f to %.1f for %.1fs", base, current.target, Config.VaultBoostDuration)
end

return ParkourBoost

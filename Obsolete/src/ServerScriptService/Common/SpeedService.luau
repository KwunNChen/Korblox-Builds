-- Single owner of Humanoid.WalkSpeed and jump height. Register named modifiers
-- instead of assigning either directly -- see the README for the full API.

local SpeedService = {}

SpeedService.MinWalkSpeed = 4

local WRITE_EPSILON = 0.05

local records = setmetatable({}, { __mode = "k" })

local function getRecord(humanoid: Humanoid)
	local record = records[humanoid]
	if not record then
		record = {
			base = humanoid.WalkSpeed,
			jumpPowerBase = humanoid.JumpPower,
			jumpHeightBase = humanoid.JumpHeight,
			mods = {},
		}
		records[humanoid] = record
	end
	return record
end

local function recompute(humanoid: Humanoid)
	local record = records[humanoid]
	if not record then
		return
	end

	local multiplier, addition = 1, 0
	local jumpMultiplier, jumpAddition = 1, 0

	for _, modifier in record.mods do
		if modifier.mul then
			multiplier *= modifier.mul
		end
		if modifier.add then
			addition += modifier.add
		end
		if modifier.jumpMul then
			jumpMultiplier *= modifier.jumpMul
		end
		if modifier.jumpAdd then
			jumpAddition += modifier.jumpAdd
		end
	end

	local target = math.max(record.base * multiplier + addition, SpeedService.MinWalkSpeed)

	if math.abs(humanoid.WalkSpeed - target) > WRITE_EPSILON then
		humanoid.WalkSpeed = target
	end

	if humanoid.UseJumpPower then
		local jumpTarget = math.max(record.jumpPowerBase * jumpMultiplier + jumpAddition, 0)
		if math.abs(humanoid.JumpPower - jumpTarget) > WRITE_EPSILON then
			humanoid.JumpPower = jumpTarget
		end
	else
		local jumpTarget = math.max(record.jumpHeightBase * jumpMultiplier + jumpAddition, 0)
		if math.abs(humanoid.JumpHeight - jumpTarget) > WRITE_EPSILON then
			humanoid.JumpHeight = jumpTarget
		end
	end
end

-- Only needed if a character's baseline legitimately changes.
function SpeedService.setBase(humanoid: Humanoid, base: number)
	getRecord(humanoid).base = base
	recompute(humanoid)
end

function SpeedService.setJumpBase(humanoid: Humanoid, base: number)
	local record = getRecord(humanoid)
	if humanoid.UseJumpPower then
		record.jumpPowerBase = base
	else
		record.jumpHeightBase = base
	end
	recompute(humanoid)
end

function SpeedService.setModifier(
	humanoid: Humanoid,
	name: string,
	modifier: { mul: number?, add: number?, jumpMul: number?, jumpAdd: number? }
)
	getRecord(humanoid).mods[name] = modifier
	recompute(humanoid)
end

function SpeedService.clearModifier(humanoid: Humanoid, name: string)
	local record = records[humanoid]
	if not record or record.mods[name] == nil then
		return
	end

	record.mods[name] = nil
	recompute(humanoid)
end

function SpeedService.getBase(humanoid: Humanoid): number
	return getRecord(humanoid).base
end

return SpeedService

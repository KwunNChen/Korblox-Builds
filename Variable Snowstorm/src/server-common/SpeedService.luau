--[[
	Single owner of Humanoid.WalkSpeed.

		final = base * (all multipliers) + (all additions)

	Register a named modifier instead of assigning WalkSpeed directly:

		SpeedService.setModifier(humanoid, "Sprint", { mul = 1.5 })
		SpeedService.clearModifier(humanoid, "Sprint")

	Re-using a name replaces that system's value. Once a humanoid is managed
	here, nothing else may assign its WalkSpeed.
]]

local SpeedService = {}

SpeedService.MinWalkSpeed = 4

local WRITE_EPSILON = 0.05

local records = setmetatable({}, { __mode = "k" })

local function getRecord(humanoid: Humanoid)
	local record = records[humanoid]
	if not record then
		record = { base = humanoid.WalkSpeed, mods = {} }
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
	for _, modifier in record.mods do
		if modifier.mul then
			multiplier *= modifier.mul
		end
		if modifier.add then
			addition += modifier.add
		end
	end

	local target = math.max(record.base * multiplier + addition, SpeedService.MinWalkSpeed)

	if math.abs(humanoid.WalkSpeed - target) > WRITE_EPSILON then
		humanoid.WalkSpeed = target
	end
end

-- Only needed if a character's baseline legitimately changes.
function SpeedService.setBase(humanoid: Humanoid, base: number)
	getRecord(humanoid).base = base
	recompute(humanoid)
end

function SpeedService.setModifier(humanoid: Humanoid, name: string, modifier: { mul: number?, add: number? })
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

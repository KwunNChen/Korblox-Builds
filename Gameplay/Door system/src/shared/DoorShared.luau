local DoorShared = {}

function DoorShared.localAxis(axis: string): Vector3
	if axis == "Y" then
		return Vector3.yAxis
	elseif axis == "Z" then
		return Vector3.zAxis
	end
	return Vector3.xAxis
end

function DoorShared.crushBoxSize(gap: number, config): Vector3
	local depth = config.CrushZoneDepth
	local height = config.CrushZoneHeight

	if config.SlideAxis == "Z" then
		return Vector3.new(depth, height, gap)
	elseif config.SlideAxis == "Y" then
		return Vector3.new(depth, gap, depth)
	end
	return Vector3.new(gap, height, depth)
end

return DoorShared

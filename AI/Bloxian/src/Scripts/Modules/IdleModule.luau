--[[
	Spots a soldier doing nothing in a fight: no move of more than IDLE_MOVE
	studs and no shot fired for IDLE_LIMIT seconds. The brain then moves him on.
]]

local IDLE_LIMIT = 8
local IDLE_MOVE = 4

local idle = {}

local since,from,shots = nil,nil,nil

--Called every brain tick. active: he is in a fight he should be doing
--something about. True once he has done nothing for IDLE_LIMIT seconds (and
--the clock starts over).
function idle.check(active,now,position,shotsFired)
	if not active or not since or shotsFired ~= shots or (position - from).Magnitude > IDLE_MOVE then
		since,from,shots = now,position,shotsFired
		return false
	end
	if now - since < IDLE_LIMIT then
		return false
	end
	since,from = now,position
	return true
end

return idle

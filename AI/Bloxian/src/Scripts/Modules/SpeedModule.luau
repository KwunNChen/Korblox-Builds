--[[
	A soldier's walk speed: every module sets it here, never on the Humanoid.

	What he is doing sets his base (walking, aiming, rushing); lying down cuts it to
	a share. When the place has ServerScriptService.Common.SpeedService (Random
	Arty, Ski, Variable Snowstorm ship it), that owns WalkSpeed and this goes
	through it, so a storm or a concussion multiplies his speed instead of being
	written over by it.
]]

local speed = {}

local marine = script.Parent.Parent.Parent
local myHuman = marine.Humanoid

local common = game:GetService("ServerScriptService"):FindFirstChild("Common")
local serviceModule = common and common:FindFirstChild("SpeedService")
local service = serviceModule and require(serviceModule)

local PRONE_MODIFIER = "BloxianProne"

local base = myHuman.WalkSpeed
local proneShare = nil

--Without SpeedService he is the only one writing it.
local function apply()
	myHuman.WalkSpeed = base*(proneShare or 1)
end

function speed.set(value)
	base = value
	if service then
		service.setBase(myHuman,value)
	else
		apply()
	end
end

function speed.get()
	return base
end

--share of his speed while lying down, or nil standing.
function speed.setProne(share)
	proneShare = share
	if not service then
		apply()
	elseif share then
		service.setModifier(myHuman,PRONE_MODIFIER,{mul = share})
	else
		service.clearModifier(myHuman,PRONE_MODIFIER)
	end
end

return speed

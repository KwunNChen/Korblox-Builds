local status = {
	reloading = false,
	weaponAimed = false,
	weaponCool = true,
	m4Equipped = false,
	m4Lowered = false,
	knifeEquipped = false,
	grenadeCool = true,
	currentTarget = false,
	mood = "Idle",
	pendingMood = nil,
	currentFace = "",
	tookDamage = false,
	potentialTargets = {},
	activeAllies = {},
	mag = 30,
	actionDepth = 0,
	lastDamaged = -math.huge,
	lastHit = -math.huge,
	squadHoldFire = false,
	stealth = false,
	shotsFired = 0,
	teamStance = nil,
}

function status:set(var,val)
	self[var] = val
end

function status:get(var)
	return self[var]
end

--Marks the soldier as mid-action so the chatter stays quiet until endAction.
function status:beginAction()
	self.actionDepth += 1
end

function status:endAction()
	self.actionDepth = math.max(self.actionDepth - 1,0)
end

return status

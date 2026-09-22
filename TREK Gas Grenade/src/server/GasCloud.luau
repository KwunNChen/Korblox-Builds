--[[
	GasCloud
	The lingering volume, and everything it does to the people standing in it.

	Server-only, and it will stay that way. The client draws nothing here and is
	never asked what it is standing in -- a client that simply declined to report
	being in the gas would be immune to it.

	The cloud takes a snapshot of its configuration when it spawns and never
	looks at the thrower's tool again. It has to: TREK resolves a tool's config
	through `returnTool`, which is `FindFirstChildOfClass('Tool')` on the
	character -- the *currently equipped* tool. A grenade's whole life happens
	after it left the hand, by which point that lookup returns a rifle, or
	nothing at all.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

--[[
	Bounded, and loud when it fails.

	An unbounded WaitForChild inside a require chain does not fail -- it hangs
	the module forever, and every module waiting on THIS one hangs with it.
	Adding one new file to this chain once killed the entire service that way:
	the grenade quietly stopped being held, with nothing in the output to say
	why, because nothing had errored. It was still waiting.

	Ten seconds is far longer than replication or install ever needs and far
	shorter than a playtest, so a missing file announces itself instead.
]]
local function expect(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name) or parent:WaitForChild(name, 10)

	if not child then
		error(string.format(
			"[TREKGasGrenade] %s has no child %q -- the install is incomplete. "
				.. "Check every folder moved out of the staging folder, including "
				.. "any added since you last installed.",
			parent:GetFullName(), name
		), 0)
	end

	return child
end

local GasVisuals = require(expect(script.Parent, "GasVisuals"))
local GasExposure = require(expect(script.Parent, "GasExposure"))

local GasCloud = {}

--[[
	TREK's own damage entry point, required straight out of ServerStorage the
	way BayonetService does it.

	DamagePlayer is used rather than Humanoid:TakeDamage because it also tags the
	victim for kill credit -- a WeaponTag ObjectValue the leaderboard reads -- and
	records the damage against the thrower's stats. A raw TakeDamage kills people
	and credits nobody.

	Note this deliberately avoids TREKDamageModule.setDamage and the explosion
	module's calcDamage. Both run damage through an armour-resist branch whose
	math.clamp arguments are in the wrong order (value and min are swapped), so
	any part carrying an ArmourDamageResist takes exactly zero. Falloff here is
	computed locally instead, which sidesteps that entirely.
]]
local damageModule = require(expect(ServerStorage, "TREKDamageModule"))

--[[
	How many times a raycast may pass through a body before giving up.

	A person standing between you and the gas does not stop the gas, so character
	hits are skipped and the ray continues. The cap keeps a crowd from turning
	one line-of-sight check into an unbounded loop.
]]
local MAX_LOS_PASSES = 4

local CONDITION_COUNT = "GasSourceCount"

local function characterFrom(part: BasePart): (Model?, Humanoid?)
	local humanoid = nil
	local model = part:FindFirstAncestorOfClass("Model")

	while model do
		humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return model, humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end

	return nil, nil
end

--[[
	Damage multiplier by distance.

	Full strength out to FullDamageRadius, then a straight taper to nothing at
	the edge. Deliberately gentler than a blast curve: the rim of a gas cloud
	should be unpleasant enough to move people out of it, not a safe place to
	stand and shoot from.
]]
local function falloff(distance: number, config): number
	if distance <= config.FullDamageRadius then
		return 1
	end

	local span = config.CloudRadius - config.FullDamageRadius
	if span <= 0 then
		return 1
	end

	return math.clamp(1 - ((distance - config.FullDamageRadius) / span), 0, 1)
end

--[[
	Is there world geometry between the cloud and this character?

	Bodies are transparent to gas, so a hit on another character is skipped and
	the ray re-fired from the same origin with that character excluded. Anything
	else -- a wall, a crate, a vehicle hull -- blocks.
]]
local function hasLineOfSight(origin: Vector3, target: BasePart, ignore: Instance?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local filter: { Instance } = { target.Parent :: Instance }
	if ignore then
		table.insert(filter, ignore)
	end
	params.FilterDescendantsInstances = filter

	for _ = 1, MAX_LOS_PASSES do
		local delta = target.Position - origin
		local result = workspace:Raycast(origin, delta, params)

		if not result then
			return true
		end

		local blockingCharacter = characterFrom(result.Instance)
		if not blockingCharacter then
			return false
		end

		table.insert(filter, blockingCharacter)
		params.FilterDescendantsInstances = filter
	end

	return false
end

--[[
	Mark a humanoid as being gassed.

	Ref-counted, because two overlapping clouds must not have the first one to
	expire clear a condition the second one is still applying. The BoolValue name
	follows TREK's own convention for status -- TBleedCondition, TParalCondition
	-- so anything else in the game that wants to react to "this player is in
	gas" has a consistent place to look.
]]
local function markCondition(humanoid: Humanoid, config)
	local count = (humanoid:GetAttribute(CONDITION_COUNT) or 0) + 1
	humanoid:SetAttribute(CONDITION_COUNT, count)

	if not humanoid:FindFirstChild(config.ConditionName) then
		local flag = Instance.new("BoolValue")
		flag.Name = config.ConditionName
		flag.Value = true
		flag.Parent = humanoid
	end
end

local function clearCondition(humanoid: Humanoid, config)
	if not humanoid or not humanoid.Parent then
		return
	end

	local count = (humanoid:GetAttribute(CONDITION_COUNT) or 1) - 1

	if count > 0 then
		humanoid:SetAttribute(CONDITION_COUNT, count)
		return
	end

	humanoid:SetAttribute(CONDITION_COUNT, nil)

	local flag = humanoid:FindFirstChild(config.ConditionName)
	if flag then
		flag:Destroy()
	end
end

--[[
	Should this character be affected at all?

	Mirrors TREK's explosion rule that a character sitting in a VehicleSeat is
	skipped -- being buttoned up protects you from gas the same way it protects
	you from a shell, and having the two disagree would be the kind of
	inconsistency nobody can reason about mid-fight.
]]
local function isProtected(humanoid: Humanoid, config): boolean
	if not config.VehicleSeatProtects then
		return false
	end

	local seat = humanoid.SeatPart
	return seat ~= nil and seat:IsA("VehicleSeat")
end

local function isFriendly(thrower: Player?, character: Model): boolean
	if not thrower then
		return false
	end

	local victim = Players:GetPlayerFromCharacter(character)
	if not victim then
		return false
	end

	return victim.Team ~= nil and victim.Team == thrower.Team
end

--[[
	Spawn a cloud and run it to completion.

	`thrower` may be nil -- a cloud with no owner still damages, it just credits
	nobody, which matches how TREK's own vehicle explosions pass a nil player.
]]
function GasCloud.spawn(position: Vector3, thrower: Player?, config, grenade: Instance?)
	local visuals = GasVisuals.create(position, config)

	task.spawn(function()
		local radiusSq = config.CloudRadius * config.CloudRadius
		local elapsed = 0

		-- Humanoids currently marked by THIS cloud, so the condition can be
		-- released the moment someone walks out rather than when the gas expires.
		local marked: { [Humanoid]: boolean } = {}

		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { workspace:FindFirstChild("IgnoreList") :: Instance }

		while elapsed < config.CloudDuration do
			--[[
				Density ramps in over BuildUpTime and drives both the visuals and
				the damage from the same number. A cloud that looked thin but hit
				at full strength would be a lie the player cannot see through.
			]]
			local density = if config.BuildUpTime > 0
				then math.clamp(elapsed / config.BuildUpTime, 0, 1)
				else 1

			visuals:setDensity(density)

			local inside: { [Humanoid]: boolean } = {}

			if density > 0 then
				local parts = workspace:GetPartBoundsInRadius(position, config.CloudRadius, overlap)
				local seen: { [Model]: boolean } = {}

				for _, part in ipairs(parts) do
					local character, humanoid = characterFrom(part)
					if not character or not humanoid or seen[character] then
						continue
					end
					seen[character] = true

					if humanoid.Health <= 0 or isProtected(humanoid, config) then
						continue
					end

					if not config.AffectsEveryone and isFriendly(thrower, character) then
						continue
					end

					local root = character:FindFirstChild("HumanoidRootPart")
					if not root or not root:IsA("BasePart") then
						continue
					end

					local distance = (root.Position - position).Magnitude
					if distance * distance > radiusSq then
						continue
					end

					if config.RequireLineOfSight and not hasLineOfSight(position, root, grenade) then
						continue
					end

					inside[humanoid] = true

					if not marked[humanoid] then
						marked[humanoid] = true
						markCondition(humanoid, config)
					end

					--[[
						Topped up on the same tick as the damage, so the
						disorientation follows exactly the same targeting rules:
						same radius, same line of sight, same vehicle-seat
						exemption. Anything that spares you the damage spares you
						the blur.
					]]
					GasExposure.add(humanoid, config)

					local amount = config.DamagePerTick * falloff(distance, config) * density
					if amount > 0 then
						damageModule.DamagePlayer(thrower, character, amount)
					end
				end
			end

			-- Anyone who was in the gas last tick and is not now gets their
			-- condition released immediately.
			for humanoid in pairs(marked) do
				if not inside[humanoid] then
					marked[humanoid] = nil
					clearCondition(humanoid, config)
				end
			end

			task.wait(config.TickInterval)
			elapsed += config.TickInterval
		end

		for humanoid in pairs(marked) do
			clearCondition(humanoid, config)
		end

		visuals:destroy()

		if grenade and grenade.Parent then
			grenade:Destroy()
		end
	end)
end

return GasCloud

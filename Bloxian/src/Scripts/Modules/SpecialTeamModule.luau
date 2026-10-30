--[[
	Two-man special teams, spawned together by the spawner and linked by the
	same PairId attribute:

		Sniper team   a Sniper and his Spotter
		AT team       a Rocketeer with a Javelin and his Loader

	They hold the ground they were put on and fight from it, instead of joining
	squads, chasing, investigating or wandering. The second man (Spotter,
	Loader) never leaves his leader's shoulder, even with an enemy close: he
	guards him from there. Once the leader is down, he fights on as an
	ordinary rifleman.

	Settings.Unit is "Sniper", "Spotter", "Rocketeer", "Loader" or "Infantry".
]]

local specialTeam = {}

local modules = script.Parent
local core = require(modules.CoreModule)
local movement = require(modules.MovementModule)
local status = require(modules.Status)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local unitValue = marine.Settings:FindFirstChild("Unit")
local unit = unitValue and unitValue.Value or "Infantry"

--Each second man, and the leader he guards.
local LEADER_OF = {Spotter = "Sniper", Loader = "Rocketeer"}
local LEADERS = {Sniper = true, Rocketeer = true}

--An enemy closer than this is too close for the leader's weapon; he fights him like a rifleman.
local TOO_CLOSE = 40

--How far the second man may drift from his leader, and the spot he takes beside
--and behind him.
local GUARD_LEASH = 8
local GUARD_OFFSET = Vector3.new(4,0,3)

--How far a sniper team spots enemies; it raises Settings.DetectionRange to this.
local SPOT_RANGE = 600

marine:SetAttribute("Unit",unit)

local detection = marine.Settings:FindFirstChild("DetectionRange")
if detection and (unit == "Sniper" or unit == "Spotter") and detection.Value < SPOT_RANGE then
	detection.Value = SPOT_RANGE
end

function specialTeam.detached(model)
	local kind = model:GetAttribute("Unit")
	return kind ~= nil and kind ~= "Infantry"
end

--The other man of this soldier's pair, alive, with the given unit; or nil.
function specialTeam.partner(wantedUnit)
	local id = marine:GetAttribute("PairId")
	if not id then return nil end
	for model,entry in pairs(_G.BloxianRadio or {}) do
		if model ~= marine and model:GetAttribute("PairId") == id and model:GetAttribute("Unit") == wantedUnit
			and entry.root.Parent and entry.human.Health > 0 then
			return entry
		end
	end
	return nil
end

--True while this module moves him; false hands him back to the usual brain.
function specialTeam.update()
	local leaderUnit = LEADER_OF[unit]
	if not leaderUnit and not LEADERS[unit] then
		return false
	end

	if leaderUnit then
		local leader = specialTeam.partner(leaderUnit)
		if not leader then
			log("brain",string.lower(leaderUnit).." down, fighting as a rifleman")
			unit = "Infantry"
			marine:SetAttribute("Unit",unit)
			return false
		end
		if (leader.root.Position - myRoot.Position).Magnitude > GUARD_LEASH then
			movement.navigate(leader.root.CFrame:PointToWorldSpace(GUARD_OFFSET))
			return true
		end
	else
		local target = status:get("currentTarget")
		if target and target.Parent and core.checkDist(target,myRoot) < TOO_CLOSE then
			return false
		end
	end

	movement.stop()
	return true
end

return specialTeam

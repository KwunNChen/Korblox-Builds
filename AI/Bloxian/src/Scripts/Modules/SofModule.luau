--[[
	Special operations: Settings.Unit "Special Recon", spawned as a Recce or a SOF
	Fireteam from the spawner's Special Operations tab.

	They lose no morale (never shaken, broken or demoralized), fire with
	SOF_SPREAD of a line soldier's spread, and carry suppressed rifles, heard out
	to SUPPRESSED_HEARING of the usual distance.

	Special Recon works like Air Force Special Reconnaissance: it gets eyes on an
	enemy player from OBSERVE_MIN to OBSERVE_MAX studs out, lies still and reports
	him, and breaks contact when compromised (GuerrillaModule). It only fires once
	engaged: for ENGAGE_TIME seconds after anyone in the unit is hit or fired at
	(a round passing within FIRED_AT_RADIUS), or after an enemy with a clear line
	comes within ENGAGE_CLOSE, or within ENGAGE_RANGE not turned away from him.
	Enemy special operations are fired on at sight; an enemy sniper is closed on
	first, and fired on from within SNIPER_RANGE. It sees out to RECON_DETECTION. Each
	enemy a recon soldier is stalking is reported to his side, at most every
	RADIO_INTERVAL seconds per unit: friendly soldiers within REPORT_RANGE who are not
	already fighting go after him.

	In a fight with no cover in reach and the enemy in sight, go
	prone and fight from the ground (a line soldier only does once he is hit).

	Special operations radiomen relay enemy players: one they are stalking goes out to every
	special operations radioman on the side, at most every RELAY_INTERVAL seconds
	per player, and each of their squads hears it and stalks him.
]]

local sof = {}

local SOF_SPREAD = 0.3
local SUPPRESSED_HEARING = 0.35
local RECON_DETECTION = 400
--Observation post: with a line to a player this far out he goes prone and watches.
local OBSERVE_MIN = 120
local OBSERVE_MAX = 250
local REPORT_RANGE = 1500
local RELAY_INTERVAL = 5
--They close on an enemy sniper to this many studs before firing on him.
local SNIPER_RANGE = 150
--Least seconds between radio reports from one unit.
local RADIO_INTERVAL = 8
--Facing: 1 is looking straight at him, 0 side-on, below that turned away.
local ENGAGE_CLOSE = 30
local ENGAGE_RANGE = 60
local ENGAGE_FACING = 0
local ENGAGE_TIME = 5
--Seconds after a hit or a round fired at the unit that any enemy in sight keeps it engaged.
local COMPROMISED_TIME = 20

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local chatter = require(modules.ChatterModule)
local threat = require(modules.ThreatModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local mySettings = marine.Settings
local teamValue = mySettings.Team
local unitValue = mySettings:FindFirstChild("Unit")

sof.UNITS = {["Special Recon"] = true}
sof.SPREAD = SOF_SPREAD
sof.SNIPER_RANGE = SNIPER_RANGE
sof.OBSERVE_MIN = OBSERVE_MIN

--His kind ("Special Recon"), or nil for everyone else.
sof.kind = unitValue and sof.UNITS[unitValue.Value] and unitValue.Value or nil
sof.recon = sof.kind == "Special Recon"

--Another model's kind, or nil.
function sof.kindOf(model)
	local kind = model:GetAttribute("Unit")
	return sof.UNITS[kind] and kind or nil
end

if sof.kind then
	chatter.useTactical()
	local fire = marine.M4:FindFirstChild("Fire")
	if fire then
		fire.RollOffMaxDistance *= SUPPRESSED_HEARING
	end
end
local detection = mySettings:FindFirstChild("DetectionRange")
if sof.recon and detection and detection.Value < RECON_DETECTION then
	detection.Value = RECON_DETECTION
end

_G.BloxianSofRadioed = _G.BloxianSofRadioed or setmetatable({},{__mode = "k"})
local radioedAt = _G.BloxianSofRadioed

--Whether he holds an observation post on a player this far off.
function sof.observes(distance,sight)
	return sight and distance >= OBSERVE_MIN and distance <= OBSERVE_MAX
end

--Recon: an enemy he is stalking goes out to his side.
function sof.report(target)
	if not sof.recon or not target or not target.Parent then return end
	local now = os.clock()
	local unit = marine:GetAttribute("SquadId") or marine
	if now - (radioedAt[unit] or -math.huge) < RADIO_INTERVAL then return end
	radioedAt[unit] = now
	chatter.radio("reconReport",target)
	log("target","recon: reported "..target.Parent.Name)

	local myRoot = marine.HumanoidRootPart
	for other,entry in pairs(_G.BloxianRadio or {}) do
		if entry.allyShot and other:GetAttribute("Unit") ~= "Special Recon" and entry.root.Parent and entry.human.Health > 0
			and entry.team.Value == teamValue.Value
			and (entry.root.Position - myRoot.Position).Magnitude <= REPORT_RANGE then
			task.spawn(entry.allyShot,target,"reconTasked")
		end
	end
end

--Radioman: an enemy player he is stalking goes to every special operations radioman on
--his side, and from them to their squads.
local relayedAt = setmetatable({},{__mode = "k"})
function sof.relay(target)
	if not sof.kind or marine:GetAttribute("Role") ~= "Radioman" or not target or not target.Parent
		or not Players:GetPlayerFromCharacter(target.Parent) then
		return
	end
	local now = os.clock()
	if now - (relayedAt[target] or -math.huge) < RELAY_INTERVAL then return end
	relayedAt[target] = now

	local radio = _G.BloxianRadio or {}
	local squads = {}
	for other,entry in pairs(radio) do
		if sof.kindOf(other) and other:GetAttribute("Role") == "Radioman" and entry.human.Health > 0
			and entry.team.Value == teamValue.Value then
			squads[entry.squadId] = true
		end
	end
	for _,entry in pairs(radio) do
		if entry.allyShot and squads[entry.squadId] and entry.root.Parent and entry.human.Health > 0
			and entry.team.Value == teamValue.Value then
			task.spawn(entry.allyShot,target,"contactRelay")
		end
	end
	log("target","radio: relayed "..target.Parent.Name)
end

--Whether target is a sniper, Bloxian or player, to be closed on before firing.
function sof.closesOn(target)
	return target.Parent:GetAttribute("Unit") == "Sniper" or threat.of(target) == "long"
end

--Whether his unit may fight target: when it last was shot or faced, by unit.
_G.BloxianSofEngaged = _G.BloxianSofEngaged or setmetatable({},{__mode = "k"})
local engagedAt = _G.BloxianSofEngaged
_G.BloxianSofCompromised = _G.BloxianSofCompromised or setmetatable({},{__mode = "k"})
local compromisedAt = _G.BloxianSofCompromised
function sof.engaged(target)
	local now = os.clock()
	local unit = marine:GetAttribute("SquadId") or marine
	local at = math.max(engagedAt[unit] or -math.huge,status:get("lastHit"))
	if ((_G.BloxianSuppressed or {})[marine] or 0) > now then
		at = now
	end
	compromisedAt[unit] = math.max(compromisedAt[unit] or -math.huge,status:get("lastHit"),at)
	if target and target.Parent then
		local toMe = (marine.HumanoidRootPart.Position - target.Position)*Vector3.new(1,0,1)
		if sof.closesOn(target) then
			return toMe.Magnitude <= SNIPER_RANGE and core.checkSight(target)
		end
		if sof.kindOf(target.Parent) and core.checkSight(target) then
			return true
		end
		local facing = toMe.Magnitude <= ENGAGE_RANGE and target.CFrame.LookVector:Dot(toMe.Unit) >= ENGAGE_FACING
		if (toMe.Magnitude <= ENGAGE_CLOSE or facing or now - compromisedAt[unit] < COMPROMISED_TIME) and core.checkSight(target) then
			at = now
		end
	end
	engagedAt[unit] = at
	return now - at < ENGAGE_TIME
end

--A player's round came close (CombatModule): a special operations unit counts as
--engaged, and anyone turns on the shooter unless fighting someone he can see.
function sof.firedAt(shooter)
	if sof.kind then
		engagedAt[marine:GetAttribute("SquadId") or marine] = os.clock()
	end
	core.markSeen(shooter)
	local current = status:get("currentTarget")
	if not (current and current.Parent and core.checkSight(current)) then
		status:set("currentTarget",shooter)
	end
	log("target","fired at, engaging")
end

return sof

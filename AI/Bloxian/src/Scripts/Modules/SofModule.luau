--[[
	Special operations: Settings.Unit "Special Recon" or "Raider", spawned as an
	ODA from the spawner's Special Operations tab. SquadModule names the ODA and
	splits it into SOF Fireteams.

	Both kinds lose no morale (never shaken, broken or demoralized), fire with
	SOF_SPREAD of a line soldier's spread, and carry suppressed rifles, heard out
	to SUPPRESSED_HEARING of the usual distance.

	Special Recon stays out of fights: it breaks contact when it meets the enemy
	and holds fire unless shot or closed on. It sees out to RECON_DETECTION. Each
	enemy a recon soldier sees is reported to his side, at most every
	REPORT_INTERVAL seconds: friendly soldiers within REPORT_RANGE who are not
	already fighting go after him, and friendly F-4s strike him first.

	Both kinds, in a fight with no cover in reach and the enemy in sight, go
	prone and fight from the ground (a line soldier only does once he is hit).

	Raiders always push the enemy, whatever the numbers. They push on from cover
	after RAIDER_COVER_MAX seconds (not COVER_MAX_TIME) whenever the enemy cannot
	see them, hide RAIDER_HIDE of the usual time between peeks, always send a
	pincer or flank when the squad can, and have a grenade every
	RAIDER_GRENADE_COOLDOWN seconds.

	Special Recon also marks enemy armor it sees: friendly F-4s strike it first
	(Mavericks).

	Special operations radiomen (the only ones who call an airstrike; line
	radiomen call artillery instead) bring in air cover: a radioman who knows of
	an enemy aircraft that is up, of reported enemy armor, or who sees an enemy
	soldier (marked for the F-4s to strike first), while none of his side's
	F-4s is up, checked every
	AIR_CALL_CHECK seconds, calls an F-4 Phantom AIR_CALL_CHANCE of the time, at
	most every AIR_CALL_COOLDOWN seconds per radioman. It comes in AIR_CALL_HEIGHT
	studs over him, AIR_CALL_OFFSET studs off, and leaves after AIR_CALL_TIME
	seconds unless shot down first. The F-4 is the one in
	ServerStorage.BloxianVehicles (the Vehicle Spawner's folder).
]]

local sof = {}

local SOF_SPREAD = 0.3
local SUPPRESSED_HEARING = 0.35
local RECON_DETECTION = 400
local REPORT_RANGE = 1500
local REPORT_INTERVAL = 10
local RAIDER_COVER_MAX = 3
local RAIDER_HIDE = 0.3
local RAIDER_GRENADE_COOLDOWN = 5
local AIR_CALL_CHECK = 2
local AIR_CALL_CHANCE = 0.35
local AIR_CALL_COOLDOWN = 60
local AIR_CALL_HEIGHT = 650
local AIR_CALL_OFFSET = 800
local AIR_CALL_TIME = 40

local modules = script.Parent
local core = require(modules.CoreModule)
local chatter = require(modules.ChatterModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local mySettings = marine.Settings
local teamValue = mySettings.Team
local unitValue = mySettings:FindFirstChild("Unit")

sof.UNITS = {["Special Recon"] = true, Raider = true}
sof.SPREAD = SOF_SPREAD

--His kind ("Special Recon" or "Raider"), or nil for everyone else.
sof.kind = unitValue and sof.UNITS[unitValue.Value] and unitValue.Value or nil
sof.recon = sof.kind == "Special Recon"
sof.raider = sof.kind == "Raider"
sof.coverMax = sof.raider and RAIDER_COVER_MAX or nil
sof.hideScale = sof.raider and RAIDER_HIDE or 1
sof.grenadeCooldown = sof.raider and RAIDER_GRENADE_COOLDOWN or nil

--Another model's kind, or nil.
function sof.kindOf(model)
	local kind = model:GetAttribute("Unit")
	return sof.UNITS[kind] and kind or nil
end

if sof.kind then
	local fire = marine.M4:FindFirstChild("Fire")
	if fire then
		fire.RollOffMaxDistance *= SUPPRESSED_HEARING
	end
end
local detection = mySettings:FindFirstChild("DetectionRange")
if sof.recon and detection and detection.Value < RECON_DETECTION then
	detection.Value = RECON_DETECTION
end

--Read by F4 jets: spotted[root] = {team, at (server time)}.
_G.BloxianSpotted = _G.BloxianSpotted or setmetatable({},{__mode = "k"})
local spotted = _G.BloxianSpotted
local reportedAt = setmetatable({},{__mode = "k"})

--Recon: an enemy in sight goes out to his side.
function sof.report(target)
	if not sof.recon or not target or not target.Parent or not core.checkSight(target) then return end
	local now = os.clock()
	if now - (reportedAt[target] or -math.huge) < REPORT_INTERVAL then return end
	reportedAt[target] = now
	spotted[target] = {team = teamValue.Value, at = workspace:GetServerTimeNow()}
	chatter.callout("reconReport",nil,0.7)
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

--The F-4 template: the model in ServerStorage.BloxianVehicles that flies itself with a Jet script.
local function jetTemplate()
	local folder = game:GetService("ServerStorage"):FindFirstChild("BloxianVehicles")
	for _,model in ipairs(folder and folder:GetChildren() or {}) do
		if model:IsA("Model") and model:FindFirstChild("Jet") then
			return model
		end
	end
	return nil
end

local roleValue = mySettings:FindFirstChild("Role")
local airCheckAt,airCalledAt = -math.huge,-math.huge

--Whether an F-4 of his side is flying.
local function friendlyJetUp()
	for _,jet in ipairs(game:GetService("CollectionService"):GetTagged("BloxianJet")) do
		local settings = jet:FindFirstChild("Settings")
		local team = settings and settings:FindFirstChild("Team")
		local side = team and team.Value ~= "" and team.Value or "Friendly"
		if side == teamValue.Value and jet:IsDescendantOf(workspace) and not jet:GetAttribute("ShotDown") then
			return true
		end
	end
	return false
end

--Recon radioman: craft (an enemy aircraft's root from TacticsModule, or a part
--of enemy armor, whose model is model) in sight may bring in a Phantom.
function sof.callAir(craft,model,call)
	local now = os.clock()
	if not sof.kind or not craft or not roleValue or roleValue.Value ~= "Radioman"
		or now - airCheckAt < AIR_CALL_CHECK or now - airCalledAt < AIR_CALL_COOLDOWN or friendlyJetUp() then
		return
	end
	airCheckAt = now
	model = model or craft.Parent
	if math.random() >= AIR_CALL_CHANCE then
		return false
	end
	local template = jetTemplate()
	if not template then
		log("target","recon: no F-4 in ServerStorage.BloxianVehicles to call")
		return false
	end
	airCalledAt = now

	local myRoot = marine.HumanoidRootPart
	local angle = math.random()*math.pi*2
	local at = myRoot.Position + Vector3.new(math.cos(angle)*AIR_CALL_OFFSET,AIR_CALL_HEIGHT,math.sin(angle)*AIR_CALL_OFFSET)
	local jet = template:Clone()
	local settings = jet:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	if team then
		team.Value = teamValue.Value
	end
	jet:SetAttribute("Lifetime",AIR_CALL_TIME)
	jet:SetAttribute("NoRespawn",true)
	jet:SetAttribute("SpawnedBy",marine:GetAttribute("SpawnedBy"))
	jet:AddTag("VehicleSpawned")
	jet:PivotTo(CFrame.lookAt(at,Vector3.new(craft.Position.X,at.Y,craft.Position.Z)))
	jet.Parent = workspace
	chatter.callout(call or "airCall",nil,1)
	log("target","recon: called in an F-4 against "..model.Name)
	return true
end

--Radioman: an enemy soldier in sight is marked for the F-4s (struck first, like
--a recon report), and may bring one in.
function sof.callStrike(target)
	if not sof.kind or not roleValue or roleValue.Value ~= "Radioman" or not target or not target.Parent
		or not core.checkSight(target) then
		return
	end
	local root = target.Parent:FindFirstChild("HumanoidRootPart") or target
	spotted[root] = {team = teamValue.Value, at = workspace:GetServerTimeNow()}
	sof.callAir(target,target.Parent,"groundAirCall")
end

--Enemy armor (car, aimed at part) seen and reported (JavelinModule): recon
--marks it for the F-4s, and a special operations radioman may bring one in.
function sof.markArmor(car,part)
	if sof.recon then
		spotted[car.PrimaryPart or part] = {team = teamValue.Value, at = workspace:GetServerTimeNow()}
	end
	sof.callAir(part,car,"armorAirCall")
end

return sof

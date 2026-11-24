--[[
	Flares, chaff and the missiles they fool, shared by everything that fires
	at aircraft (the F-4's missiles, the AA truck's rockets). One copy of the
	rules, built into each package that needs it (a child named AirDefense,
	next to a Sides).

	A missile has a seeker: "ir" (heat: the Sidewinder) is fooled by flares,
	"radar" (the AA truck's rockets) by chaff. Each aircraft carries Flares and
	Chaff counts and the server time of its last salvo of each (FlaresAt,
	ChaffAt). A missile calls decoy() once, when it gets within FLARE_RANGE, and
	touchedFlare() every step after that.
]]

local runService = game:GetService("RunService")
local debris = game:GetService("Debris")
local collectionService = game:GetService("CollectionService")

local sides = require(script.Parent:WaitForChild("Sides"))

local airDefense = {}

--Flares, after the real dispensers: the flares each kind carries (a Phantom's
--two an/ALE-40s hold 15 each, an Apache's M130 holds 30; the AC-130's is a
--guess, there being no published figure), how many go in one salvo (the F-4's
--programmer bursts 1, 2, 4 or 8), and the least time between salvos (its
--shortest burst interval, 3 seconds: at most 20 salvos a minute, and the load
--runs out long before). A salvo goes when a missile gets within FLARE_RANGE,
--and each flare burning near it has FLARE_PULL odds of pulling it off: 2 flares
--about 51%, 4 about 76%, 8 about 94%. A missile that passes within FLARE_TOUCH
--studs of a burning flare (or chaff, for a radar missile) bursts on it, and the
--aircraft is spared.
airDefense.FLARE_LOAD = {BloxianJet = 30,BloxianGunship = 120,BloxianAircraft = 30}
airDefense.FLARE_SALVO = {BloxianJet = 4,BloxianGunship = 8,BloxianAircraft = 2}
airDefense.FLARE_INTERVAL = 3
airDefense.FLARE_RANGE = 500
airDefense.FLARE_PULL = 0.3
airDefense.FLARE_TOUCH = 10

--Chaff, against radar missiles, from the same dispensers: bundles carried, per
--salvo, and each bundle's odds of pulling a radar missile off. A pilot beaming
--it (flying within BEAM_ANGLE degrees of square across its path, at least
--BEAM_SPEED studs/s) hides in the clutter: each bundle's odds go up BEAM_BONUS
--times, to at most BEAM_MAX. 4 bundles: about 59% flying straight, 94% beaming.
airDefense.CHAFF_LOAD = {BloxianJet = 30,BloxianGunship = 120,BloxianAircraft = 30}
airDefense.CHAFF_SALVO = {BloxianJet = 4,BloxianGunship = 8,BloxianAircraft = 2}
airDefense.CHAFF_PULL = 0.2
airDefense.BEAM_ANGLE = 30
airDefense.BEAM_SPEED = 20
airDefense.BEAM_BONUS = 2.5
airDefense.BEAM_MAX = 0.9

--Each plane's health against missiles and rounds (where its AirHealth starts).
airDefense.AIR_HEALTH = {BloxianJet = 200,BloxianGunship = 600}

local FLARE_TAG = "BloxianFlare"

--What each seeker is fooled by, and the attributes that count it.
local DECOYS = {
	ir = {kind = "flare",count = "Flares",at = "FlaresAt",load = airDefense.FLARE_LOAD,salvo = airDefense.FLARE_SALVO,pull = airDefense.FLARE_PULL},
	radar = {kind = "chaff",count = "Chaff",at = "ChaffAt",load = airDefense.CHAFF_LOAD,salvo = airDefense.CHAFF_SALVO,pull = airDefense.CHAFF_PULL},
}

--Damage to an aircraft: a helicopter's Humanoid, else a plane's AirHealth,
--which brings it down at zero.
function airDefense.hurtAircraft(craft,planeDamage,heliDamage)
	local kind = sides.airKind(craft)
	if kind == sides.HELI_TAG then
		local human = craft:FindFirstChildOfClass("Humanoid")
		if human then
			human:TakeDamage(heliDamage)
		end
		return
	end
	local health = craft:GetAttribute("AirHealth") or airDefense.AIR_HEALTH[kind] or 100
	health -= planeDamage
	craft:SetAttribute("AirHealth",health)
	if health <= 0 then
		craft:SetAttribute("ShotDown",true)
	end
end

function airDefense.plainPart(name,size,color,material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

function airDefense.addTrail(part,color,lifetime,width)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0,width/2,part.Size.Z/2)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0,-width/2,part.Size.Z/2)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = lifetime
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.2,1)
	trail.WidthScale = NumberSequence.new(1,4)
	trail.LightEmission = 0.5
	trail.Parent = part
end

--How fast an aircraft is going, from where it was last looked at.
local tracked = setmetatable({},{__mode = "k"})
function airDefense.velocityOf(craft)
	local part = craft.PrimaryPart
	if not part then return Vector3.zero end
	local now = os.clock()
	local entry = tracked[craft]
	if not entry then
		tracked[craft] = {pos = part.Position,time = now,vel = Vector3.zero}
		return Vector3.zero
	end
	if now - entry.time >= 0.05 then
		entry.vel = (part.Position - entry.pos)/(now - entry.time)
		entry.pos,entry.time = part.Position,now
	end
	return entry.vel
end

--A salvo of count flares (or chaff bundles) thrown out behind and below an aircraft.
local function throwDecoys(craft,count,kind)
	local from = craft.PrimaryPart
	if not from then return end
	local back = -from.CFrame.LookVector
	local carried = airDefense.velocityOf(craft)
	local chaff = kind == "chaff"
	for _ = 1,count do
		local decoy
		if chaff then
			decoy = airDefense.plainPart("Chaff",Vector3.one*0.8,Color3.fromRGB(200,205,210),Enum.Material.Foil)
			local glitter = Instance.new("ParticleEmitter")
			glitter.Color = ColorSequence.new(Color3.fromRGB(220,225,230))
			glitter.LightEmission = 0.6
			glitter.Size = NumberSequence.new(0.3)
			glitter.Lifetime = NumberRange.new(1,2)
			glitter.Rate = 40
			glitter.Speed = NumberRange.new(2,6)
			glitter.SpreadAngle = Vector2.new(180,180)
			glitter.Parent = decoy
		else
			decoy = airDefense.plainPart("Flare",Vector3.one*1.2,Color3.fromRGB(255,235,170),Enum.Material.Neon)
			decoy.Shape = Enum.PartType.Ball
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255,200,120)
			light.Brightness = 4
			light.Range = 30
			light.Parent = decoy
			airDefense.addTrail(decoy,Color3.fromRGB(240,240,240),1.5,0.8)
		end
		decoy.CFrame = CFrame.new(from.Position - Vector3.new(0,3,0))
		--Any missile coming in at this aircraft while it lasts can be pulled onto it.
		local owner = Instance.new("ObjectValue")
		owner.Name = "Craft"
		owner.Value = craft
		owner.Parent = decoy
		decoy:SetAttribute("Decoy",kind)
		decoy:AddTag(FLARE_TAG)
		decoy.Parent = workspace
		--Its Heartbeat belongs to the shooter's script: Debris clears it if that goes first.
		debris:AddItem(decoy,6)
		--Chaff hangs in the air as a cloud; flares are thrown clear and drop.
		local side = from.CFrame.RightVector*(math.random() - 0.5)*80
		local velocity = if chaff then carried*0.15 + side*0.3 else carried*0.4 + back*60 + side + Vector3.new(0,-20,0)
		local fall = if chaff then 4 else 30
		local life = if chaff then 5 else 4
		local born = os.clock()
		local connection
		connection = runService.Heartbeat:Connect(function(dt)
			if not decoy.Parent or os.clock() - born > life then
				connection:Disconnect()
				decoy:Destroy()
				return
			end
			velocity += Vector3.new(0,-fall*dt,0)
			decoy.CFrame = CFrame.new(decoy.Position + velocity*dt)
		end)
	end
end

--Flares (or chaff, kind) an aircraft has out within FLARE_RANGE of a missile at
--from, whoever's missile they were thrown against.
local function liveDecoys(craft,from,kind)
	local list = {}
	for _,decoy in ipairs(collectionService:GetTagged(FLARE_TAG)) do
		local owner = decoy:FindFirstChild("Craft")
		if owner and owner.Value == craft and decoy.Parent and decoy:GetAttribute("Decoy") == kind
			and (decoy.Position - from).Magnitude < airDefense.FLARE_RANGE then
			list[#list+1] = decoy
		end
	end
	return list
end

--Whether target is beaming a missile at from: flying fast and square across its path.
function airDefense.beaming(target,from)
	local root = target.PrimaryPart
	local velocity = airDefense.velocityOf(target)
	if not root or velocity.Magnitude < airDefense.BEAM_SPEED then return false end
	local line = root.Position - from
	if line.Magnitude < 1 then return false end
	return math.abs(velocity.Unit:Dot(line.Unit)) < math.sin(math.rad(airDefense.BEAM_ANGLE))
end

--A missile with this seeker ("ir" by default, or "radar") at from has just come
--within FLARE_RANGE of target: a fresh salvo of what fools it if the dispenser
--is ready, then every one of those out near the missile has its chance to pull
--it off. Gives back the decoy it now chases, or nil.
function airDefense.decoy(target,from,seeker)
	local spec = DECOYS[seeker or "ir"]
	local kind = sides.airKind(target)
	if not kind or not spec then return nil end
	local left = target:GetAttribute(spec.count) or spec.load[kind] or 0
	local serverNow = workspace:GetServerTimeNow()
	local ready = serverNow - (target:GetAttribute(spec.at) or -math.huge) >= airDefense.FLARE_INTERVAL
	if left > 0 and ready then
		local count = math.min(spec.salvo[kind] or 2,left)
		target:SetAttribute(spec.count,left - count)
		target:SetAttribute(spec.at,serverNow)
		throwDecoys(target,count,spec.kind)
	end
	local pull = spec.pull
	if seeker == "radar" and airDefense.beaming(target,from) then
		pull = math.min(pull*airDefense.BEAM_BONUS,airDefense.BEAM_MAX)
	end
	local decoys = liveDecoys(target,from,spec.kind)
	if #decoys > 0 and math.random() < 1 - (1 - pull)^#decoys then
		return decoys[math.random(#decoys)]
	end
	return nil
end

--Whether a missile with this seeker at from is within FLARE_TOUCH of one of
--target's decoys that fools it.
function airDefense.touchedFlare(target,from,seeker)
	local spec = DECOYS[seeker or "ir"]
	for _,decoy in ipairs(liveDecoys(target,from,spec.kind)) do
		if (decoy.Position - from).Magnitude < airDefense.FLARE_TOUCH then
			return true
		end
	end
	return false
end

return airDefense

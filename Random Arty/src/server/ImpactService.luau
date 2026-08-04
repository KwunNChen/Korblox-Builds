--[[
	ImpactService
	What a shell does when it lands.

	Damage is server-only and always will be. The client draws the explosion,
	but it never reports what it hit and it is never asked -- a client that
	simply declined to tell us it was standing in the crater would be immortal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Dismember = require(script.Parent:WaitForChild("Dismember"))
local Common = ServerScriptService:WaitForChild("Common")
local CharacterCache = require(Common:WaitForChild("CharacterCache"))
local SpeedService = require(Common:WaitForChild("SpeedService"))

local ImpactService = {}

local CONCUSSION_MODIFIER = "Concussed"

-- How far a blast reaches at all. ConcussionRadius is deliberately allowed to
-- exceed DamageRadius -- being rattled by a near miss that did no damage is the
-- point of it -- so this is whichever of the two reaches further. Config is
-- frozen, so it is worked out once.
local BLAST_REACH = if Config.EnableConcussion
	then math.max(Config.DamageRadius, Config.ConcussionRadius)
	else Config.DamageRadius

-- The onion only works if the layers nest. Out of order, an inner sphere
-- swallows an outer one and that band silently never happens -- which looks
-- like a broken feature rather than a bad number, so it is worth saying out
-- loud at startup instead of leaving it to be inferred from behaviour.
do
	local layers = {
		{ "KillRadius", Config.KillRadius },
		{ "DismemberRadius", Config.DismemberRadius },
		{ "DamageRadius", Config.DamageRadius },
		{ "ConcussionRadius", Config.ConcussionRadius },
	}

	for index = 2, #layers do
		local outer, inner = layers[index], layers[index - 1]
		if outer[2] < inner[2] then
			warn(
				string.format(
					"[Artillery] %s (%.0f) is smaller than %s (%.0f) -- the damage layers are out of "
						.. "order, so the '%s' band never happens. See the onion note in ArtilleryConfig.",
					outer[1],
					outer[2],
					inner[1],
					inner[2],
					outer[1]
				)
			)
		end
	end
end

-- Built once and reused; the victim's own body is swapped into the filter per
-- cast rather than allocating fresh params every time.
local coverParams = RaycastParams.new()
coverParams.FilterType = Enum.RaycastFilterType.Exclude
coverParams.IgnoreWater = true
coverParams.RespectCanCollide = true

local npcParams = OverlapParams.new()
npcParams.FilterType = Enum.RaycastFilterType.Exclude

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Artillery] " .. message, ...))
	end
end

-- Sampled up the body rather than at one point. A single ray to the torso is a
-- COIN FLIP at any partial cover: shuffle a stud sideways and the whole hit
-- swings between full damage and a quarter of it, with nothing in between. That
-- is most of what "the damage is inconsistent" actually is.
local COVER_SAMPLES = {
	Vector3.new(0, 2.2, 0), -- head
	Vector3.new(0, 0, 0), -- torso
	Vector3.new(0, -2.2, 0), -- legs
}

--[[
	0 fully exposed, 1 fully behind something.

	The origin is LIFTED off the ground first. Impact points come from a downward
	raycast so they sit exactly on the surface, and a ray cast from there hits
	that surface on the first stud -- which reads as cover on every shell in the
	open and quietly caps artillery at a quarter of its damage.
]]
local function coverFraction(blastPosition: Vector3, target: Vector3, character: Model): number
	if not Config.EnableCoverCheck then
		return 0
	end

	local origin = blastPosition + Vector3.new(0, Config.CoverRayLift, 0)
	coverParams.FilterDescendantsInstances = { character }

	local blocked = 0
	for _, offset in COVER_SAMPLES do
		local point = target + offset
		if workspace:Raycast(origin, point - origin, coverParams) then
			blocked += 1
		end
	end

	return blocked / #COVER_SAMPLES
end

--[[
	EVERY POINT OF ARTILLERY DAMAGE GOES THROUGH HERE, and it is deliberately
	not Humanoid:TakeDamage.

	TakeDamage is BLOCKED BY A ForceField. Assigning Humanoid.Health is not --
	and Dismember assigns it. Two paths, two behaviours, and no sign of the
	difference at either call site. Left split, the onion comes apart against a
	freshly spawned player: layers 2 and 3 do nothing to them while layer 1 kills
	them outright through the shield. Same barrage, same player, opposite
	outcomes decided only by which ring they were standing in.

	One helper, one behaviour: artillery goes through spawn protection. A shell
	does not care that you just respawned, and every layer agrees about it.

	Tag your spawns with ArtillerySafeZone if you want them left alone -- that is
	the supported way to protect a spawn, and unlike a ForceField it stops the
	shell being aimed there in the first place.
]]
local function applyDamage(humanoid: Humanoid, amount: number)
	humanoid.Health = math.max(humanoid.Health - amount, 0)
end

local function falloffDamage(distance: number, cover: number): number
	local band = math.max(Config.DamageRadius - Config.KillRadius, 0.001)
	local t = math.clamp((distance - Config.KillRadius) / band, 0, 1)

	local damage = Config.MaxFalloffDamage * (1 - t) ^ Config.FalloffExponent

	-- Scaled by how much of the body is behind something, not switched by
	-- whether any of it is.
	return damage * (1 + (Config.CoverDamageReduction - 1) * cover)
end

local function applyConcussion(humanoid: Humanoid, distance: number)
	if not Config.EnableConcussion or distance > Config.ConcussionRadius then
		return
	end

	-- Fades with distance so the edge of the radius is a stumble, not a stop.
	local strength = 1 - distance / Config.ConcussionRadius

	SpeedService.setModifier(humanoid, CONCUSSION_MODIFIER, {
		mul = 1 + (Config.ConcussionSpeedMultiplier - 1) * strength,
		jumpMul = 1 + (Config.ConcussionJumpMultiplier - 1) * strength,
	})

	task.delay(Config.ConcussionDuration, function()
		if humanoid.Parent then
			SpeedService.clearModifier(humanoid, CONCUSSION_MODIFIER)
		end
	end)
end

--[[
	Shrapnel takes an arm off someone the blast only wounded. The caller has
	already established they are in layer 2; this only decides whether the roll
	lands.

	Cover scales the odds rather than switching them off, matching how it scales
	damage. A boolean here was the same coin-flip problem: a stud of shuffling
	decided whether you kept both arms.
]]
local function tryMaim(
	character: Model,
	humanoid: Humanoid,
	blastPosition: Vector3,
	distance: number,
	cover: number
): number
	if not Config.EnableMaiming then
		return 0
	end

	-- Odds fall across layer 2 itself, from its inner edge to its outer one,
	-- rather than from the crater -- nobody in this layer is closer than
	-- KillRadius, so measuring from zero would waste most of the curve.
	local band = math.max(Config.DismemberRadius - Config.KillRadius, 0.001)
	local acrossLayer = (distance - Config.KillRadius) / band

	local chance = Config.MaimChance * (1 - acrossLayer) * (1 - cover)
	if math.random() > chance then
		return 0
	end

	return Dismember.maim(character, humanoid, blastPosition, math.random(1, math.max(Config.MaxLimbsMaimed, 1)))
end

local function shove(root: BasePart, blastPosition: Vector3, distance: number)
	if Config.BlastImpulse <= 0 then
		return
	end

	local away = root.Position - blastPosition
	if away.Magnitude < 0.1 then
		return
	end

	local strength = 1 - math.clamp(distance / Config.DamageRadius, 0, 1)
	root.AssemblyLinearVelocity += (away.Unit + Vector3.new(0, 0.6, 0)) * Config.BlastImpulse * strength
end

--[[
	One victim, one distance, one layer. See the onion note in ArtilleryConfig.

	    1  <= KillRadius        dead, always, no cover
	    2  <= DismemberRadius   damage, and limbs come off
	    3  <= DamageRadius      damage only
	    4  <= ConcussionRadius  dazed
]]
local function hit(character: Model, humanoid: Humanoid, root: BasePart, blastPosition: Vector3)
	local offset = root.Position - blastPosition
	local flat = Vector2.new(offset.X, offset.Z).Magnitude

	-- The vertical gap is scaled DOWN before the length is taken, so the blast is
	-- a flattened ellipsoid rather than a sphere. A true sphere spends the same
	-- radius budget on height as on ground distance, which is what lets a shell
	-- land a few studs in front of someone standing up a slope and leave them
	-- untouched. See BlastVerticalScale.
	local distance = Vector3.new(offset.X, offset.Y * Config.BlastVerticalScale, offset.Z).Magnitude

	if distance > BLAST_REACH then
		return
	end

	-- Spawn protection is NOT checked. Artillery penetrates a ForceField, in
	-- every layer -- see applyDamage.

	-- LAYER 4. Past the damage sphere entirely: rattled, unhurt.
	if distance > Config.DamageRadius then
		applyConcussion(humanoid, distance)
		return
	end

	-- LAYER 1. Pure distance and nothing else -- no raycast is even fired here.
	-- A shell that lands on top of you is not survivable by standing behind
	-- something, and making it survivable is what turns the kill sphere into a
	-- suggestion.
	if distance <= Config.KillRadius then
		Dismember.apply(character, humanoid, blastPosition, 1 - distance / Config.KillRadius)
		shove(root, blastPosition, distance)
		log("%s at %.1f (%.0f flat, %+.0f up) -- LAYER 1, killed", character.Name, distance, flat, offset.Y)
		return
	end

	-- LAYERS 2 and 3. Cover applies out here.
	local cover = coverFraction(blastPosition, root.Position, character)
	local damage = falloffDamage(distance, cover)
	local tearsLimbs = distance <= Config.DismemberRadius
	local layer = if tearsLimbs then 2 else 3

	if damage <= 0 then
		applyConcussion(humanoid, distance)
		return
	end

	local outcome

	if damage >= humanoid.Health then
		if tearsLimbs or Config.DismemberOnAnyKill then
			Dismember.apply(character, humanoid, blastPosition, 0)
			outcome = "killed, limbs off"
		else
			-- Layer 3 kills die intact, so what is left of a body tells you
			-- which layer caught them. INTACT STILL MEANS LIMP -- it ragdolls
			-- and gets the same cleanup as every other kill, it just keeps all
			-- its limbs. prepareRagdoll has to run before the damage lands or
			-- Roblox breaks the joints itself on death first.
			Dismember.prepareRagdoll(humanoid)
			applyDamage(humanoid, damage)
			Dismember.finishRagdoll(character)
			Dismember.cleanupCorpse(character)
			outcome = "killed intact"
		end
	else
		applyDamage(humanoid, damage)
		applyConcussion(humanoid, distance)

		local torn = if tearsLimbs then tryMaim(character, humanoid, blastPosition, distance, cover) else 0
		outcome = if torn > 0 then string.format("survived, %d limbs off", torn) else "survived"
	end

	-- One line per victim. "The damage feels inconsistent" is almost always two
	-- shells overlapping, or partial cover, or a health pool already chewed
	-- down -- none of which you can see from inside the game.
	log(
		"%s at %.1f (%.0f flat, %+.0f up) -- LAYER %d, cover %.0f%%, %.0f damage, %s (%.0f HP left)",
		character.Name,
		distance,
		flat,
		offset.Y,
		layer,
		cover * 100,
		damage,
		outcome,
		math.max(humanoid.Health, 0)
	)

	shove(root, blastPosition, distance)
end

-- Walks up for the model that actually OWNS a Humanoid, rather than taking the
-- nearest Model ancestor. A hat, a tool or a weapon rig is a Model too, and
-- stopping at one of those silently skips the NPC wearing it.
local function findHumanoidModel(part: BasePart): (Model?, Humanoid?)
	local current: Instance? = part

	while current and current ~= workspace do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return current, humanoid
			end
		end
		current = current.Parent
	end

	return nil, nil
end

local function sweepNPCs(blastPosition: Vector3)
	local parts = workspace:GetPartBoundsInRadius(blastPosition, BLAST_REACH, npcParams)

	local seen = {}
	for _, part in parts do
		local character, humanoid = findHumanoidModel(part)
		if not character or seen[character] then
			continue
		end
		seen[character] = true

		-- Players were already swept by name in detonate; hitting them twice
		-- would double the damage of every shell.
		if Players:GetPlayerFromCharacter(character) then
			continue
		end

		local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
		if humanoid and (humanoid :: Humanoid).Health > 0 and root and root:IsA("BasePart") then
			local ok, err = pcall(hit, character, humanoid, root, blastPosition)
			if not ok then
				warn("[ImpactService] NPC hit failed for", character.Name, err)
			end
		end
	end
end

function ImpactService.detonate(blastPosition: Vector3)
	for _, player in Players:GetPlayers() do
		local entry = CharacterCache.getAlive(player)
		if entry then
			local ok, err = pcall(hit, entry.character, entry.humanoid, entry.root, blastPosition)
			if not ok then
				warn("[ImpactService] hit failed for", player.Name, err)
			end
		end
	end

	if Config.AffectNPCs then
		local ok, err = pcall(sweepNPCs, blastPosition)
		if not ok then
			warn("[ImpactService] NPC sweep failed", err)
		end
	end

	log("impact at %.0f, %.0f, %.0f", blastPosition.X, blastPosition.Y, blastPosition.Z)
end

return ImpactService

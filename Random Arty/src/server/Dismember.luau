--[[
	Dismember
	Takes limbs off an R6 character killed by a shell, then lets the rest of the
	body fall.

	R6 is held together by Motor6Ds living on the Torso. Severing a limb means
	destroying its motor and reparenting the part to Workspace so it becomes its
	own physics assembly; going limp means swapping the remaining motors for
	BallSocketConstraints, the same trick SkiRagdoll uses for a wipeout. The
	difference is that this one never recovers.

	ORDER MATTERS. BreakJointsOnDeath has to be turned off BEFORE the humanoid
	dies. Roblox's default is to break every joint at once on death, which drops
	the character into an anonymous pile of parts -- deciding which joints break
	is the whole difference between dismemberment and a heap.

	LIMB SEVERING IS R6 ONLY -- the joint names below do not exist on R15, so an
	R15 character is detected and keeps all its limbs. It still gets
	PlatformStand and falls over rather than standing there dead, just not a
	jointed ragdoll: there is no R15 joint table here to swap onto ball sockets.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Shared = require(ArtilleryFolder:WaitForChild("ArtilleryShared"))

local Dismember = {}

-- Limb part -> the Motor6D on the Torso that holds it on.
local LIMB_JOINTS = {
	["Right Arm"] = "Right Shoulder",
	["Left Arm"] = "Left Shoulder",
	["Right Leg"] = "Right Hip",
	["Left Leg"] = "Left Hip",
}

-- Shuffled per kill, so which limbs go is random. The victim is dead either
-- way, so there is nothing to protect by ordering these.
local SEVER_ORDER = { "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

-- What a SURVIVOR can lose. Arms only unless MaimIncludesLegs is on -- an R6
-- Humanoid derives its hip height from the leg parts, so someone still walking
-- around without them hovers.
local MAIM_ARMS = { "Right Arm", "Left Arm" }

local warnedNonR6 = false

-- Joints that go limp on whatever is left. RootJoint is absent on purpose: it
-- holds the Torso to the HumanoidRootPart, and freeing it separates the corpse
-- from the part the respawn logic tracks.
local RAGDOLL_JOINTS = { "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Artillery] " .. message, ...))
	end
end

local function findJoint(character: Model, name: string): Motor6D?
	local torso = character:FindFirstChild("Torso")
	local joint = torso and torso:FindFirstChild(name)
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

-- RigType is the direct answer, but it is only trustworthy on a Humanoid Roblox
-- built. The part check backs it up for custom rigs that report R6 without
-- actually having R6's parts.
function Dismember.isR6(character: Model, humanoid: Humanoid): boolean
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return false
	end
	return character:FindFirstChild("Torso") ~= nil and character:FindFirstChild("Right Arm") ~= nil
end

-- A disc of bone left in the socket. Welded rather than positioned, so it rides
-- the torso as the corpse falls.
local function addStump(torso: BasePart, socket: CFrame)
	local stump = Instance.new("Part")
	stump.Name = "ArtilleryStump"
	stump.Shape = Enum.PartType.Cylinder
	-- X is the cylinder's axis, and every R6 limb joint points its X outward
	-- from the torso, so this lands as a flat cross-section facing where the
	-- limb used to be.
	stump.Size = Vector3.new(0.35, 0.85, 0.85)
	stump.Color = Config.StumpColor
	stump.Material = Enum.Material.SmoothPlastic
	stump.CanCollide = false
	stump.CanQuery = false
	stump.CanTouch = false
	stump.Massless = true
	stump.Parent = torso

	local weld = Instance.new("Weld")
	weld.Part0 = torso
	weld.Part1 = stump
	weld.C0 = socket
	weld.Parent = stump

	if Config.EnableBlood then
		local attachment = Instance.new("Attachment")
		attachment.Parent = stump

		local blood = Instance.new("ParticleEmitter")
		blood.Color = ColorSequence.new(Config.BloodColor)
		blood.Size = NumberSequence.new(0.5, 0.05)
		blood.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		blood.Lifetime = NumberRange.new(0.6, 1.4)
		blood.Rate = 45
		blood.Speed = NumberRange.new(6, 16)
		blood.SpreadAngle = Vector2.new(25, 25)
		blood.Acceleration = Vector3.new(0, -60, 0)
		blood.LightEmission = 0
		blood.Parent = attachment

		-- Spurts, then stops. A corpse that bleeds forever is a particle leak.
		task.delay(1.5, function()
			blood.Enabled = false
		end)
	end
end

local function severLimb(character: Model, limbName: string, blastPosition: Vector3)
	local joint = findJoint(character, LIMB_JOINTS[limbName])
	local limb = character:FindFirstChild(limbName)
	if not joint or not limb or not limb:IsA("BasePart") then
		return false
	end

	local torso = joint.Part0
	local socket = joint.C0

	joint:Destroy()

	limb.CanCollide = true
	limb.Massless = false
	limb.Anchored = false
	-- Decoration only. Left queryable, gore on the ground would block the next
	-- shell's ground-snap ray and count as cover on that shell's blast check.
	limb.CanQuery = false
	limb.Parent = workspace

	-- Severed limbs are their own assembly the instant they leave the character,
	-- and an assembly with no owner gets handed to whichever client is nearest.
	-- That is the documented cause of gore sinking through the floor, so the
	-- server keeps them.
	pcall(function()
		limb:SetNetworkOwner(nil)
	end)

	local away = limb.Position - blastPosition
	if away.Magnitude < 0.1 then
		away = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
	end

	limb.AssemblyLinearVelocity = away.Unit * Shared.rollRange(Config.LimbFlingSpeed)
		+ Vector3.new(0, Shared.rollRange(Config.LimbFlingSpeed) * 0.35, 0)

	limb.AssemblyAngularVelocity = Vector3.new(
		(math.random() - 0.5) * 2 * Config.LimbSpin,
		(math.random() - 0.5) * 2 * Config.LimbSpin,
		(math.random() - 0.5) * 2 * Config.LimbSpin
	)

	if Config.ShowStumps and torso and torso:IsA("BasePart") then
		addStump(torso, socket)
	end

	Debris:AddItem(limb, Config.GoreLifetime)
	return true
end

-- Shuffles `pool` and takes up to `count` of it off. Returns how many actually
-- came away -- a limb already missing from an earlier shell severs nothing.
local function severSome(character: Model, blastPosition: Vector3, pool: { string }, count: number): number
	local order = table.clone(pool)
	for index = #order, 2, -1 do
		local swap = math.random(index)
		order[index], order[swap] = order[swap], order[index]
	end

	local severed = 0
	for index = 1, math.min(count, #order) do
		if severLimb(character, order[index], blastPosition) then
			severed += 1
		end
	end
	return severed
end

-- Swaps whatever motors are left for ball sockets so the body folds instead of
-- staying rigid. Attachments have to sit exactly on the motor's own C0/C1 or
-- the limb snaps to a new pose the moment it goes limp.
local function ragdollRemains(character: Model)
	for _, name in RAGDOLL_JOINTS do
		local joint = findJoint(character, name)
		if joint and joint.Part0 and joint.Part1 then
			local a0 = Instance.new("Attachment")
			a0.CFrame = joint.C0
			a0.Parent = joint.Part0

			local a1 = Instance.new("Attachment")
			a1.CFrame = joint.C1
			a1.Parent = joint.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = 75
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Parent = joint.Part0

			joint:Destroy()
		end
	end

	for name in LIMB_JOINTS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.CanCollide = true
		end
	end
end

--[[
	Makes sure a corpse actually goes away. NOTHING DOES THIS BY DEFAULT.

	CorpseLifetime <= 0 used to mean "skip scheduling cleanup, the normal
	respawn clears it" -- which was never true. Respawning only reassigns
	player.Character to a NEW Model; the old corpse is abandoned in Workspace
	exactly as it was, forever, because nothing ever calls :Destroy() on it.
	That is the whole reason corpses were piling up regardless of the timer.

	Two independent mechanisms now, and a corpse only needs one to fire:

	  THE BACKSTOP. CorpseLifetime, if positive, force-destroys the corpse
	  after that many seconds no matter what else happens. NPCs have no
	  respawn to hook at all, so for them this -- or GoreLifetime as a floor
	  when it is left at 0 -- is the ONLY thing that will ever clean them up.

	  RESPAWN. For a player corpse, destroyed the instant CharacterAdded fires
	  for the player who died, or immediately if they leave first
	  (PlayerRemoving) rather than leaving an orphan with no owner left to
	  respawn at all. This is what CorpseLifetime = 0 was always meant to mean
	  for a player -- it just never actually happened before.

	Both can be armed on the same corpse; whichever fires first destroys it,
	and the guard on corpse.Parent makes the second one a harmless no-op.
]]
local function cleanupCorpse(character: Model)
	local player = Players:GetPlayerFromCharacter(character)

	local backstop = if Config.CorpseLifetime > 0
		then Config.CorpseLifetime
		elseif not player then Config.GoreLifetime
		else nil

	if backstop then
		Debris:AddItem(character, backstop)
	end

	if not player then
		return
	end

	local corpse = character
	local characterConn: RBXScriptConnection
	local leavingConn: RBXScriptConnection

	local function cleanup()
		characterConn:Disconnect()
		leavingConn:Disconnect()
		if corpse.Parent then
			corpse:Destroy()
		end
	end

	characterConn = player.CharacterAdded:Connect(cleanup)
	leavingConn = Players.PlayerRemoving:Connect(function(leaving)
		if leaving == player then
			cleanup()
		end
	end)
end

--[[
	Everything a corpse needs BEFORE Health hits 0, and everything it needs
	AFTER, exposed separately so ImpactService's layer-3 "killed intact" path
	can ragdoll a kill it deliberately routes around Dismember.apply -- it
	wants no limbs off even when gore is otherwise on, specifically so an
	intact corpse is what tells you the layer that caught them. "Intact"
	should still mean limp, not stiff.

	ORDER MATTERS, same as everywhere else in this module: BreakJointsOnDeath
	has to go false BEFORE Health hits 0, or Roblox breaks every joint itself
	first and there is nothing left to hand to ragdollRemains.
]]
function Dismember.prepareRagdoll(humanoid: Humanoid)
	humanoid.BreakJointsOnDeath = false
	humanoid.PlatformStand = true
end

Dismember.finishRagdoll = ragdollRemains
Dismember.cleanupCorpse = cleanupCorpse

--[[
	Takes limbs off someone the blast did NOT kill.

	No ragdoll and no death -- they keep playing, one arm short. Nothing here
	touches BreakJointsOnDeath either: when they eventually die of something
	else, they should come apart normally.

	Silent on a non-R6 rig rather than warning. Dismember.apply already says so
	once per kill, and a barrage would otherwise print it a dozen times a minute.
]]
function Dismember.maim(character: Model, humanoid: Humanoid, blastPosition: Vector3, count: number): number
	if not Config.EnableGore or humanoid.Health <= 0 then
		return 0
	end

	if not Dismember.isR6(character, humanoid) then
		return 0
	end

	local pool = if Config.MaimIncludesLegs then SEVER_ORDER else MAIM_ARMS
	local severed = severSome(character, blastPosition, pool, count)

	if severed > 0 then
		log("%s maimed by shell, %d limbs off, still alive", character.Name, severed)
	end

	return severed
end

--[[
	Kills the character and takes limbs off.

	`severity` is 0 at the edge of the kill radius and 1 at the crater, and only
	decides how many limbs come off.

	EVERY ARTILLERY KILL RAGDOLLS. Gore only decides whether pieces come off
	first -- BreakJointsOnDeath goes false and PlatformStand goes true on every
	branch below, including the two that never sever anything, or a "no gore"
	kill is a corpse frozen under the humanoid's own state control instead of
	one gone limp. Roblox does not hand you a ragdoll for free just because
	Health hit 0; without this the character keeps whatever pose the last
	animation had it in and looks stood-up rather than dead.
]]
function Dismember.apply(character: Model, humanoid: Humanoid, blastPosition: Vector3, severity: number)
	if humanoid.Health <= 0 then
		return
	end

	Dismember.prepareRagdoll(humanoid)

	if not Config.EnableGore then
		humanoid.Health = 0
		ragdollRemains(character)
		cleanupCorpse(character)
		return
	end

	if not Dismember.isR6(character, humanoid) then
		-- Once per server, not once per kill. With AffectNPCs on, a barrage
		-- through a crowd of R15 NPCs would otherwise print this a dozen times a
		-- minute for the rest of the round.
		if not warnedNonR6 then
			warnedNonR6 = true
			warn(
				string.format(
					"[Artillery] NO DISMEMBERMENT: %s is not an R6 rig, so it was killed intact.\n"
						.. "  RigType reports %s, Torso %s, 'Right Arm' %s -- all three are required.\n"
						.. "  For players: Game Settings > Avatar > Rig Type = R6. For NPCs: rebuild the rig as R6.\n"
						.. "  Set EnableGore = false to silence this. Reported once per server.",
					character.Name,
					humanoid.RigType.Name,
					if character:FindFirstChild("Torso") then "found" else "MISSING",
					if character:FindFirstChild("Right Arm") then "found" else "MISSING"
				)
			)
		end
		-- ragdollRemains needs "Torso" and the named Motor6Ds to do anything,
		-- and a non-R6 rig has neither -- findJoint just returns nil for each
		-- and the loop is a no-op. PlatformStand above is still in effect
		-- though, which is what stops an R15 corpse standing there stiffly;
		-- it just falls and topples as one rigid piece instead of a jointed
		-- ragdoll, since there is no R15 joint table here to swap.
		humanoid.Health = 0
		ragdollRemains(character)
		cleanupCorpse(character)
		return
	end

	local span = Config.MaxLimbsSevered - Config.MinLimbsSevered
	local count = math.clamp(
		math.round(Config.MinLimbsSevered + span * math.clamp(severity, 0, 1)),
		0,
		#SEVER_ORDER
	)

	local severed = severSome(character, blastPosition, SEVER_ORDER, count)

	humanoid.Health = 0
	ragdollRemains(character)

	cleanupCorpse(character)

	log("%s killed by shell, %d limbs off", character.Name, severed)
end

return Dismember

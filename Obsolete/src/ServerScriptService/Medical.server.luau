-- Medical: bleeding, limb injuries, downed + revive, Bandage / Medkit tools. Player characters only.
-- Death is blocked by disabling the Dead state (here and in StarterCharacterScripts.MedicalClient,
-- mirrored through the character attribute CanDie). Lethal damage downs you; a second one kills.
-- Medics: set the Player attribute Medic = true; they get a Medkit on their next spawn.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local BLEED_MIN_DAMAGE = 8 -- hits smaller than this don't bleed or injure limbs
local BLEED_PER_HIT = 0.5 -- HP/s added per hit
local BLEED_MAX = 3
local DOWNED_HP = 1
local BLEEDOUT_TIME = 60 -- seconds downed before death
local REVIVE_HP = 30
local REVIVE_HOLD = 6 -- seconds a teammate holds E
local TREAT_RANGE = 7 -- studs, for treating a teammate in front of you

local TOOLS = {
	Bandage = { time = 3, uses = 4, healMissing = 0.5, stopBleed = true }, -- heals half the HP you're missing
	Medkit = { time = 6, uses = 8, healMissing = 1, stopBleed = true, fixLimbs = true, revive = true }, -- heals to full; also revives a downed teammate
}
local pillTemplate = ServerStorage:WaitForChild("Painkiller")
-- Bandage animation timing (ReplicatedStorage.MedicalAnimations, 60 fps): roll put away at f120,
-- pill out of the pocket at f132, in the mouth at f148, swallowed by f158
local PILL_OUT, PILL_GONE = 132 / 60, 158 / 60
local DEAD = Enum.HumanoidStateType.Dead
local Gore = require(game:GetService("ReplicatedStorage").SPH_Assets.Modules.Gore)
-- Gore.Mark's attributes. The downing shot's are saved as Down<name>: SPH_Server clears the mark once
-- you survive at 1 HP, so a bleed-out death would otherwise have no gore.
local GORE_KEYS = { "GoreHit", "GoreDir", "GoreDamage", "GoreShotgun", "GorePos" }

local tracked: { [Model]: { player: Player, hum: Humanoid } } = {}

-- Kill and revive feed (StarterPlayerScripts.KillFeed draws it)
local feed = Instance.new("RemoteEvent")
feed.Name = "KillFeed"
feed.Parent = game:GetService("ReplicatedStorage")
local function npcTeam(char: Model): string? -- Bloxian AI soldiers carry Settings.Team
	local s = char:FindFirstChild("Settings")
	local t = s and s:FindFirstChild("Team")
	return t and (t :: any).Value
end
local function nameOf(char: Model): string
	local p = Players:GetPlayerFromCharacter(char)
	if p then return p.DisplayName end
	if char:GetAttribute("FeedName") then return char:GetAttribute("FeedName") end -- named NPCs (Tower Assault bosses)
	local team = npcTeam(char)
	if team then -- "Bloxian Rifleman", "Bloxian Radioman", "Korblox Sniper"
		local unit = (char :: any).Settings:FindFirstChild("Unit")
		local job = if unit and unit.Value ~= "Infantry" and unit.Value ~= "" then unit.Value else char:GetAttribute("Role") or "Rifleman"
		local side = team:match("^(%S+)")
		return (if side and side ~= "Hostile" then side else "Bloxian") .. " " .. job
	end
	return char.Name
end
local function colorOf(char: Model): Color3?
	local p = Players:GetPlayerFromCharacter(char)
	local team = if p then p.Team else game:GetService("Teams"):FindFirstChild(char:GetAttribute("MedTeam") or npcTeam(char) or "") -- test dummies, NPCs
	return team and (team :: Team).TeamColor.Color
end
-- the kill goes to whoever downed you (revive clears that), even if you then bled out or gave up
local function reportDeath(char: Model)
	local killer = char:FindFirstChild("Killer")
	local k = killer and (killer :: any).Value
	local hit = char:GetAttribute("GoreHit") or char:GetAttribute("KillHit") or char:GetAttribute("DownGoreHit")
	local entry = { kind = "kill", b = nameOf(char), bColor = colorOf(char), head = hit == "Head" or nil }
	if typeof(k) == "Instance" and k:IsA("Player") and k.Character ~= char then
		entry.a, entry.aColor, entry.weapon = k.DisplayName, k.Team and k.Team.TeamColor.Color, killer:GetAttribute("Weapon")
	elseif typeof(k) == "Instance" and k:IsA("Model") and k ~= char then -- killed by an NPC (BLOXIAN CoreModule)
		entry.a, entry.aColor, entry.weapon = nameOf(k), colorOf(k), killer:GetAttribute("Weapon")
	elseif type(k) == "string" then
		entry.weapon = k -- "Falling"
	end
	feed:FireAllClients(entry)
end

local function limbOf(partName: string): string?
	if partName:find("Leg") or partName:find("Foot") then return "LegInjured" end
	if partName:find("Arm") or partName:find("Hand") then return "ArmInjured" end
	return nil
end

local function die(char: Model, hum: Humanoid)
	if not char:GetAttribute("GoreHit") and char:GetAttribute("DownGoreHit") then -- bled out: gore from the downing shot
		for _, k in GORE_KEYS do char:SetAttribute(k, char:GetAttribute("Down" .. k)) end
	end
	char:SetAttribute("CanDie", true)
	hum:SetStateEnabled(DEAD, true)
	hum.Health = 0
	hum:ChangeState(DEAD)
end

-- Downed ragdoll, undoable (SPH's RagdollMod only makes death corpses): limb Motor6Ds are switched off
-- and replaced by ball sockets laid out like SPH's corpses; the root joint stays so HRP rides the torso.
-- Everything added is named MedRagdoll so unragdoll can strip it.
-- Joints held off while downed. SPH turns them back on behind our back (its unequip re-enables the
-- shoulders), so each one is watched until unragdoll.
local heldOff: { [Model]: { RBXScriptConnection } } = {}
local function holdOff(char: Model, joint: Instance, restore: boolean)
	joint:SetAttribute("MedRagdoll", restore)
	;(joint :: any).Enabled = false
	table.insert(heldOff[char], joint:GetPropertyChangedSignal("Enabled"):Connect(function()
		if (joint :: any).Enabled and joint:GetAttribute("MedRagdoll") ~= nil then (joint :: any).Enabled = false end
	end))
end

local function ragdoll(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local r6 = hum.RigType == Enum.HumanoidRigType.R6
	-- the neck goes limp too; whichever client simulates the body (a carrier's, too) must not kill it for that
	hum.RequiresNeck = false
	heldOff[char] = heldOff[char] or {}
	-- SPH's WeaponRig welds the real arms to a rig hung off the head ("law"/"raw"); left on, the arms
	-- stay locked in the gun pose, sticking out
	local rig = char:FindFirstChild("WeaponRig")
	if rig then
		for _, w in rig:GetChildren() do
			if w:IsA("JointInstance") and (w.Name == "law" or w.Name == "raw") then holdOff(char, w, w.Enabled) end
		end
	end
	local torso, head = char:FindFirstChild("Torso"), char:FindFirstChild("Head")
	for _, m in char:GetDescendants() do
		-- shoulders included even when off: SPH turns them off while a gun is held
		if m:IsA("Motor6D") and m:GetAttribute("MedRagdoll") == nil and m.Part0 and m.Part1 and m.Part0.Parent == char and m.Part1.Parent == char
			and m.Part0.Name ~= "HumanoidRootPart" and m.Part1.Name ~= "HumanoidRootPart" then
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Name, a1.Name = "MedRagdoll", "MedRagdoll"
			a0.CFrame, a1.CFrame = m.C0, m.C1
			if r6 and m.Part1.Name == "Left Leg" then
				a0.Position += Vector3.new(0.5, 0, 0)
				a1.Position += Vector3.new(0.5, 0, 0)
			elseif r6 and m.Part1.Name == "Right Leg" then
				a0.Position -= Vector3.new(0.5, 0, 0)
				a1.Position -= Vector3.new(0.5, 0, 0)
			end
			a0.Parent, a1.Parent = m.Part0, m.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "MedRagdoll"
			socket.Attachment0, socket.Attachment1 = a0, a1
			socket.Parent = m.Part0
			holdOff(char, m, true) -- the tool is unequipped when you go down, so the arms come back on
			if m.Part1.Name ~= "Head" then
				-- the Humanoid keeps limbs non-colliding; an invisible welded collider stops them sinking
				local limb = m.Part1
				local collider = Instance.new("Part")
				collider.Name = "MedRagdoll"
				collider.Size = limb.Size * Vector3.new(0.8, 0.9, 0.8)
				collider.Transparency = 1
				collider.Massless = true
				collider.CanQuery = false
				collider.CanTouch = false
				collider.CFrame = limb.CFrame
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = limb, collider
				weld.Parent = collider
				-- it must hit the ground, not its own torso: that jams the limb at an angle
				for _, other in { torso, head } do
					if other then
						local nc = Instance.new("NoCollisionConstraint")
						nc.Name = "MedRagdoll"
						nc.Part0, nc.Part1 = collider, other
						nc.Parent = collider
					end
				end
				collider.Parent = limb
			end
		end
	end
end

local function unragdoll(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.RequiresNeck = true end
	for _, c in heldOff[char] or {} do c:Disconnect() end
	heldOff[char] = nil
	for _, d in char:GetDescendants() do
		if d.Name == "MedRagdoll" then
			d:Destroy()
		elseif d:IsA("JointInstance") and d:GetAttribute("MedRagdoll") ~= nil then
			local was = d:GetAttribute("MedRagdoll")
			d:SetAttribute("MedRagdoll", nil)
			d.Enabled = was
		end
	end
	-- stand the body back up where it lies, facing the way the torso pointed
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if flat.Magnitude < 0.2 then flat = root.CFrame.UpVector * Vector3.new(1, 0, 1) end
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
		local at = root.Position + Vector3.new(0, 2, 0)
		char:PivotTo(CFrame.lookAt(at, at + flat))
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	end
end

-- Moving a downed teammate (F on them): fireman carry over the right shoulder, or, with a chest wound,
-- a drag by the collar. carries is keyed by the carrier.
local CARRY_C0 = CFrame.fromMatrix(Vector3.new(1, 1.4, 0.1), Vector3.new(-1, 0, 0), Vector3.new(0, -1, 2).Unit, Vector3.new(0, 2, 1).Unit) -- belly on the shoulder, head down the back
local DRAG_BREAK = 10 -- studs between hand and collar before the grip slips
-- a dragged body's parts skip each other (so its colliders can't jam its joints) but hit the world
game:GetService("PhysicsService"):RegisterCollisionGroup("MedDrag")
game:GetService("PhysicsService"):CollisionGroupSetCollidable("MedDrag", "MedDrag", false)
local carries: { [Model]: { patient: Model, drag: boolean, made: { Instance }, saved: { [BasePart]: { any } }, conns: { RBXScriptConnection } } } = {}

local function setPrompts(patient: Model, dist: number)
	local root = patient:FindFirstChild("HumanoidRootPart")
	for _, p in if root then root:GetChildren() else {} do
		if p:IsA("ProximityPrompt") then p.MaxActivationDistance = dist end -- not Enabled: the client hides its own prompts with it
	end
end

local function release(carrier: Model)
	local c = carries[carrier]
	if not c then return end
	carries[carrier] = nil
	for _, x in c.conns do x:Disconnect() end
	for _, x in c.made do x:Destroy() end
	for part, s in c.saved do
		part.Massless, part.CanCollide, part.CustomPhysicalProperties, part.CollisionGroup = s[1], s[2], s[3], s[4]
	end
	for _, s in c.patient:GetDescendants() do -- hip limits from the drag off again: back to a loose ragdoll
		if s:IsA("BallSocketConstraint") and s.Name == "MedRagdoll" then s.LimitsEnabled, s.TwistLimitsEnabled, s.MaxFrictionTorque = false, false, 0 end
	end
	carrier:SetAttribute("Carrying", nil)
	carrier:SetAttribute("TreatAnim", nil)
	c.patient:SetAttribute("CarriedBy", nil)
	setPrompts(c.patient, 8)
	local owner = Players:GetPlayerFromCharacter(c.patient)
	for part in c.saved do
		if part:IsDescendantOf(workspace) then pcall(part.SetNetworkOwner, part, owner) end
	end
end

-- char stops carrying and stops being carried
local function releaseAll(char: Model)
	release(char)
	for carrier, c in carries do
		if c.patient == char then release(carrier) end
	end
end

local DRAG_PHYSICS = PhysicalProperties.new(0.02, 0.05, 0, 100, 1)
local function pickUp(rescuer: Player, patient: Model, pHum: Humanoid, forceDrag: boolean?)
	local rc = rescuer.Character
	local data = rc and tracked[rc]
	if not data or data.hum.Health <= 0 or rc:GetAttribute("Downed") or rc:GetAttribute("Treating") or carries[rc] then return end
	if not patient:GetAttribute("Downed") or pHum.Health <= 0 or patient:GetAttribute("CarriedBy") then return end
	local rTorso, arm, pTorso = rc:FindFirstChild("Torso"), rc:FindFirstChild("Right Arm"), patient:FindFirstChild("Torso")
	if not (rTorso and arm and pTorso) then return end
	local drag = forceDrag or patient:GetAttribute("ChestInjured") == true
	data.hum:UnequipTools()
	local c = { patient = patient, drag = drag, made = {}, saved = {}, conns = {} }
	-- SPH moves the arms onto its gun rig on equip (shoulders off, law/raw on), which freezes the carry
	-- pose; hold the unarmed setup until release, which is also what SPH's unequip leaves
	local function force(j: Instance?, on: boolean)
		if not j then return end
		;(j :: any).Enabled = on
		table.insert(c.conns, j:GetPropertyChangedSignal("Enabled"):Connect(function()
			if (j :: any).Enabled ~= on then (j :: any).Enabled = on end
		end))
	end
	force(rTorso:FindFirstChild("Right Shoulder"), true)
	force(rTorso:FindFirstChild("Left Shoulder"), true)
	local rig = rc:FindFirstChild("WeaponRig")
	force(rig and rig:FindFirstChild("law"), false)
	force(rig and rig:FindFirstChild("raw"), false)
	for _, part in patient:GetDescendants() do
		if part:IsA("BasePart") then
			c.saved[part] = { part.Massless, part.CanCollide, part.CustomPhysicalProperties, part.CollisionGroup }
			if drag then
				-- near-weightless and slippery: it slides along the ground, and bumping into the dragger can't
				-- fling them (gravity pulls it the same, so the limbs still dangle)
				part.CustomPhysicalProperties = DRAG_PHYSICS
				part.CollisionGroup = "MedDrag"
			else
				part.Massless, part.CanCollide = true, false -- rides along without weighing the carrier down
			end
		end
	end
	-- The body comes to you, not you to it: hand its physics to your client first, then move it so the
	-- grip already lines up. Otherwise the joint appears while your client still treats the server-owned
	-- body as immovable, and closing the gap yanks you to the body.
	for part in c.saved do pcall(part.SetNetworkOwner, part, rescuer) end
	if drag then
		-- laid out behind you, face up, head at your hand and legs trailing away: just sliding it over as it
		-- lay could land it on top of you, and that overlap shoved you yards away
		local back = rTorso.CFrame.LookVector * Vector3.new(-1, 0, -1)
		back = if back.Magnitude > 0.1 then back.Unit else Vector3.zAxis
		local center = arm.CFrame * Vector3.new(0, -1, 0) + back -- torso centre one stud behind the hand: its collar (0, 1, 0) lands exactly on it
		local torsoAt = CFrame.lookAt(center, center + Vector3.yAxis, -back) -- front up, head toward you
		patient:PivotTo(torsoAt * pTorso.CFrame:ToObjectSpace(patient:GetPivot()))
	else -- straight onto your shoulder, where the carry weld puts it
		patient:PivotTo(rTorso.CFrame * CARRY_C0 * pTorso.CFrame:ToObjectSpace(patient:GetPivot()))
	end
	if drag then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Name, a1.Name = "MedCarry", "MedCarry"
		a0.Position, a1.Position = Vector3.new(0, -1, 0), Vector3.new(0, 1, 0) -- hand, collar
		a0.Parent, a1.Parent = arm, pTorso
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "MedCarry"
		socket.Attachment0, socket.Attachment1 = a0, a1
		socket.MaxFrictionTorque = 2 -- the body swings on your hand less
		socket.Parent = arm
		c.made = { a0, a1, socket }
		-- the Humanoid keeps the torso and arms non-colliding (the ragdoll's arm colliders are slimmed),
		-- so full-size colliders stop them sinking into the floor or passing through walls
		local solid = {}
		for _, name in { "Torso", "Left Arm", "Right Arm" } do
			local limb = patient:FindFirstChild(name) :: BasePart?
			if limb then
				local col = Instance.new("Part")
				col.Name = "MedCarry"
				col.Size, col.CFrame = limb.Size, limb.CFrame
				col.Transparency, col.Massless, col.CanQuery, col.CanTouch = 1, true, false, false
				col.CollisionGroup = "MedDrag"
				col.CustomPhysicalProperties = DRAG_PHYSICS
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = limb, col
				w.Parent = col
				col.Parent = limb
				table.insert(c.made, col)
				solid[col] = true
			end
		end
		for part in c.saved do solid[part] = part.CanCollide or nil end
		-- the body bumps into the dragger, except the gripping hand, which sits on the collar
		for part in solid do
			do
				for _, name in { "Right Arm" } do
					local other = rc:FindFirstChild(name)
					if other then
						local nc = Instance.new("NoCollisionConstraint")
						nc.Name = "MedCarry"
						nc.Part0, nc.Part1 = part, other
						nc.Parent = a1
					end
				end
			end
		end
	else
		local weld = Instance.new("Weld")
		weld.Name = "MedCarry"
		weld.Part0, weld.Part1 = rTorso, pTorso
		weld.C0 = CARRY_C0
		weld.Parent = rTorso
		c.made = { weld }
	end
	-- limbs locked instead of flopping: carried, legs hang down the carrier's front and arms down the back;
	-- dragged, nothing is welded: the whole body trails loose on its ground colliders, each joint held to
	-- a cone (deg: cone, twist) so the limbs drag behind instead of flailing
	-- { cone, twist, joint friction }. The friction soaks up the flailing that tugs the dragger around but is
	-- too weak to hold a limb up against gravity, so it still dangles (torques sized for DRAG_PHYSICS' density).
	-- Joint friction, not a damper on the parts: a damper also fights the body turning to follow you.
	local DRAG_LIMITS = { Leg = { 20, 5, 2 }, Arm = { 35, 10, 1.5 }, Head = { 20, 10, 1.5 } }
	for _, s in if drag then pTorso:GetChildren() else {} do
		local a1 = s:IsA("BallSocketConstraint") and s.Name == "MedRagdoll" and s.Attachment1
		local lim = a1 and a1.Parent and DRAG_LIMITS[a1.Parent.Name:match("Leg") or a1.Parent.Name:match("Arm") or a1.Parent.Name]
		if lim then
			s.LimitsEnabled, s.UpperAngle = true, lim[1]
			s.TwistLimitsEnabled, s.TwistLowerAngle, s.TwistUpperAngle = true, -lim[2], lim[2]
			s.MaxFrictionTorque = lim[3]
		end
	end
	for _, m in if drag then {} else patient:GetDescendants() do
		if m:IsA("Motor6D") and m:GetAttribute("MedRagdoll") ~= nil and m.Part0 == pTorso and m.Part1 then
			local name = m.Part1.Name
			local dir = if name:find("Leg") then Vector3.new(0, -1, -0.25) elseif name:find("Arm") then Vector3.new(0, -1, 0.2) else nil
			local turn = CFrame.identity
			if dir then -- swing the limb's tip toward dir (carrier space)
				local want = m.C0.Rotation:Inverse() * CARRY_C0:VectorToObjectSpace(dir.Unit)
				local tip = m.C1.Rotation:Inverse() * (Vector3.new(0, -1, 0) - m.C1.Position)
				turn = CFrame.fromRotationBetweenVectors(tip.Unit, want.Unit)
			end
			local lw = Instance.new("Weld")
			lw.Name = "MedCarry"
			lw.Part0, lw.Part1 = pTorso, m.Part1
			lw.C0, lw.C1 = m.C0 * turn, m.C1
			lw.Parent = pTorso
			table.insert(c.made, lw)
		end
	end
	carries[rc] = c
	local pPlayer = Players:GetPlayerFromCharacter(patient)
	patient:SetAttribute("CarriedBy", rescuer.DisplayName)
	rc:SetAttribute("Carrying", if pPlayer then pPlayer.DisplayName else patient.Name)
	rc:SetAttribute("TreatAnim", if drag then "Drag" else "Carry")
	setPrompts(patient, 0)
end

local function revive(char: Model, hum: Humanoid, by: Model?)
	feed:FireAllClients({ kind = "revive", a = by and nameOf(by), aColor = by and colorOf(by), b = nameOf(char), bColor = colorOf(char) })
	local medic = by and Players:GetPlayerFromCharacter(by)
	if medic then medic:SetAttribute("Revives", (medic:GetAttribute("Revives") or 0) + 1) end -- TowerRun's raid score
	releaseAll(char)
	for _, name in { "Revive", "Carry" } do
		local prompt = hum.RootPart and hum.RootPart:FindFirstChild(name)
		if prompt then prompt:Destroy() end
	end
	unragdoll(char)
	hum:SetStateEnabled(DEAD, false)
	char:SetAttribute("CanDie", false)
	char:SetAttribute("BleedOut", nil)
	char:SetAttribute("Downed", nil)
	char:SetAttribute("ChestInjured", nil)
	for _, k in GORE_KEYS do -- the downing wound's gore mark must not fire on a later death
		char:SetAttribute(k, nil)
		char:SetAttribute("Down" .. k, nil)
	end
	for _, c in char:GetChildren() do
		if c.Name == "Killer" then c:Destroy() end -- credit the next kill to whoever makes it
	end
	hum.Health = REVIVE_HP
	hum.PlatformStand = false
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
end

-- Downed players are off-limits (no NPC target, no damage) while a teammate in the same place (run or lobby)
-- is still up. Once nobody is, they're LastStand: shootable and targeted again.
local function refreshLastStand()
	for char, d in tracked do
		local alone = false
		if char:GetAttribute("Downed") and d.hum.Health > 0 then
			alone = true
			for other, od in tracked do
				if other ~= char and od.hum.Health > 0 and not other:GetAttribute("Downed") and od.player.Team == d.player.Team
					and od.player:GetAttribute("InTowerRun") == d.player:GetAttribute("InTowerRun") then
					alone = false
					break
				end
			end
			char:SetAttribute("LastStand", alone or nil)
		else
			char:SetAttribute("LastStand", nil)
		end
		local shield = char:FindFirstChild("DownedShield")
		local want = char:GetAttribute("Downed") == true and not alone and d.hum.Health > 0
		if want and not shield then
			shield = Instance.new("ForceField")
			shield.Name, shield.Visible = "DownedShield", false
			shield.Parent = char
		elseif not want and shield then
			shield:Destroy()
		end
	end
end
task.spawn(function()
	while true do
		task.wait(0.25)
		refreshLastStand()
	end
end)

local function down(player: Player, char: Model, hum: Humanoid, part: string?)
	if char:GetAttribute("SuppressRagdoll") then return die(char, hum) end -- CBRN nerve gas (GasRagdoll): no downed state, straight death
	releaseAll(char)
	-- chest wound (the downing shot, or an earlier one still bleeding): dragged, not carried
	local chest = (part or char:GetAttribute("GoreHit")) == "Torso"
		or (char:GetAttribute("Bleeding") ~= nil and char:GetAttribute("WoundArea") == "Torso")
	char:SetAttribute("ChestInjured", chest or nil)
	hum.Health = DOWNED_HP -- before enabling Dead, so the humanoid never sits at 0 with death allowed
	hum:SetStateEnabled(DEAD, true)
	char:SetAttribute("CanDie", true)
	char:SetAttribute("Bleeding", nil)
	char:SetAttribute("BleedOut", BLEEDOUT_TIME)
	char:SetAttribute("Downed", true)
	refreshLastStand() -- shield on before the next bullet lands
	hum:UnequipTools()
	hum.PlatformStand = true
	local hit = char:GetAttribute("GoreHit") -- still set: we're inside the downing shot's TakeDamage
	if hit then
		for _, k in GORE_KEYS do char:SetAttribute("Down" .. k, char:GetAttribute(k)) end
	end
	local blood = Gore.Bleed(char, if hit ~= "Explosion" then hit else nil, char:GetAttribute("GorePos"))
	if blood then blood.Name = "MedRagdoll" end -- unragdoll removes it on revive
	ragdoll(char)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Revive"
	prompt.ActionText = "Revive"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = REVIVE_HOLD
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom -- MedicalClient draws a small tag instead of the big default button
	prompt.Triggered:Connect(function(rescuer: Player)
		local rc = rescuer.Character
		local rh = rc and rc:FindFirstChildOfClass("Humanoid")
		if rescuer == player or rescuer.Team ~= player.Team or not rh or rh.Health <= 0 or rc:GetAttribute("Downed") then return end
		if char:GetAttribute("Downed") and hum.Health > 0 then revive(char, hum, rc) end
	end)
	prompt.Parent = hum.RootPart

	local carry = Instance.new("ProximityPrompt")
	carry.Name = "Carry"
	carry.ActionText = if chest then "Drag" else "Carry"
	carry.ObjectText = player.DisplayName
	carry.KeyboardKeyCode = Enum.KeyCode.F
	carry.HoldDuration = 0.5
	carry.MaxActivationDistance = 8
	carry.RequiresLineOfSight = false
	carry.Style = Enum.ProximityPromptStyle.Custom
	carry.Triggered:Connect(function(rescuer: Player)
		if rescuer == player then return end
		pickUp(rescuer, char, hum, rescuer.Team ~= player.Team) -- enemies can only drag the body away
	end)
	carry.Parent = hum.RootPart
end

local function needs(patient: Model, hum: Humanoid, spec): boolean
	return (spec.stopBleed and (patient:GetAttribute("Bleeding") or 0) > 0)
		or ((spec.heal or spec.healMissing) and hum.Health < hum.MaxHealth)
		or (spec.fixLimbs and (patient:GetAttribute("LegInjured") or patient:GetAttribute("ArmInjured")))
		or (spec.revive and patient:GetAttribute("Downed"))
		or false
end

-- Nearest character in front of the user who needs this item, else nil (treat yourself).
-- Players must be on your team; NPCs (no player) can always be treated.
local function findPatient(player: Player, char: Model, root: BasePart, spec): Model?
	local best, bestDist = nil, TREAT_RANGE
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	for _, part in workspace:GetPartBoundsInRadius(root.Position, TREAT_RANGE, params) do
		local model = part.Parent
		local hum = model and part.Name == "HumanoidRootPart" and model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local other = Players:GetPlayerFromCharacter(model)
			local offset = part.Position - root.Position
			if (not other or other.Team == player.Team) and offset.Magnitude < bestDist
				and root.CFrame.LookVector:Dot(offset.Unit) > 0.3 and needs(model, hum, spec)
				and (spec.revive or not model:GetAttribute("Downed")) then
				best, bestDist = model, offset.Magnitude
			end
		end
	end
	return best
end

local function treat(player: Player, tool: Tool, spec)
	local char = player.Character
	local data = char and tracked[char]
	if not data or data.hum.Health <= 0 or char:GetAttribute("Downed") or char:GetAttribute("Treating") then return end
	local root = data.hum.RootPart
	if not root then return end
	local patient = findPatient(player, char, root, spec) or char
	local pHum = patient:FindFirstChildOfClass("Humanoid")
	if not pHum or not needs(patient, pHum, spec) then return end
	local reviving = patient:GetAttribute("Downed") == true
	local pPlayer = Players:GetPlayerFromCharacter(patient)

	char:SetAttribute("Treating", if patient == char then "yourself" elseif pPlayer then pPlayer.DisplayName else patient.Name)
	-- the patient's MedicalClient shows this in their status bars
	local function tellPatient(text) if patient ~= char then patient:SetAttribute("TreatedBy", text) end end
	tellPatient((if tool.Name == "Medkit" then "Treated by " else "Bandaged by ") .. player.DisplayName)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	local arm = char:FindFirstChild("Right Arm") :: BasePart?
	local pill: BasePart? = nil
	-- MedicalClient plays the animation for the wound's spot; a Bandage on a teammate uses the in-front
	-- (torso) wrap, a Medkit on someone else has its own (Medkit_Other)
	local area = patient:GetAttribute("WoundArea") or "Torso"
	if tool.Name == "Bandage" then
		char:SetAttribute("TreatAnim", "Bandage_" .. (if patient == char then area else "Torso"))
	elseif tool.Name == "Medkit" then
		char:SetAttribute("TreatAnim", "Medkit_" .. (if patient == char then area else "Other"))
	end
	-- Medkit: the open case goes down on the ground in front of the medic while they work
	local hidden: { [BasePart]: number } = {}
	local prop: Model? = nil
	if tool.Name == "Medkit" and handle then
		prop = Instance.new("Model")
		prop.Name = "MedkitProp"
		for _, p in tool:GetDescendants() do
			if p:IsA("BasePart") then
				local copy = p:Clone()
				for _, j in copy:GetChildren() do
					if j:IsA("JointInstance") or j:IsA("WeldConstraint") or j:IsA("TouchTransmitter") then j:Destroy() end
				end
				copy.Anchored = true
				copy.Parent = prop
				if p == handle then prop.PrimaryPart = copy end
				hidden[p] = p.Transparency
				p.Transparency = 1
			end
		end
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local at = root.Position + flat.Unit * 1.6
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, patient, prop }
		local hit = workspace:Raycast(at, Vector3.new(0, -8, 0), params)
		local ground = if hit then hit.Position else at - Vector3.new(0, 3, 0)
		prop:PivotTo(CFrame.lookAlong(ground + Vector3.new(0, handle.Size.Y / 2, 0), flat))
		prop.Parent = workspace
	end
	local function putAway()
		if prop then prop:Destroy() end
		for p, t in hidden do p.Transparency = t end
	end
	local start = os.clock()
	while os.clock() - start < spec.time do
		task.wait(0.1)
		local t = os.clock() - start
		if tool.Name == "Bandage" and arm then
			if not pill and t >= PILL_OUT and t < PILL_GONE then
				if handle then handle.Transparency = 1 end
				pill = pillTemplate:Clone()
				local weld = Instance.new("Weld")
				weld.Part0, weld.Part1 = arm, pill
				weld.C0 = CFrame.new(0, -1.05, -0.15)
				weld.Parent = pill
				pill.Parent = char
			elseif pill and t >= PILL_GONE then
				pill:Destroy()
			end
		end
		local pRoot = pHum.RootPart
		if tool.Parent ~= char or data.hum.Health <= 0 or char:GetAttribute("Downed") or pHum.Health <= 0
			or (patient:GetAttribute("Downed") == true) ~= reviving or not pRoot or (pRoot.Position - root.Position).Magnitude > TREAT_RANGE + 2 then
			char:SetAttribute("Treating", nil) -- interrupted: nothing used up
			char:SetAttribute("TreatAnim", nil)
			tellPatient(nil)
			if pill then pill:Destroy() end
			if handle then handle.Transparency = 0 end
			putAway()
			return
		end
	end
	char:SetAttribute("Treating", nil)
	char:SetAttribute("TreatAnim", nil)
	tellPatient(nil)
	if pill then pill:Destroy() end
	if handle then handle.Transparency = 0 end
	putAway()

	if reviving then revive(patient, pHum, char) end
	if spec.stopBleed then
		patient:SetAttribute("Bleeding", nil)
		patient:SetAttribute("WoundArea", nil)
	end
	if spec.fixLimbs then
		patient:SetAttribute("LegInjured", nil)
		patient:SetAttribute("ArmInjured", nil)
	end
	if spec.heal then pHum.Health = math.min(pHum.MaxHealth, pHum.Health + spec.heal) end
	if spec.healMissing then pHum.Health += (pHum.MaxHealth - pHum.Health) * spec.healMissing end

	local uses = tool:GetAttribute("Uses") - 1
	tool:SetAttribute("Uses", uses)
	if uses <= 0 then tool:Destroy() end
end

local function hookTool(player: Player, tool: Instance)
	local spec = tool:IsA("Tool") and TOOLS[tool.Name]
	if not spec or tool:GetAttribute("Uses") then return end -- Uses doubles as the hooked flag
	tool:SetAttribute("Uses", spec.uses)
	;(tool :: Tool).Activated:Connect(function()
		treat(player, tool :: Tool, spec)
	end)
end

-- NPC guns live in ServerStorage, so the feed gets a copy of the killer's gun to draw its icon from:
-- ReplicatedStorage.KillFeedGuns.<name>, with an AimPart on the M4 (its -Z is the muzzle, +Y up).
local npcGuns = Instance.new("Folder")
npcGuns.Name = "KillFeedGuns"
npcGuns.Parent = game:GetService("ReplicatedStorage")
local function npcGun(npc: Model): string?
	local m4 = npc:FindFirstChild("M4") :: BasePart?
	if not m4 then return nil end
	local held = m4:FindFirstChild("GunModel")
	local name = held and held:GetAttribute("GunName") or "M4"
	if npcGuns:FindFirstChild(name) then return name end
	local icon = Instance.new("Model")
	icon.Name = name
	local function copy(p: Instance)
		local c = p:Clone()
		for _, d in c:GetDescendants() do
			if not (d:IsA("BasePart") or d:IsA("DataModelMesh") or d:IsA("Model")) then d:Destroy() end
		end
		c.Parent = icon
	end
	if held then
		copy(held)
	else -- plain M4 mesh and its magazine
		local mesh = m4:Clone()
		mesh:ClearAllChildren()
		mesh.Transparency, mesh.Parent = 0, icon
		local mag = npc:FindFirstChild("Mag")
		if mag then copy(mag); (icon:FindFirstChild("Mag") :: BasePart).Transparency = 0 end
	end
	local aim = Instance.new("Part")
	aim.Name, aim.CFrame, aim.Size, aim.Transparency = "AimPart", m4.CFrame, Vector3.one * 0.1, 1
	aim.Parent = icon
	for _, p in icon:GetDescendants() do
		if p:IsA("BasePart") then p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false end
	end
	icon.Parent = npcGuns
	return name
end

-- SPH's kill credit: note the gun for the feed
local function noteWeapon(c: Instance)
	if c.Name ~= "Killer" or not c:IsA("ObjectValue") then return end
	task.spawn(function()
		if not c.Value then c.Changed:Wait() end -- SPH parents it before setting Value
		local v = c.Value
		if v and v:IsA("Model") then -- an NPC (BLOXIAN CoreModule)
			local ok, name = pcall(npcGun, v)
			if ok and name then c:SetAttribute("Weapon", name) end
			return
		end
		local kc = if v and v:IsA("Player") then v.Character else nil
		local tool = kc and kc:FindFirstChildOfClass("Tool")
		if tool then c:SetAttribute("Weapon", tool.Name) end
	end)
end

local function setup(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 20) :: Humanoid
	if not hum then return end
	hum:SetStateEnabled(DEAD, false)
	char:SetAttribute("CanDie", false)
	tracked[char] = { player = player, hum = hum }

	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		local dmg = last - h
		last = h
		local part = char:GetAttribute("LastHitPart") -- set by SPH_Server just before bullet damage
		if part then char:SetAttribute("LastHitPart", nil) end
		if h <= 0 then
			if char:GetAttribute("Downed") then die(char, hum) elseif not char:GetAttribute("CanDie") then down(player, char, hum, part) end
		elseif dmg >= BLEED_MIN_DAMAGE and not char:GetAttribute("Downed") then
			char:SetAttribute("Bleeding", math.min(BLEED_MAX, (char:GetAttribute("Bleeding") or 0) + BLEED_PER_HIT))
			local limb = part and limbOf(part)
			if limb then char:SetAttribute(limb, true) end
			-- where the Bandage animation wraps: the latest bleeding hit
			char:SetAttribute("WoundArea", if limb == "LegInjured" then "Leg" elseif limb == "ArmInjured" then "Arm" else "Torso")
		end
	end)
	hum.Died:Connect(function() reportDeath(char); tracked[char] = nil; heldOff[char] = nil; releaseAll(char) end)
	char.Destroying:Connect(function() tracked[char] = nil; heldOff[char] = nil; releaseAll(char) end)

	-- Downed players and carriers can't use tools
	char.ChildAdded:Connect(function(c)
		noteWeapon(c)
		hookTool(player, c)
		if c:IsA("Tool") and (char:GetAttribute("Downed") or carries[char]) then task.defer(hum.UnequipTools, hum) end
	end)
	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(function(c) hookTool(player, c) end)
	for _, c in backpack:GetChildren() do hookTool(player, c) end
	-- the kit (and a medic's extra Medkit) comes from TowerRun's giveKit, per raid difficulty
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(char) setup(player, char) end)
	if player.Character then task.spawn(setup, player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end

-- NPC deaths in the feed too: any living non-player humanoid with Settings.Team (Bloxian AI)
local watchedNpcs: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function watchNpc(hum: Instance)
	local m = hum.Parent
	if not hum:IsA("Humanoid") or not (m and m:IsA("Model")) or watchedNpcs[m] or tracked[m] then return end
	if Players:GetPlayerFromCharacter(m) or not npcTeam(m) or hum.Health <= 0 then return end
	watchedNpcs[m] = true
	m.ChildAdded:Connect(noteWeapon)
	hum.Died:Once(function() reportDeath(m) end)
end
workspace.DescendantAdded:Connect(watchNpc)
for _, d in workspace:GetDescendants() do watchNpc(d) end

-- Roblox's reset sets Health = 0 on the client, which the blocked Dead state ignores; MedicalClient
-- sends the reset button here instead and the server kills properly
local resetRemote = Instance.new("RemoteEvent")
resetRemote.Name = "MedicalReset"
resetRemote.Parent = game:GetService("ReplicatedStorage")
resetRemote.OnServerEvent:Connect(function(player: Player)
	local char = player.Character
	local data = char and tracked[char]
	if data and data.hum.Health > 0 then die(char, data.hum) end
end)

-- F while carrying: put them down
local carryRemote = Instance.new("RemoteEvent")
carryRemote.Name = "MedicalCarry"
carryRemote.Parent = game:GetService("ReplicatedStorage")
carryRemote.OnServerEvent:Connect(function(player: Player)
	if player.Character then release(player.Character) end
end)

-- Studio test dummies: a downed soldier in front of you, from the Command Bar (Client view) during Play:
--   game.ReplicatedStorage.MedicalDummy:FireServer("friendly")        teammate, carry or revive
--   game.ReplicatedStorage.MedicalDummy:FireServer("friendly", true)  teammate with a chest wound: drag
--   game.ReplicatedStorage.MedicalDummy:FireServer("enemy")           enemy: drag only
-- Live servers never create the remote.
if game:GetService("RunService"):IsStudio() then
	local dummyRemote = Instance.new("RemoteEvent")
	dummyRemote.Name = "MedicalDummy"
	dummyRemote.Parent = game:GetService("ReplicatedStorage")
	dummyRemote.OnServerEvent:Connect(function(player: Player, kind: string?, chest: boolean?)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end
		local enemy = kind == "enemy"
		local team = player.Team
		if enemy then -- another team, one with a uniform if there is one
			team = nil
			for _, t in game:GetService("Teams"):GetChildren() do
				if t ~= player.Team and (not team or ServerStorage.TeamMorphs:FindFirstChild(t.Name)) then team = t end
			end
		end
		local d = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
		d.Name = if enemy then "Enemy" else "Friendly"
		local morph = ServerStorage:FindFirstChild("ApplyTeamMorph")
		if morph and team then morph:Invoke(d, team.Name) end
		d:SetAttribute("MedTeam", team and team.Name) -- MedicalClient: no Player to read the team from
		d:PivotTo(root.CFrame * CFrame.new(0, 0, -5))
		d.Parent = workspace
		local hum = d:FindFirstChildOfClass("Humanoid") :: Humanoid
		tracked[d] = { player = player, hum = hum }
		hum.Died:Connect(function()
			reportDeath(d)
			tracked[d], heldOff[d] = nil, nil
			releaseAll(d)
			game:GetService("Debris"):AddItem(d, 30)
		end)
		task.wait(0.2)
		-- down() only reads the owner's DisplayName and Team, and compares it with the rescuer
		down({ DisplayName = d.Name, Team = team } :: any, d, hum, if chest or enemy then "Torso" else nil)
	end)
end

-- Blood trail: a bleeding or downed body drips as it moves (walking, carried); a dragged one smears
local lastDrip: { [Model]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
task.spawn(function()
	while true do
		task.wait(0.2)
		local dragged = {}
		for _, c in carries do
			if c.drag then dragged[c.patient] = true end
		end
		for char in tracked do
			local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
			if not (torso and (char:GetAttribute("Downed") or char:GetAttribute("Bleeding"))) then
				lastDrip[char] = nil
				continue
			end
			local last = lastDrip[char]
			local step = if last then torso.Position - last else Vector3.zero
			if not last or step.Magnitude >= (if dragged[char] then 1.5 else 3) then
				lastDrip[char] = torso.Position
				if last then Gore.Drip(char, if dragged[char] then step else nil) end
			end
		end
	end
end)

-- Bleeding and bleed-out tick
while true do
	task.wait(1)
	for carrier, c in carries do -- a drag snagged on something lets go
		local arm, collar = carrier:FindFirstChild("Right Arm"), c.patient:FindFirstChild("Torso")
		if c.drag and (not arm or not collar or (arm.Position - collar.Position).Magnitude > DRAG_BREAK) then release(carrier) end
	end
	for char, data in tracked do
		local hum = data.hum
		if hum.Health <= 0 then continue end
		if char:GetAttribute("Downed") then
			local left = (char:GetAttribute("BleedOut") or 0) - 1
			char:SetAttribute("BleedOut", left)
			if left <= 0 then die(char, hum) end
		else
			local rate = char:GetAttribute("Bleeding")
			if rate then hum.Health = math.max(0, hum.Health - rate) end
		end
	end
end

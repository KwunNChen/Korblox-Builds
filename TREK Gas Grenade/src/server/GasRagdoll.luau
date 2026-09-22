--[[
	GasRagdoll
	A living ragdoll: a limp, disarmed body on a character that is still alive.

	It started as SkiRagdoll's wipeout -- R6 Motor6Ds swapped for
	BallSocketConstraints, PlatformStand on the Humanoid -- and playtesting took
	it somewhere else, because a wipeout lasts two seconds and this lasts the
	twelve it takes someone to die. Everything below that Ski does not do was
	added to fix something that was actually happening on screen:

	    Physics state       PlatformStand alone is a property the state machine
	                        walks back out of. Jump on the same frame as the
	                        dose and the Humanoid lands, runs Landed -> Running,
	                        and stands the body up with its limbs still limp.
	    blocked states      GettingUp is the door back to standing; Jumping and
	                        Climbing are how a held key re-enters from the far
	                        end.
	    network ownership   all of the above is the server asking politely. For
	                        a player's own character the CLIENT owns the physics
	                        and runs its own state machine, so it is free to
	                        overrule any of it on the next frame.
	    full-body collision including the Head and Torso, which Ski omits. Ski
	                        gets away with it at speed; a body lying still for
	                        twelve seconds has its chest looked at.
	    disarming           a limp body holding a rifle level reads as a player
	                        still playing, and on a nerve agent the victim is
	                        alive long enough to actually use it.

	Every one of those is recorded before it is taken, so stop() can hand it all
	back. Nothing calls stop() today -- there is no recovery from the gas -- but
	start() should not be a one-way trapdoor, and a gas mask would need it.

	R6 only. TREK is an R6 framework, the joints below are R6 names, and on an
	R15 rig this finds nothing and leaves the character standing -- which is the
	right failure, because a nerve agent that silently did nothing is better than
	one that half-rigged a skeleton it did not understand.
]]

local Players = game:GetService("Players")

local GasRagdoll = {}

local JOINTS = { "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

--[[
	Every visible part collides, including the Head and the Torso.

	These two were briefly excluded, on the theory that a colliding Torso was
	what held a dosed body hovering at chest height. That was wrong. The hover
	was the Humanoid still driving the character -- the same fault that let a
	player jump through their own ragdoll and stay standing -- and it is fixed
	where it actually lives, by putting the Humanoid into Physics and taking
	network ownership. With the Humanoid genuinely off the body, the Torso is
	simply the part the chest is supposed to land on, and without it the trunk
	and head have nothing to rest on and sink through the floor.

	SkiRagdoll omits both, which is what the earlier version copied. Ski gets
	away with it because a wipeout lasts a couple of seconds at speed, where
	nobody is looking closely at where the chest is. A body that lies there for
	twelve seconds dying is looked at closely.
]]
local COLLIDE = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

--[[
	What gets shaken by the convulsions.

	The same list, kept separate because they answer different questions and
	have already disagreed once. A seizure that leaves the trunk and head
	perfectly still reads as a puppet with loose arms, so if COLLIDE ever
	narrows again, this must not narrow with it.
]]
local LIMBS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local TAG = "GasRagdoll"

--[[
	The routes back to standing, closed while the body is limp.

	GettingUp is the one that actually stands a ragdoll up. Jumping and Climbing
	are here because a key held down at the moment of the dose would otherwise
	re-enter the state machine from the other end -- which is the exact bug this
	list was added for.

	FallingDown and Ragdoll are Roblox's own half-ragdoll states; left enabled
	they fight the constraints for control of the same body.
]]
local BLOCKED_STATES = {
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

--[[
	Characters currently limp, and what was created to make them so.

	Weak-keyed: a character destroyed on respawn takes its entry with it rather
	than holding the model alive in this table forever.
]]
type Session = {
	created: { Instance },
	joints: { Motor6D },
	restore: Restore,
	collision: { [BasePart]: boolean },
	stash: Folder?,
	guards: { RBXScriptConnection },
}

type Restore = {
	autoRotate: boolean,
	walkSpeed: number,
	jumpPower: number,
	states: { [Enum.HumanoidStateType]: boolean },
}

local active: { [Model]: Session } =
	setmetatable({}, { __mode = "k" }) :: any

--[[
	Take their weapons off them, and keep them off.

	A limp body holding a rifle level is the single thing that breaks the
	illusion hardest -- worse than a stiff pose, because it reads as a player
	still playing. And on a nerve agent it is not only cosmetic: the victim is
	alive for twelve seconds, and without this they can fight the whole way down.

	Three parts, because unequipping alone is not enough:

		UnequipTools    puts down whatever is in their hands right now
		the stash       moves the Backpack somewhere the hotbar cannot see, so
		                there is nothing left to select. Emptying the hotbar is
		                what actually stops the equipping; unequipping on its own
		                just means they press the key again
		the guards      catch anything handed to them mid-death by some other
		                system, and anything forced directly into the character

	The stash hangs off the Player rather than the character, because a character
	is destroyed on respawn and stop() may need to give these back -- there is no
	recovery from the gas today, but a gas mask would want one.
]]
local function disarm(character: Model, humanoid: Humanoid): (Folder?, { RBXScriptConnection })
	local guards: { RBXScriptConnection } = {}

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		-- An NPC has no Backpack to empty. Its hands still get emptied.
		humanoid:UnequipTools()
		return nil, guards
	end

	humanoid:UnequipTools()

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil, guards
	end

	local stash = Instance.new("Folder")
	stash.Name = TAG .. "_Tools"
	stash.Parent = player

	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			item.Parent = stash
		end
	end

	-- Anything granted after this point goes straight past the hotbar.
	table.insert(guards, backpack.ChildAdded:Connect(function(item)
		if item:IsA("Tool") and stash.Parent then
			item.Parent = stash
		end
	end))

	--[[
		A Tool parented directly into the character is an equip that never
		touched the Backpack, so the guard above cannot see it. Deferred because
		unequipping inside ChildAdded fights the equip that is still in progress.
	]]
	table.insert(guards, character.ChildAdded:Connect(function(item)
		if not item:IsA("Tool") then
			return
		end

		task.defer(function()
			if item.Parent == character and humanoid.Parent then
				humanoid:UnequipTools()
			end
		end)
	end))

	--[[
		The stash dies with them.

		Left alone it would sit under the Player holding a duplicate loadout,
		and respawning refills the Backpack from StarterPack regardless -- so
		keeping it past death only ever produces two of everything.
	]]
	table.insert(guards, humanoid.Died:Connect(function()
		if stash.Parent then
			stash:Destroy()
		end
	end))

	return stash, guards
end

--[[
	Go limp.

	Returns the parts worth shaking for a convulsion, which is NOT the same as
	the set made collidable -- see COLLIDE and LIMBS above. The caller would
	otherwise have to re-derive the list.
]]
function GasRagdoll.start(character: Model): { BasePart }
	local limbs: { BasePart } = {}

	if active[character] then
		return limbs
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local torso = character:FindFirstChild("Torso")

	if not humanoid or humanoid.Health <= 0 or not torso or not torso:IsA("BasePart") then
		return limbs
	end

	local created: { Instance } = {}
	local disabled: { Motor6D } = {}

	for _, name in ipairs(JOINTS) do
		local joint = torso:FindFirstChild(name)

		if joint and joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
			--[[
				The attachments inherit the joint's own C0/C1, so the socket
				hangs the limb exactly where the Motor6D held it. Built from
				scratch instead would drop every limb to the torso origin on the
				first frame.
			]]
			local a0 = Instance.new("Attachment")
			a0.Name = TAG .. "_" .. name
			a0.CFrame = joint.C0
			a0.Parent = joint.Part0

			local a1 = Instance.new("Attachment")
			a1.Name = TAG .. "_" .. name
			a1.CFrame = joint.C1
			a1.Parent = joint.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = TAG .. "_" .. name
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			--[[
				Looser than they were, and matched to RagdollDeath.

				A tight limit is not a safer limit. Every degree a limb is pushed
				past its cone is a constraint violation the solver has to answer,
				and it answers with position corrections large enough to put a
				forearm through a floor. The convulsions here push limbs past their
				limits constantly, for twelve seconds, on a body already resting on
				geometry.

				RagdollDeath uses 75 and +/-45 on corpses that lie around
				indefinitely, which is the closest thing in this place to what
				happens here. Ski's 70 and +/-50 works too. The 60 and +/-40 this
				started with was tighter than either, for no reason beyond it
				sounding more anatomical.
			]]
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = 75
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Parent = joint.Part0

			table.insert(created, a0)
			table.insert(created, a1)
			table.insert(created, socket)

			joint.Enabled = false
			table.insert(disabled, joint)
		end
	end

	if #disabled == 0 then
		-- R15 or a malformed rig. Nothing was changed, so nothing is tracked.
		return limbs
	end

	local collision: { [BasePart]: boolean } = {}

	for _, name in ipairs(COLLIDE) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			collision[part] = part.CanCollide
			part.CanCollide = true
		end
	end

	--[[
		The invisible root does NOT collide.

		HumanoidRootPart is a 2x2x1 block sitting coincident with the Torso and
		in the same assembly, so while both collide they rest at the same height
		and it changes nothing -- until the body lands on an edge or a slope,
		where the floor is being held off by a box nobody can see and the pose
		reads as subtly wrong with no visible reason.

		Collide with the geometry people can actually see.
	]]
	local stash, guards = disarm(character, humanoid)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		collision[rootPart] = rootPart.CanCollide
		rootPart.CanCollide = false
	end

	for _, name in ipairs(LIMBS) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(limbs, part)
		end
	end

	--[[
		Take the body off the Humanoid, and make sure it cannot be handed back.

		PlatformStand alone is not enough, and the way it fails is specific:
		jump on the same frame as the dose and the Humanoid is already in
		Jumping. It lands, runs Landed -> Running, and Running stands the body
		back up -- so the victim finishes the jump on their feet with limp limbs
		hanging off a torso the Humanoid is still driving. PlatformStand is a
		property the state machine is free to walk out of; Physics is a state it
		cannot leave on its own.

		So all four of these, and each one is load-bearing:

			Jump = false      drops an input queued in the same frame, which
			                  would otherwise fire after everything below
			SetStateEnabled   shuts the doors back to standing. GettingUp is
			                  the one that matters; Jumping and Climbing stop a
			                  held key starting the trip again
			PlatformStand     still wanted -- it is what stops movement input
			                  being applied at all
			Physics           the actual ragdoll state. Nothing simulates the
			                  character but the solver

		WalkSpeed and JumpPower go to zero as well. Not redundant: they are the
		backstop if some other system in the place changes state on this
		Humanoid, and the cost of being wrong here is a dosed player sprinting
		around for twelve seconds.

		Everything is recorded first so stop() can hand it all back.
	]]
	local restore = {
		autoRotate = humanoid.AutoRotate,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		states = {} :: { [Enum.HumanoidStateType]: boolean },
	}

	for _, state in ipairs(BLOCKED_STATES) do
		restore.states[state] = humanoid:GetStateEnabled(state)
		humanoid:SetStateEnabled(state, false)
	end

	humanoid.Jump = false
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	--[[
		Take the body off the player's machine.

		Everything above is the server asking politely. For a player's own
		character the CLIENT owns the physics and runs its own copy of the state
		machine, so a server-side ChangeState is a request the client is free to
		overrule on the very next frame -- which is precisely what a jump does,
		because the client is mid-jump and knows it.

		Handing ownership to the server ends the argument. It is also the only
		version of this that survives someone who does not want to ragdoll: with
		the client authoritative, refusing to fall over is a matter of ignoring
		a replicated property.

		pcall because SetNetworkOwner throws on an anchored part or one outside
		the workspace, and a character being destroyed mid-dose can be both.
		Failing here should cost the shove its authority, not the death.
	]]
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	--[[
		Tell the place's death ragdoll to leave this character alone.

		RagdollDeath reads SuppressRagdoll before ragdolling a corpse. Without
		it, a character that dies already limp gets a second set of constraints
		layered onto the first and the body folds through itself.
	]]
	character:SetAttribute("SuppressRagdoll", true)

	active[character] = {
		created = created,
		joints = disabled,
		restore = restore,
		collision = collision,
		stash = stash,
		guards = guards,
	}

	return limbs
end

--[[
	Stand back up.

	Nothing in the nerve agent calls this -- once dosed you do not recover -- but
	it exists so the ragdoll is a complete thing rather than a one-way trapdoor,
	and so a future gas mask or medic could undo it.
]]
function GasRagdoll.stop(character: Model)
	local state = active[character]
	if not state then
		return
	end

	active[character] = nil

	for _, instance in ipairs(state.created) do
		if instance.Parent then
			instance:Destroy()
		end
	end

	for _, joint in ipairs(state.joints) do
		if joint.Parent then
			joint.Enabled = true
		end
	end

	for part, wasCollidable in pairs(state.collision) do
		if part.Parent then
			part.CanCollide = wasCollidable
		end
	end

	--[[
		Drop the guards BEFORE returning the tools.

		The backpack guard moves any Tool that lands in the Backpack into the
		stash. Restore in the other order and every tool handed back is caught
		and put straight where it came from -- a loop that terminates only
		because it runs out of tools to move, leaving the player empty-handed
		and nothing anywhere saying why.
	]]
	for _, guard in ipairs(state.guards) do
		guard:Disconnect()
	end

	if state.stash then
		local stash = state.stash :: Folder
		local player = Players:GetPlayerFromCharacter(character)
		local backpack = player and player:FindFirstChildOfClass("Backpack")

		if backpack then
			for _, item in ipairs(stash:GetChildren()) do
				item.Parent = backpack
			end
		end

		stash:Destroy()
	end

	character:SetAttribute("SuppressRagdoll", nil)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	--[[
		Hand back exactly what was taken, in the reverse order it was taken in.

		The states are re-enabled BEFORE the state change, because ChangeState
		into a disabled state does nothing at all -- restoring in the other
		order leaves the character in Physics with no way out, which is a more
		thorough version of the bug this whole block exists to fix.
	]]
	local restore = state.restore

	for blocked, wasEnabled in pairs(restore.states) do
		humanoid:SetStateEnabled(blocked, wasEnabled)
	end

	humanoid.AutoRotate = restore.autoRotate
	humanoid.WalkSpeed = restore.walkSpeed
	humanoid.JumpPower = restore.jumpPower
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	--[[
		Give the body back to whoever was driving it.

		Nil rather than the player when there is no player: that is Roblox's
		"decide automatically", which is right for an NPC and wrong to leave
		pinned to the server forever.
	]]
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local owner = Players:GetPlayerFromCharacter(character)
		pcall(function()
			root:SetNetworkOwner(owner)
		end)
	end
end

return GasRagdoll

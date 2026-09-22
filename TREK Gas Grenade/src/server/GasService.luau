--[[
	GasService
	Owns every grenade between the moment it is cooked and the moment its cloud
	expires.

	The server keeps the fuse clock. That is not paranoia about a stray exploiter
	so much as the only arrangement that works: if the client reported how long
	it had cooked, the cheapest possible cheat would be to claim a full cook on a
	grenade thrown instantly, which lands a cloud on someone with no warning at
	all. Cook start and throw arrive as two separate messages and the elapsed
	time between them is measured here.

	Everything else follows from that. The client says "I am cooking" and "I am
	throwing, in this direction". It does not say how long, where the grenade
	landed, or who was standing in the gas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local GasService = {}

local package = expect(ReplicatedStorage, "TREKGasGrenade")
local Config = require(expect(package, "GasConfig"))
local GasShared = require(expect(package, "GasShared"))
local GasCloud = require(expect(script.Parent, "GasCloud"))

local throwRemote = expect(package, "ThrowGrenade") :: RemoteEvent

--[[
	Per-player cook state.

	Keyed by player, cleared on throw, death, unequip and disconnect. `token`
	exists so a watchdog that has already been superseded can tell -- comparing
	the token it captured against the current one is cheaper and more reliable
	than trying to cancel a sleeping thread.
]]
local cooking: { [Player]: { start: number, token: number, tool: Tool } } = {}
local lastThrow: { [Player]: number } = {}
local nextToken = 0

--[[
	Find the two grenade models in ServerStorage.

	Deliberately not a single FindFirstChild on a fixed folder. Installing the
	package drags in a staging folder that is ALSO called TREKGasGrenade -- the
	signpost wrapper the README tells you to delete afterwards -- and until it is
	deleted ServerStorage holds two children with that name. FindFirstChild
	returns whichever it reaches first, and half the time that is the empty
	staging folder, which would leave the grenade silently unthrowable with a
	"model is missing" warning pointing at a folder that plainly exists.

	So: preferred folder first, then a recursive sweep of ServerStorage. The
	sweep also covers anyone who simply parked the models somewhere else.
]]
local function resolveModels(): (Model?, Model?)
	local active, inactive

	for _, child in ipairs(ServerStorage:GetChildren()) do
		if child.Name == "TREKGasGrenade" then
			active = active or child:FindFirstChild("ActiveGasGrenade")
			inactive = inactive or child:FindFirstChild("InactiveGasGrenade")
		end
	end

	active = active or ServerStorage:FindFirstChild("ActiveGasGrenade", true)
	inactive = inactive or ServerStorage:FindFirstChild("InactiveGasGrenade", true)

	return (active :: Model?), (inactive :: Model?)
end

--[[
	The grenade tool the player currently has out, or nil.

	Deliberately not TREK's `returnTool`: that resolves through GunConfigs and is
	fine for a gun, but here we want a flat identity check against the tool name
	with no dependency on the config lookup succeeding.
]]
local function equippedGrenade(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool.Name == Config.ToolName then
		return tool
	end

	return nil
end

--[[
	TREK builds TAmmo as one folder per mode, each holding DoubleConstrainedValues
	named Ammo and Stored. The mode folders are named after the config table's
	keys, so the single `[1]` mode in the shim becomes a folder called "1".
]]
local function ammoValue(tool: Tool): DoubleConstrainedValue?
	local store = tool:FindFirstChild("TAmmo")
	if not store then
		return nil
	end

	local mode = store:FindFirstChild("1")
	if not mode then
		return nil
	end

	local ammo = mode:FindFirstChild("Ammo")
	return (ammo and ammo:IsA("DoubleConstrainedValue")) and ammo or nil
end

local function clearCook(player: Player)
	cooking[player] = nil
end

--[[
	Spend one grenade, and take the tool away if that was the last.

	Both of the places ammo is spent -- a throw, and a cook that went off in the
	hand -- go through here, so "out of grenades" means the same thing in both.

	Destroying the tool is what makes a one-shot grenade read as one. Left in the
	hotbar at zero it still selects, still puts a grenade in your hand, and
	silently refuses to throw. It also removes the moment where the held model
	and the thrown model both exist, which at a capacity of one should never
	happen.

	The client handler dies with the tool, but the throw animation does not: the
	track belongs to the character's Animator, so it plays out after the tool is
	gone.
]]
local function consumeAmmo(tool: Tool)
	local ammo = ammoValue(tool)
	if not ammo then
		return
	end

	ammo.Value = math.max(ammo.Value - 1, 0)

	if not Config.DestroyWhenEmpty or ammo.Value > 0 then
		return
	end

	local store = tool:FindFirstChild("TAmmo")
	local mode = store and store:FindFirstChild("1")
	local reserve = mode and mode:FindFirstChild("Stored")

	-- Only when there is genuinely nothing left to reload from. A tool with a
	-- reserve is empty, not spent.
	if reserve and reserve:IsA("DoubleConstrainedValue") and reserve.Value > 0 then
		return
	end

	--[[
		Empty the hand now, remove the slot shortly after.

		The grenade is in the air, so continuing to show one in the hand is
		simply wrong -- and it is the same frame the thrown model appears, which
		would otherwise put two grenades on screen at once. The Tool itself
		survives a little longer because destroying it fires Unequipped, and
		having the slot disappear out of the hotbar mid-swing reads badly even
		once the animation is no longer cut short by it.
	]]
	local model = tool:FindFirstChild("InactiveGasGrenade")
	if model then
		model:Destroy()
	end

	if Config.DestroyDelay <= 0 then
		tool:Destroy()
		return
	end

	task.delay(Config.DestroyDelay, function()
		if tool and tool.Parent then
			tool:Destroy()
		end
	end)
end

--[[
	Launch direction.

	The aim vector is lofted by ThrowAngle around the horizontal axis
	perpendicular to it. Looking straight up or straight down makes that
	perpendicular degenerate, so in that case the throw goes exactly where the
	player is looking, which is what they asked for anyway.
]]
local function launchVector(direction: Vector3): Vector3
	local dir = direction.Unit
	local axis = dir:Cross(Vector3.yAxis)

	if axis.Magnitude < 1e-3 then
		return dir * Config.ThrowPower
	end

	local lofted = CFrame.fromAxisAngle(axis.Unit, math.rad(Config.ThrowAngle)) * dir
	return lofted.Unit * Config.ThrowPower
end

--[[
	Put a live grenade into the world.

	Returns the model so the fuse can read its resting position later -- the
	whole point of a bouncing grenade is that where it detonates is not where it
	was thrown.
]]
local function spawnGrenade(position: Vector3, velocity: Vector3, template: Model): Model?
	local grenade = template:Clone()
	local root = GasShared.prepareRig(grenade)

	if not root then
		grenade:Destroy()
		return nil
	end

	--[[
		Low elasticity and high friction. A gas grenade that pinballs off a wall
		and rolls back to the thrower's feet is funny exactly once, and the
		player has no way to predict it.
	]]
	root.CustomPhysicalProperties = PhysicalProperties.new(
		root.CurrentPhysicalProperties.Density,
		Config.BounceFriction,
		Config.BounceElasticity,
		1,
		1
	)

	grenade:PivotTo(CFrame.new(position))
	grenade.Parent = GasShared.ignoreList()

	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = Vector3.new(
		math.random() - 0.5,
		math.random() - 0.5,
		math.random() - 0.5
	).Unit * Config.ThrowSpin

	return grenade
end

--[[
	Run a fuse, then leave a cloud wherever the grenade ended up.

	`grenade` may be nil, which is the cook-in-hand case: there is nothing in the
	world to track, and the cloud simply appears on the player.
]]
local function detonateAfter(delaySeconds: number, grenade: Model?, fallback: () -> Vector3?, thrower: Player?)
	task.delay(math.max(delaySeconds, 0), function()
		local position: Vector3?

		if grenade and grenade.Parent then
			position = grenade:GetPivot().Position
		else
			position = fallback()
		end

		if not position then
			if grenade and grenade.Parent then
				grenade:Destroy()
			end
			return
		end

		GasCloud.spawn(position, thrower, Config, grenade)
	end)
end

local function onCook(player: Player)
	if cooking[player] then
		return
	end

	local tool = equippedGrenade(player)
	if not tool then
		return
	end

	local last = lastThrow[player]
	if last and (os.clock() - last) < Config.ThrowCooldown then
		return
	end

	local ammo = ammoValue(tool)
	if not ammo or ammo.Value < 1 then
		return
	end

	nextToken += 1
	local token = nextToken
	cooking[player] = { start = os.clock(), token = token, tool = tool }

	if not Config.CookKillsYou then
		return
	end

	--[[
		Hold past the fuse and it goes off in your hand.

		The watchdog checks the token rather than assuming it is still relevant,
		because by the time it wakes the player may have thrown, died, swapped
		tools or left.
	]]
	task.delay(Config.FuseTime, function()
		local state = cooking[player]
		if not state or state.token ~= token then
			return
		end

		clearCook(player)

		consumeAmmo(state.tool)

		detonateAfter(0, nil, function()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			return root and (root :: BasePart).Position or nil
		end, player)
	end)
end

local function onThrow(player: Player, direction: Vector3)
	local state = cooking[player]
	if not state then
		return
	end

	clearCook(player)

	-- A direction that is zero-length, infinite or NaN would poison every
	-- downstream vector operation, so it is rejected outright rather than
	-- normalised into something arbitrary.
	if typeof(direction) ~= "Vector3" then
		return
	end

	local magnitude = direction.Magnitude
	if magnitude < 1e-3 or magnitude ~= magnitude or magnitude == math.huge then
		return
	end

	local tool = equippedGrenade(player)
	if not tool or tool ~= state.tool then
		return
	end

	local ammo = ammoValue(tool)
	if not ammo or ammo.Value < 1 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local active = resolveModels()
	if not active then
		warn("[GasService] ServerStorage.TREKGasGrenade.ActiveGasGrenade is missing; nothing to throw.")
		return
	end

	local elapsed = os.clock() - state.start
	local remaining = Config.FuseTime - elapsed

	--[[
		Spawned a little in front of the chest so the grenade does not begin its
		life intersecting the thrower's own collision volume, which launches it
		sideways at whatever speed the solver decides is fair.
	]]
	local origin = (root :: BasePart).Position + direction.Unit * 2 + Vector3.new(0, 1, 0)
	local velocity = launchVector(direction) + (root :: BasePart).AssemblyLinearVelocity

	local grenade = spawnGrenade(origin, velocity, active)
	if not grenade then
		warn("[GasService] ActiveGasGrenade contains no BaseParts; cannot build a rig.")
		return
	end

	--[[
		Spend it only once one is actually in the world.

		Decrementing before the spawn meant any failure past that point -- a
		model with no BaseParts, a missing template -- still cost the player
		their grenade and handed them nothing for it. At a capacity of one that
		is the whole loadout gone to a warning in the output.
	]]
	lastThrow[player] = os.clock()
	consumeAmmo(tool)

	detonateAfter(remaining, grenade, function()
		return nil
	end, player)
end

--[[
	Prepare the held model the moment a grenade tool appears on a character.

	Doing it here rather than asking anyone to bake it into the asset means a
	re-export of GasGrenades.rbxm -- which arrives anchored, unwelded and with no
	AnimPart every single time -- still produces a tool that hangs correctly off
	the hand.
]]
local function onToolAdded(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= Config.ToolName then
		return
	end

	--[[
		GasGrenades.rbxm contains no part called Handle, and Roblox refuses to
		equip a RequiresHandle tool without one. Rather than make anyone rename a
		Korean-named mesh to "Handle", the requirement is dropped and the model
		is hung off AnimPart like every other TREK weapon.
	]]
	tool.RequiresHandle = false

	--[[
		Keep it off the player's back.

		TREK Bayonet's HolsterService slings any Tool carrying an AnimPart,
		because until now an AnimPart only ever meant "rifle". The grenade needs
		one to be held at all, so without this it gets slung across the back like
		a weapon -- and worse, its spawn scan stops at the first match, so a
		grenade sorting before the rifle would take the rifle's place entirely.

		Harmless if that package is not installed; it is just an unread
		attribute.
	]]
	tool:SetAttribute("NoHolster", true)

	local character = tool.Parent
	if not character or not character:IsA("Model") then
		return
	end

	local offset = GasShared.gripOffsetFor(character, Config)
	local root = GasShared.prepareHeldRig(tool)

	if not root then
		warn("[GasService] " .. tool.Name .. " contains no InactiveGasGrenade model; nothing to hold.")
		return
	end

	--[[
		Join it to the hand ourselves.

		TREK's updateMotor is not involved and cannot be: it joins the torso, and
		prepareHeldRig has just removed the AnimPart it keys off, so checkForGun
		skips it entirely. That is the point -- a torso joint is what made the
		grenade hover beside the chest instead of following the arm.
	]]
	if not GasShared.attachToHand(character, root, offset) then
		warn(
			"[GasService] could not attach " .. tool.Name .. " to " .. character.Name
				.. " -- no right hand part appeared (Right Arm on R6, RightHand on R15). "
				.. "The grenade will not stay in the hand."
		)
	end
end

--[[
	A flag the diagnostic can read.

	The require chain that reaches this point is four modules deep and gated on
	TREK_INSTALLED, and every way it can stall is silent. This is the one
	unambiguous signal that the server half is actually alive -- without it,
	"nothing happens" and "the service never started" look identical from inside
	Studio.
]]
function GasService.start()
	_G.__GasServiceStarted = true
	throwRemote.OnServerEvent:Connect(function(player, action, direction)
		if action == "cook" then
			onCook(player)
		elseif action == "throw" then
			onThrow(player, direction)
		end
	end)

	local function onCharacter(player: Player, character: Model)
		clearCook(player)
		character.ChildAdded:Connect(onToolAdded)

		--[[
			Drop the grip joint when the grenade is put away.

			The joint lives on the arm, not on the tool, so nothing destroys it
			when the tool leaves. Left in place it points at a grenade sitting in
			the backpack, which is inert but makes the next attach look like it
			worked when it only reused a joint aimed at the wrong thing.
		]]
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") and child.Name == Config.ToolName then
				GasShared.detachFromHand(character)
			end
		end)

		for _, child in ipairs(character:GetChildren()) do
			onToolAdded(child)
		end

		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				clearCook(player)
			end)
		end
	end

	local function bind(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)

		--[[
			Catch a character that already exists.

			This service starts behind the TREK_INSTALLED gate, and TREK's
			installer routinely takes longer to finish than the player takes to
			spawn -- in Studio solo it is not close. Binding only to
			CharacterAdded means that on the very life you are standing in, the
			ChildAdded hook is never connected: the tool is never rigged, the
			motor is never attached, and the grenade does not appear in your hand
			at all. Respawning would have masked it.

			Spawned rather than called, because onCharacter yields on
			WaitForChild and this runs during service startup.
		]]
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end

		player.CharacterRemoving:Connect(function()
			clearCook(player)
		end)
	end

	Players.PlayerAdded:Connect(bind)
	for _, player in ipairs(Players:GetPlayers()) do
		bind(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		clearCook(player)
		lastThrow[player] = nil
	end)

	--[[
		Tools sitting in a Backpack get prepared on equip via the character hook
		above; this catches any staged in ServerStorage or placed in the world
		before the first character exists.
	]]
	local _, inactive = resolveModels()
	if not inactive then
		warn("[GasService] ServerStorage.TREKGasGrenade.InactiveGasGrenade is missing; the held model will not be rigged.")
	end
end

return GasService

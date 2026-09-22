--!strict
--[[
	The only LocalScript in this package. Input, state machine, and the frame
	loop that drives a move once one starts.

	It lives in StarterPlayerScripts, not StarterCharacterScripts, and that is a
	deliberate choice rather than a convention. TREK's own movement scripts live
	in StarterCharacterScripts and there is a known failure where a place ends up
	with two copies running -- see TREK Bayonet/tools/SprintDiagnostic.client.luau,
	which was written to catch exactly that. One keypress then does everything
	twice. Running once per player instead of once per life sidesteps the whole
	class of problem, and the guard below catches anyone who moves this file.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local package = ReplicatedStorage:WaitForChild("TREKParkour", 20)
if not package then
	warn("[TREKParkour] ReplicatedStorage.TREKParkour is missing -- parkour is off. See install step 1.")
	return
end

local Config = require(package:WaitForChild("ParkourConfig"))
local Shared = require(package:WaitForChild("ParkourShared"))
local Detect = require(package:WaitForChild("ParkourDetect"))
local Motion = require(script.Parent:WaitForChild("ParkourMotion"))
local Pose = require(script.Parent:WaitForChild("ParkourPose"))
local Boost = require(script.Parent:WaitForChild("ParkourBoost"))

--[[
	If a second copy of this script starts, the first one wins and the second
	returns quietly. Two controllers would both watch JumpRequest and both fire
	the remote, and the server would reject the duplicate as a rate-limit
	violation -- which looks exactly like a broken mantle.
]]
if _G.__TREKParkourController then
	Shared.warn("a second ParkourController started -- ignoring it. Only one copy should be installed.")
	return
end
_G.__TREKParkourController = true

local player = Players.LocalPlayer

--[[
	The server builds these at runtime, so they can appear after this script
	does. Resolved off the critical path: if a move somehow happens before they
	arrive it simply runs without the lockout rather than yielding an input
	handler or erroring.
]]
local remoteBegin: RemoteEvent? = nil
local remoteEnd: RemoteEvent? = nil

task.spawn(function()
	remoteBegin = Shared.getRemote("ParkourBegin")
	remoteEnd = Shared.getRemote("ParkourEnd")
end)

local State = table.freeze({
	Idle = "Idle",
	Vaulting = "Vaulting",
	Mantling = "Mantling",
})

type Session = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	state: string,
	cooldownUntil: number,
	lastJumpAt: number,
	airborneSince: number?,
	lastVaultReason: string?,
	connections: { RBXScriptConnection },
}

local session: Session? = nil

--[[
	Tear down whatever is running. Safe on a session that never started a move,
	safe to call twice, and it must stay that way -- every abort path funnels
	through here, including ones that fire a frame apart.
]]
local function endSession(reason: string)
	local current = session
	if not current then
		return
	end
	session = nil

	-- A move in flight belongs to the body that is going away. Stop it before
	-- the connections go, so its teardown still has something to restore.
	Motion.stop("session ended")
	Boost.cancel()

	for _, connection in current.connections do
		connection:Disconnect()
	end

	Shared.log("session ended (%s)", reason)
end

local function beginSession(character: Model)
	endSession("new character")

	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		Shared.warn("character arrived without a Humanoid or a root -- parkour is off for this life.")
		return
	end

	-- TREK's per-character config carries the flags this package reads and sets.
	-- Without it there is no sprint to veto and no UsingAbility to claim.
	if not character:WaitForChild("TREK_PlrConfig", 15) then
		Shared.warn("no TREK_PlrConfig on this character -- parkour is off for this life.")
		return
	end

	local current: Session = {
		character = character,
		humanoid = humanoid,
		root = root,
		state = State.Idle,
		cooldownUntil = 0,
		lastJumpAt = 0,
		airborneSince = nil,
		lastVaultReason = nil,
		connections = {},
	}

	table.insert(
		current.connections,
		humanoid.Died:Connect(function()
			endSession("died")
		end)
	)

	table.insert(
		current.connections,
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				endSession("character removed")
			end
		end)
	)

	session = current

	-- Build and download the tracks now, not on the first vault. A track whose
	-- asset has not arrived plays nothing, which makes the first move of each
	-- life the one that looks broken.
	task.spawn(Pose.prepare, humanoid)

	Shared.log("session started")
end

--[[
	The gate both moves pass through. Cheap tests first, because the vault runs
	this ten times a second.

	`announce` is off for the vault poll -- a refusal reason printed at 10Hz
	drowns the log it is supposed to be helping you read. The mantle announces,
	because it is a thing you asked for and got told no about.
]]
local function readyFor(current: Session, announce: boolean): boolean
	if current.state ~= State.Idle then
		return false
	end

	if os.clock() < current.cooldownUntil then
		return false
	end

	local blocked = Shared.blockReason(current.character, current.humanoid)
	if blocked then
		if announce then
			Shared.log("refused -- %s", blocked)
		end
		return false
	end

	return true
end

local probeClock = 0

--[[
	The vault polls, so it only speaks when its answer CHANGES. Logging every
	refusal at 10Hz buries everything else in Output and makes the one line you
	were looking for impossible to find.
]]
local function noteVault(current: Session, reason: string?)
	if reason == current.lastVaultReason then
		return
	end
	current.lastVaultReason = reason
	if reason then
		Shared.log("vault -- %s", reason)
	end
end

--[[
	Fire the remote, run the move, and own every way out of it.

	The two moves build genuinely different specs -- one derives a hang point
	from a Reading, the other just reads its own position -- so they keep their
	own setup. What they had in common was the whole tail: the same remote fire,
	the same onFinish, the same failure path, differing only in the word in the
	log line. That is what lives here.

	The remote is fired BEFORE the motion starts, not after it finishes. The
	server has to take the weapon and veto sprint now; waiting a round trip
	before moving would make the whole thing feel laggy, so the client moves
	immediately and the lockout catches up. ParkourMotion covers the gap by not
	claiming rotation until the weapon has actually gone.
]]
local function launch(
	current: Session,
	action: string,
	label: string,
	draft: Motion.Draft,
	onComplete: (() -> ())?
): boolean
	if remoteBegin then
		remoteBegin:FireServer({ action = action, start = draft.from, finish = draft.to })
	end

	local function finished(reason: string)
		current.state = State.Idle
		current.cooldownUntil = os.clock() + Config.Cooldown
		current.lastVaultReason = nil
		if remoteEnd then
			remoteEnd:FireServer({ reason = reason })
		end
	end

	draft.onFinish = function(reason: string)
		finished(reason)
		Shared.log("%s ended (%s)", label, reason)

		-- Only a move that actually ran to the end earns its reward. A vault cut
		-- short by death, a seat or the deadline gets nothing.
		if reason == "completed" and onComplete then
			onComplete()
		end
	end

	if Motion.start(current.character, current.humanoid, current.root, draft :: Motion.Spec) then
		return true
	end

	-- Nothing started, so nothing will call onFinish. Release by hand or the
	-- server holds the lockout until its watchdog fires.
	finished("could not start")
	Shared.log("%s could not start -- something else has the body", label)
	return false
end

local function startVault(current: Session, land: Vector3, height: number)
	current.state = State.Vaulting

	--[[
		The vault goes through the server for the same reasons the mantle does --
		UsingAbility so other systems can see it, a rate limit, and the anchor
		check -- even though it costs the player nothing. A move the server never
		hears about is a move with no bound on how far or how often it can happen.
	]]
	local ok = launch(current, Shared.Action.Vault, "vault", {
		from = current.root.Position,
		to = land,
		duration = Config.VaultDuration,
		arcHeight = Config.ArcHeight,

		--[[
			No facing. The vault writes position only and leaves rotation to
			whoever else wants it -- which while a weapon is out is TREK's
			HeadAndArmsController, every frame. Not contesting it is what lets
			the weapon stay in your hands through a vault.
		]]
		facing = nil,
		animation = "Vault",
	}, function()
		Boost.apply(current.character, current.humanoid)
	end)

	if ok then
		Shared.log("VAULT -- %.1f studs", height)
	end
end

--[[
	Order matters here, and it is not the order it reads in.

	The two property reads below reject almost every tick -- standing still,
	walking, or airborne -- and they cost nothing. readyFor is the expensive one:
	through blockReason it makes three FindFirstChild calls and a
	Humanoid:GetState(), which forces a state-machine query.

	Running the cheap pair first means an idle player pays two property reads ten
	times a second instead of thirty instance lookups and ten state queries.
]]
local function pollVault(current: Session)
	if not Config.EnableVault then
		return
	end

	-- Airborne is the mantle's business, not the vault's.
	if current.humanoid.FloorMaterial == Enum.Material.Air then
		noteVault(current, nil)
		return
	end

	local velocity = current.root.AssemblyLinearVelocity
	if Vector3.new(velocity.X, 0, velocity.Z).Magnitude < Config.MinApproachSpeed then
		noteVault(current, nil)
		return
	end

	if not readyFor(current, false) then
		return
	end

	local reading = Detect.probe(current.character, current.humanoid, current.root, Detect.Result.Vault)

	if reading.result == Detect.Result.Vault and reading.land then
		noteVault(current, nil)
		startVault(current, reading.land, reading.height or 0)
		return
	end

	--[[
		The detector reports what it found, not what the caller wanted. A wall
		that classifies as Mantle is a perfectly good answer to "can I mantle
		this" and a refusal for the vault, so the vault has to phrase it.
	]]
	if reading.result == Detect.Result.Mantle then
		noteVault(current, string.format("%.1f studs -- too tall to vault, jump at it instead", reading.height or 0))
		return
	end

	noteVault(current, reading.reason or reading.result)
end

RunService.Heartbeat:Connect(function(dt)
	local current = session
	if not current or not current.character.Parent then
		return
	end

	--[[
		Airborne tracking. FloorMaterial is the cheap reliable answer -- it is
		Air exactly when nothing is under the Humanoid, without having to guess
		from the state machine, which TREK leaves entirely unmanaged anyway.
	]]
	if current.humanoid.FloorMaterial == Enum.Material.Air then
		if not current.airborneSince then
			current.airborneSince = os.clock()
		end
	else
		current.airborneSince = nil
	end

	probeClock += dt
	if probeClock < 1 / Config.ProbeRate then
		return
	end
	probeClock = 0

	-- A cast that throws must not kill the loop for the rest of the session.
	local ok, err = pcall(pollVault, current)
	if not ok then
		Shared.warn("vault probe errored, disabling this session: %s", tostring(err))
		endSession("probe error")
	end
end)

local function startMantle(current: Session, reading: Detect.Reading)
	local land, facePoint, topY = reading.land, reading.facePoint, reading.topY
	if not land or not facePoint or not topY then
		return
	end

	current.state = State.Mantling

	local ok = launch(current, Shared.Action.Mantle, "mantle", {
		from = current.root.Position,
		to = land,

		--[[
			The hang: root level with the lip, pulled back off the wall face so
			the body is not inside it. Feet end up dangling three studs below,
			which is what makes the first half read as hauling rather than
			floating.
		]]
		grab = Shared.grabPoint(facePoint, topY, reading.direction),
		duration = Config.MantleDuration,
		arcHeight = Config.ArcHeight,

		-- Face the wall for the whole climb. Locking it stops the move and the
		-- camera disagreeing about which way forward is halfway up.
		facing = reading.direction,
		animation = "MantleCatch",
		animationLate = "MantlePull",
	})

	if ok then
		Shared.log("MANTLE -- %.1f studs tall, lip %.1f from the root", reading.height or 0, reading.reach or 0)
	end
end

--[[
	The mantle, on the jump button.

	JumpRequest covers keyboard, gamepad and the mobile jump button in one
	connection, and it collides with none of the keys TREK has already taken.
	But it FIRES REPEATEDLY WHILE THE KEY IS HELD, several times a second -- so
	without the debounce, holding space through a jump spends the attempt on the
	first airborne frame, long before you are anywhere near the ledge.
]]
UserInputService.JumpRequest:Connect(function()
	local current = session
	if not current or not Config.EnableMantle then
		return
	end

	local now = os.clock()
	if now - current.lastJumpAt < Config.JumpDebounce then
		return
	end
	current.lastJumpAt = now

	-- Grounded means this press is the jump itself, not a mantle.
	local airborneSince = current.airborneSince
	if not airborneSince then
		return
	end

	--[[
		Checked before the window, not after. A vault sets PlatformStand, which
		makes FloorMaterial read as Air, so a jump pressed mid-vault looks
		airborne and would otherwise report a window failure for a move that was
		never eligible. readyFor rejects a busy state silently.
	]]
	if not readyFor(current, true) then
		return
	end

	local aloft = now - airborneSince
	if aloft < Config.MantleWindowMin or aloft > Config.MantleWindowMax then
		Shared.log("mantle -- %.2fs aloft, outside the window", aloft)
		return
	end

	local ok, reading = pcall(Detect.probe, current.character, current.humanoid, current.root, Detect.Result.Mantle)
	if not ok then
		Shared.warn("mantle probe errored: %s", tostring(reading))
		return
	end

	if reading.result == Detect.Result.Mantle and reading.land then
		startMantle(current, reading)
	else
		Shared.log("mantle refused -- %s", reading.reason or reading.result)
	end
end)

player.CharacterAdded:Connect(beginSession)
if player.Character then
	task.spawn(beginSession, player.Character)
end

player.CharacterRemoving:Connect(function()
	endSession("character removing")
end)

Shared.log("client ready -- vault %s, mantle %s", tostring(Config.EnableVault), tostring(Config.EnableMantle))

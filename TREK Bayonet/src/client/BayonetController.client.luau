--!strict
--[[
	The local half of the bayonet: the keybind, the charge pose and the thrust
	animation.

	It decides nothing and sends nothing. The hitbox is the bayonet part itself,
	welded to the character, so the server sweeps it directly -- there is no
	position to report and none to spoof. The cooldown here is for feel, not for
	fairness.

	Nothing in here modifies TREK. The charge pose is our own AnimationTrack
	played at Action priority, which outranks the gun handler's SprintHold
	without going anywhere near determineAnim.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[
	Every wait below is bounded and says something when it gives up.

	The first version of this script yielded forever on each of them. When the
	bayonet then did nothing, the log was completely silent -- no error, no
	warning, no way to tell whether this script had run, stalled, or never been
	installed at all. Silence is the worst possible failure for something a
	player triggers by pressing a key, because there is nothing to search for.
]]
local WAIT = 30

local installed = ReplicatedStorage:WaitForChild("TREK_INSTALLED", WAIT)
if not installed then
	warn("[TREKBayonet] TREK_INSTALLED never appeared -- is TREK installed? Bayonet disabled.")
	return
end

local waited = 0
while not installed.Value do
	waited += task.wait()
	if waited > WAIT then
		warn("[TREKBayonet] TREK_INSTALLED exists but never turned true. Bayonet disabled.")
		return
	end
end

local package = ReplicatedStorage:WaitForChild("TREKBayonet", WAIT)
if not package then
	warn("[TREKBayonet] ReplicatedStorage.TREKBayonet is missing -- the ReplicatedStorage "
		.. "folder from the package was not installed. Bayonet disabled.")
	return
end

local Config = require(package:WaitForChild("BayonetConfig"))

local stabRemote = package:WaitForChild("BayonetStab", WAIT) :: RemoteEvent?
if not stabRemote then
	warn("[TREKBayonet] BayonetStab never appeared. That remote is created at runtime by "
		.. "BayonetService -- so the ServerScriptService half is missing, or it errored "
		.. "before reaching that line. Bayonet disabled.")
	return
end

local player = Players.LocalPlayer

local ACTION_NAME = "TREKBayonetStab"
local KEY = Config.resolveKey()

--[[
	Per-life state.

	Everything here is rebuilt on respawn. This script lives in
	StarterPlayerScripts, so it survives death while every instance it points at
	does not -- holding an AnimationTrack from a previous character is how you
	get a pose that will not start again after you die once.
]]
local character: Model? = nil
local sprinting: BoolValue? = nil
local chargeTrack: AnimationTrack? = nil
local thrustTrack: AnimationTrack? = nil
local sprintConnection: RBXScriptConnection? = nil
local toolConnections: { RBXScriptConnection } = {}

-- Reset each life, so the "no bayonet" explanation is said once per spawn
-- rather than once per press or once per session.
local explainedIneligible = false

local lastStab = 0

local function loadTrack(animator: Animator, id: number | string): AnimationTrack?
	-- An unset or malformed id is not a fault: the bayonet still stabs, it just
	-- does it without a pose. Damage must never depend on an animation.
	local url = Config.animationUrl(id)
	if not url then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = url

	local track = animator:LoadAnimation(animation)

	-- Action outranks the gun's Idle and SprintHold, so TREK keeps playing its
	-- own animations underneath and ours simply wins while it is running.
	track.Priority = Enum.AnimationPriority.Action
	return track
end

-- Does the equipped weapon actually carry a bayonet?
--
-- Asked of the Tool rather than of a weapon whitelist, so fitting a bayonet to
-- another rifle is a modelling job rather than a config edit.
local function equippedBayonet(): boolean
	local chr = character
	if not chr then
		return false
	end

	local tool = chr:FindFirstChildOfClass("Tool")
	if not tool then
		return false
	end

	-- Recursive, to match the server. A loose Part under the Tool and a Model
	-- nested a few levels down are both valid ways to build a bayonet, and the
	-- two sides must agree or the client will offer a stab the server refuses.
	return tool:FindFirstChild(Config.BayonetPartName, true) ~= nil
end

local function refreshChargePose()
	local track = chargeTrack
	if not track then
		return
	end

	local shouldCharge = equippedBayonet()
		and sprinting ~= nil
		and (sprinting :: BoolValue).Value == true

	if shouldCharge then
		if not track.IsPlaying then
			track:Play()
		end
	elseif track.IsPlaying then
		track:Stop()
	end
end

local function onStabPressed(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	-- Not eligible, so do not swallow the key -- something else in the place may
	-- want it.
	if not equippedBayonet() then
		-- Said once per life, not every press, so it cannot spam the log. This
		-- is the single most likely reason a player reports "G does nothing",
		-- and without it the press is indistinguishable from the script not
		-- running at all.
		if not explainedIneligible then
			explainedIneligible = true
			local chr = character
			local tool = chr and chr:FindFirstChildOfClass("Tool")
			warn(string.format(
				"[TREKBayonet] %s pressed but %s -- nothing named %q inside the Tool "
					.. "(the search is recursive, so any depth counts)",
				KEY.Name,
				tool and ("the equipped " .. tool.Name .. " has no bayonet") or "no tool is equipped",
				Config.BayonetPartName
			))
		end
		return Enum.ContextActionResult.Pass
	end

	if Config.RequireSprint and not (sprinting and sprinting.Value) then
		return Enum.ContextActionResult.Pass
	end

	local now = os.clock()
	if now - lastStab < Config.Cooldown then
		return Enum.ContextActionResult.Sink
	end
	lastStab = now

	local track = thrustTrack
	if track then
		track:Play()
		task.delay(Config.ThrustLength, function()
			if track.IsPlaying then
				track:Stop()
			end
		end)
	end

	-- No arguments, and none are needed. The hitbox is the bayonet itself, which
	-- is welded to the character, so the server can see exactly where it is and
	-- sweeps it as the thrust plays.
	stabRemote:FireServer()

	-- Printed so the client half can be ruled in or out. If this appears and no
	-- server line follows, the press never arrived; if neither appears, the
	-- press never got past the checks above.
	if Config.Debug then
		warn(string.format("[TREKBayonet] sent a stab (thrust track %s)",
			thrustTrack and "loaded" or "MISSING -- check ThrustAnimation"))
	end

	return Enum.ContextActionResult.Sink
end

local function teardown()
	if sprintConnection then
		sprintConnection:Disconnect()
		sprintConnection = nil
	end

	for _, connection in ipairs(toolConnections) do
		connection:Disconnect()
	end
	table.clear(toolConnections)

	if chargeTrack then
		chargeTrack:Stop()
		chargeTrack:Destroy()
		chargeTrack = nil
	end

	if thrustTrack then
		thrustTrack:Stop()
		thrustTrack:Destroy()
		thrustTrack = nil
	end

	character = nil
	sprinting = nil
	explainedIneligible = false
end

local function onCharacter(chr: Model)
	teardown()
	character = chr

	local humanoid = chr:WaitForChild("Humanoid") :: Humanoid
	local animator = (humanoid:FindFirstChildOfClass("Animator")
		or humanoid:WaitForChild("Animator")) :: Animator

	chargeTrack = loadTrack(animator, Config.ChargeAnimation)
	thrustTrack = loadTrack(animator, Config.ThrustAnimation)

	-- TREK keeps its movement state on the character, not the player.
	local plrconfig = chr:WaitForChild("TREK_PlrConfig")
	sprinting = plrconfig:WaitForChild("Sprinting") :: BoolValue

	sprintConnection = (sprinting :: BoolValue):GetPropertyChangedSignal("Value"):Connect(refreshChargePose)

	-- Equipping and unequipping a tool re-parents it into and out of the
	-- character, so these two signals are also "the player changed weapon".
	table.insert(toolConnections, chr.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			refreshChargePose()
		end
	end))
	table.insert(toolConnections, chr.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			refreshChargePose()
		end
	end))

	table.insert(toolConnections, humanoid.Died:Connect(function()
		if chargeTrack and chargeTrack.IsPlaying then
			chargeTrack:Stop()
		end
	end))

	refreshChargePose()
end

ContextActionService:BindAction(ACTION_NAME, onStabPressed, false, KEY)

print(string.format("[TREKBayonet] controller ready -- press %s to stab", KEY.Name))

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
player.CharacterRemoving:Connect(teardown)

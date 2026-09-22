--!strict
--[[
	WEAPON POSE PRIORITY

	LocalScript. Rojo puts it in StarterPlayerScripts.

	Not bayonet-specific -- it fixes every TREK weapon in the place, including
	vanilla rifle mode. It lives here because this is where it was diagnosed.

	--------------------------------------------------------------------------
	THE BUG
	--------------------------------------------------------------------------

	Sprinting plays two animations at once: TREK's global body/legs Run, and the
	weapon's own upper-body SprintHold pose. Measured on a live character:

		WalkAnim    Core       1.00
		SprintHold  Movement   1.00
		Run         Movement   1.00

	Same priority, same weight. Roblox blends equal-priority tracks by weight,
	so the arms and torso end up averaged halfway between the two poses -- the
	weapon reads as dropped, or as having no animation at all.

	Idle is authored at Action, which is why standing still never showed this
	and only sprinting did.

	It is also why the two fire modes behaved differently. 2SprintHold points at
	the same asset as 2Idle, so it inherits Action and wins; SprintHold points
	at the Patrol asset, authored at Movement, and ties. That asymmetry was
	accidental, not designed.

	--------------------------------------------------------------------------
	THE FIX, AND WHY IT IS THIS ONE
	--------------------------------------------------------------------------

	AnimationTrack.Priority is writable at runtime, so a weapon pose can be
	raised above Run without republishing anyone's animation and without editing
	a single TREK script.

	The alternative -- re-playing the track so it becomes the most recent -- is
	what pressing V does by accident, and it is a race: it only holds until
	something plays Run again.

	Raising the priority states the actual invariant. A pose that belongs to a
	weapon should out-rank the global movement animation on the joints it
	keyframes, and Run keeps the legs because SprintHold does not keyframe them.

	--------------------------------------------------------------------------
	SCOPE
	--------------------------------------------------------------------------

	Only tracks whose Animation instance lives in a weapon's Animations folder,
	and only when they are BELOW Action. Raising something that was already
	going to win is pointless; raising something that was going to lose to Run
	is the whole point. Nothing is ever lowered.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Core 0, Idle 1, Movement 2, Action 3. Anything below Action can tie with or
-- lose to Run, which is itself Movement.
local TARGET = Enum.AnimationPriority.Action
local FLOOR = TARGET.Value

-- Set true to print every track it raises. Off by default: this runs for every
-- weapon, every equip, and the log is already dense with TREK asset warnings.
local DEBUG = false

--[[
	Is this track a weapon's own pose?

	The test is where the Animation instance lives, not its name. Names are not
	reliable here -- the mode prefix means a weapon can carry SprintHold and
	2SprintHold at once, and TREK weapons share animation ids between each
	other, so an id-based test would match the wrong weapon.

	GunConfigs holds one module per weapon, each with an Animations folder. That
	containment is the definition of "belongs to a weapon".
]]
local function isWeaponPose(track: AnimationTrack): boolean
	local anim = track.Animation
	if not anim then
		return false
	end

	local folder = anim.Parent
	if not folder or folder.Name ~= "Animations" then
		return false
	end

	local services = ReplicatedStorage:FindFirstChild("TREK_SERVICES")
	local configs = services and services:FindFirstChild("GunConfigs")
	if not configs then
		return false
	end

	return folder:IsDescendantOf(configs)
end

local raised: { [string]: boolean } = {}

local function consider(track: AnimationTrack)
	if track.Priority.Value >= FLOOR then
		return
	end
	if not isWeaponPose(track) then
		return
	end

	local was = track.Priority.Name
	track.Priority = TARGET

	if DEBUG and not raised[track.Name] then
		raised[track.Name] = true
		print(("[TREKPosePriority] %s raised %s -> %s"):format(
			track.Name, was, TARGET.Name))
	end
end

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 20) :: Humanoid?
	if not humanoid then
		return
	end

	-- Anything already running. loadAnimations fires on every equip, so on a
	-- respawn the tracks can predate this connection.
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		consider(track)
	end

	humanoid.AnimationPlayed:Connect(consider)
end

if player.Character then
	task.spawn(watch, player.Character)
end
player.CharacterAdded:Connect(watch)

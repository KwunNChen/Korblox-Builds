--!strict
--[[
	Plays the configured animation for a move, if there is one.

	An empty slot in ParkourConfig.Animations plays nothing at all -- the move
	still happens, the body still travels the arc, you just do not get a pose for
	it. That is the shipping state: the slots are empty until an animator fills
	them, and the package is playable meanwhile.

	Tracks are cached per Animator and loaded lazily, because LoadAnimation is
	not free and a player who never mantles should never pay for the mantle
	tracks.

	One failure mode worth knowing, because it produces no error: an animation
	the place cannot read still returns a track from LoadAnimation. Play() on it
	does nothing visible. So an id published under the wrong account looks
	exactly like an empty slot, and the only symptom is in Output as
	"Failed to load animation with sanitized ID".
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local package = ReplicatedStorage:WaitForChild("TREKParkour")
local Config = require(package:WaitForChild("ParkourConfig"))
local Shared = require(package:WaitForChild("ParkourShared"))

local ParkourPose = {}

local SLOTS = { "Vault", "MantleCatch", "MantlePull" }

-- Weak keys: when a character dies its Animator goes with it, and the cached
-- tracks should not keep it alive.
local cache: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

local function animatorFor(humanoid: Humanoid): Animator?
	return humanoid:FindFirstChildOfClass("Animator")
end

-- Bare numbers and full rbxassetid:// URLs both work, so that whoever fills the
-- config in can paste whichever form the publish dialog handed them.
local function normalise(id: string): string
	if id:match("^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

local function trackFor(humanoid: Humanoid, slot: string): AnimationTrack?
	local id = (Config.Animations :: { [string]: string })[slot]
	if not id or id == "" then
		return nil
	end

	local animator = animatorFor(humanoid)
	if not animator then
		return nil
	end

	local bySlot = cache[animator]
	if not bySlot then
		bySlot = {}
		cache[animator] = bySlot
	end

	if bySlot[slot] then
		return bySlot[slot]
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = normalise(id)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		Shared.warn("could not load the %s animation (%s) -- that slot stays silent.", slot, id)
		return nil
	end

	--[[
		Action2 sits above TREK's weapon, crouch and run tracks, which all load
		at default priority, and deliberately below Action4 -- which is what the
		place's tempclimb script uses. If that ever plays, it should win.
	]]
	track.Priority = Config.AnimationPriority
	track.Looped = false

	bySlot[slot] = track
	return track
end

--[[
	Build every track and wait for the assets, once per character.

	Without this, the first time you vault is the first time LoadAnimation is
	called, and a track whose asset has not downloaded yet has a Length of 0 and
	plays nothing. The symptom is a move that is posed every time except the
	first -- which reads as "the animation sometimes doesn't load", because that
	is exactly what is happening.

	Called off the critical path; PreloadAsync yields for as long as the network
	takes.
]]
function ParkourPose.prepare(humanoid: Humanoid)
	local pending: { Instance } = {}

	for _, slot in SLOTS do
		local track = trackFor(humanoid, slot)
		if track then
			table.insert(pending, track.Animation :: Instance)
		end
	end

	if #pending > 0 then
		pcall(ContentProvider.PreloadAsync, ContentProvider, pending)
	end
end

--[[
	`window` is how long this pose has to cover. If the animator's track is a
	different length from the move, the track is sped up or slowed down to fit.

	This is what stops a 0.6s pull-up ending halfway through a 1.1s climb and
	dropping the character back to idle while they are still being dragged up
	the wall -- an animation that is "too short" for its move.

	Turn MatchAnimationSpeed off if the animator's timing should win instead, and
	tune VaultDuration / MantleDuration to match their tracks by hand.
]]
function ParkourPose.play(humanoid: Humanoid, slot: string, window: number?)
	local track = trackFor(humanoid, slot)
	if not track then
		return
	end

	track:Play(Config.AnimationFade)

	-- Length is 0 until the asset has downloaded, and dividing by it would send
	-- the speed to infinity. prepare() is what normally makes this non-zero.
	local speed, wanted = 1, 1
	if Config.MatchAnimationSpeed and window and window > 0 and track.Length > 0 then
		wanted = track.Length / window

		--[[
			Clamped, because matching is a correction and not a conversion. An
			unclamped ratio turned a 12.5s climb loop into 25x speed in testing,
			which is not a fast animation, it is a strobe. Past the limit the
			track keeps its own pace and gets cut off instead.
		]]
		local limit = math.max(Config.MaxAnimationStretch, 1)
		speed = math.clamp(wanted, 1 / limit, limit)
		track:AdjustSpeed(speed)
	end

	--[[
		The number that explains why a borrowed animation looks wrong.

		Anything much above 1 is the track being rushed to fit its slice, and a
		cyclic animation -- a ladder climb, a run -- turns into flailing well
		before 2. Either lengthen the move, turn MatchAnimationSpeed off and let
		it be cut short instead, or accept that the animation is not built for
		the window it is in.
	]]
	Shared.log(
		"%s: track %.2fs into a %.2fs window -- playing at %.2f speed%s",
		slot,
		track.Length,
		window or 0,
		speed,
		-- Naming the ratio it wanted is what tells you the animation is the
		-- wrong length for the move, rather than the move being mistuned.
		if math.abs(speed - wanted) > 0.01
			then string.format(" (clamped from %.2f -- this track is the wrong length for this move)", wanted)
			else ""
	)
end

function ParkourPose.stop(humanoid: Humanoid, slot: string)
	local track = trackFor(humanoid, slot)
	if track then
		track:Stop(Config.AnimationFade)
	end
end

-- Used on teardown, where we do not know which slot was playing -- and after an
-- abort, may not be the one we started.
function ParkourPose.stopAll(humanoid: Humanoid)
	local animator = animatorFor(humanoid)
	local bySlot = animator and cache[animator]
	if not bySlot then
		return
	end

	for _, track in bySlot do
		if track.IsPlaying then
			track:Stop(Config.AnimationFade)
		end
	end
end

return ParkourPose

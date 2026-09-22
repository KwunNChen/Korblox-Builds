--!strict
--[[
	TREK PARKOUR -- the one file you should need to edit.

	Vaulting over low cover, and pulling yourself up onto ledges. This holds the
	shape of both moves: how far the character reaches, how high it will climb,
	how long it takes, and what it costs you while it happens.

	It does NOT hold anything about your weapons. This package never touches a
	weapon's config -- it only puts the thing away while you climb and hands it
	back afterwards.
]]

local ParkourConfig = {}

-- ============================================================
-- WHAT IS TURNED ON
-- ============================================================

-- Vault fires on its own when you sprint at low cover. Mantle always needs the
-- jump key. If vaulting feels grabby in playtest, turn it off here rather than
-- retuning the heights -- the heights are also what the mantle uses.
ParkourConfig.EnableVault = true
ParkourConfig.EnableMantle = true

-- Prints every refusal with its reason, and every completed move with its
-- measured distance. Leave it on while you are tuning the heights below; the
-- refusal reasons are the whole diagnostic.
ParkourConfig.DebugLog = true

-- ============================================================
-- THE RIGs
-- ============================================================

--[[
	TREK is R6, and these numbers assume it.

	3.0 is not arbitrary: an R6 root sits exactly 3 studs above the soles. Every
	height below is measured from the FEET, not from the root, so this is the
	term that converts between them.

	It is a config value rather than a constant only so an R15 install has
	something to change. If you do change it, every height below moves with it.
]]
ParkourConfig.RootToSoles = 3.0

-- ============================================================
-- WHAT COUNTS AS AN OBSTACLE
-- ============================================================

--[[
	Heights are measured from the player's feet to the TOP SURFACE of the thing
	in front of them. The bands are contiguous on purpose -- a gap between them
	is a height where the player gets no move and no explanation.

	  below StepHeight     ignored, the Humanoid already walks over it
	  StepHeight..VaultMax  VAULT   -- go over it without stopping
	  VaultMax..MantleMax   MANTLE  -- haul yourself up onto it
	  above MantleMax       refused

	The default VaultMax of 3.5 is roughly chest height on R6, which is the
	point past which going over something stops looking like vaulting.
]]
ParkourConfig.StepHeight = 1.0
ParkourConfig.VaultMaxHeight = 3.5
ParkourConfig.MantleMaxHeight = 7.0

--[[
	THE MANTLE IS NOT MEASURED THE SAME WAY, and this is the part that is easy
	to get wrong -- I got it wrong first time round.

	Everything above is measured from the soles, which is right for a vault: you
	are standing on the ground, and a crate is a fixed height in front of you.

	A mantle is a REACH. You are in mid-air when you ask for it, so your feet
	are wherever the jump has taken them -- measure from the soles near the top
	of a jump and a five-stud wall reads as a one-stud step. What actually
	matters is where the lip is relative to your HANDS, so these are measured
	from the root.

	  negative   the lip is below your chest -- you are hauling down onto it
	  positive   the lip is above your chest -- you are reaching up for it

	MantleMaxHeight above still applies as an absolute ceiling on how tall a
	thing may be before it is simply unclimbable.
]]
ParkourConfig.MantleGrabLow = -1.5
ParkourConfig.MantleGrabHigh = 2.5

-- How far in front of the root we look for a face to grab. Much beyond 3 and
-- you start catching walls you were only running past.
ParkourConfig.ProbeDistance = 3.0

--[[
	A surface only counts as a wall face if its normal is near-horizontal.
	0.3 allows a slight batter on the wall without letting a steep ramp read as
	a ledge -- a ramp you can already walk up, and mantling one looks wrong.
]]
ParkourConfig.MaxFaceTilt = 0.3

-- And the top has to be something you could stand on. Below this it is a slope,
-- and landing a pull-up on a slope slides you straight back off it.
ParkourConfig.MinTopFlatness = 0.7

-- How far back from the lip to start the downward cast that finds the top
-- surface. Too small and a rounded or bevelled lip is missed entirely.
ParkourConfig.TopProbeInset = 0.5

--[[
	Where the forward probe is fired from.

	The vault probe is measured up from the SOLES, because a crate is the same
	height whether you are crouched or standing. 1.6 is shin-to-knee on R6 --
	below the top of anything worth vaulting, above anything the Humanoid would
	have stepped over on its own.

	The mantle probe is measured from the ROOT, because a mantle is a reach: it
	is defined by where your hands are, and when you press jump in mid-air the
	root could be at any height. -0.3 is roughly chest.
]]
ParkourConfig.VaultProbeHeight = 1.6
ParkourConfig.MantleProbeHeight = -0.3

--[[
	How square-on you have to be hitting the surface, as a dot product against
	your direction of travel. At 0 you could vault a wall you were running
	parallel to; at 1 you would need to be perfectly perpendicular. 0.5 is about
	60 degrees off, which is forgiving without being silly.
]]
ParkourConfig.MinApproachDot = 0.5

-- How far past the lip you end up standing, measured horizontally from the wall
-- face. Under about a stud you finish balanced on the very edge.
ParkourConfig.LandInset = 1.2

-- How far back off the wall face the root sits at the hang, mid-mantle. Without
-- it the body is inside the wall for the first half of the climb. This is a
-- config key rather than a constant because ParkourRig draws a marker at this
-- exact point for the animator, and a number typed in two places drifts.
ParkourConfig.GrabPullback = 0.5

--[[
	The space the player has to fit into once they are up there, as a box
	centred on where they would be standing. Slightly under a real R6 hull
	(2 x 5 x 1) so a snug-but-legal spot is not refused over a stud of trim.
]]
ParkourConfig.ClearanceSize = Vector3.new(1.8, 4.6, 1.8)

-- ============================================================
-- HOW THE MOVES FEEL
-- ============================================================

-- Seconds. The vault is deliberately short enough that you barely lose tempo;
-- the mantle is deliberately long enough that you feel the cost of it.
ParkourConfig.VaultDuration = 0.45
ParkourConfig.MantleDuration = 1.1

--[[
	How high the arc bulges above a straight line between start and finish, as a
	fraction of the climb. 0 is a dead-straight slide up the wall, which reads
	as a glitch. 0.35 looks like someone throwing their weight.
]]
ParkourConfig.ArcHeight = 0.35

--[[
	The mantle is two beats, not one, and this is where it changes gear:

	  0 .. HangFraction   rise up the face to the lip. Hanging and hauling.
	  HangFraction .. 1   move forward onto the top. Swinging a leg over.

	A single arc from start to finish sends you diagonally through the corner of
	the wall, which clips. Splitting at the lip is what makes it read as a climb.

	The vault ignores this -- it is one continuous hop.
]]
ParkourConfig.HangFraction = 0.45

-- Seconds before you can do it again. This is also the rate limit the server
-- enforces, so lowering it lowers the floor on how often a move can be claimed.
ParkourConfig.Cooldown = 0.6

-- ============================================================
-- WHAT IT COSTS YOU
-- ============================================================

--[[
	The mantle takes your weapon away and gives it back when you land.

	This is not only for flavour. TREK's HeadAndArmsController rewrites
	HumanoidRootPart.CFrame every frame while a weapon is out, which would fight
	the climb. Unequipping is the supported way to stop it -- TREK's own gun
	handler calls HeadArmsModule:Stop() on unequip.

	So turning this off does not just remove the cost, it reintroduces the fight.
	If you want a cheaper mantle, shorten MantleDuration instead.
]]
ParkourConfig.MantleHolstersWeapon = true

-- Sprint is vetoed for the duration via TREK_PlrConfig.CanSprint, the same lever
-- TREK's own vehicle seats use. Restored on completion, on death, and by the
-- server's watchdog if the client never reports back.
ParkourConfig.MantleBlocksSprint = true

-- The vault keeps your weapon out and never rotates you, so you carry on aiming
-- wherever the mouse is pointing. There is no reason to turn this off; it is
-- here so the asymmetry with the mantle is visible rather than buried in code.
ParkourConfig.VaultHolstersWeapon = false

-- And it does not cost you your sprint either -- a vault you have to recover
-- from is not a vault. Spelled out for the same reason as the line above: the
-- asymmetry between the two moves should be visible here rather than inferred
-- from a branch in the service.
ParkourConfig.VaultBlocksSprint = false

--[[
	Landing a vault gives you a short burst of speed.

	This is the one place the package writes Humanoid.WalkSpeed, and it is worth
	knowing what that costs. TREK rewrites WalkSpeed on a 100ms poll and on every
	crouch toggle, so the boost has to re-assert every frame to survive -- and it
	stands down the moment you crouch, start sprinting or stop sprinting, because
	those writes are TREK's and holding a boost through them would be wrong.

	The multiplier applies to whatever your speed was when you landed, not to a
	fixed number, so another package slowing you (a Variable Snowstorm storm, for
	instance) still gets its say -- you get 1.3x of the slowed value, and the
	slowed value back when the boost ends.

	Set the multiplier to 1, or EnableVaultBoost to false, and nothing in this
	package touches WalkSpeed at all.
]]
ParkourConfig.EnableVaultBoost = true
ParkourConfig.VaultBoostMultiplier = 1.3
ParkourConfig.VaultBoostDuration = 1.2

-- ============================================================
-- INPUT
-- ============================================================

--[[
	The mantle is on the jump key, caught through UserInputService.JumpRequest.
	That one connection covers keyboard, gamepad and the mobile jump button, and
	it does not collide with any key TREK has already taken (F, C, R, Q, T, N, V,
	LeftShift, LeftControl).

	JumpRequest FIRES REPEATEDLY WHILE THE KEY IS HELD -- several times a second,
	not once per press. Without this debounce, holding space through a jump
	burns the attempt on the first frame you are airborne, long before you are
	anywhere near the ledge.
]]
ParkourConfig.JumpDebounce = 0.15

--[[
	How long you must have been off the ground for a jump press to count as a
	mantle rather than as the jump itself.

	The lower bound is 0 deliberately. It used to be 0.08 to "skip the press
	that started the jump", which was reasoning about a problem that does not
	exist: airborneSince is nil while you are on the ground, so that press
	returns early regardless. All the bound actually did was eat real attempts
	-- playtesting showed every single try landing at 0.02-0.06s and being
	thrown away, because FloorMaterial does not flip to Air until a few frames
	after the jump begins.

	The upper bound still earns its place. It stops a long fall ending in a
	mantle, which reads as catching a ledge you were never near.
]]
ParkourConfig.MantleWindowMin = 0
ParkourConfig.MantleWindowMax = 1.2

--[[
	How often the vault probe runs, in casts per second, while you are actually
	moving fast enough to vault. The mantle does not poll at all -- it casts once
	when you press jump, and nowhere else.

	Raising this does not make vaulting more responsive so much as more eager:
	the probe already reaches ahead of you, so 10 is a fifth of a stud of travel
	between casts at sprint speed.
]]
ParkourConfig.ProbeRate = 10

-- Vault will not fire below this horizontal speed. TREK walks at 16 and sprints
-- at 24, but approach speed into a wall is well under either, so this is not
-- simply "is sprinting" -- tune it by watching the debug log, not by arithmetic.
ParkourConfig.MinApproachSpeed = 12

-- ============================================================
-- ANTI-CHEAT
-- ============================================================

--[[
	The client owns its own character -- that is how Roblox works, and someone
	who wants to teleport can already teleport. These bounds exist so that this
	package is not a CONVENIENT way to do it, not because they stop a determined
	exploiter.

	A claim outside these bounds is logged and refused. Nobody is kicked. The
	only kick in TREK is its anti-hitbox-expansion check, and booting a player
	over a laggy vault would be a worse outcome than the vault.
]]
ParkourConfig.MaxReach = 11.0 -- studs, horizontal, start to finish

--[[
	THE CHECK THAT ACTUALLY CLOSES THE HOLE.

	How far the start position a client claims may be from where the server
	already believes that player is. Bounding the move's LENGTH on its own is
	not enough -- a client that lies about where it started gets a full-length
	move from anywhere on the map. Measuring the claimed start against a
	position the server got from Roblox's own replication is what makes the
	length bound mean anything.

	6 studs is slack for a moving player on a bad connection, and far less than
	the move itself is worth stealing.
]]
ParkourConfig.StartTolerance = 6.0

--[[
	How far a move may take you DOWNWARD before it is refused.

	No legal move descends at all -- the landing is always derived from a top
	surface above your feet. This is not symmetry for its own sake: without it,
	a claim was a bounded step out and an UNBOUNDED drop, which is a far more
	useful thing to an exploiter than the upward bound was guarding against.

	The small allowance is for a vault onto something fractionally below where
	you started, and for the crouch HipHeight term moving the reference.
]]
ParkourConfig.MaxDescent = 3.0

-- How far from the declared destination a finished move may end up before it is
-- logged. Explosions, moving platforms and server hitches all land here, which
-- is why it logs and refuses rather than teleporting anyone back.
ParkourConfig.ArrivalTolerance = 8.0

ParkourConfig.WatchdogGrace = 0.75 -- extra seconds before the server force-ends a move

-- ============================================================
-- ANIMATION
-- ============================================================

--[[
	PUT YOUR ANIMATION IDS HERE.

	An empty slot plays NOTHING. The move still happens and the body still
	travels the arc -- you simply do not get a pose for it. That is the shipping
	state, and it is deliberately playable so the heights and timings can be
	tuned before an animator is involved at all.

	Fill them in one at a time as they are delivered; each slot is independent.

	Bare numbers and full rbxassetid:// URLs both work.

	Two things that will waste your afternoon if you do not know them:

	  - Animations must be authored R6. An R6 sequence loaded onto an R15 rig
	    gives you zero tracks and an empty timeline, with no error.
	  - An animation this place cannot READ behaves exactly like an empty slot.
	    LoadAnimation still hands back a track and Play() on it does nothing
	    visible. The only symptom is "Failed to load animation with sanitized
	    ID" in Output. Publish under the account that owns the game.

	ServerStorage.TREKParkour.Tools.ParkourRig sets up a dummy with a test ledge
	at the right height to animate against.
]]
ParkourConfig.Animations = {
	Vault = "71876103670056",
	MantleCatch = "121815965338931",
	MantlePull = "",
}

--[[
	Above TREK's weapon, crouch and run tracks, which all load at default
	priority. Deliberately BELOW Action4, which is what the place's tempclimb
	script uses -- if that ever plays, it should win.
]]
ParkourConfig.AnimationPriority = Enum.AnimationPriority.Action2

-- Crossfade in and out, seconds.
ParkourConfig.AnimationFade = 0.1

--[[
	Hold the head at its rest pose for the whole move, ignoring whatever the
	animation does to the neck.

	Borrowed animations are usually the problem here. A ladder climb has the head
	craning up at the rungs, which on a mantle reads as the character staring at
	the sky while hauling themselves over a wall -- and the head is the first
	thing anyone looks at, so a bad neck track spoils an otherwise fine pose.

	This works by writing the Neck's Transform back to identity every frame,
	after the animator has had its turn. It cancels the neck track only; the
	torso, arms and legs are left exactly as animated.

	"Straight" here means neutral RELATIVE TO THE TORSO, so the head still leans
	with the body -- which is what you want. It is not world-locked.

	If you would rather fix it in the asset than at runtime, TREK Bayonet ships
	tools/StripLegTracks.luau, which downloads an animation, deletes named joint
	tracks from it and hands you a copy to republish. Put "Head" in its STRIP
	list and point SOURCE_ID at the animation.
]]
ParkourConfig.KeepHeadLevel = true

--[[
	Stretch or squash each track to exactly fill the move it belongs to.

	An animation is almost never the same length as the move that plays it, and
	the mismatch is ugly in both directions: a track shorter than its move ends
	early and drops you back to idle while the game is still hauling you up the
	wall, and one that is longer gets cut off mid-pose.

	With this on, the durations above are the truth and the animator's timing
	bends to fit. Turn it off if you would rather their timing won -- then
	VaultDuration and MantleDuration have to be set by hand to match the tracks,
	and they must be re-matched every time an animation is re-exported.

	The mantle splits its two tracks at HangFraction, so MantleCatch fills the
	rise and MantlePull fills the swing-over.
]]
ParkourConfig.MatchAnimationSpeed = true

--[[
	How far speed-matching is allowed to go before it gives up.

	Matching is a CORRECTION, not a conversion. Stretching a 0.9s track to fill
	a 1.1s move is invisible. Crushing a 12.5s ladder-climb loop into a 0.5s
	catch is 25x speed, which is not an animation any more, it is a strobe --
	and that is a real number this hit in playtesting.

	Beyond this ratio the track plays at its own pace and simply gets cut off
	when the move ends. A partial pose at a sane speed always reads better than
	a complete one at twenty-five.

	2.0 means "up to twice as fast or twice as slow". Raise it if your
	animations are close to the right length and you want exact fills; there is
	no good reason to go much past 3.
]]
ParkourConfig.MaxAnimationStretch = 2.0

return table.freeze(ParkourConfig)

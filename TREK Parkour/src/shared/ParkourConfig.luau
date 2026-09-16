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
ParkourConfig.DebugLog = false

-- ============================================================
-- THE RIG
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

-- How far in front of the root we look for a face to grab. Much beyond 3 and
-- you start catching walls you were only running past.
ParkourConfig.ProbeDistance = 3.0

--[[
	A surface only counts as a wall face if its normal is near-horizontal.
	0.3 allows a slight batter on the wall without letting a steep ramp read as
	a ledge -- a ramp you can already walk up, and mantling one looks wrong.
]]
ParkourConfig.MaxFaceTilt = 0.3

-- How far back from the lip to start the downward cast that finds the top
-- surface. Too small and a rounded or bevelled lip is missed entirely.
ParkourConfig.TopProbeInset = 0.5

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
	mantle rather than as the jump itself. The lower bound skips the press that
	started the jump; the upper bound stops a long fall from ending in a mantle,
	which would read as catching a ledge you were nowhere near.
]]
ParkourConfig.MantleWindowMin = 0.08
ParkourConfig.MantleWindowMax = 1.2

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
ParkourConfig.MaxReach = 9.0 -- studs, horizontal, start to finish

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

	Empty means "use the procedural pose", which is a rough stand-in built out of
	joint angles in code. It is playable and it is ugly. Fill these in one at a
	time as your animator delivers them -- each slot falls back independently.

	Bare numbers and full rbxassetid:// URLs both work.

	Two things that will waste your afternoon if you do not know them:

	  - Animations must be authored R6. An R6 sequence loaded onto an R15 rig
	    gives you zero tracks and an empty timeline, with no error.
	  - Procedural poses are client-local and do NOT replicate. Real animation
	    tracks go through the Animator and DO. Until these are filled in, other
	    players see you move but not pose.

	ServerStorage.TREKParkour.Tools.ParkourRig sets up a dummy with a test ledge
	at the right height to animate against.
]]
ParkourConfig.Animations = {
	Vault = "",
	MantleCatch = "", -- the grab, played as you reach the lip
	MantlePull = "", -- the haul up, played for the rest of the move
}

--[[
	Above TREK's weapon, crouch and run tracks, which all load at default
	priority. Deliberately BELOW Action4, which is what the place's tempclimb
	script uses -- if that ever plays, it should win.
]]
ParkourConfig.AnimationPriority = Enum.AnimationPriority.Action2

-- Crossfade in and out, seconds.
ParkourConfig.AnimationFade = 0.1

return table.freeze(ParkourConfig)

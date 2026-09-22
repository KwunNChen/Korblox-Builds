--!strict
-- Every tunable for the bayonet.
--
-- Damage, fire rate and animations are NOT here. They live in the weapon's own
-- config module, because the bayonet is a fire mode now rather than a separate
-- system bolted on beside one. This file only holds what belongs to hit
-- detection.

local Config = {}

--[[
	Where the bayonet's stats live inside the weapon module.

	2, and the number means the opposite of what it used to. TREK's switchModes
	walks fire modes by INCREMENT:

		if (currentMode == 1 and not config[currentMode + 1]) then return end

	The old build put the bayonet at [9] precisely so that walk would stop dead
	and V could never reach it -- it was a key-triggered attack that only
	borrowed the config block for its numbers. Now the bayonet IS a fire mode,
	so it has to sit where V lands: immediately after [1].
]]
Config.ConfigIndex = 2

--[[
	A weapon has a bayonet if its Tool contains something with this name.

	Detection is by instance rather than by a weapon whitelist on purpose:
	putting a bayonet on another rifle is then a modelling job, not a config
	edit.

	Only the NAME is checked, and the search is recursive. A loose Part under the
	Tool, a Model of several parts, nested or not, all count -- the class and the
	depth are yours to decide.

	This instance's position AND size are the hitbox. A longer blade genuinely
	reaches further and a wider one genuinely catches more, with no config to
	update -- the geometry is the weapon.
]]
Config.BayonetPartName = "Bayonet"

--[[
	Slack added around the blade before testing for overlap.

	Measured in the ATTACKER'S frame -- level, facing where they face -- not in
	the blade's own axes. The blade's axes roll with the thrust animation, which
	made "vertical" mean something different at every point in the swing. These
	three always mean what they say:

		SIDE      how far off-centre your aim can be
		VERTICAL  how much height difference is forgiven
		FORWARD   reach past the tip

	A bayonet needs a lot of this. The KR-61's blade is 0.19 x 0.53 x 1.94 studs
	-- a sliver -- and a character is a 5 stud pillar. Padding is not a fudge
	factor here; it is most of the hitbox.

	These values were picked against the real model rather than by feel. The
	blade centre sits 2.66 studs ahead of the torso and is 1.94 long, so FORWARD
	1.5 puts the reach at about 5.1 studs -- just past the tip. SIDE 1.25 lets
	someone 1.5 studs off-centre be hit but not someone 4 studs to your left.
	VERTICAL 2.5 covers a whole character from a stab aimed at the chest.

	Raise VERTICAL first if stabs feel like they should have landed.
]]
Config.HitPadSide = 1.25
Config.HitPadVertical = 2.5
Config.HitPadForward = 1.5

--[[
	How long after the swing the blade keeps being tested, in seconds.

	NOT a delay -- a sweep. The blade is sampled repeatedly across this window as
	the thrust animation drives it forward, and the first valid overlap wins. It
	is what makes the hit land when the blade actually arrives rather than at the
	instant the mouse went down.

	Should comfortably cover the extend portion of your thrust animation.
]]
Config.HitWindow = 0.35

-- Seconds between samples inside that window. Small enough that a fast blade
-- cannot pass through a torso between two tests, which is the tunnelling that
-- makes Touched unreliable for melee.
Config.HitSampleInterval = 0.03

--[[
	No Cooldown here.

	The swing rate is RoundsPerMinute in the weapon's [2] block, because the gun
	handler is what paces the attack -- handleFireRate waits 60/RoundsPerMinute
	after every swing. The server derives its own rate limit from that same
	number, so there is one figure to change and no second one to keep in sync
	with it.

	This is the slack on that derived limit. Both sides measure the same interval
	from their own clock, so without a little give, network jitter alone would
	have the server reject swings the player made in good time.
]]
Config.ServerCooldownTolerance = 0.9

--[[
	How long to wait before calling an unresolved swing a miss, in seconds.

	A hit is knowable the instant the blade connects and is announced then. A
	miss is only PROVABLE once the whole sweep has run -- but waiting the full
	HitWindow to say so puts the announcement well after the swing it belongs
	to, so anything still unresolved at this point is called a miss.

	At or above HitWindow this is a no-op: the sweep always finishes first.
	Below one HitSampleInterval only point-blank contacts can beat it, and the
	service warns about that at startup rather than letting it look like a
	broken hitbox.
]]
Config.MissAnnounceAfter = 0.2

--[[
	Keep sprinting through the swing.

	shoot() cancels sprint before it reaches any bullet type:

		if controls.sprinting.Value then plrconfig.SprintEnabled.Value = false end

	That is right for a rifle and wrong for a bayonet charge, so our bullet type
	sets the flag back immediately afterwards. It runs inside shoot(), after that
	line, which is why this needs no edit to the gun handler.

	Set false to make the bayonet behave like every other fire mode and plant you
	when you attack.
]]
Config.RestoreSprint = true

--[[
	Print what the server decided on every swing. Off unless you are debugging.

	Turn it on when a swing is not landing. Every swing then reports itself, and
	the three outcomes are told apart on purpose:

		REFUSED   the swing never got as far as detection, and why
		MISS      it swept, and how many studs outside the box the nearest
		          person was -- so the padding above becomes arithmetic
		hit       what was hit, in which limb, on which sample

	A miss also reports how far the blade travelled during the sweep. A stud or
	more means the server watched a real thrust and the box was short; close to
	zero means the server never saw the animation, which padding cannot fix.
]]
Config.Debug = false

return Config

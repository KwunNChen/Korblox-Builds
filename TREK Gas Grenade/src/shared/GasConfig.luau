--[[
	GasConfig
	Every knob for the gas grenade, in one frozen table.

	Two audiences read this file. The gameplay systems in this package read all
	of it. TREK's core reads only what the shim in GunConfigs re-exports --
	ToolType, and a mode table carrying MagCapacity -- because that is the whole
	of what `checkForGun` and `createAmmoStore` look at.

	The numbers below are tuned for a gas grenade that punishes standing still
	rather than one that kills outright. A full duration in the cloud is lethal;
	walking through it is not.
]]

local GasConfig = {}

-- =========================================================================
-- TOOL
-- =========================================================================

--[[
	The Tool's name in the backpack, and the name of the shim module inside
	GunConfigs. These MUST match.

	TREK resolves a tool's config by `tool.Name` in several places, and at least
	one of them -- the Explosion remote handler in TREKServerGeneral -- ignores
	the TConfigToUse attribute entirely. Naming the module after the tool is the
	only arrangement where every lookup path agrees. Do not set TConfigToUse on
	this tool.
]]
GasConfig.ToolName = "Gas Grenade"

--[[
	Which handler TREK clones into the tool. `checkForGun` looks for a child of
	ServerStorage.TREKToolHandlers with this exact name. The package installs
	`Throwable` there; vanilla TREK only ships `Gun`.
]]
GasConfig.ToolType = "Throwable"

--[[
	Which model is used for which state.

	GasGrenades.rbxm ships two, and they started out split by purpose: the
	inactive one in your hand, the active one flying and venting. Both point at
	the inactive model now, so the grenade looks the same in the hand as it does
	in the air.

	Named rather than hardcoded because this is a look decision, not a structural
	one. Point Thrown back at "ActiveGasGrenade" and the split behaviour returns
	with no code change.

	Only the NAMES differ -- the rigs do not. The held copy is welded massless
	and non-collidable so it does not shove you around; the thrown copy gets a
	collidable root so it can bounce. Both are rebuilt at runtime from whatever
	the model contains, so the same model works as either.
]]
GasConfig.Models = {
	Held = "InactiveGasGrenade",
	Thrown = "InactiveGasGrenade",
}

-- How many grenades you carry. Becomes the Ammo value in the TAmmo store TREK
-- builds.
GasConfig.MagCapacity = 1

--[[
	Grenades held in reserve, drawn on reload. 0 means what you spawn with is all
	you get, which is the point of a one-shot grenade: there is nothing to reload
	from, so the reload key does nothing and it never comes back.

	Named ReservedAmmo, not StoredAmmo, because that is the field name TREK's
	createAmmoStore actually reads. Get it wrong and the store is built with
	`MaxValue = nil`, which throws inside checkForGun while the character is
	still being assembled.
]]
GasConfig.ReservedAmmo = 0

--[[
	Whether the tool disappears once you are out.

	True is what makes "throw it and you have no grenade" actually read that way.
	Without it the Tool stays in the hotbar at zero ammo: you can still select
	it, you still see a grenade in your hand, and pressing fire does nothing --
	which looks broken rather than empty.

	It also settles a smaller oddity. The grenade you throw is a separate model
	from the one in your hand, so for as long as the tool survives the throw you
	are holding a grenade while watching one fly. At a capacity of one there
	should never be two.
]]
GasConfig.DestroyWhenEmpty = true

--[[
	Seconds to leave the spent tool alone before removing it.

	Destroying a Tool fires Unequipped, and a slot vanishing out of the hotbar
	mid-swing is jarring even when the animation survives it. The grenade itself
	is taken out of your hand immediately -- it is in the air, so an empty hand is
	the truthful thing to show -- and only the Tool lingers, long enough for the
	throw to finish reading as a throw.

	Nothing can be done with the tool during this window: the ammo is already
	zero, so cooking is refused.
]]
GasConfig.DestroyDelay = 0.4

-- =========================================================================
-- THROW
-- =========================================================================

--[[
	Cooking.

	The fuse starts when you press, not when you release. That is the whole point
	of cooking -- you spend fuse time to deny the enemy time to walk away from
	where it lands. It also means a careless hold kills you, which is intended.
]]

-- Seconds from press to detonation. Also the fuse when thrown instantly.
GasConfig.FuseTime = 3.5

--[[
	Whether holding past FuseTime detonates in your hand.

	True is the honest reading of a cooked fuse and the reason cooking is a
	decision rather than a free upgrade. Set false and an over-cooked grenade is
	simply thrown at the last moment instead.
]]
GasConfig.CookKillsYou = true

--[[
	Throw velocity, in studs/second.

	Range and height both scale off this, so it is the knob to reach for when the
	throw feels short rather than flat. With ThrowAngle at 38, 105 gives roughly
	55 studs of range and a 10-stud apex -- a lob you can put over a wall.
]]
GasConfig.ThrowPower = 105

--[[
	Cooking does not weaken the throw, but it does shorten how long the grenade
	is in the air before it goes off. These stay separate so you can tune "how
	far can I get it" without touching "how long do they have to run".
]]

--[[
	Degrees of loft above wherever you are aiming.

	This is the arc, not the range. Below about 20 the grenade skids in almost
	flat and you cannot clear anything with it; at 45 you get maximum range for a
	given power but a very floaty, slow lob. 38 is a proper overarm toss -- high
	enough to drop behind a wall, quick enough that the enemy does not watch it
	travel.

	Added to your aim, so looking upward lofts further still and looking down
	lets you place one at your feet.
]]
GasConfig.ThrowAngle = 38

-- Extra spin on release. Purely cosmetic, but a grenade that leaves the hand
-- without tumbling reads as a thrown brick.
GasConfig.ThrowSpin = 18

-- Seconds after a throw before the next one can start cooking.
GasConfig.ThrowCooldown = 0.6

--[[
	The throw animation.

	Created from this id in code rather than shipped as an Animation instance in
	an Animations folder on the config module, which is how TREK weapons do it.
	Same reasoning as the gas particles: one id in one file beats an instance you
	have to open Studio to inspect. The cost is that TREK Bayonet's
	WeaponPosePriority will not see it -- that script only raises tracks whose
	Animation instance lives in a weapon's Animations folder -- so the priority
	is set explicitly below instead.

	Priority matters more than it looks. TREK's global Run and WalkAnim sit at
	Movement, and Roblox blends equal-priority tracks by weight, so a throw
	authored at Movement gets averaged halfway into your run cycle and reads as
	a twitch. Action is what WeaponPosePriority raises weapon poses to, so the
	throw sits level with them rather than fighting.

	The animation must be owned by the place owner or its group, or it will
	refuse to load at runtime.
]]
GasConfig.Animation = {
	Throw = "rbxassetid://98119005875692",

	Priority = Enum.AnimationPriority.Action,

	--[[
		Playback rate. 1 is as authored, 2 is twice as fast.

		A throw is a sharp motion and most authored throws are slower than they
		feel like they should be, because the wind-up has to be readable at 1x in
		the animation editor and does not have to be readable in a firefight.
	]]
	Speed = 1.6,

	--[[
		When the grenade leaves the hand, measured in the animation's own time at
		Speed = 1.

		A throw has a wind-up. Spawning the grenade on the same frame the
		animation starts makes it leave before the arm has moved, which reads as
		it teleporting out of you. Tune this to the frame where the hand opens,
		as you see it in the animation editor.

		Divided by Speed at runtime, so it tracks the same FRAME rather than the
		same number of seconds. Change Speed and the release stays where you put
		it; leave them independent and every speed change silently desyncs the
		throw from the hand opening.

		Client-side pacing only -- the server's fuse has been burning since you
		pressed, so this costs fuse time exactly like any other hesitation. Set
		to 0 to throw the instant you release.
	]]
	ReleaseDelay = 0.25,

	-- Blend time in and out. Short, because a throw should feel sharp.
	FadeTime = 0.1,
}

--[[
	Where the grenade sits in the right hand.

	The grenade is joined to the hand by its own Motor6D, NOT by TREK's toolAnim.
	TREK joins tools to the torso and relies on each weapon's animations to
	keyframe the AnimPart track and carry the weapon into the hands. That works
	for a rifle with a full animation set; the grenade has no idle pose, so the
	same arrangement parks it at a fixed point beside the chest -- attached and
	moving with the body, but never following the arm, which reads as floating in
	mid air.

	Joining to the hand instead means it swings with every walk cycle and gets
	carried by the throw animation for free.

	This is C0 on that joint, so it is measured from the hand part's centre.
	R6 has no separate hand -- "Right Arm" is the whole limb, 1x2x1, so the grip
	is a stud down from its middle. R15 has a small dedicated RightHand and
	barely needs any offset at all.

	Positive X is away from the body, negative Y is toward the fingers, negative
	Z is forward.

	Six named numbers rather than a CFrame expression, because these are meant to
	be tried rather than derived -- and because tools/GripTuner prints its result
	in exactly this shape, so what it gives you is what you paste.

	    X, Y, Z            studs. Negative Y is toward the fingers.
	    Pitch, Yaw, Roll   degrees, applied in that order

	Yaw is the axis running along the limb on both rigs, so it spins the grenade
	in the palm. Pitch and Roll tip it out of the hand.

	Rotation is applied AFTER the translation, so the grenade spins about its own
	position in the fist rather than being swung around the wrist on an arm's
	length of radius.
]]
GasConfig.GripOffset = {
	-- Studs from the hand's centre, then degrees.
	R6 = { X = 0, Y = -1, Z = 0, Pitch = 180, Yaw = 90, Roll = 90 },
	R15 = { X = 0, Y = -0.3, Z = 0, Pitch = 90, Yaw = 90, Roll = 90 },
}

--[[
	How bouncy the grenade is, 0 to 1, and how much speed it keeps when it
	scrapes along a surface.

	Low elasticity is deliberate. A gas grenade that pinballs off a wall and ends
	up back at your feet is funny exactly once.
]]
GasConfig.BounceElasticity = 0.25
GasConfig.BounceFriction = 0.7

-- =========================================================================
-- CLOUD
-- =========================================================================

-- Studs from the grenade that count as inside the gas.
GasConfig.CloudRadius = 18

-- Seconds the cloud keeps damaging after it starts venting.
GasConfig.CloudDuration = 14

-- Seconds between damage applications.
GasConfig.TickInterval = 0.4

--[[
	Damage per tick, at the centre.

	At the defaults that is 2.5 ticks/second and 35 damage/second in the thick of
	it -- roughly three seconds to kill a full-health player who refuses to move,
	and survivable for anyone who reacts.
]]
GasConfig.DamagePerTick = 14

--[[
	Falloff.

	Full damage within FullDamageRadius, tapering linearly to zero at
	CloudRadius. Unlike a blast, the taper is gentle on purpose: the edge of a
	gas cloud should still be unpleasant enough to push people out of it rather
	than letting them camp the rim.
]]
GasConfig.FullDamageRadius = 8

--[[
	Seconds for the gas to reach full strength after the fuse blows.

	Damage scales with the same curve as the visual density, so the cloud is not
	instantly lethal the moment it pops. This is the window in which a fast
	player can still get out of a well-placed throw.
]]
--[[
	How far past the cloud's edge to look for people, in studs.

	The overlap query only returns who is inside at this instant, so anyone who
	was outside at both samples but crossed the middle between them is never
	handed to the swept test at all. This is the margin that catches them, and
	it wants to be at least as far as a sprinting player travels in one
	TickInterval.

	At the current 0.4s tick, 24 studs covers 60 studs/second -- comfortably
	above anything on foot, and enough for most vehicles. Raise it if people
	start driving through clouds unharmed; the only cost is a wider overlap
	query, which is cheap next to the raycast that follows it.
]]
GasConfig.SweepMargin = 24

GasConfig.BuildUpTime = 1.2

--[[
	Whether a wall protects you.

	True raycasts from the cloud centre to each target and skips anyone whose
	line is blocked. Gas realistically seeps, but "realistically" here means
	players die behind cover with no feedback about why, so the check stays on.
]]
GasConfig.RequireLineOfSight = true

--[[
	Whether the thrower and their own team are affected.

	True. A gas cloud that politely ignores the person who threw it removes every
	interesting decision about where to put it.
]]
GasConfig.AffectsEveryone = true

--[[
	Whether someone in a vehicle seat is immune.

	TREK's own explosion code already skips characters sitting in a VehicleSeat,
	so matching that here keeps the two consistent -- being buttoned up in a
	vehicle protects you from gas the same way it protects you from a shell.
]]
GasConfig.VehicleSeatProtects = true

--[[
	Name of the BoolValue parented to an affected Humanoid while it stands in
	gas.

	TREK marks conditions this way already -- TBleedCondition, TParalCondition --
	so anything else in the game that wants to react to "this player is being
	gassed" has somewhere to look.
]]
GasConfig.ConditionName = "TGasCondition"

-- =========================================================================
-- VISUALS
-- =========================================================================

--[[
	The gas is built from ParticleEmitters in code rather than cloned from a
	pre-authored instance.

	This is a deliberate break from TREK convention -- every vanilla effect
	clones a `Particle` model staged inside its module -- and it buys one thing:
	the entire look is tunable from this file with no Studio round-trip.
]]

GasConfig.Visual = {
	-- Core colour of the gas.
	Colour = Color3.fromRGB(238, 242, 240),

	--[[
		How much the gas lights itself, 0 to 1.

		Pushed up from the 0.25 this used to hardcode, because a saturated orange
		rendered unlit goes muddy brown the moment the cloud is in shadow -- and
		the inside of a building is exactly where a gas cloud matters most. This
		keeps it reading as the same colour indoors as in the open.

		Past about 0.6 it stops looking like gas and starts looking like fire.
	]]
	Glow = 0.08,

	--[[
		The throw arc, which is client-side UI and deliberately NOT the gas
		colour.

		It used to inherit Colour, which was fine while the gas was green. With
		orange gas the arc would be orange and its cook warning reddens toward
		red -- two similar warm colours where the whole job of the warning is to
		be unmistakable. A cool arc also stops the preview reading as gas that is
		somehow already in the air.
	]]
	ArcColour = Color3.fromRGB(180, 220, 255),
	ArcWarnColour = Color3.fromRGB(255, 70, 40),

	-- Particles per second at full density, across all emitters.
	Rate = 34,

	-- How long a single puff survives, in seconds. Longer reads as heavier gas.
	ParticleLifetime = NumberRange.new(3.5, 6),

	-- Puff size at birth and at death. Gas expands as it disperses.
	SizeStart = 9,
	SizeEnd = 22,

	-- How fast puffs drift outward from the centre.
	Speed = NumberRange.new(1.5, 4),

	-- Upward drift. Gas is heavier than air, so this is deliberately small.
	Rise = 0.6,

	-- Peak opacity of a single puff. Kept low because dozens overlap.
	Opacity = 0.34,

	-- How many emitters ring the centre. More gives a fuller, less pulsing
	-- cloud at a linear cost.
	EmitterCount = 5,

	-- Seconds the visual keeps drifting after damage stops, so the cloud thins
	-- out instead of vanishing mid-frame.
	LingerAfterExpiry = 3,
}

--[[
	The hiss the cloud makes while it is venting.

	Created on the server and parented to the cloud's anchor part, which is what
	makes it positional -- a Sound inside a BasePart is heard from that part's
	position, so players can hear roughly where the gas is without seeing it.
	That matters more than it sounds: gas is the one weapon in the game that
	hurts you from outside your field of view.

	Volume tracks the same build-up curve as the particles and the damage, so
	what you hear, what you see and what hurts you all agree.
]]
GasConfig.Sound = {
	Hiss = "rbxassetid://71965695347680",

	-- Peak volume, at full density.
	Volume = 0.6,

	--[[
		Distance band, in studs.

		Audible well outside CloudRadius on purpose -- the point is to warn
		people who are near the gas, not only the ones already choking in it.
	]]
	RollOffMin = 12,
	RollOffMax = 110,

	-- Looped, because the clip is far shorter than a cloud lasts. Turn off only
	-- if you swap in a one-shot burst.
	Looped = true,

	-- Seconds to fade the hiss out once the gas stops damaging, so it thins with
	-- the particles rather than cutting off.
	FadeOut = 1.5,
}

-- =========================================================================
-- NERVE AGENT
-- =========================================================================

--[[
	What the gas actually is.

	Not an irritant that hurts while you stand in it -- a nerve agent. One
	lungful is fatal, and nothing after that first breath changes the outcome:
	not leaving the cloud, not the cloud expiring, not a medic. The cloud is
	where you were standing when you were killed, not the thing that killed you.

	Enabled = false falls back to the old behaviour, where the cloud ticks damage
	by distance and walking out saves you. The two are mutually exclusive: with
	this on, the cloud stops dealing damage directly and only reports contact.
]]
GasConfig.Nerve = {
	Enabled = true,

	--[[
		Seconds of contact before the dose lands.

		Zero is not used -- the cloud only reports on its own tick, so anything
		at or below TickInterval means "one tick inside is enough", which is the
		intent. Written as a real number rather than 0 so it stays legible as a
		threshold rather than a special case.
	]]
	DoseThreshold = 0.01,

	--[[
		The thrower's grace, in seconds of contact.

		Not mercy so much as playability: a throw that bounced off a doorframe
		should be survivable if you turn and run immediately, because otherwise
		the weapon is exactly as dangerous to carry as it is to face and nobody
		takes one. Long enough to get clear, nowhere near long enough to fight in
		your own cloud.

		Applies only to the player who threw it. Their team gets nothing.
	]]
	ThrowerGrace = 1.4,

	-- Seconds from dose to death.
	TimeToDeath = 12,

	-- How often health is taken and the body convulses.
	TickInterval = 0.25,

	--[[
		Seconds between the dose and the body going limp.

		Short, because the seizure IS the tell. Long enough that the victim sees
		it coming; too long and a dosed player keeps fighting as though nothing
		happened, which undoes the whole weapon.
	]]
	SeizeDelay = 0.35,

	--[[
		How hard the body convulses, in angular velocity added per tick.

		Applied as spin rather than force: a limp limb on a ball socket answers
		to spin immediately and settles on its own, where a force fights the
		constraint and either does nothing visible or throws the body across the
		room.
	]]
	TwitchStrength = 14,

	--[[
		The shove the body takes at the instant it goes limp, in studs/second.

		Separate from TwitchStrength because it does a different job. The twitch
		is a repeating flutter on an already-fallen body; this is the single
		convulsion that PUTS them down, and it wants to be violent enough to be
		unmistakable from across the map. A body that simply sags could be
		someone crouching. A body that is thrown off its feet could not.

		Applied to the root assembly, which the constraints then drag the limbs
		along with. Driving each limb separately looks like it would be more
		violent and instead makes the solver push the body through the floor --
		see the note on shove() in GasNerve.

		For scale: the place's own RagdollDeath pushes a normal death fall at 22.
		This should be comfortably above that, because a nerve agent taking
		someone off their feet is not a normal death fall.

		Direction is random in the horizontal and lifted by CollapseLift, so no
		two deaths fall the same way.
	]]
	CollapseImpulse = 70,

	--[[
		How much of that shove goes upward, as a fraction of the whole.

		At 0 the body skids along the floor; at 1 it goes straight up and lands
		roughly where it stood. Around 0.4 gets a body off its feet and down
		again a short distance away, which is the shape of a real collapse.
	]]
	CollapseLift = 0.4,

	--[[
		Angular kick on the root at the same instant, in radians/second.

		Without it the body launches perfectly rigid, like a mannequin on a
		wire, because linear velocity alone does not tumble anything.

		Not comparable to TwitchStrength even though both are angular: this
		drives one assembly and the twitch drives six. SkiRagdoll tumbles a
		wipeout at 9 and RagdollDeath topples a corpse at 9, so this sits a
		little above both rather than at the 30 it started at -- which was a
		limb-by-limb figure that made no sense once the shove moved to the root.
	]]
	CollapseSpin = 12,

	--[[
		What the victim makes from the dose until they stop.

		Looped, parented to the Head so it travels with the body and everyone
		nearby hears it positionally. It starts the instant contact is
		registered -- before the seizure, not with it -- because the sound is
		the first warning anyone gets that the person beside them is already
		dead and has not noticed yet.
	]]
	Sound = {
		Id = "rbxassetid://82687386744947",
		Volume = 1,

		-- Audible across a room but not across the map. A dying man is a local
		-- event; hearing one from 200 studs away would make every gas death
		-- sound like it was happening next to you.
		RollOffMin = 6,
		RollOffMax = 90,

		--[[
			Seconds to fade out once they die.

			Cut dead on the last frame it sounds like a bug -- the loop simply
			stops mid-breath. A short fade reads as the body going quiet.
		]]
		FadeOut = 0.6,
	},

	--[[
		The attribute that tells other systems to stop making this character's
		ordinary pain noises.

		Set on the CHARACTER, not the Humanoid, matching the SuppressRagdoll
		convention the place already uses. A generic name rather than a nerve
		one so anything else that needs the same silence -- drowning, burning --
		can reuse it without depending on the gas.

		This is needed because the drain takes health in TickInterval steps,
		every one of which is a health change large enough to trigger a hurt
		bark. Left alone, a twelve-second death is forty-eight "ow"s over the
		top of the sound above.
	]]
	SuppressHurtAttribute = "SuppressHurtVoice",

	-- Seconds after the seizure before the bleeding starts. A beat, so the two
	-- read as separate stages rather than one mess.
	BloodDelay = 1.2,

	BloodColour = Color3.fromRGB(120, 8, 8),
	BloodRate = 26,
	BloodSize = 0.5,

	--[[
		Set on the Humanoid the moment someone is doomed, following TREK's own
		TBleedCondition / TParalCondition convention.

		This is the hook a gas mask would read later -- and the honest place for
		anything else to find out that a player is already dead and simply has
		not finished falling over.
	]]
	ConditionAttribute = "TNerveCondition",
}

-- =========================================================================
-- DISORIENTATION
-- =========================================================================

--[[
	What being gassed does to your senses.

	Perceptual only -- blurred, tinted vision and muffled hearing with a ring.
	Nothing here touches WalkSpeed, aim or controls, so a player caught in gas
	can still fight their way out; they just cannot see or hear well while doing
	it. The damage is what kills, this is what makes it frightening.

	Driven entirely off a single number, GasExposure, which the server writes to
	the victim's Humanoid as an attribute. The server owns it because the server
	is the only thing that knows who is standing in gas; the client reads its own
	value and renders it. A client that spoofed the attribute would only be able
	to blind itself.

	Follows the damage in who it affects: everyone in the cloud, thrower
	included, matching AffectsEveryone.
]]
GasConfig.Disorient = {
	Enabled = true,

	--[[
		Seconds of continuous exposure to reach full effect, and seconds to clear
		once you are out.

		Build shorter than fade on purpose: gas takes hold faster than it lets
		go, so running out of the cloud is the right move but not an instant
		reset. Stagger out and you are still blind for a moment.
	]]
	BuildTime = 2,
	FadeTime = 3,

	--[[
		The attribute the server writes and the client reads. Named rather than
		hardcoded so anything else in the game -- a HUD, a medic system, a
		spectator overlay -- can watch the same value.
	]]
	AttributeName = "GasExposure",

	-- Peak BlurEffect size. At 36 you cannot pick a man out at range, but the
	-- shape of the world is still readable at arm's length.
	MaxBlur = 36,

	--[[
		The colour vision washes toward, and how far at full exposure.

		MaxTint is how far along white -> TintColour the frame travels, and it is
		scaled by exposure on top of that, so the orange arrives and leaves with
		everything else.

		That scaling is the whole point. TintColor MULTIPLIES the frame, so
		assigning the gas colour directly -- at any exposure at all -- slams the
		whole screen to full orange and holds it there for the entire fade while
		the blur politely decays around it. Lerping from white is what makes it
		decay rather than merely switch off at the end.
	]]
	TintColour = Color3.fromRGB(226, 232, 235),
	MaxTint = 0.75,

	-- Negative drains colour. Combined with the tint this gives the flat,
	-- bleached look of stinging eyes rather than a coloured filter.
	MaxSaturation = -0.7,

	--[[
		Darkening and contrast at full exposure.

		Both push the effect from "the screen has gone orange" toward "I cannot
		see properly". Brightness goes NEGATIVE -- gas closing your eyes darkens
		the world; brightening it reads as a flashbang instead.
	]]
	MaxBrightness = -0.12,
	MaxContrast = 0.3,

	--[[
		Ear ringing. Empty means use TREK's own staged Tinnitus sound, which is
		what its explosions already ring with -- so gas and blasts sound like the
		same game. Set an id here to override.
	]]
	Ring = "",
	RingVolume = 1.9,

	--[[
		How hard the world is muffled, in decibels of high and mid gain.

		Applied through an EqualizerSoundEffect on SoundService.Muffle, which is
		the same SoundGroup TREK's own concussion muffle uses. If a place has no
		Muffle group the muffle is skipped and everything else still works --
		checked rather than assumed, because TREK guards it the same way.
	]]
	MuffleGain = -46,

	--[[
		How fast the client chases the server's value, in units per second.

		The server only writes on each cloud tick, so the raw number arrives in
		steps. Without smoothing the blur visibly jumps every TickInterval.
	]]
	SmoothSpeed = 5,
}

-- =========================================================================

--[[
	Frozen depth-first, because table.freeze is shallow.

	Freezing only the outer table would leave GasConfig.Visual writable, and a
	config that is immutable everywhere except one nested table is worse than one
	that is mutable everywhere -- it invites exactly the stray write it looks like
	it is preventing.
]]
table.freeze(GasConfig.Visual)
table.freeze(GasConfig.Models)
table.freeze(GasConfig.Nerve.Sound)
table.freeze(GasConfig.Nerve)
table.freeze(GasConfig.Sound)
table.freeze(GasConfig.Disorient)
-- One level deeper than the rest: GripOffset now holds a table per rig type, and
-- freezing only the outer one would leave those writable.
table.freeze(GasConfig.GripOffset.R6)
table.freeze(GasConfig.GripOffset.R15)
table.freeze(GasConfig.GripOffset)
table.freeze(GasConfig.Animation)

return table.freeze(GasConfig)

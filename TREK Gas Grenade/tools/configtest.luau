--[[
	Headless checks on GasConfig and the pure geometry.

		lune run tools/configtest.luau

	None of these are style preferences. Each is a value that would otherwise be
	found by a player: a full-damage radius larger than the cloud, so falloff
	divides by a negative span and the gas gets *stronger* toward the edge; a
	tick interval of zero, so the cloud loop spins the scheduler instead of
	ticking; a build-up longer than the duration, so the gas expires before it
	ever reaches full strength and nothing ever dies in it.

	The last block is the one worth keeping. It reads every Config.X and
	config.X the source touches and checks the key actually exists. Delete a key
	from GasConfig and nothing complains until someone throws a grenade.

	Nothing here touches Roblox. Just enough is stubbed for GasConfig to load,
	which is why only the pure parts are testable -- anything that raycasts or
	spawns an Instance belongs in Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

-- ============================================================
-- HARNESS
-- ============================================================

local passed, failed = 0, 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		print("pass  " .. name)
	else
		failed += 1
		print("FAIL  " .. name .. (if detail then "  -- " .. detail else ""))
	end
end

-- ============================================================
-- JUST ENOUGH ROBLOX
-- ============================================================

local function Color3_fromRGB(r: number, g: number, b: number)
	return { R = r / 255, G = g / 255, B = b / 255, __kind = "Color3" }
end

local env = {
	Color3 = {
		fromRGB = Color3_fromRGB,
		new = function(r, g, b)
			return { R = r, G = g, B = b, __kind = "Color3" }
		end,
	},
	NumberRange = {
		new = function(min, max)
			return { Min = min, Max = max or min, __kind = "NumberRange" }
		end,
	},
	--[[
		CFrames need a __mul, because the grip offsets compose a translation with
		a rotation. Without it the config does not merely fail a check -- it
		errors on load and every check below it never runs, which reads as the
		whole suite passing if you are not watching the count.
	]]
	CFrame = (function()
		local meta = {}
		meta.__index = meta
		meta.__mul = function(a, _b)
			return setmetatable({ X = a.X or 0, Y = a.Y or 0, Z = a.Z or 0, __kind = "CFrame" }, meta)
		end

		local function new(x, y, z)
			return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __kind = "CFrame" }, meta)
		end

		return {
			new = new,
			Angles = function(rx, ry, rz)
				return setmetatable({ RX = rx or 0, RY = ry or 0, RZ = rz or 0, __kind = "CFrame" }, meta)
			end,
			fromAxisAngle = function()
				return new(0, 0, 0)
			end,
		}
	end)(),
	--[[
		Only the members the config actually names. A stub that invented every
		enum would happily accept a typo like AnimationPriority.Actoin, which is
		exactly the mistake worth catching -- it fails silently at runtime by
		leaving the track at its default priority.
	]]
	Enum = {
		AnimationPriority = {
			Idle = { Name = "Idle", Value = 0, __kind = "EnumItem" },
			Movement = { Name = "Movement", Value = 1, __kind = "EnumItem" },
			Action = { Name = "Action", Value = 2, __kind = "EnumItem" },
			Action2 = { Name = "Action2", Value = 3, __kind = "EnumItem" },
			Action3 = { Name = "Action3", Value = 4, __kind = "EnumItem" },
			Action4 = { Name = "Action4", Value = 5, __kind = "EnumItem" },
			Core = { Name = "Core", Value = 1000, __kind = "EnumItem" },
		},
	},
}

local function loadModule(path: string)
	local source = fs.readFile(path)
	local chunk = luau.load(source, {
		debugName = path,
		environment = env,
		injectGlobals = true,
	})
	return chunk()
end

local Config = loadModule("src/shared/GasConfig.luau")

-- ============================================================
-- SHAPE
-- ============================================================

local REQUIRED = {
	"ToolName", "ToolType", "MagCapacity", "ReservedAmmo",
	"FuseTime", "CookKillsYou", "ThrowPower", "ThrowAngle", "ThrowSpin",
	"ThrowCooldown", "BounceElasticity", "BounceFriction",
	"CloudRadius", "CloudDuration", "TickInterval", "DamagePerTick",
	"FullDamageRadius", "BuildUpTime", "RequireLineOfSight",
	"AffectsEveryone", "VehicleSeatProtects", "ConditionName",
	"DestroyWhenEmpty", "DestroyDelay",
	"GripOffset", "Animation", "Sound", "Disorient", "Models", "Nerve", "Visual",
}

for _, key in ipairs(REQUIRED) do
	check("GasConfig defines " .. key, Config[key] ~= nil)
end

local VISUAL_REQUIRED = {
	"Colour", "ArcColour", "ArcWarnColour", "Rate", "ParticleLifetime",
	"SizeStart", "SizeEnd", "Speed", "Rise", "Opacity", "Glow", "EmitterCount",
	"LingerAfterExpiry",
}

for _, key in ipairs(VISUAL_REQUIRED) do
	check("GasConfig.Visual defines " .. key, Config.Visual[key] ~= nil)
end

check("config is frozen", table.isfrozen(Config))

check(
	"the nested Visual table is frozen too",
	table.isfrozen(Config.Visual),
	"table.freeze is shallow -- freezing only the outer table leaves this writable"
)

check("the nested GripOffset table is frozen too", table.isfrozen(Config.GripOffset))

--[[
	Both rig types need an offset. gripOffsetFor falls through to R15 for any
	non-R6 character, so a missing R15 entry hands a nil CFrame to the weld
	maths and the grenade ends up somewhere unrepeatable.
]]
for _, rig in ipairs({ "R6", "R15" }) do
	local offset = Config.GripOffset[rig]
	check("GripOffset defines " .. rig, offset ~= nil)

	if offset then
		--[[
			Named components, so a typo is catchable. `Rol = 90` or `yaw = 90`
			would otherwise read as zero and silently leave the grenade in its
			old orientation while looking, in the file, like it had been changed.
		]]
		for _, field in ipairs({ "X", "Y", "Z", "Pitch", "Yaw", "Roll" }) do
			check(
				string.format("GripOffset.%s.%s is a number", rig, field),
				type(offset[field]) == "number",
				"missing or misspelled fields silently read as zero"
			)
		end

		check(
			string.format("GripOffset.%s is frozen", rig),
			table.isfrozen(offset),
			"the per-rig tables need freezing individually -- table.freeze is shallow"
		)

		local known = { X = true, Y = true, Z = true, Pitch = true, Yaw = true, Roll = true }
		local strays = {}
		for key in pairs(offset) do
			if not known[key] then
				table.insert(strays, key)
			end
		end

		check(
			string.format("GripOffset.%s has no stray fields", rig),
			#strays == 0,
			#strays > 0 and ("unread: " .. table.concat(strays, ", ")) or nil
		)
	end
end

check("the nested Animation table is frozen too", table.isfrozen(Config.Animation))

--[[
	Animation ids are a rich source of silent failure: a bare number, a decal id
	pasted by mistake, or the asset-delivery prefix that does not resolve for
	animations. None of them error -- the track just never plays.
]]
local throwId = Config.Animation.Throw

check("throw animation id is a string", type(throwId) == "string")

check(
	"throw animation id uses the rbxassetid:// prefix",
	type(throwId) == "string" and string.match(throwId, "^rbxassetid://%d+$") ~= nil,
	string.format("got %q -- a bare number or an http:// url will not load", tostring(throwId))
)

check(
	"throw animation priority is Action or above",
	Config.Animation.Priority ~= nil and Config.Animation.Priority.Value >= 2,
	"below Action it blends with TREK's global Run instead of replacing it"
)

check(
	"release delay is not negative",
	Config.Animation.ReleaseDelay >= 0
)

check(
	"release delay leaves fuse to spare",
	Config.Animation.ReleaseDelay < Config.FuseTime,
	"the grenade would detonate in hand before the animation let go of it"
)

check("animation fade time is not negative", Config.Animation.FadeTime >= 0)

--[[
	Speed divides the release delay at runtime, so zero does not merely freeze
	the animation -- it makes the release delay infinite and the grenade never
	leaves the hand at all. Negative runs the throw backwards.
]]
-- ============================================================
-- SOUND
-- ============================================================

check("GasConfig defines Sound", Config.Sound ~= nil)
check("the nested Sound table is frozen too", table.isfrozen(Config.Sound))

--[[
	Same silent-failure family as the animation id. A bare number or an http url
	does not error -- the Sound simply never makes a noise, and a silent gas
	cloud looks exactly like a working one.
]]
check(
	"hiss id uses the rbxassetid:// prefix",
	type(Config.Sound.Hiss) == "string" and string.match(Config.Sound.Hiss, "^rbxassetid://%d+$") ~= nil,
	string.format("got %q -- a bare number or an http:// url will not load", tostring(Config.Sound.Hiss))
)

check(
	"hiss volume is audible and not deafening",
	Config.Sound.Volume > 0 and Config.Sound.Volume <= 2,
	"zero is silent; above about 2 it clips"
)

check(
	"the hiss rolloff band is the right way round",
	Config.Sound.RollOffMax > Config.Sound.RollOffMin,
	"max below min makes the sound audible nowhere"
)

--[[
	The hiss has to reach past the gas itself. Its job is to warn people near the
	cloud, not to confirm to the ones already choking in it that they are indeed
	choking.
]]
check(
	"the hiss carries beyond the cloud",
	Config.Sound.RollOffMax >= Config.CloudRadius,
	string.format(
		"audible to %.0f studs but the gas reaches %.0f",
		Config.Sound.RollOffMax, Config.CloudRadius
	)
)

check("hiss fade-out is not negative", Config.Sound.FadeOut >= 0)

-- ============================================================
-- DISORIENTATION
-- ============================================================

-- ============================================================
-- MODELS
-- ============================================================

check("the nested Models table is frozen too", table.isfrozen(Config.Models))

--[[
	Both names must be non-empty strings. An empty one makes every
	FindFirstChild in the service return nil, which surfaces as "model is
	missing" against a folder that plainly contains it.

	Pointing both at the same model is legitimate -- the grenade then looks
	identical in the hand and in the air -- so that is not checked against.
]]
for _, slot in ipairs({ "Held", "Thrown" }) do
	check(
		string.format("Models.%s names a model", slot),
		type(Config.Models[slot]) == "string" and Config.Models[slot] ~= "",
		"an empty name makes every lookup return nil"
	)
end

-- ============================================================

-- ============================================================
-- NERVE AGENT
-- ============================================================

check("the nested Nerve table is frozen too", table.isfrozen(Config.Nerve))

local nerve = Config.Nerve

check("time to death is positive", nerve.TimeToDeath > 0)
check("nerve tick interval is positive", nerve.TickInterval > 0)

check(
	"the death drain ticks more than once",
	nerve.TickInterval < nerve.TimeToDeath,
	"one tick means health jumps straight to zero instead of draining"
)

--[[
	The dose threshold is measured in cloud ticks, so anything at or below one
	TickInterval means "one tick inside is enough". Above it, the victim gets a
	grace nobody asked for -- silently, because the only symptom is people
	surviving gas that was meant to be lethal.
]]
check(
	"any contact doses",
	nerve.DoseThreshold <= Config.TickInterval,
	string.format(
		"threshold %.2fs exceeds the cloud's %.2fs tick, so a brief pass through survives",
		nerve.DoseThreshold, Config.TickInterval
	)
)

check(
	"the thrower's grace is longer than everyone else's",
	nerve.ThrowerGrace >= nerve.DoseThreshold,
	"a shorter grace punishes the thrower more than the target"
)

--[[
	The grace has to fit inside the cloud's life, or it is not a grace: the gas
	would expire before the thrower could ever be dosed, making them immune to
	their own weapon rather than merely quick enough to escape it.
]]
check(
	"the thrower can still be dosed by their own gas",
	nerve.ThrowerGrace < Config.CloudDuration,
	string.format(
		"grace %.1fs vs a %.1fs cloud -- the thrower would be outright immune",
		nerve.ThrowerGrace, Config.CloudDuration
	)
)

check("seize delay is not negative", nerve.SeizeDelay >= 0)

-- ---- can anyone run through it? --------------------------------

--[[
	The speed the sweep has to beat.

	Deliberately generous against anything on foot in TREK -- if it holds for
	something this fast it holds for a sprint.
]]
local FAST_PLAYER = 60

check("the sweep margin is not negative", Config.SweepMargin >= 0)

--[[
	THE test for "people can just run through it".

	The overlap query only returns who is inside the cloud at the instant of a
	tick. Someone moving faster than the margin covers can be outside at two
	consecutive samples having crossed the middle between them, and the swept
	test never sees them because the query never handed them over.
]]
check(
	"a sprinting player cannot cross between two samples unseen",
	Config.SweepMargin >= FAST_PLAYER * Config.TickInterval,
	string.format(
		"margin %.0f studs vs %.0f a player covers in one %.2fs tick",
		Config.SweepMargin, FAST_PLAYER * Config.TickInterval, Config.TickInterval
	)
)

--[[
	One tick in the cloud has to be a lethal dose, or the gas is an area you
	push through rather than a wall. expose() accumulates TickInterval per tick,
	so a threshold above one tick's worth means brief contact does nothing at
	all -- and brief contact is all a moving player ever has.
]]
check(
	"a single tick of contact is a dose",
	nerve.DoseThreshold <= Config.TickInterval,
	string.format(
		"threshold %.2fs needs %.1f ticks of %.2fs -- anyone moving survives",
		nerve.DoseThreshold, nerve.DoseThreshold / Config.TickInterval, Config.TickInterval
	)
)

--[[
	The thrower's grace is the deliberate exception, and it must stay an
	exception: a grace shorter than a tick is no grace at all, and one longer
	than the cloud makes them immune (checked separately below).
]]
check(
	"the thrower's grace is longer than everyone else's",
	nerve.ThrowerGrace > nerve.DoseThreshold,
	"the grace would be no different from standing in it as anyone else"
)
check("twitch strength is not negative", nerve.TwitchStrength >= 0)
check("collapse impulse is not negative", nerve.CollapseImpulse >= 0)
check("collapse spin is not negative", nerve.CollapseSpin >= 0)

--[[
	Outside 0..1 the lift stops meaning "a fraction of the shove". Above 1 the
	horizontal term goes negative, which does not error -- it just silently
	inverts the heading, so the body reliably falls the opposite way from the
	one the direction was drawn for.
]]
check(
	"collapse lift is a fraction",
	nerve.CollapseLift >= 0 and nerve.CollapseLift <= 1,
	string.format("lift %.2f is outside 0..1", nerve.CollapseLift)
)

--[[
	A ceiling on the root's spin, rather than a comparison against the twitch.

	The two are not comparable: CollapseSpin drives one assembly and
	TwitchStrength drives six, so an earlier check that the collapse "outweighed"
	the twitch was comparing quantities with different meanings and passed
	happily at a value that threw bodies through the floor.

	The limit is drawn from what demonstrably works in this place -- SkiRagdoll
	tumbles at 9, RagdollDeath topples at 9. Well above that and the ball sockets
	start fighting the spin hard enough for the solver to answer with impulses
	that clip geometry.
]]
check(
	"the collapse spin stays inside what the constraints can absorb",
	nerve.CollapseSpin <= 20,
	string.format(
		"spin %.0f rad/s -- Ski and RagdollDeath both use 9; past about 20 the "
			.. "ball sockets fight it and bodies get pushed through the floor",
		nerve.CollapseSpin
	)
)
check("blood delay is not negative", nerve.BloodDelay >= 0)

-- ---- the victim's sound ----------------------------------------

local nerveSound = nerve.Sound

check("the nerve sound table exists", type(nerveSound) == "table")
check("the nerve sound table is frozen", table.isfrozen(nerveSound))

--[[
	A bare number here is the classic way to get silence with no error. Roblox
	accepts the assignment, finds no asset, and plays nothing -- and the failure
	looks identical to the sound simply not being wired up.
]]
check(
	"the nerve sound id is an rbxassetid string",
	type(nerveSound.Id) == "string" and nerveSound.Id:match("^rbxassetid://%d+$") ~= nil,
	"got " .. tostring(nerveSound.Id)
)

check("the nerve sound is audible", nerveSound.Volume > 0)
check("the nerve sound roll-off is ordered", nerveSound.RollOffMin < nerveSound.RollOffMax)
check("the nerve sound fade is not negative", nerveSound.FadeOut >= 0)

--[[
	The fade is what plays after death, so a long one on a short death leaves a
	corpse groaning well after everyone has stopped looking at it.
]]
check(
	"the fade-out is short against the death it follows",
	nerveSound.FadeOut < nerve.TimeToDeath,
	string.format(
		"a %.1fs fade on a %.1fs death",
		nerveSound.FadeOut, nerve.TimeToDeath
	)
)

--[[
	The suppression attribute has to be a usable name. An empty string is a
	legal attribute name to SET and silently unreadable, so the hurt barks would
	come back with nothing anywhere saying why.
]]
check(
	"the hurt-suppression attribute is named",
	type(nerve.SuppressHurtAttribute) == "string" and #nerve.SuppressHurtAttribute > 0
)

check(
	"the blood starts before they are dead",
	nerve.BloodDelay < nerve.TimeToDeath,
	"blood scheduled past the death is blood nobody ever sees"
)

check(
	"the seizure lands before death",
	nerve.SeizeDelay < nerve.TimeToDeath,
	"they would die on their feet, having never gone limp"
)

-- ============================================================

check("GasConfig defines Disorient", Config.Disorient ~= nil)
check("the nested Disorient table is frozen too", table.isfrozen(Config.Disorient))

local dis = Config.Disorient

check("disorient build time is positive", dis.BuildTime > 0)
check("disorient fade time is positive", dis.FadeTime > 0)

--[[
	Gas has to take hold faster than it lets go.

	Build and fade run against each other: the cloud tops exposure up while you
	are in it and it decays once you leave. If fading were the quicker of the two
	you could stand in the thickest part of a cloud and never reach full effect,
	which would look exactly like the feature being broken.
]]
check(
	"gas takes hold faster than it clears",
	dis.BuildTime <= dis.FadeTime,
	string.format(
		"build %.1fs vs fade %.1fs -- exposure would never accumulate",
		dis.BuildTime, dis.FadeTime
	)
)

--[[
	The build has to fit inside a cloud's life, or nobody ever sees full effect
	no matter how long they stand in it.
]]
check(
	"full disorientation is reachable before the cloud expires",
	dis.BuildTime < Config.CloudDuration,
	string.format("build %.1fs vs a %.1fs cloud", dis.BuildTime, Config.CloudDuration)
)

check("max blur is not negative", dis.MaxBlur >= 0)
check("ring volume is not negative", dis.RingVolume >= 0)

check(
	"saturation drain is within range",
	dis.MaxSaturation >= -1 and dis.MaxSaturation <= 0,
	"positive values oversaturate instead of bleaching; below -1 is clamped anyway"
)

--[[
	MaxTint is a lerp position along white -> TintColour, so it only means
	anything between 0 and 1. Above 1 the lerp overshoots past the gas colour
	into whatever lies beyond it, which is not a colour anyone chose.
]]
check(
	"tint strength is a valid lerp position",
	dis.MaxTint >= 0 and dis.MaxTint <= 1,
	"MaxTint is how far from white toward the gas colour, so it lives in 0..1"
)

check(
	"the gas darkens rather than brightens",
	dis.MaxBrightness <= 0,
	"a positive brightness reads as a flashbang, not as gas stinging your eyes"
)

check(
	"brightness and contrast stay in sane bounds",
	dis.MaxBrightness >= -1 and dis.MaxContrast >= -1 and dis.MaxContrast <= 1
)

check(
	"muffle gain attenuates rather than boosts",
	dis.MuffleGain <= 0,
	"a positive gain makes the world LOUDER when gassed"
)

check(
	"smoothing is fast enough to keep up",
	dis.SmoothSpeed > 0,
	"zero freezes the rendered value at 0 and nothing ever appears"
)

check(
	"the attribute name is a non-empty string",
	type(dis.AttributeName) == "string" and dis.AttributeName ~= "",
	"the server and client agree only by this name"
)

-- ============================================================

check(
	"animation speed is positive",
	type(Config.Animation.Speed) == "number" and Config.Animation.Speed > 0,
	"zero or negative Speed stops the grenade ever being released"
)

-- ============================================================
-- INVARIANTS
-- ============================================================

check(
	"FullDamageRadius fits inside CloudRadius",
	Config.FullDamageRadius <= Config.CloudRadius,
	string.format("full=%.1f cloud=%.1f -- falloff span goes negative", Config.FullDamageRadius, Config.CloudRadius)
)

check("CloudRadius is positive", Config.CloudRadius > 0)
check("CloudDuration is positive", Config.CloudDuration > 0)

check(
	"TickInterval is positive",
	Config.TickInterval > 0,
	"a zero interval turns the cloud loop into a busy wait"
)

check(
	"TickInterval is shorter than CloudDuration",
	Config.TickInterval < Config.CloudDuration,
	"the cloud would tick once or not at all"
)

check(
	"BuildUpTime leaves time at full strength",
	Config.BuildUpTime < Config.CloudDuration,
	"gas would expire before it finished thickening"
)

check("DamagePerTick is positive", Config.DamagePerTick > 0)
check("FuseTime is positive", Config.FuseTime > 0)
check("ThrowPower is positive", Config.ThrowPower > 0)

check(
	"ThrowAngle is a sane loft",
	Config.ThrowAngle >= -89 and Config.ThrowAngle <= 89,
	"at +-90 the loft axis degenerates and the throw goes straight up"
)

-- ============================================================
-- TRAJECTORY
-- ============================================================

--[[
	Power and angle are individually plausible numbers that together produce a
	throw nobody would ship.

	The pair shipped before this block existed -- power 70, angle 12 -- reads as
	perfectly reasonable in the file and lands the grenade 10 studs away having
	risen half a stud. Neither value is wrong on its own; the product is. So the
	check is on the trajectory they actually describe.

	Roblox's default gravity. A place that has changed workspace.Gravity will
	throw further or shorter than this predicts, which is worth knowing but not
	worth failing over.
]]
local GRAVITY = 196.2

local theta = math.rad(Config.ThrowAngle)
local speed = Config.ThrowPower
local range = (speed * speed) * math.sin(2 * theta) / GRAVITY
local apex = ((speed * math.sin(theta)) ^ 2) / (2 * GRAVITY)
local flight = 2 * speed * math.sin(theta) / GRAVITY

print(string.format(
	"      (throw: %.1f studs range, %.1f studs apex, %.2fs flight)",
	range, apex, flight
))

check(
	"a level throw carries a useful distance",
	range >= 25 and range <= 120,
	string.format("%.1f studs -- under 25 lands at your feet, over 120 is a mortar", range)
)

check(
	"the throw actually arcs",
	apex >= 3,
	string.format("%.1f stud apex -- too flat to clear cover, raise ThrowAngle", apex)
)

check(
	"the grenade is not in the air longer than its fuse",
	flight < Config.FuseTime,
	string.format("%.2fs flight vs %.2fs fuse -- it detonates mid-air on a full throw", flight, Config.FuseTime)
)

check(
	"BounceElasticity is within physics range",
	Config.BounceElasticity >= 0 and Config.BounceElasticity <= 1
)

check(
	"BounceFriction is within physics range",
	Config.BounceFriction >= 0 and Config.BounceFriction <= 1
)

check("MagCapacity is at least one", Config.MagCapacity >= 1)

--[[
	This one has already caught itself once.

	TREK's createAmmoStore assigns ReservedAmmo straight into a
	DoubleConstrainedValue's MaxValue and Value with no nil check. Spell it
	StoredAmmo -- which reads like the obvious name, and is what the ammo folder
	is actually called -- and the store is built with MaxValue = nil, which
	throws inside checkForGun while the character is still spawning.
]]
check(
	"ReservedAmmo is a number, not nil",
	type(Config.ReservedAmmo) == "number",
	"createAmmoStore assigns this into MaxValue with no nil check and will throw"
)

check("ReservedAmmo is not negative", (Config.ReservedAmmo or -1) >= 0)

--[[
	The dead-tool combination.

	No reserve and no destroy leaves a spent Tool sitting in the hotbar forever:
	it selects, it puts a grenade in your hand, and it refuses to throw. That
	reads as a broken grenade rather than a used one, and there is no way back
	from it short of respawning.
]]
check(
	"a spent grenade can either be reloaded or goes away",
	Config.ReservedAmmo > 0 or Config.DestroyWhenEmpty == true,
	"ReservedAmmo 0 with DestroyWhenEmpty false strands an unusable tool in the hotbar"
)

check("DestroyDelay is not negative", Config.DestroyDelay >= 0)

--[[
	The destroy has to outlast the wind-up.

	The tool is only spent once the grenade actually leaves, which is
	ReleaseDelay-scaled-by-Speed after the animation starts. Compared against the
	scaled value, not the raw one, because that is what actually elapses -- at
	Speed 2 a 0.25 delay is really 0.125.
]]
local windUp = Config.Animation.ReleaseDelay / math.max(Config.Animation.Speed or 1, 0.01)

check(
	"DestroyDelay outlasts the throw's wind-up",
	Config.DestroyDelay >= windUp or Config.DestroyDelay == 0,
	string.format(
		"destroy=%.2fs vs wind-up=%.2fs at speed %.2f -- the slot would vanish before the throw reads",
		Config.DestroyDelay, windUp, Config.Animation.Speed
	)
)
check("EmitterCount is at least one", Config.Visual.EmitterCount >= 1)

check(
	"Opacity is within range",
	Config.Visual.Opacity >= 0 and Config.Visual.Opacity <= 1
)

check(
	"particles grow rather than shrink",
	Config.Visual.SizeEnd >= Config.Visual.SizeStart,
	"gas that shrinks as it ages reads as smoke being sucked inward"
)

-- ============================================================
-- TIME TO KILL
-- ============================================================

--[[
	A sanity band, not a balance opinion. The point is to catch a decimal slip
	that makes the gas either instantly lethal or completely ignorable, not to
	pin down an exact number.
]]
local ticksPerSecond = 1 / Config.TickInterval
local dps = Config.DamagePerTick * ticksPerSecond
local ttk = 100 / dps

check(
	"centre TTK is between 1 and 12 seconds",
	ttk >= 1 and ttk <= 12,
	string.format("%.2f dps gives a %.2fs TTK", dps, ttk)
)

check(
	"the cloud outlives its own TTK",
	Config.CloudDuration >= ttk,
	"gas expires before it can kill anyone standing in it"
)

-- ============================================================
-- FALLOFF
-- ============================================================

--[[
	Mirrors GasCloud's falloff. Duplicated rather than imported because the real
	one is a local inside a module that requires ServerStorage at load time, and
	stubbing all of TREK to reach one pure function is worse than restating four
	lines and checking they agree.
]]
local function falloff(distance: number): number
	if distance <= Config.FullDamageRadius then
		return 1
	end
	local span = Config.CloudRadius - Config.FullDamageRadius
	if span <= 0 then
		return 1
	end
	return math.clamp(1 - ((distance - Config.FullDamageRadius) / span), 0, 1)
end

check("falloff is full at the centre", falloff(0) == 1)
check("falloff is full at the inner edge", falloff(Config.FullDamageRadius) == 1)
check("falloff is zero at the outer edge", falloff(Config.CloudRadius) == 0)
check("falloff is zero beyond the cloud", falloff(Config.CloudRadius * 2) == 0)

local monotonic = true
local previous = 1
for step = 0, 40 do
	local distance = (step / 40) * Config.CloudRadius
	local value = falloff(distance)
	if value > previous + 1e-9 then
		monotonic = false
		break
	end
	previous = value
end
check("falloff never increases with distance", monotonic)

local midpoint = (Config.FullDamageRadius + Config.CloudRadius) / 2
check(
	"falloff is partial between the radii",
	falloff(midpoint) > 0 and falloff(midpoint) < 1,
	string.format("midpoint %.1f gave %.3f", midpoint, falloff(midpoint))
)

-- ============================================================
-- EVERY KEY THE SOURCE READS ACTUALLY EXISTS
-- ============================================================

local function collectFiles(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collectFiles(path, out)
		elseif string.match(path, "%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

local files = collectFiles("src", {})
local missing: { string } = {}

for _, path in ipairs(files) do
	local source = fs.readFile(path)

	--[[
		%f[%w] is a frontier pattern: it requires a non-word/word transition, so
		"config" has to START a name rather than end one.

		Without it, any local ending in Config -- soundConfig, visualConfig --
		matches on its tail, and every field read off that NESTED table gets
		checked against the ROOT config, where it does not exist. Which is how
		this reported Config.Hiss as missing while GasConfig.Sound.Hiss was
		sitting there perfectly well defined.
	]]
	for prefix, key in string.gmatch(source, "%f[%w]([Cc]onfig)%.([A-Za-z_][A-Za-z0-9_]*)") do
		-- GasConfig.luau assigns these rather than reading them.
		if string.match(path, "GasConfig%.luau$") then
			continue
		end
		-- The shim reaches for the module instance, not the table.
		if key == "luau" or prefix == "GunConfig" then
			continue
		end
		if Config[key] == nil then
			table.insert(missing, string.format("%s reads Config.%s", path, key))
		end
	end

	for key in string.gmatch(source, "visual%.([A-Za-z_][A-Za-z0-9_]*)") do
		if Config.Visual[key] == nil then
			table.insert(missing, string.format("%s reads Visual.%s", path, key))
		end
	end
end

check(
	"every config key the source reads is defined",
	#missing == 0,
	#missing > 0 and table.concat(missing, "; ") or nil
)

-- ============================================================

print(string.format("\n%d passed, %d failed", passed, failed))

if failed > 0 then
	process.exit(1)
end

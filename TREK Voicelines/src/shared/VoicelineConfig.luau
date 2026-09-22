--!strict
-- Every tunable for the voiceline system.
--
-- Sounds ship empty. Roblox audio is private to the place that owns it, so an
-- id lifted from another game plays as silence and reports no error. Upload
-- your clips to this place (or your group) and paste the ids in below.

export type AssetId = number | string

export type EventConfig = {
	Priority: number,
	Cooldown: number,
	Chance: number,
	Sounds: { AssetId }?,
	SharesWith: string?,
	Concurrent: boolean?,
	IgnoresCrowd: boolean?,
	StartOffset: number?,
}

local Config = {}

--[[
	Turn whatever went into a Sounds list into a usable SoundId.

	All of these are accepted, because all of them are things you get from
	copying an id out of Studio or the website:

		3526632933
		"3526632933"
		"rbxassetid://3526632933"
		"http://www.roblox.com/asset/?id=3526632933"

	Blindly prefixing instead would turn an already-prefixed entry into
	"rbxassetid://rbxassetid://3526632933", which fails to load and reports
	only "asset was not found".
]]
function Config.toAssetUrl(id: AssetId): string
	if type(id) == "number" then
		return "rbxassetid://" .. id
	end

	local text = tostring(id):match("^%s*(.-)%s*$") or ""

	-- Bare digits.
	if text:match("^%d+$") then
		return "rbxassetid://" .. text
	end

	-- Peel any number of rbxassetid:// prefixes. The loop rather than a single
	-- strip is what recovers the doubled form.
	local stripped = text
	while true do
		local rest = stripped:match("^rbxassetid://(.*)$")
		if not rest then
			break
		end
		stripped = rest
	end
	if stripped:match("^%d+$") then
		return "rbxassetid://" .. stripped
	end

	-- Website URLs, both shapes.
	local fromQuery = text:match("[?&]id=(%d+)")
	if fromQuery then
		return "rbxassetid://" .. fromQuery
	end

	local fromLibrary = text:match("roblox%.com/[%w]+/(%d+)")
	if fromLibrary then
		return "rbxassetid://" .. fromLibrary
	end

	-- Anything else -- an rbxasset:// path, say -- is passed through untouched.
	-- Matching a trailing digit run here would mangle "sounds/uuhhh.mp3" into
	-- asset id 3.
	return text
end

-- A slot that is deliberately empty and waiting for a real id. Placeholders are
-- skipped when picking, so an event holding only these is simply silent -- it
-- never plays a gap where a line should be.
Config.Placeholder = "PLACEHOLDER"

function Config.isPlaceholder(id: AssetId): boolean
	return type(id) == "string" and id:upper():match("^%s*PLACEHOLDER") ~= nil
end

--[[
	Resolve a Sounds list down to the urls that can actually play.

	Placeholders and malformed entries are dropped here rather than at playback,
	so a half-filled list never costs you a silent voiceline -- the picker only
	ever chooses between clips that exist.
]]
-- Accepts nil: an event that borrows a voice through SharesWith has no list of
-- its own, and a caller reading the field directly would otherwise hand nil to
-- ipairs and take the whole script down with it.
function Config.playableSounds(sounds: { AssetId }?): { string }
	local out = {}

	for _, id in ipairs(sounds or {}) do
		if not Config.isPlaceholder(id) then
			local url = Config.toAssetUrl(id)
			if url:match("^rbxassetid://%d+$") or url:match("^rbxasset://") then
				table.insert(out, url)
			end
		end
	end

	return out
end

--[[
	Follow SharesWith to the event that actually owns the clips.

	Sharing is deeper than copying ids between two lists. Events that share a
	voice also share the no-repeat memory and the cooldown clock, so going low
	and then reloading cannot say the same line twice in four seconds -- which is
	exactly what two separate lists holding the same ids would do.
]]
--[[
	Resolved answers, memoised on first use.

	Both of these are pure functions of Config.Events, which does not change while
	the server runs -- yet soundsFor was being called on every single bark request,
	re-running the whole string-matching normaliser over every id in the list. It
	cost ~24us per request on a five-clip event and, because it sat above the
	cooldown check, it was paid in full by requests that were then refused. At a
	firefight's request rate that is milliseconds per second of pure re-parsing for
	an answer that is identical every time.

	Cached lazily rather than built at load, so editing the tables above before the
	first bark still takes effect -- which is how live tuning in Studio works.
]]
local voiceKeyCache: { [string]: string } = {}
local soundsCache: { [string]: { string } } = {}

-- Drop the caches. Only needed if you edit Config.Events at runtime, e.g. from
-- the command bar while tuning.
function Config.refresh()
	voiceKeyCache = {}
	soundsCache = {}
end

function Config.voiceKey(event: string): string
	local cached = voiceKeyCache[event]
	if cached then
		return cached
	end

	local seen = {}
	local current = event

	while true do
		local cfg = Config.Events[current]
		if not cfg or not cfg.SharesWith or seen[current] then
			break
		end
		seen[current] = true
		current = cfg.SharesWith
	end

	voiceKeyCache[event] = current
	return current
end

-- The playable clips for an event, following SharesWith.
--
-- The returned table is SHARED and must be treated as read-only -- every caller
-- gets the same one. Nothing mutates it today (the picker indexes it, the
-- preloader and the startup check only read), and nothing should start.
function Config.soundsFor(event: string): { string }
	local cached = soundsCache[event]
	if cached then
		return cached
	end

	local cfg = Config.Events[Config.voiceKey(event)]
	local sounds = cfg and Config.playableSounds(cfg.Sounds) or {}

	soundsCache[event] = sounds
	return sounds
end

--[[
	Report entries that cannot become a usable asset, as { event, position, raw }.

	A bad entry is otherwise invisible: Roblox reports "Failed to load sound
	rbxassetid://: Request asset was not found" with no clue which list it came
	from, and the line just plays as silence. An empty "rbxassetid://" left over
	from a half-finished paste is the usual culprit.
]]
function Config.findBadEntries(): { { event: string, index: number, raw: string } }
	local bad = {}

	for event, cfg in pairs(Config.Events) do
		-- An event that shares a voice owns no list of its own; the clips it uses
		-- are checked under whichever event does own them.
		for index, id in ipairs(cfg.Sounds or {}) do
			-- Placeholders are intentional and reported separately; only genuine
			-- mistakes belong in this list.
			if not Config.isPlaceholder(id) then
				local url = Config.toAssetUrl(id)
				if not url:match("^rbxassetid://%d+$") and not url:match("^rbxasset://") then
					table.insert(bad, { event = event, index = index, raw = tostring(id) })
				end
			end
		end
	end

	return bad
end

-- Pause after a line ENDS before the next one may begin -- the breath between
-- two consecutive callouts, whatever events they came from.
--
-- 0 is safe. It does NOT let lines overlap: while a clip is playing the channel
-- is occupied and Priority decides, so an equal or lower event is refused and a
-- higher one stops the current clip before starting. This value only controls
-- the gap AFTER a line finishes, so 0 means callouts can run back to back with
-- no pause for breath. Raise it to about 0.4 if that sounds too rushed.
Config.GlobalCooldown = 0

-- Hard ceiling on how long a line is allowed to occupy the channel. The server
-- cannot read Sound.TimeLength until the asset loads, so this is the fallback
-- that frees the slot if a clip never reports Ended.
Config.MaxLineLength = 8

-- Playback. Voicelines come out of the speaker's head so squadmates hear them
-- positionally -- that is the whole point of them.
Config.Volume = 0.85

--[[
	How the volume falls off with distance.

	This MUST be set. Sound.RollOffMode defaults to "Inverse", and in that mode
	RollOffMaxDistance is ignored entirely -- the curve is driven by MinDistance
	alone and the clip stays faintly audible far past whatever you put in Max.
	For the first release that meant barks carried across the map while the
	config claimed a 140 stud limit.

	"InverseTapered" behaves like real sound near the source -- roughly inverse
	square -- then tapers so it actually reaches silence at MaxDistance. That is
	the combination worth having: natural close up, genuinely bounded far away.

	The other options, if you want to experiment:
	  Inverse        natural, but NO maximum. Do not use here.
	  Linear         hard straight ramp to silence. Predictable, unnatural.
	  LinearSquare   quieter sooner than Linear, still bounded.
	  InverseTapered natural near, bounded far.  <- default
]]
Config.RollOffMode = "InverseTapered"

-- Full volume within this radius.
Config.RollOffMinDistance = 10

-- Silent beyond this. A shout should reach the people you are fighting
-- alongside, not someone across the compound -- and since barks have no team
-- filter, anything you say is heard by enemies in range too, so range is a
-- tactical setting as much as an audio one.
Config.RollOffMaxDistance = 70

-- Bind NPCs, dummies and admin-spawned clones as well as player characters.
-- They get their own Hurt and Death lines, and -- the useful part -- killing one
-- can credit a Kill, since attribution is read off the victim's WeaponTag rather
-- than requiring the victim to be a player.
Config.IncludeNPCs = true

-- Print a line on every humanoid death saying whether a WeaponTag was present
-- and who it named. Turn on when a Kill is not firing and you want to know
-- whether the kill simply was not attributed.
Config.Debug = false

-- Minimum damage in a single hit before Hurt is considered. 1 means any damage
-- at all counts -- chip hits, bleed ticks, explosion falloff, fall damage.
-- Raise it if you want only solid hits to register.
Config.HurtDamageThreshold = 1

-- At or below this fraction of a magazine, LowAmmo fires. Reaching exactly zero
-- is included rather than special-cased: an empty magazine is as low as ammo
-- gets, and it speaks the same line the rest of the threshold does.
Config.LowAmmoFraction = 0.2

-- How close to an explosion you must be to react to it.
Config.IncomingRadius = 70

-- Bayonet barks, from the TREK Bayonet package. Automatically inert in places
-- without it; this switch is for turning them off in places that have it.
Config.BayonetBarks = true

-- Objective barks. Automatically inert in places with no TObjectiveSystem; this
-- switch is for turning them off in places that have one.
Config.ObjectiveBarks = true
Config.ObjectiveRadius = 150

-- The objective system tracks sides as 'Raiders' and 'Defenders'. Map those to
-- the real Team names so only the capturing side celebrates.
Config.ObjectiveTeamNames = {
	Raiders = "Opfor",
	Defenders = "Korblox",
}

-- Crowd control. Barks are per character, so without a limiter a twenty-player
-- push produces twenty simultaneous voices and none of them are legible.
--
-- Counted per locality rather than globally: a firefight across the map should
-- not silence the one happening next to you.
Config.CrowdWindow = 1.5   -- seconds a recent bark keeps counting for
Config.CrowdRadius = 70    -- studs; matches RollOffMaxDistance, so a bark only
                           -- competes with others a listener can actually hear
Config.CrowdLimit = 2      -- nearby speakers allowed inside the window

-- Per-event tuning.
--
--   Priority  higher wins. A line already playing is cut off only by something
--             strictly higher, so Death always lands and Reload never stomps a
--             Hurt call.
--   Cooldown  seconds before this same event can fire again on this character.
--   Concurrent  true lifts the event out of the one-voice-at-a-time rule: it
--             layers over whatever is already speaking rather than waiting for
--             it or cutting it off. Priority stops meaning anything for such an
--             event -- it neither blocks nor is blocked -- but Cooldown and
--             Chance still apply.
--   Chance    0-1 probability the line actually plays. 1.0 = every time. 0.5 =
--             half the time, silent the rest. Below 1 keeps a repeated action
--             from producing the same bark every single time -- but note a
--             FAILED roll still starts the cooldown, so the real gap between
--             lines is roughly Cooldown / Chance, not Cooldown.
--   StartOffset  seconds of the clip to skip. For trimming LEADING SILENCE off
--             a recording, which is the one kind of lateness no amount of work
--             on this side can fix: if the file opens with a third of a second
--             of room tone, the bark is a third of a second late however fast
--             the server reaches it. Applies to every clip in the event, so
--             split clips across two events if their lead-ins differ. Leave at
--             0 or omit for a clip that starts on the word.
--
--             To find the value, drop a Sound with the id into Workspace in
--             Studio, run it, and step TimePosition until the line starts
--             immediately. See "MEASURING A LEAD-IN" below.
Config.Events = {
	-- Reload owns the ammo voice; LowAmmo borrows it below.
	Reload = {
		Priority = 2,
		Cooldown = 0.25,
		Chance = 1.0,
		Sounds = {
			"rbxassetid://121374962330189",
			"rbxassetid://125253712563509",
			"rbxassetid://123852457854451",
			"rbxassetid://93840917543863",
		},
	},

	-- Same clips, same no-repeat memory, same cooldown clock as Reload. Going
	-- low and then reloading a second later cannot repeat a line, and cannot
	-- talk over itself. Keeps its own Priority and Chance.
	LowAmmo = {
		Priority = 3,
		Cooldown = 0.25,
		Chance = 0.85,
		SharesWith = "Reload",
	},

	-- Something exploded near you. Fires on everyone within IncomingRadius, not
	-- on whoever fired it.
	Incoming = {
		Priority = 7,
		Cooldown = 6,
		Chance = 0.8,
		Sounds = { "PLACEHOLDER", "PLACEHOLDER", "PLACEHOLDER" },
	},

	-- A capture point changed hands. Only the capturing side speaks, and only
	-- those near the point.
	PointTaken = {
		Priority = 4,
		Cooldown = 10,
		Chance = 0.7,
		Sounds = { "PLACEHOLDER", "PLACEHOLDER" },
	},

	--[[
		Bayonet thrusts, split by outcome.

		Both are the swing, not the kill. A bayonet KILL already speaks through
		Kill below: the bayonet damages through TREK's own DamagePlayer, which
		calls lbmodule.tagPlr, which writes the WeaponTag the Kill hook reads. So
		a fatal stab says its contact line and then its kill line, which is the
		right pair -- the kill bark is Concurrent and layers over it.

		"Contact" means the sweep found a humanoid, which is reported before
		armour is applied: a hit reduced to zero damage still connected, and still
		looked like a hit to both players.

		Only ACCEPTED thrusts speak. A thrust the bayonet refuses -- rate limited,
		no blade fitted, seated in a vehicle -- reports no outcome at all, so
		neither of these can fire for a swing that never happened. That also means
		a client spamming the stab remote gets nothing extra out of it.

		EVERY thrust speaks, and it takes all four of these to guarantee that:

		  Cooldown 0     no gap to fall inside. The weapon's own 1.2s cooldown is
		                 the real rate limit, and only accepted thrusts report an
		                 outcome at all, so nothing here needs a second one.
		  Chance 1.0     never rolls itself out.
		  Concurrent     layers instead of queueing. Without it a thrust during a
		                 Hurt line (priority 6) loses the channel and says nothing.
		  IgnoresCrowd   a melee is crowded by definition -- your own fight is
		                 exactly the situation the limiter would silence.

		Priority is therefore decorative here, as it is for Kill: a concurrent
		event neither blocks nor is blocked.
	]]
	BayonetHit = {
		Priority = 5,
		Cooldown = 0,
		Chance = 1.0,
		Concurrent = true,
		IgnoresCrowd = true,
		Sounds = { "rbxassetid://17545135500" },
	},

	BayonetMiss = {
		Priority = 5,
		Cooldown = 0,
		Chance = 1.0,
		Concurrent = true,
		IgnoresCrowd = true,
		Sounds = { "rbxassetid://137951817204948" },
	},

	Hurt = {
		Priority = 6,
		Cooldown = 5,
		Chance = 1.0,
		Sounds = {"rbxassetid://136844926219636", "rbxassetid://113033490917993","rbxassetid://128990841342566","rbxassetid://131587512422496","rbxassetid://76456045012714"},
	},

	Kill = {
		Priority = 5,
		Cooldown = 0.25,
		Chance = 1.0,
		Concurrent = true,
		-- Must ignore the crowd limiter, and this is not a preference.
		--
		-- A kill arrives at the end of a chain that has already made noise: the
		-- victim's Hurt bark when you first hit them, then the victim's Death bark
		-- an instant before this one. Both are within CrowdRadius of the killer at
		-- any normal engagement range, so a Kill request routinely saw the limit
		-- already reached and was refused -- by the very death that earned it.
		-- Kills only landed when the victim took longer than CrowdWindow to die
		-- after their last Hurt bark, which reads exactly like "it works sometimes".
		--
		-- Concurrent was never the problem: it already exempts Kill from priority
		-- and from the one-voice rule. The crowd gate is a separate gate and it
		-- applied anyway.
		IgnoresCrowd = true,
		Sounds = {"rbxassetid://95443426895855"},
	},

	-- Cooldown is moot: you die once per life, and Service.reset clears the
	-- channel on respawn.
	Death = {
		Priority = 10,
		Cooldown = 0,
		Chance = 1.0,
		-- Always lands. A death carries information nobody else can supply, so
		-- it is the one line the crowd limiter must not swallow.
		IgnoresCrowd = true,
		Sounds = {"rbxassetid://3526632933", "rbxassetid://1869828588", "rbxassetid://101474734749359", "rbxassetid://140539866173088"},
	},
}

-- MEASURING A LEAD-IN
--
-- A bark that is consistently late by the same amount, every single time, is
-- not a timing bug. Timing bugs vary with ping, load and distance. A fixed
-- offset that never moves is the clip.
--
-- Turn Config.Debug on and the service reports, for every line it plays, how
-- long it spent between being asked and calling Play. That number is the whole
-- of what this package controls. If it reads a fraction of a millisecond and
-- the bark still sounds late, the delay is inside the audio file and the only
-- fix is StartOffset.
--
-- To measure one, paste this into the Studio command bar with the id you want:
--
--     local s = Instance.new("Sound")
--     s.SoundId = "rbxassetid://95443426895855"
--     s.Parent = workspace
--     s.Loaded:Wait()
--     print("length", s.TimeLength)
--     s.TimePosition = 0.4   -- raise until the line starts on the instant
--     s:Play()
--
-- Step TimePosition until the very first syllable is audible immediately, then
-- put that number in StartOffset for the event. Go too far and you clip the
-- start of the word, so come back down until you can hear the whole thing.

return Config

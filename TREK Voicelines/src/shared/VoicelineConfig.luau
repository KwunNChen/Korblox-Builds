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
function Config.voiceKey(event: string): string
	local seen = {}

	while true do
		local cfg = Config.Events[event]
		if not cfg or not cfg.SharesWith or seen[event] then
			return event
		end
		seen[event] = true
		event = cfg.SharesWith
	end
end

-- The playable clips for an event, following SharesWith.
function Config.soundsFor(event: string): { string }
	local cfg = Config.Events[Config.voiceKey(event)]
	if not cfg then
		return {}
	end
	return Config.playableSounds(cfg.Sounds or {})
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
Config.RollOffMinDistance = 12
Config.RollOffMaxDistance = 140

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

-- At or below this fraction of a magazine, a reload triggers LowAmmo instead.
Config.LowAmmoFraction = 0.2

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

	-- Deliberately NOT near-zero. Time-to-kill is slow here, so you take a great
	-- many hits per life; without a real gap this becomes a constant whimper.
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
		Sounds = {"rbxassetid://95443426895855"},
	},

	-- Cooldown is moot: you die once per life, and Service.reset clears the
	-- channel on respawn.
	Death = {
		Priority = 10,
		Cooldown = 0,
		Chance = 1.0,
		Sounds = {"rbxassetid://3526632933", "rbxassetid://1869828588", "rbxassetid://101474734749359", "rbxassetid://140539866173088"},
	},
}

return Config

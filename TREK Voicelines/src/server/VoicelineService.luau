--!strict
-- Owns the one voice channel each character has: decides whether a requested
-- line is allowed to speak right now, and plays it if so.
--
-- Everything arrives here through request(). Hooks never touch Sound directly.

local Config = require(game:GetService("ReplicatedStorage")
	:WaitForChild("TREKVoicelines"):WaitForChild("VoicelineConfig"))

local Service = {}

--[[
	The falloff curve, resolved once at load.

	Two reasons this is not a direct `Enum.RollOffMode[Config.RollOffMode]` at
	playback time. It would run on every single bark for a value that never
	changes; and more importantly an unrecognised name THROWS rather than
	returning nil -- "The enum item 'X' does not exist" -- so the obvious
	`... or default` guard protects nothing and the error surfaces mid-bark,
	inside a Died or OnServerEvent handler, taking the rest of that handler with
	it. Walking GetEnumItems cannot throw.

	Setting this at all is the point: RollOffMode defaults to Inverse, which
	ignores RollOffMaxDistance completely.
]]
local ROLLOFF_MODE: Enum.RollOffMode = (function()
	for _, item in ipairs(Enum.RollOffMode:GetEnumItems()) do
		if item.Name == Config.RollOffMode then
			return item
		end
	end

	warn(string.format(
		"[TREKVoicelines] Config.RollOffMode %q is not a real RollOffMode -- using InverseTapered",
		tostring(Config.RollOffMode)
	))
	return Enum.RollOffMode.InverseTapered
end)()

type Channel = {
	busyUntil: number,
	playing: Sound?,
	priority: number,
	lastFired: { [string]: number },
	lastIndex: { [string]: number },
}

-- Keyed by character. Weak so a character that is destroyed without us hearing
-- about it cannot pin its channel in memory.
local channels: { [Model]: Channel } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Recently started barks, as { at, position }, newest last.

	Arbitration is otherwise entirely per character, so nothing stops twenty
	people in a push from shouting at once -- each one is obeying its own
	cooldown perfectly. This is the only state in the system that is global.

	Pruned on every append rather than on a timer, so it stays proportional to
	how much shouting is actually happening rather than to how long the server
	has been up.
]]
local recentBarks: { { at: number, position: Vector3, speaker: Model } } = {}

-- Prune expired entries in place and append the new one.
--
-- Entries are appended in time order, so everything expired is a prefix of the
-- list: find where the survivors start and shift them down. The previous version
-- built a whole replacement array (plus a fresh entry table) on every bark, and
-- discarded the old one -- garbage generated at exactly the moment the server is
-- busiest. The only allocation left is the entry itself.
local function noteBark(now: number, position: Vector3, speaker: Model)
	local cutoff = now - Config.CrowdWindow
	local count = #recentBarks

	local first = 1
	while first <= count and recentBarks[first].at <= cutoff do
		first += 1
	end

	local kept = 0
	if first > 1 then
		for i = first, count do
			kept += 1
			recentBarks[kept] = recentBarks[i]
		end
		for i = count, kept + 1, -1 do
			recentBarks[i] = nil
		end
	else
		kept = count
	end

	recentBarks[kept + 1] = { at = now, position = position, speaker = speaker }
end

--[[
	How many OTHER characters started a bark near this spot inside the window.

	The speaker's own recent lines are excluded deliberately. This gate exists
	because several voices at once are unintelligible; one voice saying two things
	in sequence is not that, and how often a single character may speak is already
	fully governed by Cooldown and by the channel. Counting your own last line
	against you was double jeopardy -- and it is what made Kill unreliable, since a
	kill always follows barks from the fight that produced it.
]]
-- Compares squared distances so the loop never takes a square root, and stops as
-- soon as the limit is reached rather than counting the whole list -- the caller
-- only ever asks whether the count has hit CrowdLimit.
local function nearbyBarkCount(now: number, position: Vector3, speaker: Model, limit: number): number
	local count = 0
	local radius = Config.CrowdRadius
	local radiusSq = radius * radius
	local cutoff = now - Config.CrowdWindow

	for i = 1, #recentBarks do
		local bark = recentBarks[i]
		if bark.speaker ~= speaker and bark.at > cutoff then
			local delta = bark.position - position
			if delta:Dot(delta) <= radiusSq then
				count += 1
				if count >= limit then
					return count
				end
			end
		end
	end

	return count
end

local function channelFor(character: Model): Channel
	local c = channels[character]
	if not c then
		c = { busyUntil = 0, playing = nil, priority = 0, lastFired = {}, lastIndex = {} }
		channels[character] = c
	end
	return c
end

-- Pick a clip, avoiding the one we used last time for this event. With a single
-- clip configured there is nothing to avoid and it just returns that one.
--
-- The roll is over the (n - 1) eligible slots and then steps over the excluded
-- one, which leaves every eligible clip equally likely. Rolling across all n and
-- nudging collisions onto the next slot would be simpler and wrong: it hands the
-- successor its own share plus the collision's, making it twice as likely as any
-- other clip -- and with exactly two clips it degenerates into strict alternation.
local function pickSound(channel: Channel, event: string, sounds: { any }): any
	if #sounds == 1 then
		return sounds[1]
	end

	local last = channel.lastIndex[event]
	local index

	if last and last <= #sounds then
		index = math.random(1, #sounds - 1)
		if index >= last then
			index += 1
		end
	else
		index = math.random(1, #sounds)
	end

	channel.lastIndex[event] = index
	return sounds[index]
end

-- Where the sound comes from. Living characters emit from the head so the line
-- tracks them. A death line cannot: TREK gibs the character, and a Sound whose
-- parent is destroyed stops instantly. So death gets a detached anchored part
-- parked where the head was.
local function emitterFor(character: Model, event: string): BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?

	if event ~= "Death" then
		return head
	end

	local origin = head or (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if not origin then
		return nil
	end

	local marker = Instance.new("Part")
	marker.Name = "VoicelineEmitter"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.new(1, 1, 1)
	marker.CFrame = origin.CFrame
	marker.Parent = workspace

	game:GetService("Debris"):AddItem(marker, Config.MaxLineLength + 1)
	return marker
end

local function release(channel: Channel, sound: Sound)
	-- Only the line that is actually current may free the channel. A clip that
	-- got preempted finishing late must not clear its replacement.
	if channel.playing ~= sound then
		return
	end

	channel.playing = nil
	channel.priority = 0
	channel.busyUntil = os.clock() + Config.GlobalCooldown
end

--[[
	Ask for a line. Returns true if it actually played.

	Refused when: the event is unknown or has no clips, its own cooldown has not
	elapsed, the chance roll fails, or something of equal or higher priority is
	already speaking.
]]
function Service.request(character: Model, event: string): boolean
	--[[
		Ordered cheapest-reject-first, and the order is load-bearing.

		Everything down to the cooldown check is now plain table lookups and
		arithmetic: no Roblox API call, no allocation. That matters because most
		requests in a firefight are REFUSED -- Hurt fires on every damaging hit but
		speaks once per cooldown -- so the refusal path is the hot one, and it
		should cost as close to nothing as possible.

		The workspace descendancy test used to run first. It is a C-side ancestor
		walk, and it was being paid by requests that a one-line table lookup was
		about to reject anyway.
	]]
	local cfg = Config.Events[event]
	if not cfg then
		return false
	end

	-- Placeholders and malformed entries are stripped here, so a partly-filled
	-- list never spends a turn on a clip that cannot play. Memoised in Config, so
	-- this is a table lookup rather than a re-parse of every id.
	local sounds = Config.soundsFor(event)
	if #sounds == 0 then
		return false
	end

	-- Events sharing a voice share their cooldown and no-repeat memory too, so
	-- LowAmmo followed by Reload cannot repeat a line or talk over itself.
	local voice = Config.voiceKey(event)

	if typeof(character) ~= "Instance" then
		return false
	end

	local existing = channels[character]
	local now = os.clock()

	-- Cooldown before the descendancy walk. This refusal is the single most
	-- common outcome of the whole function, and checking it needs nothing but the
	-- channel this character already has.
	if existing then
		local lastFired = existing.lastFired[voice]
		if lastFired and now - lastFired < cfg.Cooldown then
			return false
		end
	end

	if not character:IsDescendantOf(workspace) then
		return false
	end

	local channel = existing or channelFor(character)

	-- A concurrent event sits outside the one-voice-at-a-time rule: it layers
	-- over whatever is already speaking instead of waiting for or interrupting
	-- it. Priority is meaningless for these -- they neither block nor are
	-- blocked -- but Cooldown and Chance still apply.
	local concurrent = cfg.Concurrent == true

	if not concurrent then
		if channel.playing then
			-- Strictly greater, so two equal-priority events cannot trade the
			-- channel back and forth mid-line.
			if cfg.Priority <= channel.priority then
				return false
			end
			channel.playing:Stop()
			channel.playing:Destroy()
			channel.playing = nil
		elseif now < channel.busyUntil then
			-- Inside the post-line quiet window. Death is the one thing urgent
			-- enough to ignore it.
			if event ~= "Death" then
				return false
			end
		end
	end

	-- Crowd gate. Placed after the cooldown check so a refused bark costs
	-- nothing, and before the chance roll so a dropped bark does not also burn
	-- the cooldown -- the speaker should still be able to talk once the noise
	-- around them dies down.
	local speakerRoot = character:FindFirstChild("HumanoidRootPart")
	if not cfg.IgnoresCrowd and speakerRoot and speakerRoot:IsA("BasePart") then
		local limit = Config.CrowdLimit
		if nearbyBarkCount(now, speakerRoot.Position, character, limit) >= limit then
			return false
		end
	end

	if cfg.Chance < 1 and math.random() > cfg.Chance then
		-- A failed roll still counts as fired, otherwise the next tick of a
		-- continuous event (taking fire) just rolls again immediately.
		channel.lastFired[voice] = now
		return false
	end

	local emitter = emitterFor(character, event)
	if not emitter then
		return false
	end

	local sound = Instance.new("Sound")
	sound.Name = "Voiceline_" .. event
	sound.SoundId = pickSound(channel, voice, sounds)
	sound.Volume = Config.Volume
	sound.RollOffMinDistance = Config.RollOffMinDistance
	sound.RollOffMaxDistance = Config.RollOffMaxDistance

	sound.RollOffMode = ROLLOFF_MODE
	sound.Parent = emitter

	channel.lastFired[voice] = now

	if speakerRoot and speakerRoot:IsA("BasePart") then
		noteBark(now, speakerRoot.Position, character)
	end

	if concurrent then
		-- Deliberately never touches channel.playing or busyUntil: it must not
		-- occupy the voice, or it would block the very lines it is meant to
		-- layer over. Cleans up after itself instead of going through release.
		sound.Ended:Once(function()
			sound:Destroy()
		end)

		task.delay(Config.MaxLineLength, function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
	else
		channel.playing = sound
		channel.priority = cfg.Priority
		channel.busyUntil = now + Config.MaxLineLength

		sound.Ended:Once(function()
			release(channel, sound)
			sound:Destroy()
		end)

		-- Backstop. Ended never fires for an id that fails to load, and it is
		-- also disconnected outright if the emitter is destroyed mid-line --
		-- TREK gibbing a head does exactly that.
		--
		-- release() is therefore called unconditionally. Guarding it on
		-- sound.Parent, as this once did, skipped precisely the case it existed
		-- for: a destroyed Sound is still truthy in channel.playing, so the
		-- channel stayed occupied at that priority forever and the character
		-- could never speak below it again.
		task.delay(Config.MaxLineLength, function()
			release(channel, sound)
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end

	sound:Play()

	-- Leading silence in the recording is skipped here rather than by asking
	-- anyone to re-export the file.
	--
	-- Set AFTER Play, not before. Play() seeks the stream to the start, so an
	-- offset written first is overwritten by the call meant to honour it -- the
	-- kind of bug that reads as "StartOffset does nothing".
	-- Read off the VOICE, not the event. The clips came from the voice owner via
	-- soundsFor, so the lead-in to trim is the voice owner's too: LowAmmo speaks
	-- Reload's recordings and must skip whatever Reload skips.
	local voiceCfg = Config.Events[voice]
	local offset = voiceCfg and voiceCfg.StartOffset
	if offset and offset > 0 then
		sound.TimePosition = offset
	end

	-- What this package actually cost, measured from the moment it was asked.
	--
	-- Worth reporting because a late bark has two possible homes and they need
	-- telling apart: the path that decides and starts the line, and the clip
	-- itself. This number is the whole of the first one. If it is a fraction of
	-- a millisecond and a bark still sounds late, the lateness is baked into the
	-- audio and StartOffset is the only thing that will move it.
	if Config.Debug then
		warn(string.format(
			"[TREKVoicelines] played %s on %s -- %.3f ms from request to Play",
			event,
			character.Name,
			(os.clock() - now) * 1000
		))
	end

	return true
end

-- Drop a character's channel. Called on respawn so a new life starts clean.
function Service.reset(character: Model)
	local channel = channels[character]
	if channel and channel.playing then
		channel.playing:Destroy()
	end
	channels[character] = nil
end

return Service

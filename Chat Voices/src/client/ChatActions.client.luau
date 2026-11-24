-- ChatActions: formats player chat like a novel.
--   please *he begs*          ->  "Please," he begs.
--   c'mon! *he yells*         ->  "C'mon!" he yells.
--   *he sighs* fine           ->  He sighs. "Fine"
--   where are we?             ->  "Where are we?" PlagueByte asks.   (auto tag)
-- Speech gets quotes and a capital letter; *text* is a grey italic action.
-- Plain speech with no *action* gets a tag picked from its last punctuation.
-- Roblox allows only one OnIncomingMessage per client: merge with any other chat-tag script.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ACTION_FORMAT = '<i><font color="#8A8A8A">%s</font></i>'

-- auto tag verbs, chosen by how the message ends
local TAGS = {
	question = { "asks", "questions", "wonders", "inquires", "asks aloud" },
	exclaim = { "yells", "shouts", "exclaims", "calls out", "barks" },
	trail = { "trails off", "mutters", "murmurs", "hesitates" },
	say = { "says", "states", "remarks", "replies", "notes" },
}

-- same message -> same verb on every client (a per-client random would disagree)
local function pick(list: { string }, seed: string): string
	local h = 0
	for i = 1, #seed do
		h = (h * 31 + seed:byte(i)) % 2147483647
	end
	return list[h % #list + 1]
end

local function autoTag(speech: string, name: string, seed: string): string
	local kind
	if speech:find("%?[!?]*$") then
		kind = "question"
	elseif speech:find("!$") then
		kind = "exclaim"
	elseif speech:find("%.%.%.$") or speech:find("…$") then
		kind = "trail"
	else
		kind = "say"
		speech = speech:gsub("%.$", "") .. "," -- "Okay," Name says.
	end
	return '"' .. speech .. '" ' .. ACTION_FORMAT:format(name .. " " .. pick(TAGS[kind], seed) .. ".")
end

local function trim(s: string): string
	return s:match("^%s*(.-)%s*$")
end

local function capitalize(s: string): string
	return s:sub(1, 1):upper() .. s:sub(2)
end

local function format(text: string, name: string?, seed: string?): string
	-- split into speech / action segments, dropping empty ones
	local segments = {}
	local function add(kind: string, s: string)
		s = trim(s)
		if s ~= "" then table.insert(segments, { kind = kind, text = s }) end
	end
	local pos = 1
	for startPos, action, endPos in text:gmatch("()%*(.-)%*()") do
		add("say", text:sub(pos, startPos - 1))
		add("act", action)
		pos = endPos
	end
	add("say", text:sub(pos))

	if name and #segments == 1 and segments[1].kind == "say" then
		return autoTag(capitalize(segments[1].text), name, seed or text)
	end

	local parts = {}
	for i, seg in segments do
		local t = seg.text
		local nextSeg = segments[i + 1]
		if seg.kind == "say" then
			t = capitalize(t)
			if nextSeg and nextSeg.kind == "act" and not t:find("[,!?]$") and not t:find("%.%.%.$") then
				t = t:gsub("%.$", "") .. "," -- "Please," he begs.
			end
			table.insert(parts, '"' .. t .. '"')
		else
			if i == 1 then t = capitalize(t) end
			if not t:find("[%.!?,]$") then t ..= "." end
			table.insert(parts, ACTION_FORMAT:format(t))
		end
	end
	return table.concat(parts, " ")
end

TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	if not message.TextSource then return end -- system messages stay as they are
	local first = message.Text:sub(1, 1)
	if first == "/" or first == ":" then return end -- commands
	local speaker = Players:GetPlayerByUserId(message.TextSource.UserId)
	local properties = Instance.new("TextChatMessageProperties")
	properties.Text = format(message.Text, speaker and speaker.DisplayName, message.MessageId)
	return properties
end

local chatter = {}

local Players = game:GetService("Players")

local modules = script.Parent
local status = require(modules.Status)
local core = require(modules.CoreModule)
local radioNet = require(modules.RadioModule)
local lines = require(modules.ChatterLines)
--Special operations (SofModule calls useTactical) speak only ChatterSof's clipped lines, and make no small talk.
local tactical = false
local banter = require(modules.ChatterBanter)

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local myHead = marine.Head
local myHuman = marine.Humanoid

local mySettings = marine.Settings
local teamValue = mySettings.Team
local detectionRange = mySettings.DetectionRange
local chatterValue = mySettings:FindFirstChild("Chatter")

--Studs a radio call carries.
local HEARING_RANGE = 70

--Studs gunfire carries. Every ally this close to a soldier who opens fire joins
--the fight, whether chatter is on or not.
local GUNFIRE_HEARING = 150

--Seconds quiet after speaking. Lines tied to what the soldier is doing right now
--(reload, grenade, hit, kill) only need the short gap.
local LINE_COOLDOWN = 2.5
local ACTION_COOLDOWN = 1

--Seconds a bubble stays up.
local BUBBLE_TIME = 3

--Seconds before an ally answers a call, min and max.
local REPLY_DELAY_MIN = 0.7
local REPLY_DELAY_MAX = 1.6

--How long a busy soldier keeps waiting to say something before dropping it.
local REPLY_PATIENCE = 3

--Chance the nearest ally answers a call.
local REPLY_CHANCE = 0.6

--Chance of picking a situation-specific line over a plain one, when one fits.
local SPECIFIC_CHANCE = 0.65

--What counts as far, close, a group, or low health.
local FAR_RANGE = 90
local CLOSE_RANGE = 35
local MANY_ENEMIES = 3
local LOW_HEALTH = 0.35

--Idle talk: seconds between attempts (min, max), how close a partner must be,
--and seconds between the turns of a conversation.
local IDLE_MIN = 20
local IDLE_MAX = 45
local BANTER_RANGE = 25
local TURN_GAP_MIN = 2.8
local TURN_GAP_MAX = 3.8

--Chance an idle soldier with nobody close mutters to himself.
local SOLO_CHANCE = 0.5

--Radio reports (chatter.radio): the radio chatter played with one, its volume, how
--far the noise and text carry, and studs per map grid square.
local RADIO_SOUND = "rbxassetid://139540720"
local RADIO_VOLUME = 0.5
local RADIO_HEARING = 150
local GRID_SIZE = 100

local COMPASS = {"north","northeast","east","southeast","south","southwest","west","northwest"}

local CLOCK_WORDS = {"twelve","one","two","three","four","five","six","seven","eight","nine","ten","eleven"}

--Every soldier in the server registers here so calls can reach the others.
_G.BloxianRadio = _G.BloxianRadio or {}
local radio = _G.BloxianRadio

--Never the same entry twice in a row from one list.
local lastPicked = {}
local function pick(list)
	local index = math.random(#list)
	if index == lastPicked[list] and #list > 1 then
		index = index % #list + 1
	end
	lastPicked[list] = index
	return list[index]
end

local function textOf(entry)
	return type(entry) == "string" and entry or entry.text or entry[1]
end

--Swaps {clock}, {dist} and {n} for what this soldier actually saw.
local function fill(text,ctx)
	return (text:gsub("{(%w+)}",function(key)
		local value = ctx and ctx[key]
		return value ~= nil and tostring(value) or "over there"
	end))
end

--Picks from a situation-specific pool when tags apply, else the plain "any" pool.
local function chooseEntry(group,tags)
	local pool = group.any
	if #tags > 0 and math.random() < SPECIFIC_CHANCE then
		pool = group[tags[math.random(#tags)]]
	end
	return pick(pool)
end

local function enabled()
	return not chatterValue or chatterValue.Value
end

--Hands full: reloading, mid-burst, throwing, stabbing, drawing a weapon.
--Idle talk and answers wait for this to end.
local function isBusy()
	return status:get("reloading") or not status:get("weaponCool") or status:get("actionDepth") > 0
end

--Alive, no target, and not doing anything. The only time soldiers make small talk.
local function isIdle()
	return myHuman.Health > 0 and not status:get("currentTarget") and not isBusy()
end

local bubble
local bubbleLabel
local bubbleToken = 0
--Studs a speech bubble shows from (a radio report carries further, RADIO_HEARING).
local BUBBLE_DISTANCE = 80
local function showBubble(text,maxDistance)
	if not bubble then
		bubble = Instance.new("BillboardGui")
		bubble.Name = "Chatter"
		bubble.Adornee = myHead
		bubble.Size = UDim2.fromOffset(220,40)
		bubble.StudsOffset = Vector3.new(0,2.6,0)
		bubble.ResetOnSpawn = false
		bubble.Enabled = false

		bubbleLabel = Instance.new("TextLabel")
		bubbleLabel.Size = UDim2.fromScale(1,1)
		bubbleLabel.BackgroundColor3 = Color3.fromRGB(20,20,20)
		bubbleLabel.BackgroundTransparency = 0.3
		bubbleLabel.TextColor3 = Color3.fromRGB(235,235,235)
		bubbleLabel.Font = Enum.Font.Code
		bubbleLabel.TextScaled = true
		bubbleLabel.Parent = bubble

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0,6)
		corner.Parent = bubbleLabel

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0,6)
		padding.PaddingRight = UDim.new(0,6)
		padding.PaddingTop = UDim.new(0,3)
		padding.PaddingBottom = UDim.new(0,3)
		padding.Parent = bubbleLabel

		bubble.Parent = myHead
	end

	bubbleLabel.Text = text
	bubble.MaxDistance = maxDistance or BUBBLE_DISTANCE
	bubble.Enabled = true

	bubbleToken += 1
	local token = bubbleToken
	task.delay(BUBBLE_TIME,function()
		if token == bubbleToken then
			bubble.Enabled = false
		end
	end)
end

--own: the line is part of what the soldier is doing right now, so being busy does not block it.
local lastSpoke = -math.huge
function chatter.say(text,own)
	--A stalking guerrilla says nothing at all.
	if not enabled() or myHuman.Health <= 0 or status:get("stealth") then
		return false
	end
	if not own and isBusy() then
		return false
	end

	local now = os.clock()
	if now - lastSpoke < (own and ACTION_COOLDOWN or LINE_COOLDOWN) then
		return false
	end

	lastSpoke = now
	showBubble(text)
	return true
end

--Waits for the soldier to stop being busy, gives up when it takes too long.
function chatter.sayWhenFree(text)
	local deadline = os.clock() + REPLY_PATIENCE
	while os.clock() < deadline and myHuman.Health > 0 do
		if chatter.say(text) then
			return true
		end
		task.wait(0.25)
	end
	return false
end

local function nearbyAllies(range)
	local list = {}
	for other,entry in pairs(radio) do
		if other ~= marine and entry.root.Parent and entry.human.Health > 0 and entry.team.Value == teamValue.Value then
			local dist = (entry.root.Position - myRoot.Position).Magnitude
			if dist <= range then
				list[#list+1] = {entry = entry, dist = dist}
			end
		end
	end
	table.sort(list,function(a,b) return a.dist < b.dist end)
	return list
end

--Tells the allies in earshot. The nearest replyCount of them are asked to answer.
local function broadcast(kind,packet,replyCount)
	if not enabled() then return end

	for i,heard in ipairs(nearbyAllies(HEARING_RANGE)) do
		heard.entry.hear(kind,packet,i <= replyCount and i or nil)
	end
end

local function randomDelay()
	return REPLY_DELAY_MIN + math.random()*(REPLY_DELAY_MAX - REPLY_DELAY_MIN)
end

--What this soldier does when it hears a call from someone else.
local function hear(kind,packet,rank)
	if myHuman.Health <= 0 then return end

	local engaged = status:get("currentTarget") and true or false

	--A spotted target is shared: he now knows where it is, and idle soldiers turn to face it.
	local hostile = packet.target and packet.target.Parent and not core.isAlly(packet.target.Parent)
	if kind == "spotted" and hostile then
		core.markSeen(packet.target)
	end
	if kind == "spotted" and not engaged and hostile then
		if (packet.target.Position - myRoot.Position).Magnitude <= detectionRange.Value then
			status:set("currentTarget",packet.target)
		end
	end

	if not rank then return end

	--The answer is chosen to fit the call: the line's own answers if it has
	--them, otherwise the kind's.
	local answer
	if kind == "manDown" then
		answer = pick(rank == 1 and lines.calls.manDown.any or lines.replies.manDown)
	else
		local pool = not tactical and type(packet.entry) == "table" and packet.entry.replies
		if not pool or #pool == 0 then
			pool = lines.replies[kind]
			if kind == "spotted" and pool then
				pool = engaged and pool.engaged or pool.fresh
			end
		end
		if not pool or #pool == 0 then return end
		answer = pick(pool)
	end

	local text = fill(textOf(answer),packet.ctx)
	task.delay(randomDelay(),function()
		if chatter.sayWhenFree(text) and type(answer) == "table" and answer.back then
			--The original caller follows up on a question.
			local back = fill(pick(answer.back),packet.ctx)
			task.delay(randomDelay(),function()
				packet.speaker.sayWhenFree(back)
			end)
		end
	end)
end

--An ally is shooting at target: now he knows where it is, and takes it on if he
--has nothing else to fight.
local function takeContact(target)
	if myHuman.Health <= 0 or not target or not target.Parent or core.isAlly(target.Parent) then return end
	core.markSeen(target)
	local current = status:get("currentTarget")
	if not current or not current.Parent then
		status:set("currentTarget",target)
	end
end

local chatting = false
radio[marine] = {
	root = myRoot,
	human = myHuman,
	team = teamValue,
	hear = hear,
	alert = takeContact,
	isIdle = isIdle,
	say = chatter.say,
	sayWhenFree = chatter.sayWhenFree,
	isChatting = function() return chatting end,
	setChatting = function(value) chatting = value end,
}
marine.Destroying:Connect(function()
	radio[marine] = nil
end)

local function call(kind,entry,ctx,replyCount)
	--Callouts are for squadmates. Alone, shouting them only gives him away.
	local spoke = #nearbyAllies(HEARING_RANGE) > 0 and chatter.say(fill(textOf(entry),ctx),true)
	broadcast(kind,{
		entry = entry,
		ctx = ctx,
		target = ctx and ctx.target,
		speaker = radio[marine],
	},spoke and replyCount or 0)
end

local function roll()
	return math.random() < REPLY_CHANCE and 1 or 0
end

--Where the target is relative to this soldier, as a clock position and a distance.
--On a radio net, a contact goes to every squad on it, however far apart.
local function relayContact(target)
	for _,entry in ipairs(radioNet.netMembers()) do
		if entry.alert then
			entry.alert(target)
		end
	end
end

local function describeTarget(target)
	local offset = myRoot.CFrame:PointToObjectSpace(target.Position)
	local degrees = (math.deg(math.atan2(offset.X,-offset.Z)) + 360) % 360
	local hour = math.floor(degrees/30 + 0.5) % 12
	local distance = (target.Position - myRoot.Position).Magnitude
	local count = math.max(#status:get("potentialTargets"),1)

	return {
		target = target,
		clock = CLOCK_WORDS[hour + 1],
		distance = distance,
		dist = math.floor(distance/10 + 0.5)*10,
		count = count,
		n = count,
		isPlayer = Players:GetPlayerFromCharacter(target.Parent) ~= nil,
	}
end

function chatter.spotted(target)
	relayContact(target)

	--Alone, there is nobody to warn, and shouting would give him away.
	if #nearbyAllies(HEARING_RANGE) == 0 then return end

	local ctx = describeTarget(target)
	local tags = {"clock"}
	if ctx.distance > FAR_RANGE then tags[#tags+1] = "far" end
	if ctx.distance < CLOSE_RANGE then tags[#tags+1] = "close" end
	if ctx.count >= MANY_ENEMIES then tags[#tags+1] = "many" end
	if ctx.isPlayer then tags[#tags+1] = "player" end

	call("spotted",chooseEntry(lines.calls.spotted,tags),ctx,roll())
end

--The map grid square of a position, like "503-498".
local function gridOf(position)
	return string.format("%03d-%03d",(math.floor(position.X/GRID_SIZE) + 500) % 1000,(math.floor(position.Z/GRID_SIZE) + 500) % 1000)
end

--A radio report on target, with its grid, compass direction and distance from him:
--radio chatter with it. Heard even while stalking; nobody answers it.
local radioSound
function chatter.radio(kind,target)
	if not enabled() or myHuman.Health <= 0 or not target or not target.Parent then return end
	local ctx = describeTarget(target)
	local offset = target.Position - myRoot.Position
	ctx.grid = gridOf(target.Position)
	ctx.compass = COMPASS[math.floor(((math.deg(math.atan2(offset.X,-offset.Z)) + 360) % 360)/45 + 0.5) % 8 + 1]

	if not radioSound then
		radioSound = Instance.new("Sound")
		radioSound.Name = "RadioChatter"
		radioSound.SoundId = RADIO_SOUND
		radioSound.Volume = RADIO_VOLUME
		radioSound.RollOffMaxDistance = RADIO_HEARING
		radioSound.Parent = myHead
	end
	radioSound:Play()

	lastSpoke = os.clock()
	showBubble(fill(textOf(pick(lines.calls[kind].any)),ctx),RADIO_HEARING)
end

--He sees an enemy vehicle (part is the part he sees). hasAT: an at team on
--his side is near enough to come for it.
function chatter.armor(part,hasAT)
	local kind = hasAT and "armorAT" or "armor"
	call(kind,pick(lines.calls[kind].any),describeTarget(part),roll())
end

function chatter.reload()
	local target = status:get("currentTarget")
	local tags = {}
	if target and target.Parent and (target.Position - myRoot.Position).Magnitude < CLOSE_RANGE + 5 then
		tags[1] = "close"
	end
	call("reload",chooseEntry(lines.calls.reload,tags),nil,roll())
end

function chatter.grenade()
	call("grenade",pick(lines.calls.grenade.any),nil,roll())
end

function chatter.hit()
	local low = myHuman.Health/myHuman.MaxHealth < LOW_HEALTH
	if low or math.random(3) == 1 then
		call("hit",chooseEntry(lines.calls.hit,low and {"low"} or {}),nil,roll())
	end
end

--how: "knife" when it was a stabbing
function chatter.kill(how)
	if math.random(2) == 1 then
		call("kill",chooseEntry(lines.calls.kill,how == "knife" and {"knife"} or {}),nil,roll())
	end
end

function chatter.cover()
	if math.random() < 0.6 then
		call("cover",pick(lines.calls.cover.any),nil,roll())
	end
end

function chatter.advance()
	call("advance",pick(lines.calls.advance.any),nil,roll())
end

--Called each time he opens fire: every ally within earshot of the shots engages.
function chatter.shareContact(target)
	if not target or not target.Parent then return end
	for other,entry in pairs(radio) do
		if other ~= marine and entry.alert and entry.root.Parent and entry.human.Health > 0
			and entry.team.Value == teamValue.Value
			and (entry.root.Position - myRoot.Position).Magnitude <= GUNFIRE_HEARING then
			entry.alert(target)
		end
	end
	relayContact(target)
end

--Any call from lines.calls[kind]: squad orders, rushes. chance: odds it is said at all.
function chatter.callout(kind,ctx,chance)
	local group = lines.calls[kind]
	if not group or (chance and math.random() >= chance) then return end
	call(kind,pick(group.any),ctx,lines.replies[kind] and roll() or 0)
end

--The target slipped away without dying.
function chatter.lost()
	if math.random(2) == 1 then
		call("lost",pick(lines.calls.lost.any),nil,roll())
	end
end

--Called as this soldier dies. The nearest two react, one after the other.
function chatter.died()
	broadcast("manDown",{speaker = radio[marine]},2)
end

--Plays out a written thread between this soldier and a partner, turn by turn.
local function converse(partner,thread)
	chatting = true
	partner.setChatting(true)

	for i,text in ipairs(thread) do
		local said
		if i % 2 == 1 then
			said = chatter.say(text)
		else
			said = partner.say(text)
		end
		if not said then break end

		task.wait(TURN_GAP_MIN + math.random()*(TURN_GAP_MAX - TURN_GAP_MIN))

		--Anything happening ends the chat right where it stands.
		local close = (partner.root.Position - myRoot.Position).Magnitude <= BANTER_RANGE * 1.5
		if i < #thread and not (isIdle() and partner.isIdle() and close) then
			break
		end
	end

	chatting = false
	partner.setChatting(false)
end

task.spawn(function()
	while myHuman.Health > 0 and marine.Parent do
		task.wait(IDLE_MIN + math.random()*(IDLE_MAX - IDLE_MIN))

		if enabled() and not tactical and isIdle() and not chatting then
			local nearby = nearbyAllies(BANTER_RANGE * 2)
			local partner
			for _,heard in ipairs(nearby) do
				if heard.dist <= BANTER_RANGE and heard.entry.isIdle() and not heard.entry.isChatting() then
					partner = heard.entry
					break
				end
			end

			if partner then
				converse(partner,pick(banter))
			elseif #nearby == 0 and math.random() < SOLO_CHANCE then
				chatter.say(pick(lines.solo))
			end
		end
	end
end)

function chatter.useTactical()
	tactical = true
	lines = require(modules.ChatterSof)
end

return chatter

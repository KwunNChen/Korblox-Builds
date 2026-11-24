--[[
	Openings: moments an enemy player can't fight back properly, reloading or
	healing, and what a soldier does when he hears one.

	One watcher per server (the first soldier to load starts it) marks a
	player's character as reloading or healing from whatever reaches the server:
		- an animation playing on him whose name has "reload", or "heal",
		  "bandage", "medkit" or "inject" in it
		- a sound in his character or tools with one of those words in its name
		  starting to play
		- a Reloading or Healing attribute set true on his character or tool,
		  for gun systems that publish it
		- his health jumping up by HEAL_JUMP or more at once (a medkit; the
		  default regeneration is far smaller)

	A soldier who sees him, or is within earshot (Settings.HearingRange), and
	knows the opening:
		- close enough to make it (PUSH_RANGE): calls it ("He's reloading,
		  push!") and pushes, whatever the numbers, until it closes
		- further off: tops off his own magazine if it is below TOP_OFF_SHARE
]]

local openings = {}

local Players = game:GetService("Players")

local modules = script.Parent
local core = require(modules.CoreModule)
local status = require(modules.Status)
local chatter = require(modules.ChatterModule)
local weapon = require(modules.WeaponProfiles).current
local actions = require(modules.ActionsModule)
local log = require(modules.Troubleshoot).log

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local hearingValue = marine.Settings:FindFirstChild("HearingRange")

--Seconds an opening lasts from its last sign, for a reload and for healing.
local RELOAD_WINDOW = 2.5
local HEAL_WINDOW = 3

--A jump in health this big at once counts as healing.
local HEAL_JUMP = 15

--Within this many studs he pushes into an opening; further off he tops off
--his own magazine if it is under TOP_OFF_SHARE full.
local PUSH_RANGE = 90
local TOP_OFF_SHARE = 0.7

--Words in an animation's, sound's or tool's name that give him away.
local RELOAD_WORDS = {"reload"}
local HEAL_WORDS = {"heal", "bandage", "medkit", "inject", "syringe"}

local DEFAULT_HEARING_RANGE = 120

-- Server-wide watcher -------------------------------------------------------

_G.BloxianOpenings = _G.BloxianOpenings or {}
local marks = _G.BloxianOpenings

local function kindOf(name)
	name = string.lower(name)
	for _,word in ipairs(RELOAD_WORDS) do
		if string.find(name,word,1,true) then return "reloading" end
	end
	for _,word in ipairs(HEAL_WORDS) do
		if string.find(name,word,1,true) then return "healing" end
	end
	return nil
end

local function mark(character,kind,seconds)
	marks[character] = {kind = kind, untilTime = os.clock() + (seconds or (kind == "reloading" and RELOAD_WINDOW or HEAL_WINDOW))}
end

--Equipping re-adds a tool and its sounds to the character: each is watched once.
local watched = setmetatable({},{__mode = "k"})

local function watchSound(character,sound)
	local kind = kindOf(sound.Name)
	if not kind or watched[sound] then return end
	watched[sound] = true
	sound:GetPropertyChangedSignal("Playing"):Connect(function()
		if sound.Playing then
			mark(character,kind)
		end
	end)
end

local function watchFlags(character,holder)
	if watched[holder] then return end
	watched[holder] = true
	for _,attribute in ipairs({"Reloading","Healing"}) do
		holder:GetAttributeChangedSignal(attribute):Connect(function()
			if holder:GetAttribute(attribute) == true then
				mark(character,attribute == "Reloading" and "reloading" or "healing",30)
			elseif marks[character] then
				marks[character] = nil
			end
		end)
	end
end

local function watchCharacter(character)
	local human = character:WaitForChild("Humanoid",10)
	if not human then return end
	watchFlags(character,character)

	local animator = human:WaitForChild("Animator",10)
	if animator then
		animator.AnimationPlayed:Connect(function(track)
			local kind = kindOf(track.Name) or (track.Animation and kindOf(track.Animation.Name))
			if kind then
				mark(character,kind,math.max(track.Length,1))
			end
		end)
	end

	local health = human.Health
	human.HealthChanged:Connect(function(now)
		if now - health >= HEAL_JUMP then
			mark(character,"healing")
		end
		health = now
	end)

	for _,item in ipairs(character:GetDescendants()) do
		if item:IsA("Sound") then
			watchSound(character,item)
		elseif item:IsA("Tool") then
			watchFlags(character,item)
		end
	end
	character.DescendantAdded:Connect(function(item)
		if item:IsA("Sound") then
			watchSound(character,item)
		elseif item:IsA("Tool") then
			watchFlags(character,item)
		end
	end)
	character.Destroying:Connect(function()
		marks[character] = nil
	end)
end

--The watchers die with the soldier who set them up, so the next one takes over.
local function ensureWatching()
	local owner = _G.BloxianOpeningsOwner
	if owner and owner.Parent then return end
	_G.BloxianOpeningsOwner = marine
	local function watchPlayer(player)
		if player.Character then
			task.spawn(watchCharacter,player.Character)
		end
		player.CharacterAdded:Connect(watchCharacter)
	end
	for _,player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end
ensureWatching()

-- Per soldier ---------------------------------------------------------------

--"reloading" or "healing" if root's owner is in the middle of one, else nil.
function openings.of(root)
	local character = root and root.Parent
	local entry = character and marks[character]
	if entry and os.clock() < entry.untilTime then
		return entry.kind
	end
	return nil
end

local pushing = false
local calledFor = nil

--Whether he should push his target right now because of an opening he knows about.
function openings.pushing()
	return pushing
end

--Looks for an opening on his target. Called from the target loop.
function openings.update()
	ensureWatching()
	local target = status:get("currentTarget")
	local kind = target and target.Parent and openings.of(target)
	if not kind then
		pushing = false
		calledFor = nil
		return
	end

	local dist = core.checkDist(myRoot,target)
	local earshot = hearingValue and hearingValue.Value or DEFAULT_HEARING_RANGE
	if dist > earshot and not core.checkSight(target) then
		pushing = false
		return
	end

	local opening = target.Parent
	if dist <= PUSH_RANGE then
		if not pushing then
			log("openings","enemy "..kind..", pushing")
			if calledFor ~= opening then
				calledFor = opening
				chatter.callout(kind == "reloading" and "enemyReloading" or "enemyHealing",nil,0.6)
			end
		end
		pushing = true
	else
		pushing = false
		if not status:get("reloading") and status:get("mag") < weapon.magSize*TOP_OFF_SHARE then
			log("openings","enemy "..kind..", topping off")
			task.spawn(actions.reload)
		end
	end
end

return openings

--[[
	SkiService
	Who has skis, and whether they are on their feet or on their back.

	The gear itself is built by SkiGear. This file owns the Tool, the equip
	state, and the walk penalty -- all of which were already working before the
	rebuild and are deliberately unchanged.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SkiFolder = ReplicatedStorage:WaitForChild("Ski")
local Config = require(SkiFolder:WaitForChild("SkiConfig"))
local Shared = require(SkiFolder:WaitForChild("SkiShared"))

local SkiGear = require(script.Parent:WaitForChild("SkiGear"))
local SkiRagdoll = require(script.Parent:WaitForChild("SkiRagdoll"))

local Attr = Shared.Attr

-- SpeedService is the only thing allowed to write WalkSpeed. If Common is
-- missing the install is broken, but a broken speed penalty shouldn't take the
-- rest of the system down with it.
local SpeedService
do
	local common = ServerScriptService:FindFirstChild("Common")
	local module = common and common:FindFirstChild("SpeedService")
	if module then
		SpeedService = require(module)
	else
		warn("[Ski] ServerScriptService.Common.SpeedService missing -- skis will not slow walking. See install step 3.")
	end
end

local MODIFIER_NAME = "Ski"

local SkiService = {}

local equipped: { [Player]: boolean } = {}
local equipEvent: RemoteEvent

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

-- ============================================================
-- THE TOOL
-- ============================================================

-- RequiresHandle is off because the skis are welded to the character, not
-- carried in a hand. The Tool is a control token: something in the hotbar so
-- equipping has somewhere to live.
local function makeTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = Config.ToolName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Strap in."
	return tool
end

function SkiService.setEquipped(player: Player, isEquipped: boolean)
	if equipped[player] == isEquipped then
		return
	end
	equipped[player] = isEquipped

	local character = player.Character
	if not character then
		return
	end

	character:SetAttribute(Attr.Equipped, isEquipped)
	SkiGear.setStowed(character, not isEquipped)

	-- Only slows you while the skis are actually on your feet. Carrying them on
	-- your back should walk at normal speed.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if SpeedService and humanoid then
		if isEquipped then
			SpeedService.setModifier(humanoid, MODIFIER_NAME, { mul = Config.WalkSpeedMultiplier })
		else
			SpeedService.clearModifier(humanoid, MODIFIER_NAME)
		end
	end

	if equipEvent then
		equipEvent:FireClient(player, isEquipped)
	end

	log("%s skis %s", player.Name, isEquipped and "on" or "off")
end

local function bindTool(player: Player, tool: Tool)
	tool.Equipped:Connect(function()
		SkiService.setEquipped(player, true)
	end)

	tool.Unequipped:Connect(function()
		SkiService.setEquipped(player, false)
	end)

	-- Dying while equipped never fires Unequipped, so the flag would stick and
	-- the next character would spawn believing it already had skis on.
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			SkiService.setEquipped(player, false)
		end
	end)
end

function SkiService.giveTool(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild(Config.ToolName) then
		return
	end

	local character = player.Character
	if character and character:FindFirstChild(Config.ToolName) then
		return
	end

	local tool = makeTool()
	bindTool(player, tool)
	tool.Parent = backpack
end

-- ============================================================
-- TRIGGERS
-- ============================================================

local zoneCooldown: { [Player]: number } = {}

--[[
	Every trigger -- the Tool, the keybind, a zone you walk into -- comes through
	here, and where possible it works by actually equipping the Tool rather than
	setting the flag behind its back. That keeps one source of truth: press G and
	the hotbar slot lights up, unequip from the hotbar and the keybind agrees.

	Pass nil for isEquipped to toggle.
]]
function SkiService.request(player: Player, isEquipped: boolean?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local target = if isEquipped == nil then not equipped[player] else isEquipped
	if target == equipped[player] then
		return
	end

	if target then
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tool = backpack and backpack:FindFirstChild(Config.ToolName)
		if tool and tool:IsA("Tool") then
			humanoid:EquipTool(tool)
		else
			-- No Tool to work through -- either it's already in hand or the game
			-- doesn't hand one out at all. Drive the state directly so zones and
			-- the keybind still work.
			SkiService.setEquipped(player, true)
		end
	else
		humanoid:UnequipTools()
		-- Unequipped only fires if a tool was actually in hand; this covers the
		-- case where the state was set directly above.
		SkiService.setEquipped(player, false)
	end
end

local function bindZone(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	part.Touched:Connect(function(hit)
		local character = hit.Parent
		local toucher = character and Players:GetPlayerFromCharacter(character)
		if not toucher then
			return
		end

		-- Touched fires many times a second while you stand on something.
		local now = os.clock()
		if now < (zoneCooldown[toucher] or 0) then
			return
		end
		zoneCooldown[toucher] = now + Config.ZoneCooldown

		SkiService.request(toucher, part:GetAttribute(Config.ZoneRemovesAttribute) ~= true)
	end)
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

function SkiService.onCharacterAdded(player: Player, character: Model)
	equipped[player] = false
	character:SetAttribute(Attr.Equipped, false)

	-- A character that died mid-wipeout leaves its old entry behind.
	SkiRagdoll.stop(character)

	-- Deferred only so the Backpack has been rebuilt by the time we hand out the
	-- Tool. The limbs themselves need no waiting: the server assembles the whole
	-- character model before parenting it, so they are all already there.
	-- (WaitForChild-ing them by name would also stall R15 spawns for the full
	-- timeout, since R15 has no part called "Torso".)
	task.defer(function()
		if not character.Parent then
			return
		end

		SkiGear.build(character)

		-- You spawn carrying them, not wearing them.
		SkiGear.setStowed(character, true)

		if Config.GiveOnSpawn and player.Parent then
			SkiService.giveTool(player)
		end
	end)
end

function SkiService.onPlayerRemoving(player: Player)
	equipped[player] = nil
	zoneCooldown[player] = nil
end

-- Everything here is present already: ensureRemotes built whatever was missing
-- before this ran, so nothing in this function can yield.
function SkiService.init(remotes: Folder)
	equipEvent = remotes:FindFirstChild("SkiEquip") :: RemoteEvent

	-- Fired with no arguments by the client's keybind. Nothing else is trusted
	-- from it: the server decides what the new state actually is and fires back.
	equipEvent.OnServerEvent:Connect(function(player)
		SkiService.request(player, nil)
	end)

	--[[
		The client asks for a wipeout, because only the client knows the angle it
		landed at. It sends no arguments -- there is nothing to lie about, and
		the worst a spammer achieves is repeatedly knocking themselves over.

		Rate limited by the ragdoll itself: start() ignores a character that is
		already down.
	]]
	local crashEvent = remotes:FindFirstChild("SkiCrash") :: RemoteEvent
	crashEvent.OnServerEvent:Connect(function(player)
		local character = player.Character
		if not character or not equipped[player] then
			return
		end

		SkiRagdoll.start(character)

		-- Take the skis off on the way down. Getting up mid-slide with the sim
		-- still running would fight the ragdoll for control of the character.
		SkiService.request(player, false)
	end)

	for _, part in CollectionService:GetTagged(Config.ZoneTag) do
		bindZone(part)
	end
	CollectionService:GetInstanceAddedSignal(Config.ZoneTag):Connect(bindZone)
end

return SkiService

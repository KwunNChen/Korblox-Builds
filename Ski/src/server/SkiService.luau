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

local unequippedAt: { [Player]: number } = {}
local UNEQUIP_CRASH_GRACE = 1

local function log(message: string, ...)
	if Config.DebugLog then
		print(string.format("[Ski] " .. message, ...))
	end
end

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

	if not isEquipped then
		SkiService.clearState(character)
		unequippedAt[player] = os.clock()
	end

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

function SkiService.clearState(character: Model)
	character:SetAttribute(Attr.State, Shared.State.Walking)
	character:SetAttribute(Attr.Speed, 0)
	character:SetAttribute(Attr.Scrub, 0)
	character:SetAttribute(Attr.Lean, 0)
	character:SetAttribute(Attr.OnSnow, false)
end

local function cleanNumber(value: unknown, limit: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(value, -limit, limit)
end

function SkiService.onStateReport(player: Player, payload: unknown)
	local character = player.Character
	if type(payload) ~= "table" or not character or not equipped[player] then
		return
	end

	local data = payload :: any

	if type(data.state) == "string" and Shared.State[data.state] then
		character:SetAttribute(Attr.State, data.state)
	end

	local speed = cleanNumber(data.speed, Config.MaxSpeed)
	if speed then
		character:SetAttribute(Attr.Speed, math.abs(speed))
	end

	local scrub = cleanNumber(data.scrub, Config.MaxSpeed)
	if scrub then
		character:SetAttribute(Attr.Scrub, math.abs(scrub))
	end

	local lean = cleanNumber(data.lean, 1)
	if lean then
		character:SetAttribute(Attr.Lean, lean)
	end

	if type(data.onSnow) == "boolean" then
		character:SetAttribute(Attr.OnSnow, data.onSnow)
	end
end

local zoneCooldown: { [Player]: number } = {}

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
			SkiService.setEquipped(player, true)
		end
	else
		humanoid:UnequipTools()
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

		local now = os.clock()
		if now < (zoneCooldown[toucher] or 0) then
			return
		end
		zoneCooldown[toucher] = now + Config.ZoneCooldown

		SkiService.request(toucher, part:GetAttribute(Config.ZoneRemovesAttribute) ~= true)
	end)
end

function SkiService.onCharacterAdded(player: Player, character: Model)
	equipped[player] = false
	character:SetAttribute(Attr.Equipped, false)

	SkiService.clearState(character)
	SkiRagdoll.stop(character)

	task.defer(function()
		if not character.Parent then
			return
		end

		SkiGear.build(character)
		SkiGear.setStowed(character, true)

		if Config.GiveOnSpawn and player.Parent then
			SkiService.giveTool(player)
		end
	end)
end

function SkiService.onPlayerRemoving(player: Player)
	equipped[player] = nil
	zoneCooldown[player] = nil
	unequippedAt[player] = nil
end

function SkiService.init(remotes: Folder)
	equipEvent = remotes:FindFirstChild("SkiEquip") :: RemoteEvent

	equipEvent.OnServerEvent:Connect(function(player)
		SkiService.request(player, nil)
	end)

	local stateEvent = remotes:FindFirstChild("SkiState") :: RemoteEvent
	stateEvent.OnServerEvent:Connect(SkiService.onStateReport)

	local crashEvent = remotes:FindFirstChild("SkiCrash") :: RemoteEvent
	crashEvent.OnServerEvent:Connect(function(player)
		local character = player.Character
		if not character then
			return
		end

		local justUnequipped = os.clock() - (unequippedAt[player] or -math.huge) < UNEQUIP_CRASH_GRACE
		if not equipped[player] and not justUnequipped then
			return
		end

		SkiRagdoll.start(character)
		SkiService.request(player, false)
	end)

	for _, part in CollectionService:GetTagged(Config.ZoneTag) do
		bindZone(part)
	end
	CollectionService:GetInstanceAddedSignal(Config.ZoneTag):Connect(bindZone)
end

return SkiService

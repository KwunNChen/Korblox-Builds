-- Entry point. Starts the barrage cycle and wires up the debug knobs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local BarrageService = require(script.Parent:WaitForChild("BarrageService"))

local DEBUG_ATTRIBUTE = "DebugBarrageNow"

BarrageService.start()

-- Set true to drop a barrage immediately. Resets itself, same contract as the
-- snowstorm's DebugThunder -- the Command Bar runs its own VM, so an attribute
-- is the only thing that reliably reaches a running server script.
ArtilleryFolder:SetAttribute(DEBUG_ATTRIBUTE, false)

ArtilleryFolder:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
	if ArtilleryFolder:GetAttribute(DEBUG_ATTRIBUTE) ~= true then
		return
	end

	ArtilleryFolder:SetAttribute(DEBUG_ATTRIBUTE, false)

	if not Config.Enabled then
		warn("[Artillery] DebugBarrageNow ignored -- Enabled is false in ArtilleryConfig.")
		return
	end

	if BarrageService.isActive() then
		print("[Artillery] barrage already running")
		return
	end

	if BarrageService.triggerNow() then
		print(string.format("[Artillery] barrage -> %.0fs warning, then shells", Config.BarrageWarningLead))
	else
		warn("[Artillery] barrage could not start -- the service never came up. Check Output above.")
	end
end)

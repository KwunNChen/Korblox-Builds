--[[
	ArtilleryClient
	Entry point. Owns the single render loop every shell is stepped from.

	One RenderStepped connection for all shells, not one per shell -- a
	twenty-shell barrage would otherwise churn twenty connections in the space
	of a few seconds, every couple of minutes, forever.

	The client is told four things per shell and works out the rest itself. It
	is never asked what it hit; damage is the server's business entirely.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArtilleryFolder = ReplicatedStorage:WaitForChild("Artillery")
local Config = require(ArtilleryFolder:WaitForChild("ArtilleryConfig"))
local Shared = require(ArtilleryFolder:WaitForChild("ArtilleryShared"))
local ArtilleryAudio = require(script.Parent:WaitForChild("ArtilleryAudio"))
local ArtilleryShake = require(script.Parent:WaitForChild("ArtilleryShake"))
local DebrisChunks = require(script.Parent:WaitForChild("DebrisChunks"))
local DustCloud = require(script.Parent:WaitForChild("DustCloud"))
local ShellRender = require(script.Parent:WaitForChild("ShellRender"))

local Attr = Shared.Attr

local function log(...)
	if Config.DebugLog then
		print("[Artillery/client]", ...)
	end
end

local shellEvent = Shared.getShellEvent()
if not shellEvent then
	warn(
		"[ArtilleryClient] ReplicatedStorage.ArtilleryShell is missing -- nothing will be drawn. "
			.. "Move it into ReplicatedStorage alongside Artillery and ArtilleryState (install step 2)."
	)
	return
end

local stateHolder = Shared.getStateHolder()

ArtilleryAudio.init()
ArtilleryShake.init()
ShellRender.init()

-- The warning. Driven off the attribute rather than its own remote, the same
-- way the snowstorm's clients pick up ThunderActive.
stateHolder:GetAttributeChangedSignal(Attr.WarningActive):Connect(function()
	if stateHolder:GetAttribute(Attr.WarningActive) == true then
		log("BARRAGE INCOMING -- take cover")
		ArtilleryAudio.batteryReport()
	end
end)

shellEvent.OnClientEvent:Connect(function(launch, impact, flightTime, impactTime)
	if
		typeof(launch) ~= "Vector3"
		or typeof(impact) ~= "Vector3"
		or type(flightTime) ~= "number"
		or type(impactTime) ~= "number"
		or flightTime <= 0
	then
		return
	end

	ShellRender.add(launch, impact, flightTime, impactTime)
end)

-- GetServerTimeNow is the same clock on every machine, so a shell drawn here
-- reaches its crater on the frame the server applies the damage regardless of
-- ping. Nothing else in the loop needs to know about latency.
RunService.RenderStepped:Connect(function()
	ShellRender.step(workspace:GetServerTimeNow())

	-- Debris and dust run on os.clock instead, because their motion is purely
	-- local decoration -- nothing on the server is waiting on it, so it has no
	-- reason to be pinned to the shared clock the way a shell's impact does.
	DebrisChunks.step()
	DustCloud.step()
end)

log("ready -- listening for shells")

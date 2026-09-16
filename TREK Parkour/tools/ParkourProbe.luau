--[[
	PARKOUR PROBE -- see what the detector sees.

	NOT a lune script, and not installed with the package. Paste it into the
	Studio COMMAND BAR.

	--------------------------------------------------------------------------
	USING IT
	--------------------------------------------------------------------------

	1. Press Play.
	2. Switch the command bar to CLIENT. That is the dropdown at the left of the
	   command bar, which says "Server" by default. This will not work on Server
	   -- the detector runs on the player's own machine and casts against what
	   that machine can see.
	3. Paste this whole file in and press enter.
	4. Walk at things.

	To stop it: _G.__ParkourProbeStop()

	--------------------------------------------------------------------------
	READING IT
	--------------------------------------------------------------------------

	Two probes are drawn at once, because the game uses different ones depending
	on whether you are on the ground or in the air:

	    VAULT    fired from shin height, measured up from your soles
	    MANTLE   fired from chest height, measured from your root

	Each gets a ray, a marker where it hit the wall, a marker on the top surface
	it found, and a label.

	    GREEN    a move would happen here
	    YELLOW   found something, but it is not a move -- the label says why
	    RED      refused

	The commonest surprise is a YELLOW "no room up there". That is the clearance
	box hitting something above the ledge, and no amount of changing the height
	bands will fix it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if _G.__ParkourProbeStop then
	_G.__ParkourProbeStop()
end

local package = ReplicatedStorage:FindFirstChild("TREKParkour")
if not package then
	error(
		"[ParkourProbe] no ReplicatedStorage.TREKParkour. Either the package is not installed, or you are"
			.. " running this on Server -- switch the command bar to Client.",
		0
	)
end

local Detect = require(package:WaitForChild("ParkourDetect"))
local Config = require(package:WaitForChild("ParkourConfig"))

local player = Players.LocalPlayer
if not player then
	error("[ParkourProbe] no LocalPlayer. Switch the command bar to Client and press Play first.", 0)
end

local COLOURS = {
	go = Color3.fromRGB(80, 220, 120),
	note = Color3.fromRGB(240, 200, 80),
	no = Color3.fromRGB(230, 90, 90),
}

local visuals = Instance.new("Folder")
visuals.Name = "ParkourProbeVisuals"
visuals.Parent = workspace

local function newPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.35
	part.Parent = visuals
	return part
end

-- One set of visuals per mode, built once and moved every frame. Rebuilding
-- parts each frame would be the slowest possible way to do this.
local function newRig(mode: string)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextStrokeTransparency = 0.4

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(300, 34)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	label.Parent = billboard

	local anchor = newPart(mode .. "Anchor", Vector3.new(0.1, 0.1, 0.1))
	anchor.Transparency = 1
	billboard.Parent = anchor

	return {
		ray = newPart(mode .. "Ray", Vector3.new(0.12, 0.12, 1)),
		face = newPart(mode .. "Face", Vector3.new(0.5, 0.5, 0.5)),
		top = newPart(mode .. "Top", Vector3.new(0.7, 0.2, 0.7)),
		land = newPart(mode .. "Land", Config.ClearanceSize),
		anchor = anchor,
		label = label,
	}
end

local rigs = {
	[Detect.Result.Vault] = newRig("Vault"),
	[Detect.Result.Mantle] = newRig("Mantle"),
}

for _, rig in rigs do
	rig.land.Transparency = 0.85
end

local function hide(rig)
	rig.face.Transparency = 1
	rig.top.Transparency = 1
	rig.land.Transparency = 1
end

local function draw(mode: string, rig, reading)
	local colour = if reading.land then COLOURS.go
		elseif reading.result == Detect.Result.TooHigh or reading.result == Detect.Result.None then COLOURS.no
		else COLOURS.note

	hide(rig)

	-- The ray, as a thin box from the origin to wherever it ended.
	local finish = reading.facePoint or (reading.origin + reading.direction * Config.ProbeDistance)
	local length = math.max((finish - reading.origin).Magnitude, 0.05)
	rig.ray.Size = Vector3.new(0.12, 0.12, length)
	rig.ray.CFrame = CFrame.lookAt(reading.origin:Lerp(finish, 0.5), finish)
	rig.ray.Color = colour
	rig.ray.Transparency = 0.35

	if reading.facePoint then
		rig.face.Position = reading.facePoint
		rig.face.Color = colour
		rig.face.Transparency = 0.2
	end

	if reading.topY and reading.facePoint then
		rig.top.Position = Vector3.new(reading.facePoint.X, reading.topY, reading.facePoint.Z)
		rig.top.Color = colour
		rig.top.Transparency = 0.2
	end

	if reading.land then
		rig.land.Position = reading.land
		rig.land.Color = colour
		rig.land.Transparency = 0.85
	end

	rig.anchor.Position = reading.origin
	rig.label.TextColor3 = colour
	rig.label.Text = string.format(
		"%s: %s%s%s",
		mode:upper(),
		reading.result,
		if reading.height then string.format("  (%.1f studs)", reading.height) else "",
		if reading.reason then "\n" .. reading.reason else ""
	)
end

local RATE = 1 / 20
local since = 0
local connection

connection = RunService.RenderStepped:Connect(function(dt)
	since += dt
	if since < RATE then
		return
	end
	since = 0

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (character and humanoid and root) then
		for _, rig in rigs do
			hide(rig)
			rig.ray.Transparency = 1
			rig.label.Text = ""
		end
		return
	end

	for mode, rig in rigs do
		local ok, reading = pcall(Detect.probe, character, humanoid, root, mode)
		if ok then
			draw(mode, rig, reading)
		else
			rig.label.Text = mode:upper() .. ": probe errored\n" .. tostring(reading)
			rig.label.TextColor3 = COLOURS.no
		end
	end
end)

_G.__ParkourProbeStop = function()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	visuals:Destroy()
	_G.__ParkourProbeStop = nil
	print("[ParkourProbe] stopped.")
end

print("[ParkourProbe] running. Walk at things. Stop with: _G.__ParkourProbeStop()")

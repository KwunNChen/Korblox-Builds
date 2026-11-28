local StarterGui = game:GetService("StarterGui")
--[[
	Insertion

	Films the raid's insertion. ServerScriptService.TowerRun fires ReplicatedStorage.Insertion with
	{ forest, cut, city = seconds of each phase, start = where the van leaves the staging post, stop = where it
	brakes at the tower }; the van faces -Z, +X is its right flank. The van itself is found as
	workspace.InsertionVan: an instance in the remote's args can arrive nil before it streams in.
	Forest: trackside ahead of the staging post, the van pulls away past the camera into the trees.
	Cut: black while the server jumps the van to the city (the drive in, skipped).
	City: across the street, opening up on the tattered Bloxian flags, tilting down onto the van as it pulls in.
	Then a fade to black while the server moves the squad to floor 1.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

-- the hull is one big textured mesh; without this it pops in a second into the shot
task.spawn(function()
	ContentProvider:PreloadAsync({ ReplicatedStorage:WaitForChild("InsertionVan") })
end)

local player = Players.LocalPlayer
local BAR = 0.11 -- letterbox bar height, screen fraction

local gui = Instance.new("ScreenGui")
gui.Name = "InsertionCam"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function black(name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Parent = gui
	return f
end
local top = black("Top")
top.Size = UDim2.fromScale(1, 0)
local bottom = black("Bottom")
bottom.AnchorPoint = Vector2.new(0, 1)
bottom.Position = UDim2.fromScale(0, 1)
bottom.Size = UDim2.fromScale(1, 0)
local fade = black("Fade")
fade.Size = UDim2.fromScale(1, 1)
fade.BackgroundTransparency = 1
fade.ZIndex = 5

local function tween(o, t, props)
	local tw = TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), props)
	tw:Play()
	return tw
end

local playing = false

ReplicatedStorage:WaitForChild("Insertion").OnClientEvent:Connect(function(cue)
	if playing then return end
	playing = true
	local start, stop, drive = cue.start, cue.stop, cue.city
	local cityAt = cue.forest + cue.cut -- clock time the van is on the plaza road
	local van = workspace:WaitForChild("InsertionVan", 3)
	local camera = workspace.CurrentCamera
	local fov = camera.FieldOfView
	local t0 = os.clock()
	player:SetAttribute("Cutscene", true) -- local only: storm stays on, HUD header drops below the bar
	-- no guns during the ride: holster and hide the hotbar so number keys can't draw one
	local riderHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if riderHum then riderHum:UnequipTools() end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	gui.Enabled = true
	fade.BackgroundTransparency = 1
	tween(top, 0.6, { Size = UDim2.fromScale(1, BAR) })
	tween(bottom, 0.6, { Size = UDim2.fromScale(1, BAR) })
	camera.CameraType = Enum.CameraType.Scriptable

	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0 - cityAt
		local vanAt = van and van.Parent and van:GetPivot() or stop
		if t < -cue.cut then
			-- forest: trackside ahead of the staging post on its open side, low, the van pulls off past us
			local eye = (start * CFrame.new(10, 3, -55)).Position
			camera.CFrame = CFrame.lookAt(eye, (vanAt * CFrame.new(0, 4, 0)).Position)
			camera.FieldOfView = 55
		elseif t < 0 then
			-- black; hold still
		else
			-- city: low across the road from the HQ doors, opening on the tattered Bloxian flags (City.SpawnLife),
			-- then tilting down to the stop as the van drives into frame. Aims at fixed points, never at the van:
			-- its replicated position jitters and shook the camera.
			local a = math.clamp(t / 3.5, 0, 1)
			a = a * a * (3 - 2 * a)
			local eye = (stop * CFrame.new(-25, 4, 6)).Position
			local flags = (stop * CFrame.new(4, 46, 0)).Position
			camera.CFrame = CFrame.lookAt(eye, flags:Lerp((stop * CFrame.new(0, 4, 0)).Position, a))
			camera.FieldOfView = 60
		end
	end)

	-- dip to black as the van leaves the clearing, back up once it is on the plaza road
	task.wait(cue.forest - 0.5)
	tween(fade, 0.5, { BackgroundTransparency = 0 })
	task.wait(cue.cut + 0.5)
	tween(fade, 0.4, { BackgroundTransparency = 1 })
	-- the server parks for 1.2 s, then moves the squad; be black by then and stay black until it has
	task.wait(drive + 0.4)
	tween(fade, 0.6, { BackgroundTransparency = 0 }).Completed:Wait()
	-- stay black until the server has actually moved us off the street (the teleport streams first)
	local waited = 0
	repeat
		waited += task.wait(0.1)
		local char = player.Character
		local away = char and (char:GetPivot().Position - stop.Position).Magnitude > 500
	until away or waited > 6
	task.wait(0.3)
	player:SetAttribute("Cutscene", nil)
	local char = player.Character
	-- MedicalClient hides the hotbar while carrying someone; respect that
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, not (char and char:GetAttribute("Carrying")))
	conn:Disconnect()
	camera.FieldOfView = fov
	camera.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then camera.CameraSubject = hum end
	top.Size = UDim2.fromScale(1, 0)
	bottom.Size = UDim2.fromScale(1, 0)
	tween(fade, 0.8, { BackgroundTransparency = 1 }).Completed:Wait()
	gui.Enabled = false
	playing = false
end)

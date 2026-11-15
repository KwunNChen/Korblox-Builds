--!strict
-- Every player gets this. While Soul Rip has their soul out, the server parents an ObjectValue
-- "DarkMagicSoul" (pointing at the soul) to their Player: the camera follows the soul, their
-- movement input steers it, and a countdown shows until it's pulled back in.
-- It also plays the camera shake and colour drain the server sends when a spell lands nearby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Dark Magic Soul") :: UnreliableRemoteEvent

-- the default PlayerModule reads keyboard, gamepad and touch alike
local controls: any = nil
pcall(function()
	controls = (require :: any)(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
end)

local function steer(link: ObjectValue)
	-- the link can arrive before the soul part has replicated, so give it a moment
	local t0 = os.clock()
	while not link.Value and link.Parent and os.clock() - t0 < 3 do
		task.wait()
	end
	local core = link.Value :: BasePart?
	local camera = workspace.CurrentCamera
	if not (core and camera) then
		return
	end
	local oldSubject = camera.CameraSubject
	camera.CameraSubject = core

	local gui = Instance.new("ScreenGui")
	gui.Name = "SoulCountdown"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 60)
	label.Size = UDim2.fromOffset(240, 40)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Oswald
	label.TextSize = 30
	label.TextColor3 = Color3.fromRGB(205, 80, 255)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	local lastSent = Vector3.new(math.huge, 0, 0)
	local nextSend = 0
	local conn = RunService.RenderStepped:Connect(function()
		local left = math.max((link:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow(), 0)
		label.Text = string.format("SOUL  %d", math.ceil(left))

		-- camera-relative, flattened: forward on the stick goes where the camera looks
		local move = controls and controls:GetMoveVector() or Vector3.zero
		local cf = camera.CFrame
		local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
		fwd = fwd.Magnitude > 0 and fwd.Unit or Vector3.zero
		right = right.Magnitude > 0 and right.Unit or Vector3.zero
		local dir = right * move.X - fwd * move.Z
		if dir.Magnitude > 1 then
			dir = dir.Unit
		end

		-- ~20 sends a second, and only when the input changed
		local now = os.clock()
		if now >= nextSend and (dir - lastSent).Magnitude > 0.05 then
			nextSend = now + 0.05
			lastSent = dir
			remote:FireServer(dir)
		end
	end)

	link.AncestryChanged:Wait() -- the server removes it when the soul goes back
	conn:Disconnect()
	gui:Destroy()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = hum or oldSubject
end

player.ChildAdded:Connect(function(child)
	if child.Name == "DarkMagicSoul" and child:IsA("ObjectValue") then
		steer(child)
	end
end)

-- Spell impacts: the server sends (where, radius, shake 0..1, darkness 0..1). Inside the radius the
-- camera shakes and the world briefly drains of colour, both weaker the further away you are.
local TweenService = game:GetService("TweenService")
local fx = ReplicatedStorage:WaitForChild("Dark Magic FX") :: RemoteEvent

-- fetch the spell textures up front; otherwise the first chain or tendril anyone sees is a blank white strip
-- (keep in step with TEX_* in DarkMagic.server.luau)
task.spawn(function()
	local decals = {}
	for _, id in { 128829109917714, 138082068081539, 121817789379823, 110818878717565, 109175035979792 } do
		local d = Instance.new("Decal")
		d.Texture = "rbxassetid://" .. id
		table.insert(decals, d)
	end
	game:GetService("ContentProvider"):PreloadAsync(decals)
end)
local drain = Instance.new("ColorCorrectionEffect")
drain.Name = "DarkMagicDrain"
local shake = 0

RunService:BindToRenderStep("DarkMagicShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shake <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local t = os.clock() * 30
	local a = shake * 0.03 -- radians of wobble at full strength
	camera.CFrame *= CFrame.Angles(math.noise(t, 1.3) * a, math.noise(t, 2.7) * a, math.noise(t, 4.1) * a * 0.5)
	shake = math.max(shake - dt * 1.8, 0) -- dies out in about half a second
end)

fx.OnClientEvent:Connect(function(at: any, radius: any, strength: any, dark: any)
	local camera = workspace.CurrentCamera
	if typeof(at) ~= "Vector3" or type(radius) ~= "number" or not camera then
		return
	end
	local k = 1 - math.clamp((camera.Focus.Position - at).Magnitude / radius, 0, 1)
	if k <= 0 then
		return
	end
	shake = math.max(shake, (tonumber(strength) or 0) * k)
	local d = (tonumber(dark) or 0) * k
	if d > 0 then
		drain.Parent = camera -- re-parented each time in case the camera was replaced
		drain.Saturation = -0.9 * d
		drain.Contrast = 0.35 * d
		drain.Brightness = -0.12 * d
		drain.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(190, 160, 255), d)
		TweenService:Create(drain, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Saturation = 0,
			Contrast = 0,
			Brightness = 0,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
	end
end)

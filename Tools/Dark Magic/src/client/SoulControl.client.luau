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

-- the default PlayerModule reads keyboard, gamepad and touch alike. Some games replace it, so look
-- for it in the background: waiting here would stall everything below (textures, shake, tendrils).
local controls: any = nil
task.spawn(pcall, function()
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

-- fetch the spell textures up front; otherwise the first chain anyone sees is a blank white strip
-- (keep in step with TEX_* in DarkMagic.server.luau)
task.spawn(function()
	local decals = {}
	for _, id in { 128829109917714, 121817789379823, 110818878717565, 109175035979792 } do
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

-- Shadow tendrils: the server sends (arm, target part, seconds held). Each arm throws one thick
-- tendril and two thin ones: black tapering segments with a violet rim that whip out in an arc,
-- writhe while held, then pull back into the hand. Drawn here so they move at frame rate.
local tendrilRemote = ReplicatedStorage:WaitForChild("Dark Magic Tendril") :: RemoteEvent
local SEGS = 16 -- fewer shows corners at the bends
local OUT, BACK = 0.16, 0.22 -- seconds to lash out / pull back

local function strand(model: Model, width: number): { BasePart }
	local parts = {}
	for i = 1, SEGS do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder -- length runs along X
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(10, 0, 16)
		local w = width * (1 - (i - 1) / SEGS * 0.8) -- tapers to a fifth at the tip
		p.Size = Vector3.new(0.1, w, w)
		p.Parent = model
		parts[i] = p
	end
	return parts
end

tendrilRemote.OnClientEvent:Connect(function(arm: any, target: any, hold: any)
	if not (typeof(arm) == "Instance" and arm:IsA("BasePart") and typeof(target) == "Instance" and target:IsA("BasePart")) then
		return
	end
	local held = math.clamp(tonumber(hold) or 0.5, 0.1, 3)
	local model = Instance.new("Model")
	model.Name = "DarkMagicTendril"
	local strands = { { parts = strand(model, 0.55), seed = math.random() * 100, amp = 1, aim = Vector3.zero } }
	for _ = 1, 2 do
		local aim = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.4
		table.insert(strands, { parts = strand(model, 0.25), seed = math.random() * 100, amp = 1.7, aim = aim })
	end
	local rim = Instance.new("Highlight")
	rim.FillTransparency = 1
	rim.OutlineColor = Color3.fromRGB(150, 45, 230)
	rim.OutlineTransparency = 0.25
	rim.DepthMode = Enum.HighlightDepthMode.Occluded
	rim.Parent = model
	model.Parent = workspace

	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > OUT + held + BACK or not (arm.Parent and target.Parent) then
			conn:Disconnect()
			model:Destroy()
			return
		end
		local reach = if t < OUT then 1 - (1 - t / OUT) ^ 3
			elseif t < OUT + held then 1
			else 1 - ((t - OUT - held) / BACK) ^ 2
		local a = (arm.CFrame * CFrame.new(0, -arm.Size.Y / 2, 0)).Position -- the fingertips
		for _, s in strands do
			local span = target.Position + s.aim - a
			local len = span.Magnitude
			if len < 0.1 then
				continue
			end
			local dir = span / len
			local side = dir:Cross(Vector3.yAxis)
			side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
			local up = side:Cross(dir)
			local bend = math.min(len / 10, 1) -- short reaches writhe less
			local prev = a
			local cfs = table.create(SEGS)
			for i, p in s.parts do
				local u = i / SEGS * reach
				local env = math.sin(math.pi * u) -- pinned at the hand and where it bites
				local w1 = math.sin(u * 7 + t * 9 + s.seed) * 1.1 * s.amp
				local w2 = math.cos(u * 5 - t * 7 + s.seed) * 0.8 * s.amp + 1.2 -- +1.2: lashes over in an arc
				local pt = a + span * u + (side * w1 + up * w2) * env * bend
				local seg = pt - prev
				local l = seg.Magnitude
				p.Size = Vector3.new(l + p.Size.Y * 0.8, p.Size.Y, p.Size.Z) -- overlap hides the joints
				cfs[i] = if l > 1e-3
					then CFrame.lookAt((prev + pt) / 2, pt) * CFrame.Angles(0, math.pi / 2, 0) -- X along the segment
					else CFrame.new(pt)
				prev = pt
			end
			workspace:BulkMoveTo(s.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end)

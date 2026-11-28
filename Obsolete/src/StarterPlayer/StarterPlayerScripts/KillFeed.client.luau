-- Kill feed and revive feed, top right, Battlefield-style icons. Entries come from ServerScriptService.Medical (RemoteEvent KillFeed):
-- { kind = "kill" | "revive", a = killer/medic name?, aColor, b = victim/patient name, bColor, weapon?, head? }
-- Gun icons are white silhouettes rendered live from ReplicatedStorage.SPH_Assets.WeaponModels, so new guns need no art.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local me = Players.LocalPlayer
local MAX_ROWS, LIFE, ROW_H, ICON_H = 6, 7, 24, 18
local SKULL = "rbxassetid://123249306807606"
local WHITE, GREY, GREEN = Color3.new(1, 1, 1), Color3.fromRGB(220, 220, 220), Color3.fromRGB(111, 224, 127)
local Models = ReplicatedStorage:WaitForChild("SPH_Assets"):WaitForChild("WeaponModels")
local NpcGuns = ReplicatedStorage:WaitForChild("KillFeedGuns") -- NPC guns, copied in by ServerScriptService.Medical

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "KillFeed", false, 5
local list = Instance.new("Frame")
list.AnchorPoint, list.Position = Vector2.new(1, 0), UDim2.new(1, -12, 0, 8)
list.Size, list.AutomaticSize, list.BackgroundTransparency = UDim2.fromOffset(400, 0), Enum.AutomaticSize.Y, 1
list.Parent = gui
local layout = Instance.new("UIListLayout")
layout.HorizontalAlignment, layout.SortOrder, layout.Padding = Enum.HorizontalAlignment.Right, Enum.SortOrder.LayoutOrder, UDim.new(0, 3)
layout.Parent = list
gui.Parent = me:WaitForChild("PlayerGui")

local function frame(class: string, size: UDim2, parent: Instance?): any
	local f = Instance.new(class)
	f.Size, f.BackgroundTransparency, f.BorderSizePixel = size, 1, 0
	f.Parent = parent
	return f
end
local function round(f: GuiObject)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = f
end
local function bar(parent: Instance, size: UDim2, pos: UDim2, color: Color3, rot: number?)
	local b = frame("Frame", size, parent)
	b.AnchorPoint, b.Position, b.Rotation = Vector2.new(0.5, 0.5), pos, rot or 0
	b.BackgroundColor3, b.BackgroundTransparency = color, 0
	return b
end

local icons: { [string]: ViewportFrame | false } = {}
local function weaponIcon(name: string): ViewportFrame?
	if icons[name] == nil then
		icons[name] = false
		local src = Models:FindFirstChild(name) or NpcGuns:FindFirstChild(name)
		local aim = src and src:FindFirstChild("AimPart")
		if aim then
			local m = src:Clone()
			local fwd, up = aim.CFrame.LookVector, aim.CFrame.UpVector
			local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") then
					if p.Transparency > 0.4 then
						p.Transparency = 1
					else
						p.Color, p.Material, p.Transparency = WHITE, Enum.Material.SmoothPlastic, 0
						if p:IsA("MeshPart") then p.TextureID = "" end
						local h = p.Size / 2
						for _, s in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) } do
							local w = p.CFrame:PointToWorldSpace(h * s)
							x0, x1 = math.min(x0, w:Dot(fwd)), math.max(x1, w:Dot(fwd))
							y0, y1 = math.min(y0, w:Dot(up)), math.max(y1, w:Dot(up))
						end
					end
				elseif p:IsA("Decal") or p:IsA("SurfaceAppearance") or p:IsA("ParticleEmitter") or p:IsA("Light") or p:IsA("Beam") then
					p:Destroy()
				end
			end
			if x1 > x0 then
				local len, ht = x1 - x0, y1 - y0
				local w = math.clamp(math.ceil(ICON_H * len / ht), ICON_H, 84)
				local vp = frame("ViewportFrame", UDim2.fromOffset(w, ICON_H))
				vp.Ambient, vp.LightColor, vp.ImageColor3 = WHITE, Color3.new(), GREY -- flat silhouette
				local cam = Instance.new("Camera")
				cam.FieldOfView = 8 -- near-orthographic
				local half = math.max(ht, len * ICON_H / w) * 1.08 / 2
				local dist = half / math.tan(math.rad(cam.FieldOfView / 2))
				local centre = fwd * (x0 + x1) / 2 + up * (y0 + y1) / 2
				local side = fwd:Cross(up) -- camera sits off the gun's right side
				local depth = aim.Position:Dot(side)
				cam.CFrame = CFrame.fromMatrix(centre + side * (depth + dist), fwd, up) -- barrel points right
				cam.Parent, vp.CurrentCamera = vp, cam
				m.Parent = vp
				icons[name] = vp
			end
		end
	end
	local t = icons[name]
	return if t then t:Clone() else nil
end

local function headshotIcon(): Frame
	local f = frame("Frame", UDim2.fromOffset(ICON_H - 2, ICON_H - 2))
	local ring = frame("Frame", UDim2.new(1, -4, 1, -4), f)
	ring.Position = UDim2.fromOffset(2, 2)
	round(ring)
	local s = Instance.new("UIStroke"); s.Color, s.Thickness = GREY, 1.5; s.Parent = ring
	for _, p in { UDim2.new(0.5, 0, 0, 2), UDim2.new(0.5, 0, 1, -2), UDim2.new(0, 2, 0.5, 0), UDim2.new(1, -2, 0.5, 0) } do
		local vertical = p.X.Scale == 0.5
		bar(f, if vertical then UDim2.fromOffset(2, 5) else UDim2.fromOffset(5, 2), p, GREY)
	end
	round(bar(f, UDim2.fromOffset(4, 4), UDim2.fromScale(0.5, 0.5), GREY))
	return f
end
local function reviveIcon(): Frame -- star of life
	local f = frame("Frame", UDim2.fromOffset(ICON_H, ICON_H))
	for _, r in { 0, 60, 120 } do bar(f, UDim2.fromOffset(4, ICON_H - 2), UDim2.fromScale(0.5, 0.5), GREEN, r) end
	return f
end
local function skullIcon(): ImageLabel
	local i = frame("ImageLabel", UDim2.fromOffset(ICON_H - 2, ICON_H - 2))
	i.Image, i.ImageColor3 = SKULL, GREY
	return i
end
local function nameLabel(name: string, color: Color3?): TextLabel
	local l = frame("TextLabel", UDim2.fromOffset(0, ROW_H))
	l.AutomaticSize, l.Text, l.Font, l.TextSize = Enum.AutomaticSize.X, name, Enum.Font.GothamBold, 14
	l.TextColor3 = (color or WHITE):Lerp(WHITE, 0.35) -- lifted: dark team colours vanish on the dark rows
	return l
end

local count = 0
ReplicatedStorage:WaitForChild("KillFeed").OnClientEvent:Connect(function(e)
	local parts = {}
	if e.a then table.insert(parts, nameLabel(e.a, e.aColor)) end
	if e.kind == "revive" then
		table.insert(parts, reviveIcon())
	else
		table.insert(parts, (e.a and e.weapon and weaponIcon(e.weapon)) or skullIcon())
		if e.head then table.insert(parts, headshotIcon()) end
	end
	table.insert(parts, nameLabel(e.b, e.bColor))

	count += 1
	local row = frame("CanvasGroup", UDim2.fromOffset(0, ROW_H))
	row.LayoutOrder, row.AutomaticSize = count, Enum.AutomaticSize.X -- newest at the bottom
	row.BackgroundColor3, row.BackgroundTransparency = Color3.new(), 0.5
	local h = Instance.new("UIListLayout")
	h.FillDirection, h.VerticalAlignment, h.SortOrder, h.Padding = Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center, Enum.SortOrder.LayoutOrder, UDim.new(0, 7)
	h.Parent = row
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = row
	for i, p in parts do p.LayoutOrder = i; p.Parent = row end
	if e.a == me.DisplayName or e.b == me.DisplayName then -- you're in it
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode, stroke.Color, stroke.Transparency, stroke.Thickness = Enum.ApplyStrokeMode.Border, WHITE, 0.4, 1
		stroke.Parent = row
	end
	row.Parent = list

	local rows = {}
	for _, r in list:GetChildren() do
		if r:IsA("CanvasGroup") then table.insert(rows, r) end
	end
	table.sort(rows, function(x, y) return x.LayoutOrder < y.LayoutOrder end)
	for i = 1, #rows - MAX_ROWS do rows[i]:Destroy() end
	task.delay(LIFE, function()
		if not row.Parent then return end
		local fade = TweenService:Create(row, TweenInfo.new(0.6), { GroupTransparency = 1 })
		fade.Completed:Connect(function() row:Destroy() end)
		fade:Play()
	end)
end)

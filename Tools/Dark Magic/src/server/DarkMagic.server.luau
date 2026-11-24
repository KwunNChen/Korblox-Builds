--!strict
-- Dark Magic. Uniform: a purple-fire vortex engulfs the target, then fades to reveal a new shirt/pants.
-- Melt mode: the same purple fire kills the target and burns them down to a ragdoll skeleton.
-- Raise: skeletons climb out of the ground to guard the caster or hunt the selected people.
-- Soul Rip, Shadow Step and Hex are the smaller combat spells at the bottom.
-- All effects run here so every player sees them.

local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Drop-in install: the exported package is just this Script, with the tool, the soul client and the
-- animation sources inside it. Put it in ServerScriptService and it moves them into place.
-- (When live-synced with Rojo they're already in place and none of this finds anything.)
local remote = ReplicatedStorage:FindFirstChild("Dark Magic") :: RemoteEvent?
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Dark Magic"
	remote.Parent = ReplicatedStorage
end
assert(remote)
do
	local soul = script:FindFirstChild("Dark Magic Soul")
	if soul then
		-- Anyone already in the server misses this, but scripts run before the first player joins.
		soul.Parent = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
	end
	local tool = script:FindFirstChildWhichIsA("Tool")
	if tool then
		tool.Parent = game:GetService("StarterPack")
		for _, p in Players:GetPlayers() do
			local bag = p:FindFirstChildOfClass("Backpack")
			if bag then
				tool:Clone().Parent = bag
			end
		end
	end
	local anims = script:FindFirstChild("Animations") -- KeyframeSequences to re-publish in another game
	if anims then
		anims.Name = "DarkMagicAnimations"
		anims.Parent = game:GetService("ServerStorage")
	end
end

-- Impacts everyone nearby feels: camera shake and a brief drain of colour (Dark Magic Soul client).
local fxRemote = Instance.new("RemoteEvent")
fxRemote.Name = "Dark Magic FX"
fxRemote.Parent = ReplicatedStorage
local function rumble(at: Vector3, radius: number, shake: number, dark: number)
	fxRemote:FireAllClients(at, radius, shake, dark)
end
-- Shadow tendrils are drawn by each client (Dark Magic Soul) so they writhe smoothly at frame rate.
local tendrilRemote = Instance.new("RemoteEvent")
tendrilRemote.Name = "Dark Magic Tendril"
tendrilRemote.Parent = ReplicatedStorage

-- The tool is recognised by this attribute, not its name, so it can be renamed freely.
local TOOL_ATTRIBUTE = "DarkMagic"
local RANGE = 150
local CLIMB = 0.45 -- seconds for the flame front to race from feet to head

-- Evil palette: no white, pink or pastel. The hottest core is a hard violet and everything burns
-- down through bruise purple into black, so the fire reads as malevolent, not pretty.
local WHITE_HOT = Color3.fromRGB(150, 45, 230) -- (names kept: "hottest" is now a hard violet)
local MAGENTA = Color3.fromRGB(100, 10, 175)
local PURPLE = Color3.fromRGB(58, 0, 120)
local DEEP = Color3.fromRGB(24, 0, 52)
local SOOT = Color3.fromRGB(6, 0, 10)

local TEX = "rbxasset://textures/particles/"
local FIRE_TEX = TEX .. "fire_main.dds"
local EMBER_TEX = TEX .. "fire_sparks_main.dds"
local SMOKE_TEX = TEX .. "smoke_main.dds"
local SPARK_TEX = EMBER_TEX -- jagged embers, not twinkling star sparkles (those read as fairy dust)
local VORTEX_TEX = TEX .. "forcefield_vortex_main.dds"
local RING_TEX = TEX .. "explosion01_shockwave_main.dds"
local GLOW_TEX = TEX .. "forcefield_glow_main.dds"
local IMPLODE_TEX = TEX .. "explosion01_implosion_main.dds"

local busy: { [Model]: boolean } = {}
local templateCache: { [string]: string } = {}

-- Accepts a catalog item id (looked up for its template) or a raw template image id.
local function resolveTemplate(id: number?, className: string, prop: string): string?
	if not id then
		return nil
	end
	local key = className .. id
	local cached = templateCache[key]
	if cached then
		return cached
	end
	local tpl = "rbxassetid://" .. id
	local ok, asset = pcall(InsertService.LoadAsset, InsertService, id)
	if ok and asset then
		local item = asset:FindFirstChildWhichIsA(className, true)
		if item then
			tpl = (item :: any)[prop]
		end
		asset:Destroy()
		templateCache[key] = tpl -- failures aren't cached, so junk IDs can't grow the cache
	end
	return tpl
end

local function setClothing(model: Model, className: string, prop: string, tpl: string?)
	if not tpl then
		return
	end
	local c = model:FindFirstChildOfClass(className) or Instance.new(className)
	;(c :: any)[prop] = tpl
	c.Parent = model
end

-- keypoint helpers: ns({{t, v}, ...}), cs({{t, color}, ...})
local function ns(points: { { number } }): NumberSequence
	local k = {}
	for _, p in points do
		table.insert(k, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(k)
end

local function cs(points: { { any } }): ColorSequence
	local k = {}
	for _, p in points do
		table.insert(k, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(k)
end

-- violet at birth, rotting through purple into black: the tips of every flame go dark
local FLAME_COLOR = cs({ { 0, WHITE_HOT }, { 0.12, MAGENTA }, { 0.45, PURPLE }, { 0.8, DEEP }, { 1, SOOT } })

-- Flame look shared by every fire layer:
-- LightEmission below 1 so stacked flames stay violet instead of adding up to white,
-- Squash > 0 stretches the round fire texture into tall tongues as they rise.
local FLAME = {
	Texture = FIRE_TEX,
	LightEmission = 0.25, -- mostly opaque: dark fire you can see against the sky, not a glow
	Squash = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, 0.9),
		NumberSequenceKeypoint.new(1, 1.6),
	}),
	-- stretched tongues must stay roughly upright, so no free spin
	Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
	Rotation = NumberRange.new(-12, 12),
	RotSpeed = NumberRange.new(-20, 20),
}

local function emitter(parent: Instance, made: { Instance }, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	-- low, not 1: additive glow on everything is what made the magic look like fairy light
	e.LightEmission = 0.3
	e.LightInfluence = 0
	e.Color = FLAME_COLOR
	e.Rotation = NumberRange.new(0, 360)
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	table.insert(made, e)
	return e
end

-- Flat particles lying on the ground: velocity points up, the face is perpendicular to it.
local FLAT = {
	Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
	EmissionDirection = Enum.NormalId.Top,
	Speed = NumberRange.new(0.01),
}

local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in extra do
		t[k] = v
	end
	return t
end

-- Stop, clear and destroy everything the effect made (skill rule: Enabled=false + Clear before Destroy).
local function cleanup(made: { Instance })
	for _, inst in made do
		if inst:IsA("ParticleEmitter") then
			inst.Enabled = false
			inst:Clear()
		end
		inst:Destroy()
	end
end

local function anchorPart(at: CFrame, size: Vector3, made: { Instance }): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = size
	p.CFrame = at
	p.Parent = workspace
	table.insert(made, p)
	Debris:AddItem(p, 15) -- backstop if the thread is killed outright
	return p
end

-- ===== Beyond particles: marks on the ground, beams, shockwaves, afterimages =====
-- Our own textures (vfx/make_textures.py), uploaded to the group.
local TEX_CHAIN = "rbxassetid://128829109917714"
local TEX_CRACKS = "rbxassetid://121817789379823"
local TEX_RUNES = "rbxassetid://110818878717565"
local TEX_RING = "rbxassetid://109175035979792"

-- How far below the root part the soles are. R6 rigs report HipHeight 0 (their legs aren't
-- counted), so their 2-stud legs are added by hand; R15 HipHeight already covers the legs.
local function soleDrop(hum: Humanoid, root: BasePart): number
	local legs = hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight
	return legs + root.Size.Y / 2
end

-- A texture lying flat on the ground: snaps in, optionally turns (radians/s), fades out by `life`.
local function groundMark(at: Vector3, size: number, tex: string, made: { Instance }, life: number, spin: number?): Part
	local p = anchorPart(CFrame.new(at + Vector3.new(0, 0.07, 0)), Vector3.new(size, 0.05, size), made)
	local d = Instance.new("Decal")
	d.Texture, d.Face, d.Transparency = tex, Enum.NormalId.Top, 1
	d.Parent = p
	TweenService:Create(d, TweenInfo.new(0.12), { Transparency = 0 }):Play()
	local fade = math.min(0.6, life)
	task.delay(life - fade, function()
		TweenService:Create(d, TweenInfo.new(fade, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
	end)
	if spin then
		local base, t0 = p.CFrame, os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			if not p.Parent then
				conn:Disconnect()
				return
			end
			p.CFrame = base * CFrame.Angles(0, (os.clock() - t0) * spin, 0)
		end)
	end
	return p
end

-- A ring tearing out across the ground; with `dome`, a dark ForceField bubble swells out and fades with it.
local function shockwave(at: Vector3, radius: number, made: { Instance }, dome: boolean?)
	local ring = groundMark(at, 1, TEX_RING, made, 0.5)
	local out = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(ring, out, { Size = Vector3.new(radius * 2, 0.05, radius * 2) }):Play()
	if dome then
		local s = anchorPart(CFrame.new(at), Vector3.one, made)
		s.Shape = Enum.PartType.Ball
		s.Material, s.Color, s.Transparency = Enum.Material.ForceField, MAGENTA, 0
		TweenService:Create(s, out, { Size = Vector3.one * radius * 1.4, Transparency = 1 }):Play()
	end
end

-- An iron chain between two attachments. It lashes out from nothing; `drop` shrinks it away over `over` seconds.
local function link(a0: Attachment, a1: Attachment, made: { Instance }): (over: number) -> ()
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = true
	b.LightEmission, b.LightInfluence = 0, 0
	b.Segments = 24
	b.TextureMode = Enum.TextureMode.Wrap
	b.Color = ColorSequence.new(Color3.new(1, 1, 1)) -- the texture carries the colour
	b.Texture, b.TextureLength = TEX_CHAIN, 2.6 -- one tile is two links: keeps the links round at this width
	local w0, w1 = 1.3, 1.3
	b.Width0, b.Width1 = 0, 0
	b.Parent = a0
	table.insert(made, b)
	TweenService:Create(b, TweenInfo.new(0.08), { Width0 = w0, Width1 = w1 }):Play()
	local t0, seed = os.clock(), math.random() * 100
	local conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		b.CurveSize0 = math.noise(t * 25, seed) * 0.4 -- a taut chain only shudders
	end)
	b.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return function(over: number)
		TweenService:Create(b, TweenInfo.new(over, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Width0 = 0, Width1 = 0 }):Play()
	end
end

-- Black silhouettes of a body left where it stood, drifting by `drift` as they fade.
local function afterimage(char: Model, made: { Instance }, drift: Vector3)
	for _, p in char:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 and p.Name ~= "HumanoidRootPart" then
			-- a plain box, not a clone: no scripts, joints or accessories come along
			local g = anchorPart(p.CFrame, p.Size, made)
			g.Material, g.Color, g.Transparency = Enum.Material.SmoothPlastic, SOOT, 0.2
			TweenService:Create(g, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				CFrame = p.CFrame + drift,
			}):Play()
		end
	end
end

-- Sounds: all from Roblox's licensed libraries (ProSoundEffects, DailySoundsFX), which play in any
-- experience; random user uploads get moderated and go silent.
local SFX = {
	FIRE = "rbxassetid://9112780462", -- fireplace, constant burning flame (loop)
	RISER = "rbxassetid://94077390731779", -- cinematic riser, 3.1s
	BOOM = "rbxassetid://94978851787238", -- deep impact boom
	WHOOSH = "rbxassetid://80984744279155", -- fast whoosh, 0.9s
	BONES = "rbxassetid://9113542694", -- bone cracks
	ROCKS = "rbxassetid://9116327457", -- loose rocks falling
	HIT = "rbxassetid://9113520731", -- body hit
	WAIL = "rbxassetid://129823359634605", -- ghost wail, 5.2s
}

-- A 3D sound on a part or attachment, heard by everyone nearby.
local function sound(parent: Instance, id: string, props: { [string]: any }?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.6
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance, s.RollOffMaxDistance = 12, 150
	for k, v in props or {} do
		(s :: any)[k] = v
	end
	s.Parent = parent
	return s
end

-- Fire and forget: plays once and removes itself.
local function sfx(parent: Instance, id: string, props: { [string]: any }?)
	local s = sound(parent, id, props)
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	Debris:AddItem(s, 10) -- in case it never loads, so Ended never fires
end

-- A looping sound that fades in; it's in `made`, so cleanup removes it. Fade it out before then.
local function loop(parent: Instance, id: string, made: { Instance }, volume: number, props: { [string]: any }?): Sound
	local s = sound(parent, id, props)
	s.Looped, s.Volume = true, 0
	table.insert(made, s)
	s:Play()
	TweenService:Create(s, TweenInfo.new(0.3), { Volume = volume }):Play()
	return s
end

local function fadeOut(s: Sound, over: number)
	TweenService:Create(s, TweenInfo.new(over), { Volume = 0 }):Play()
end

-- turbulent entries: {emitter, sideways strength, upward accel, base rate?}. Acceleration also
-- moves live particles, so this whips the flames; the rate wobble makes them flare and sag
-- (real fire is never steady). Call at ~10 Hz to keep replication light.
local function gust(turbulent: { { any } }, now: number)
	for i, t in turbulent do
		local s = t[2]
		t[1].Acceleration = Vector3.new(math.noise(now * 1.8, i) * s, t[3], math.noise(i, now * 1.8) * s)
		if t[4] then
			t[1].Rate = t[4] * (1 + math.noise(now * 3, i, 7) * 0.9)
		end
	end
end

-- Body fire that climbs. On a real body burn the fire races up from the feet, grows toward
-- the shoulders and head, and swallows the figure; each part catches when the flame front
-- reaches its height, with a burst as it does. Wicks are thin tongues tearing off above the head.
-- Returns {emitter, height 0..1} per part, and the wick emitter.
local function igniteBody(model: Model, root: BasePart, made: { Instance }, turbulent: { { any } }): ({ { any } }, ParticleEmitter)
	local parts = {}
	local lowY, highY, top = math.huge, -math.huge, root
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			table.insert(parts, p)
			lowY = math.min(lowY, p.Position.Y)
			if p.Position.Y > highY then
				highY, top = p.Position.Y, p
			end
		end
	end
	local span = math.max(highY - lowY, 0.1)
	local flames: { { any } } = {}
	for _, p in parts do
		local f = (p.Position.Y - lowY) / span
		local grow = 1 + 0.7 * f -- flames get bigger the higher they are on the body
		local e = emitter(p, made, with(FLAME, {
			Enabled = false,
			Rate = 20,
			Lifetime = NumberRange.new(0.35, 0.65),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0, 14, 0),
			Size = ns({ { 0, 0.7 * grow }, { 0.25, 1.8 * grow }, { 1, 0 } }),
			-- see-through edges at birth and death, solid in the middle of life
			Transparency = ns({ { 0, 0.45 }, { 0.15, 0.05 }, { 0.7, 0.35 }, { 1, 1 } }),
			Brightness = 2,
		}))
		table.insert(flames, { e, f })
		table.insert(turbulent, { e, 18, 14, 20 })
		task.delay(f * CLIMB, function()
			e.Enabled = true
			e:Emit(6)
		end)
	end

	local wickAtt = Instance.new("Attachment")
	wickAtt.Position = Vector3.new(0, top.Size.Y / 2 + 0.6, 0)
	wickAtt.Parent = top
	table.insert(made, wickAtt)
	local wicks = emitter(wickAtt, made, with(FLAME, {
		Enabled = false,
		Rate = 18,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(8, 13),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, 8, 0),
		Size = ns({ { 0, 0.3 }, { 0.3, 1.2 }, { 1, 0 } }),
		Squash = ns({ { 0, 0.5 }, { 1, 2.2 } }),
		Transparency = ns({ { 0, 0.6 }, { 0.2, 0.1 }, { 1, 1 } }),
		Brightness = 2.5,
	}))
	table.insert(turbulent, { wicks, 25, 8, 18 })
	task.delay(CLIMB, function()
		wicks.Enabled = true
	end)
	return flames, wicks
end

-- Flames die from the head down to the feet over `over` seconds (the reverse of the climb).
local function witherBody(flames: { { any } }, over: number)
	for _, fl in flames do
		task.delay((1 - fl[2]) * over, function()
			fl[1].Enabled = false
		end)
	end
end

local function burn(model: Model, hum: Humanoid, root: BasePart, made: { Instance }, shirtTpl: string?, pantsTpl: string?)
	-- vortex disc at the feet; LockedToPart emitters ride its spin
	local feet = root.CFrame * CFrame.new(0, -soleDrop(hum, root) + 0.15, 0)
	local disc = Instance.new("Part")
	disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch = true, false, false, false
	disc.Transparency = 1
	disc.Size = Vector3.new(1, 0.2, 1)
	disc.CFrame = feet
	disc.Parent = workspace
	table.insert(made, disc)
	Debris:AddItem(disc, 12) -- backstop if the thread is killed outright

	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = MAGENTA, 18, 0, true
	light.Parent = disc
	TweenService:Create(light, TweenInfo.new(0.9), { Brightness = 3 }):Play()
	-- a rune circle burns into the ground under them, turning against the vortex
	groundMark(feet.Position, 10, TEX_RUNES, made, 6.5, -1.2)

	-- 1. spinning vortex sigil on the ground
	local sigil = emitter(disc, made, with(FLAT, {
		Texture = VORTEX_TEX,
		LockedToPart = true,
		Rate = 8,
		Lifetime = NumberRange.new(1.1, 1.4),
		Size = ns({ { 0, 2 }, { 0.4, 8 }, { 1, 9.5 } }),
		Transparency = ns({ { 0, 1 }, { 0.25, 0.15 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(220, 300),
		Color = cs({ { 0, MAGENTA }, { 1, DEEP } }),
		Brightness = 3,
	}))

	-- 2. flame tongues spiralling up from a ring around the feet
	-- (10 small emitters rather than one Disc-shaped one: keeps each under the mobile per-emitter rate cap)
	local swirls = { sigil }
	for i = 1, 10 do
		local a = Instance.new("Attachment")
		local ang = i / 10 * math.pi * 2
		a.Position = Vector3.new(math.cos(ang) * 3.6, 0, math.sin(ang) * 3.6)
		a.Parent = disc
		table.insert(swirls, emitter(a, made, with(FLAME, {
			LockedToPart = true,
			Rate = 40,
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(1, 2.5),
			Acceleration = Vector3.new(0, 14, 0),
			Drag = 2,
			Size = ns({ { 0, 0.4 }, { 0.3, 1.3 }, { 1, 0 } }),
			Transparency = ns({ { 0, 0.6 }, { 0.2, 0.05 }, { 1, 1 } }),
			Brightness = 2,
		})))
	end


	local spin = 0
	local start = os.clock()
	local burning = false
	local nextGust = 0
	local turbulent: { { any } } = {}
	local conn = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		spin += dt * math.min(14, 3 + (now - start) * 7)
		disc.CFrame = feet * CFrame.Angles(0, spin, 0)
		if burning then
			light.Brightness = 5 + math.noise(now * 9) * 3 -- flicker
			if now >= nextGust then -- 10 Hz is plenty and keeps replication light
				nextGust = now + 0.1
				gust(turbulent, now)
			end
		end
	end)
	disc.Destroying:Connect(function()
		conn:Disconnect()
	end)

	task.wait(0.8)

	-- ignition: ground shockwave + light spike
	local ring = emitter(disc, made, with(FLAT, {
		Texture = RING_TEX,
		Rate = 0,
		Lifetime = NumberRange.new(0.45),
		Size = ns({ { 0, 1 }, { 1, 18 } }),
		Transparency = ns({ { 0, 0 }, { 1, 1 } }),
		Color = cs({ { 0, WHITE_HOT }, { 1, PURPLE } }),
		Brightness = 4,
	}))
	ring:Emit(2)
	shockwave(feet.Position, 13, made, true)
	groundMark(feet.Position, 9, TEX_CRACKS, made, 6)
	rumble(feet.Position, 70, 0.6, 0.45)
	light.Brightness = 14
	burning = true

	local rootAtt = Instance.new("Attachment")
	rootAtt.Position = Vector3.new(0, -1, 0)
	rootAtt.Parent = root
	table.insert(made, rootAtt)

	-- Layers below follow the skill's stack: soot, core flame, glow, sparks.
	-- Sizes are the fill-rate cost, so the big layers keep low Rates.

	-- 3. dark soot behind the flames; additive fire only reads as bright against something dark
	local soot = emitter(rootAtt, made, {
		Texture = SMOKE_TEX,
		LightEmission = 0,
		Color = cs({ { 0, DEEP }, { 1, SOOT } }),
		Rate = 10,
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(4, 7),
		SpreadAngle = Vector2.new(20, 20),
		Size = ns({ { 0, 3 }, { 1, 9 } }),
		Transparency = ns({ { 0, 1 }, { 0.2, 0.45 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(-30, 30),
		ZOffset = -2,
	})

	-- 4. the main column that swallows the body
	local column = emitter(rootAtt, made, with(FLAME, {
		Enabled = false, -- roars up once the climb is most of the way up the body
		Rate = 36,
		Lifetime = NumberRange.new(0.6, 0.95),
		Speed = NumberRange.new(6, 11),
		SpreadAngle = Vector2.new(14, 14),
		Acceleration = Vector3.new(0, 6, 0),
		Drag = 1.5,
		Size = ns({ { 0, 2.5 }, { 0.35, 4.5 }, { 1, 0.5 } }),
		Transparency = ns({ { 0, 0.5 }, { 0.15, 0.1 }, { 1, 1 } }),
		Brightness = 2.5,
	}))
	table.insert(turbulent, { column, 40, 6, 36 })
	task.delay(CLIMB * 0.6, function()
		column.Enabled = true
	end)

	-- 5. soft halo: very large, very faint, few particles
	local glow = emitter(root, made, {
		Texture = GLOW_TEX,
		Color = cs({ { 0, MAGENTA }, { 1, PURPLE } }),
		Rate = 5,
		Lifetime = NumberRange.new(0.5, 0.7),
		Speed = NumberRange.new(0),
		Size = ns({ { 0, 8 }, { 1, 11 } }),
		Transparency = ns({ { 0, 1 }, { 0.3, 0.7 }, { 1, 1 } }),
		Brightness = 2,
		ZOffset = -1,
	})

	-- 6. white-hot core drawn in front of everything
	local core = emitter(root, made, {
		Texture = FIRE_TEX,
		Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
		Rate = 25,
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(1, 2),
		Size = ns({ { 0, 2.5 }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.3 }, { 1, 1 } }),
		Brightness = 5,
		ZOffset = 1,
	})

	-- 7. embers as streaks that whip upward
	local embers = emitter(rootAtt, made, {
		Texture = EMBER_TEX,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rate = 50,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, 10, 0),
		Drag = 2.5,
		Size = ns({ { 0, 0.35 }, { 1, 0 } }),
		Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
		Brightness = 6,
	})

	-- 8 + 9. body fire that climbs, plus wicks off the head
	local flames, wicks = igniteBody(model, root, made, turbulent)

	local hl = Instance.new("Highlight")
	hl.FillColor, hl.OutlineColor = SOOT, MAGENTA
	hl.FillTransparency, hl.OutlineTransparency = 1, 1
	hl.Parent = model
	table.insert(made, hl)
	TweenService:Create(hl, TweenInfo.new(0.5), { FillTransparency = 0.02, OutlineTransparency = 0 }):Play()

	task.wait(1.4)
	if model.Parent then
		setClothing(model, "Shirt", "ShirtTemplate", shirtTpl)
		setClothing(model, "Pants", "PantsTemplate", pantsTpl)
	end
	task.wait(0.4)

	-- wither: the reverse of the climb, taken slowly. Flames die from the head down to the feet,
	-- each body part shedding ash as its flame goes out; the column, core and glow thin out rather
	-- than switching off; the ring of tongues around the feet gutters out one by one; the sigil,
	-- soot and embers trail off last. Nothing is cut off: cleanup waits for the last particle.
	local FADE = 2.4
	local slow = TweenInfo.new(FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	burning = false
	TweenService:Create(wicks, TweenInfo.new(0.6), { Rate = 0 }):Play()
	witherBody(flames, FADE * 0.7)
	for _, fl in flames do
		local part = fl[1].Parent
		task.delay((1 - fl[2]) * FADE * 0.7, function()
			if part and part.Parent then
				emitter(part, made, {
					Rate = 0,
					Texture = EMBER_TEX,
					Color = cs({ { 0, MAGENTA }, { 1, DEEP } }),
					Lifetime = NumberRange.new(0.9, 1.5),
					Speed = NumberRange.new(1, 3),
					SpreadAngle = Vector2.new(60, 60),
					Acceleration = Vector3.new(0, 7, 0),
					Drag = 1,
					Size = ns({ { 0, 0.3 }, { 1, 0 } }),
					Brightness = 3,
				}):Emit(8)
			end
		end)
	end
	for _, e in { column, core, glow, soot, embers, swirls[1] } do
		TweenService:Create(e, slow, { Rate = 0 }):Play()
	end
	for i = 2, #swirls do -- swirls[1] is the sigil
		task.delay((i - 2) / (#swirls - 1) * FADE * 0.8, function()
			swirls[i].Enabled = false
		end)
	end
	TweenService:Create(hl, TweenInfo.new(FADE, Enum.EasingStyle.Sine), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(FADE + 0.4, Enum.EasingStyle.Sine), { Brightness = 0 }):Play()
	emitter(root, made, {
		Texture = SPARK_TEX,
		Rate = 0,
		Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
		Size = ns({ { 0, 0.5 }, { 1, 0 } }),
		Brightness = 4,
	}):Emit(40)

	task.wait(FADE)
	for _, e in made do
		if e:IsA("ParticleEmitter") then
			e.Enabled = false -- stop new particles; the live ones finish on their own
		end
	end
	task.wait(1.9) -- longest live particle (soot, 1.8s) finishes before cleanup
end

local function play(model: Model, hum: Humanoid, shirtTpl: string?, pantsTpl: string?)
	local root = hum.RootPart :: BasePart
	local wasAnchored = root.Anchored
	root.Anchored = true
	local made: { Instance } = {}
	-- cleanup and unanchor run even if the effect errors midway
	local ok, err = pcall(burn, model, hum, root, made, shirtTpl, pantsTpl)
	cleanup(made)
	if root.Parent then
		root.Anchored = wasAnchored
	end
	if not ok then
		error(err, 0)
	end
end

-- ===== Melt: purple fire kills the target, the body collapses and burns down to a skeleton =====

local WARN = 1.5 -- seconds the victim is visibly marked before the fire takes them
local KILL_AFTER = 1.0 -- seconds of burning before death
local BONES_AFTER = 1.0 -- seconds after death before the body is bones

-- Roblox's classic skeleton, built the way Roblox's own "Skeleton" model is: CharacterMeshes
-- for the R6 torso and limbs (Roblox places each bone on its limb), and the skull on the head.
local BONE_TEX = 36780292
local LIMB_BONES: { [Enum.BodyPart]: number } = {
	[Enum.BodyPart.Torso] = 36780113,
	[Enum.BodyPart.LeftArm] = 36780032,
	[Enum.BodyPart.RightArm] = 36780156,
	[Enum.BodyPart.LeftLeg] = 36780079,
	[Enum.BodyPart.RightLeg] = 36780195,
}
local STRIP = { "Shirt", "Pants", "ShirtGraphic", "CharacterMesh", "BodyColors", "Accessory", "Hat", "Clothing" }
local R6_PARTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

-- Turn an R6 body into the bone skeleton in place: the limbs keep their positions and joints,
-- they just render as bones. R15 bodies can't take these meshes, so they are charred black instead.
local function skeletonize(model: Model)
	for _, c in model:GetChildren() do
		for _, cls in STRIP do
			if c:IsA(cls) then
				c:Destroy()
				break
			end
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.RigType == Enum.HumanoidRigType.R6) then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				p.Color, p.Material = SOOT, Enum.Material.Slate
			end
		end
		return
	end
	for bodyPart, meshId in LIMB_BONES do
		local cm = Instance.new("CharacterMesh")
		cm.BodyPart, cm.MeshId, cm.OverlayTextureId = bodyPart, meshId, BONE_TEX
		cm.Parent = model
	end
	for _, name in R6_PARTS do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = Color3.new(1, 1, 1)
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		for _, d in head:GetChildren() do
			if d:IsA("DataModelMesh") or d:IsA("Decal") then
				d:Destroy() -- head mesh, face
			end
		end
		local skull = Instance.new("SpecialMesh")
		skull.MeshType = Enum.MeshType.FileMesh
		skull.MeshId, skull.TextureId = "rbxassetid://36869983", "rbxassetid://36869975"
		skull.Scale = Vector3.new(0.95, 0.9, 0.95)
		skull.Offset = Vector3.new(0, 0, -0.1) -- where Roblox's skull hat sits on the head
		skull.Parent = head
	end
end

-- R6 ragdoll: the limb motors are switched off and ball sockets hold the limbs instead (same
-- approach as RagdollDeath/ragdoll.luau). Returns a function that stands a living body back up;
-- the dead just ignore it.
local RAGDOLL_JOINTS = { "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }
local function ragdoll(model: Model): () -> ()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local torso = model:FindFirstChild("Torso")
	local made: { Instance } = {}
	local motors: { Motor6D } = {}
	local collide: { [BasePart]: boolean } = {}
	if hum then
		hum.PlatformStand = true -- limp; the Humanoid stops trying to stand
		if hum.Health > 0 then
			-- a living Humanoid still balances itself upright unless it's put in the Physics state
			hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end
	if torso and torso:IsA("BasePart") then
		for _, name in RAGDOLL_JOINTS do
			local joint = torso:FindFirstChild(name)
			if joint and joint:IsA("Motor6D") and joint.Enabled and joint.Part0 and joint.Part1 then
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.CFrame, a1.CFrame = joint.C0, joint.C1
				a0.Parent, a1.Parent = joint.Part0, joint.Part1
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0, socket.Attachment1 = a0, a1
				socket.LimitsEnabled, socket.TwistLimitsEnabled = true, true
				socket.UpperAngle, socket.TwistLowerAngle, socket.TwistUpperAngle = 75, -45, 45
				socket.Parent = joint.Part0
				table.insert(made, a0)
				table.insert(made, a1)
				table.insert(made, socket)
				joint.Enabled = false
				table.insert(motors, joint)
			end
		end
		-- limbs collide so the body folds onto the ground instead of through itself
		for _, name in R6_PARTS do -- body parts only, not hex skulls or skeleton eyes
			local p = model:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				collide[p] = p.CanCollide
				p.CanCollide = true
			end
		end
	end
	return function()
		if not (hum and hum.Parent and hum.Health > 0) then
			return -- died while down: stays a ragdoll
		end
		for _, m in motors do
			m.Enabled = true
		end
		for _, inst in made do
			inst:Destroy()
		end
		for p, c in collide do
			p.CanCollide = c
		end
		hum.PlatformStand = false
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		-- set the body upright where it lay, facing the way it was facing; climbing up from flat stumbles
		local root = hum.RootPart
		if root then
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude < 0.2 then
				flat = Vector3.new(root.CFrame.UpVector.X, 0, root.CFrame.UpVector.Z)
			end
			flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis
			model:PivotTo(CFrame.lookAt(root.Position + Vector3.new(0, 2, 0), root.Position + Vector3.new(0, 2, 0) + flat))
			root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function melt(model: Model, hum: Humanoid, root: BasePart, made: { Instance })
	-- our own ragdoll + skeleton replaces the place's ragdoll script and joint-breaking
	model:SetAttribute("SuppressRagdoll", true)
	hum.BreakJointsOnDeath = false

	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = MAGENTA, 18, 0, true
	light.Parent = root
	table.insert(made, light)

	local rootAtt = Instance.new("Attachment")
	rootAtt.Position = Vector3.new(0, -1, 0)
	rootAtt.Parent = root
	table.insert(made, rootAtt)

	-- outline that pulses during the warning, then becomes the char silhouette in the fire
	local hl = Instance.new("Highlight")
	hl.FillColor, hl.OutlineColor = SOOT, MAGENTA
	hl.FillTransparency, hl.OutlineTransparency = 1, 1
	hl.Parent = model
	table.insert(made, hl)

	local turbulent: { { any } } = {}
	local phase = "warn"
	local warnStart = os.clock()
	local nextGust = 0
	local conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if phase == "warn" then
			-- pulse quickens and the light swells as ignition nears
			local k = math.clamp((now - warnStart) / WARN, 0, 1)
			hl.OutlineTransparency = 0.15 + 0.6 * (0.5 + 0.5 * math.cos((now - warnStart) * (6 + 14 * k)))
			light.Brightness = 1 + 3 * k
		elseif phase == "burn" then
			light.Brightness = 6 + math.noise(now * 9) * 3
		end
		if now >= nextGust then
			nextGust = now + 0.1
			gust(turbulent, now)
		end
	end)
	hl.Destroying:Connect(function() -- hl goes in cleanup, even on error, so this can't leak
		conn:Disconnect()
	end)

	-- Warning: the victim is marked before they burn. A sigil glows and spins under their feet,
	-- sparks start drifting off them, and the outline pulses faster until the fire takes them.
	local feetAtt = Instance.new("Attachment")
	feetAtt.Position = Vector3.new(0, -soleDrop(hum, root) + 0.15, 0)
	feetAtt.Parent = root
	table.insert(made, feetAtt)
	local sigil = emitter(feetAtt, made, with(FLAT, {
		Texture = VORTEX_TEX,
		LockedToPart = true,
		Rate = 6,
		Lifetime = NumberRange.new(1, 1.3),
		Size = ns({ { 0, 1.5 }, { 0.5, 6.5 }, { 1, 7.5 } }),
		Transparency = ns({ { 0, 1 }, { 0.3, 0.25 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(160, 240),
		Color = cs({ { 0, MAGENTA }, { 1, DEEP } }),
		Brightness = 3,
	}))
	local motes = emitter(rootAtt, made, {
		Texture = EMBER_TEX,
		Rate = 10,
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, 4, 0),
		Size = ns({ { 0, 0.2 }, { 1, 0 } }),
		Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
		Brightness = 4,
	})
	-- the mark: a rune circle under them, turning faster as the warning runs out
	local runes = groundMark(feetAtt.WorldPosition, 8, TEX_RUNES, made, WARN + 0.3, 1)
	-- the warning builds: more motes, faster spin
	TweenService:Create(motes, TweenInfo.new(WARN, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rate = 60 }):Play()
	TweenService:Create(runes, TweenInfo.new(WARN, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(5, 0.05, 5) }):Play()
	TweenService:Create(sigil, TweenInfo.new(WARN), { Rate = 14 }):Play()
	-- the riser's tail, timed to peak as the fire takes them
	task.wait(WARN - 0.25)
	-- last beat: light gets sucked inward, then ignition
	emitter(rootAtt, made, {
		Texture = IMPLODE_TEX,
		Rate = 0,
		Lifetime = NumberRange.new(0.25),
		Speed = NumberRange.new(0),
		Size = ns({ { 0, 9 }, { 1, 1 } }),
		Transparency = ns({ { 0, 1 }, { 0.4, 0.3 }, { 1, 1 } }),
		Color = cs({ { 0, MAGENTA }, { 1, WHITE_HOT } }),
		Brightness = 4,
	}):Emit(1)
	task.wait(0.25)
	if not model.Parent then
		return
	end
	phase = "burn"
	sigil.Enabled, motes.Enabled = false, false
	light.Brightness = 14 -- ignition flash
	shockwave(feetAtt.WorldPosition, 9, made, true)
	groundMark(feetAtt.WorldPosition, 8, TEX_CRACKS, made, KILL_AFTER + BONES_AFTER + 3.5)
	rumble(root.Position, 60, 0.45, 0.35)
	TweenService:Create(hl, TweenInfo.new(0.6), { FillTransparency = 0.05, OutlineTransparency = 0.2 }):Play()

	local soot = emitter(rootAtt, made, {
		Texture = SMOKE_TEX,
		LightEmission = 0,
		Color = cs({ { 0, DEEP }, { 1, SOOT } }),
		Rate = 12,
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(4, 7),
		SpreadAngle = Vector2.new(20, 20),
		Size = ns({ { 0, 3 }, { 1, 9 } }),
		Transparency = ns({ { 0, 1 }, { 0.2, 0.4 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(-30, 30),
		ZOffset = -2,
	})
	local embers = emitter(rootAtt, made, {
		Texture = EMBER_TEX,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rate = 40,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, 10, 0),
		Drag = 2.5,
		Size = ns({ { 0, 0.35 }, { 1, 0 } }),
		Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
		Brightness = 6,
	})
	local flames, wicks = igniteBody(model, root, made, turbulent)

	task.wait(KILL_AFTER)
	if not model.Parent then
		return
	end
	-- death: collapse burning
	rumble(root.Position, 50, 0.35, 0.6)
	hum.Health = 0
	ragdoll(model)
	root.AssemblyAngularVelocity += root.CFrame.RightVector * 6

	task.wait(BONES_AFTER)
	if not model.Parent then
		return
	end
	-- flare up and swap the flesh for bones while the fire hides it
	for _, fl in flames do
		fl[1]:Emit(10)
	end
	light.Brightness = 14
	skeletonize(model)
	model:SetAttribute("MeltCorpse", true) -- Raise can bring these bones back up

	task.wait(0.3)
	-- burn out: flames die head to feet, the char fades off the bones, smoke lingers
	phase = "out"
	wicks.Enabled = false
	witherBody(flames, 0.6)
	embers.Rate, soot.Rate = 12, 5
	TweenService:Create(hl, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(1.6), { Brightness = 0 }):Play()

	task.wait(1.6)
	embers.Enabled, soot.Enabled = false, false
	task.wait(1.9) -- let the last smoke finish before cleanup
end

local function playMelt(model: Model, hum: Humanoid)
	local made: { Instance } = {}
	local ok, err = pcall(melt, model, hum, hum.RootPart :: BasePart, made)
	cleanup(made)
	if not ok then
		error(err, 0)
	end
end

local function validId(v: any): number?
	if typeof(v) == "number" and v == v and v >= 1 and v < 2 ^ 53 and v % 1 == 0 then
		return v
	end
	return nil
end

-- ===== Shared by the combat spells: sides, the ground, live characters =====

-- Friends follow the place's convention (AI/Shared/Sides.luau): a player's Roblox team, or the
-- Team value an NPC carries. A caster's own skeletons are always on the caster's side.
local skeletonOwner: { [Model]: Player } = {}

local function teamOf(player: Player): string?
	local team = player.Team
	return (not player.Neutral and team) and team.Name or nil
end

local function sideOf(model: Model): string?
	local player = skeletonOwner[model] or Players:GetPlayerFromCharacter(model)
	if player then
		return teamOf(player)
	end
	local settings = model:FindFirstChild("Settings")
	local tag = (model:FindFirstChild("Team") or (settings and settings:FindFirstChild("Team"))) :: any
	return (tag and tag:IsA("StringValue") and tag.Value ~= "") and tag.Value or nil
end

local function isFriend(caster: Player, model: Model): boolean
	if model == caster.Character or skeletonOwner[model] == caster then
		return true
	end
	local mine = teamOf(caster)
	return mine ~= nil and sideOf(model) == mine
end

-- The humanoid and root of a living character, or nil.
local function alive(model: Instance?): (Humanoid?, BasePart?)
	if not (model and model.Parent and model:IsA("Model")) then
		return nil, nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and hum.RootPart then
		return hum, hum.RootPart
	end
	return nil, nil
end

-- Kill someone so they ragdoll. Players already ragdoll through the place's RagdollDeath
-- script; NPCs (and skeletons) don't, so they get the same R6 ragdoll melt uses.
local function killRagdoll(hum: Humanoid, health: number?)
	local model = hum.Parent
	local lethal = (health or 0) <= 0
	local npc = lethal and model ~= nil and model:IsA("Model") and not Players:GetPlayerFromCharacter(model)
	if npc then
		hum.BreakJointsOnDeath = false -- must be off before death, or the joints are already gone
	end
	hum.Health = health or 0
	if npc then
		ragdoll(model :: Model)
		local root = hum.RootPart
		if root then
			-- knock it over backwards; a limp body can otherwise balance on its legs
			root.AssemblyLinearVelocity += -root.CFrame.LookVector * 6
			root.AssemblyAngularVelocity = root.CFrame.RightVector * 8
		end
	end
end

-- Spell damage: TakeDamage (so ForceFields still block it), with a ragdoll if it's the killing blow.
local function hurt(hum: Humanoid, amount: number)
	local model = hum.Parent
	if hum.Health - amount > 0 or (model and model:FindFirstChildOfClass("ForceField")) then
		hum:TakeDamage(amount)
	else
		killRagdoll(hum)
	end
end

-- Every Humanoid in the world, kept current, so the skeletons never have to scan the map.
local humanoids: { [Humanoid]: boolean } = {}
for _, d in workspace:GetDescendants() do
	if d:IsA("Humanoid") then
		humanoids[d] = true
	end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then
		humanoids[d] = true
	end
end)
workspace.DescendantRemoving:Connect(function(d)
	if d:IsA("Humanoid") then
		humanoids[d] = nil
	end
end)

local function characters(): { Instance }
	local list: { Instance } = {}
	for hum in humanoids do
		if hum.Parent then
			table.insert(list, hum.Parent)
		end
	end
	return list
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- decorative non-solid parts aren't floor

-- The floor under a point, ignoring every character standing around; false if there's none
-- within 40 studs (a cliff edge or a gap).
local function groundBelow(pos: Vector3): (Vector3, boolean)
	rayParams.FilterDescendantsInstances = characters()
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), rayParams)
	if hit then
		return hit.Position, true
	end
	return pos, false
end

-- A spot about `radius` from `center` with solid floor at roughly the same height as the floor
-- under `center`, so nothing gets summoned over a drop. Tries `preferred` first, then a circle.
local function solidSpot(center: Vector3, radius: number, preferred: Vector3?): Vector3
	local floor, found = groundBelow(center)
	local function ok(p: Vector3): boolean
		local g, hit = groundBelow(Vector3.new(p.X, center.Y, p.Z))
		return hit and found and math.abs(g.Y - floor.Y) < 4
	end
	if preferred and ok(preferred) then
		return preferred
	end
	local start = math.random() * math.pi * 2
	for i = 0, 7 do
		local ang = start + i / 8 * math.pi * 2
		local p = center + Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius)
		if ok(p) then
			return p
		end
	end
	return center -- nowhere solid nearby: right at their feet
end

-- A dark hole in the ground: a pool of soot, a slow sigil turning the wrong way, and dark-violet
-- flame licking up out of it. Raise climbs out of these; shadow step sinks into and out of them.
local function hole(at: Vector3, size: number, made: { Instance }): { ParticleEmitter }
	local p = anchorPart(CFrame.new(at + Vector3.new(0, 0.12, 0)), Vector3.new(size * 0.55, 0.2, size * 0.55), made)
	groundMark(at, size * 1.5, TEX_CRACKS, made, 2.4) -- the ground splits open around it
	local pool = emitter(p, made, with(FLAT, {
		Texture = SMOKE_TEX,
		LightEmission = 0,
		Color = cs({ { 0, SOOT }, { 1, SOOT } }),
		Rate = 10,
		Lifetime = NumberRange.new(1.2, 1.6),
		Size = ns({ { 0, size * 0.4 }, { 0.3, size }, { 1, size * 1.1 } }),
		Transparency = ns({ { 0, 1 }, { 0.25, 0.1 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(-20, 20),
		ZOffset = -1,
	}))
	local rim = emitter(p, made, with(FLAT, {
		Texture = VORTEX_TEX,
		LockedToPart = true,
		Rate = 5,
		Lifetime = NumberRange.new(1, 1.3),
		Size = ns({ { 0, size * 0.6 }, { 1, size * 1.15 } }),
		Transparency = ns({ { 0, 1 }, { 0.3, 0.3 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(-160, -110),
		Color = cs({ { 0, MAGENTA }, { 1, DEEP } }),
		Brightness = 2,
	}))
	-- a tighter, brighter whirlpool turning faster inside the rim
	local swirl = emitter(p, made, with(FLAT, {
		Texture = VORTEX_TEX,
		LockedToPart = true,
		Rate = 8,
		Lifetime = NumberRange.new(0.8, 1.1),
		Size = ns({ { 0, size * 0.25 }, { 1, size * 0.85 } }),
		Transparency = ns({ { 0, 1 }, { 0.25, 0.1 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(-300, -230),
		Color = cs({ { 0, WHITE_HOT }, { 0.3, MAGENTA }, { 1, PURPLE } }),
		Brightness = 3,
		ZOffset = 0.5,
	}))
	local licks = emitter(p, made, with(FLAME, {
		Rate = 30,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(2, 4),
		Acceleration = Vector3.new(0, 10, 0),
		Size = ns({ { 0, 0.4 }, { 0.3, 1.2 }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.6 }, { 0.2, 0.15 }, { 1, 1 } }),
		Color = cs({ { 0, MAGENTA }, { 0.4, PURPLE }, { 1, SOOT } }),
		Brightness = 1.5,
	}))
	return { pool, rim, swirl, licks }
end

local function burst(parent: Instance, made: { Instance }, props: { [string]: any }, count: number)
	local e = emitter(parent, made, props)
	e.Rate = 0
	e:Emit(count)
end

-- earth thrown up when something breaks through the ground
local DIRT = {
	Texture = SMOKE_TEX,
	LightEmission = 0,
	Color = cs({ { 0, Color3.fromRGB(70, 55, 48) }, { 1, Color3.fromRGB(30, 24, 24) } }),
	Lifetime = NumberRange.new(0.8, 1.3),
	Speed = NumberRange.new(7, 13),
	SpreadAngle = Vector2.new(45, 45),
	EmissionDirection = Enum.NormalId.Top,
	Acceleration = Vector3.new(0, -25, 0),
	Drag = 1.5,
	Size = ns({ { 0, 1 }, { 1, 3 } }),
	Transparency = ns({ { 0, 0.2 }, { 1, 1 } }),
	RotSpeed = NumberRange.new(-60, 60),
}

local function disableAll(emitters: { Instance })
	for _, e in emitters do
		if e:IsA("ParticleEmitter") then
			e.Enabled = false
		end
	end
end

-- ===== Raise: skeletons climb out of the ground and fight for the caster =====

local SKELETON_CAP = 6 -- alive per caster; summoning past it crumbles the oldest
local SKELETON_LIFE = 10 -- then it collapses as a ragdoll
local SKELETON_HEALTH = 60
local RAISE_GUARDS = 3 -- when nobody is selected
local SWIPE_DAMAGE = 15
local SWIPE_EVERY = 0.8
local SWIPE_REACH = 4.5
local GUARD_RADIUS = 12 -- guards attack anyone this close to the caster...
local THREAT_RADIUS = 40 -- ...or this close, for a few seconds after the caster gets hurt
local LEASH = 60 -- hexed enemies are hunted from this far
local RISE = 1.0
local THINK = 0.15

-- Roblox's own R6 animations, which any game can load.
local WALK_ANIM = "rbxassetid://180426354"
local IDLE_ANIM = "rbxassetid://180435571"
local SWIPE_ANIM = "rbxassetid://129967390"

type Minion = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	owner: Player,
	assigned: Model?, -- the person it was raised to hunt
	born: number,
	slot: number,
	lastSwipe: number,
	ready: boolean,
	dead: boolean,
	walk: AnimationTrack,
	idle: AnimationTrack,
	swipe: AnimationTrack,
}
local minions: { Minion } = {} -- oldest first
local hexUntil: { [Humanoid]: number } = {} -- filled by hex; skeletons go for these first

local function loadTrack(hum: Humanoid, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local track = (animator :: Animator):LoadAnimation(anim)
	track.Looped, track.Priority = looped, priority
	return track
end

local function kill(mn: Minion)
	if mn.dead then
		return
	end
	mn.dead = true
	local i = table.find(minions, mn)
	if i then
		table.remove(minions, i)
	end
	skeletonOwner[mn.model] = nil
	mn.root.Anchored = false
	for _, t in { mn.walk, mn.idle, mn.swipe } do
		t:Stop(0)
	end
	-- collapse as a ragdoll (whether its time ran out or something killed it)
	killRagdoll(mn.hum)
	-- the bones lie there a moment, then fade into dust
	task.delay(2.5, function()
		for _, p in mn.model:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				TweenService:Create(p, TweenInfo.new(1.2), { Transparency = 1 }):Play()
			end
		end
		local torso = mn.model:FindFirstChild("Torso")
		if torso then
			burst(torso, {}, with(DIRT, { Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, 2, 0) }), 8)
		end
	end)
	Debris:AddItem(mn.model, 4.5)
end

local function buildSkeleton(): Model
	local m = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	m.Name = "Skeleton"
	for _, d in m:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- default Animate/Health scripts; the AI below drives it
		end
	end
	skeletonize(m)
	local hum = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.BreakJointsOnDeath = false -- however it dies, kill() ragdolls it
	-- the tilted climb out of the ground would otherwise leave it toppling over as it gets free
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum.MaxHealth, hum.Health = SKELETON_HEALTH, SKELETON_HEALTH
	hum.WalkSpeed = 17
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- glowing eye sockets and a lick of purple flame on the skull
	local head = m:FindFirstChild("Head") :: BasePart
	for _, x in { -0.19, 0.19 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.2, 0.2, 0.2)
		eye.Material, eye.Color = Enum.Material.Neon, MAGENTA
		eye.CanCollide, eye.CanQuery, eye.CanTouch, eye.Massless = false, false, false, true
		eye.CFrame = head.CFrame * CFrame.new(x, 0.1, -0.42)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head, eye
		weld.Parent = eye
		eye.Parent = m
	end
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = MAGENTA, 7, 1.5
	glow.Parent = head
	local flameAtt = Instance.new("Attachment")
	flameAtt.Position = Vector3.new(0, 0.55, 0)
	flameAtt.Parent = head
	emitter(flameAtt, {}, with(FLAME, {
		Rate = 14,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(1, 2),
		Acceleration = Vector3.new(0, 8, 0),
		Size = ns({ { 0, 0.35 }, { 0.3, 0.9 }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.6 }, { 0.2, 0.25 }, { 1, 1 } }),
		Brightness = 2,
	}))
	return m
end

-- One skeleton claws its way up out of a hole at `at`, facing `face`.
local function summon(owner: Player, at: Vector3, face: Vector3, assigned: Model?)
	local count = 0
	for _, mn in minions do
		if mn.owner == owner then
			count += 1
		end
	end
	if count >= SKELETON_CAP then
		for _, mn in minions do
			if mn.owner == owner then
				kill(mn) -- oldest first
				break
			end
		end
	end

	local m = buildSkeleton()
	local hum = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
	local ground = groundBelow(at)
	local look = Vector3.new(face.X, ground.Y + 3, face.Z)
	if (look - (ground + Vector3.new(0, 3, 0))).Magnitude < 0.1 then
		look += Vector3.new(0, 0, -1)
	end
	local stand = CFrame.lookAt(ground + Vector3.new(0, 3, 0), look)
	-- buried a body-length down, behind the hole, leaning forward as if crawling up
	local buried = stand * CFrame.new(0, -5.5, 1.5) * CFrame.Angles(math.rad(-35), 0, 0)
	root.Anchored = true
	m:PivotTo(buried)
	m:SetAttribute("NecroOwner", owner.UserId) -- lets the caster's client leave its own skeletons alone
	skeletonOwner[m] = owner
	m.Parent = workspace

	local mn: Minion = {
		model = m,
		hum = hum,
		root = root,
		owner = owner,
		assigned = assigned,
		born = os.clock(),
		slot = 1, -- wedge position, reassigned every think
		lastSwipe = 0,
		ready = false,
		dead = false,
		walk = loadTrack(hum, WALK_ANIM, true, Enum.AnimationPriority.Movement),
		idle = loadTrack(hum, IDLE_ANIM, true, Enum.AnimationPriority.Idle),
		swipe = loadTrack(hum, SWIPE_ANIM, false, Enum.AnimationPriority.Action),
	}
	table.insert(minions, mn)
	hum.Died:Connect(function()
		kill(mn)
	end)

	local made: { Instance } = {}
	local ok, err = pcall(function()
		local fx = hole(ground, 6, made)
		local mouth = fx[1].Parent :: Instance
		task.wait(0.35)
		burst(mouth, made, DIRT, 18)
		rumble(ground, 40, 0.3, 0)
		local t0 = os.clock()
		while m.Parent and not mn.dead do
			local a = math.min((os.clock() - t0) / RISE, 1)
			local e = 1 - (1 - a) ^ 3
			-- a struggling wobble that settles as it gets free
			m:PivotTo(buried:Lerp(stand, e) * CFrame.Angles(0, 0, math.sin(a * 28) * 0.08 * (1 - a)))
			if a >= 1 then
				break
			end
			task.wait()
		end
		if mn.dead or not m.Parent then
			return
		end
		burst(mouth, made, with(FLAT, {
			Texture = RING_TEX,
			Lifetime = NumberRange.new(0.4),
			Size = ns({ { 0, 1 }, { 1, 10 } }),
			Transparency = ns({ { 0, 0.2 }, { 1, 1 } }),
			Color = cs({ { 0, MAGENTA }, { 1, DEEP } }),
			Brightness = 3,
		}), 1)
		root.Anchored = false
		pcall(root.SetNetworkOwner, root, nil) -- server-owned, so the server's MoveTo drives it smoothly
		mn.ready = true
		disableAll(made) -- the hole closes up
		task.wait(1.6)
	end)
	cleanup(made)
	if not ok then
		kill(mn)
		error(err, 0)
	end
end

-- An old melt skeleton sinks back into the ground and a minion climbs out in its place.
local function raiseCorpse(owner: Player, corpse: Model, face: Vector3)
	corpse:SetAttribute("MeltCorpse", nil) -- one raise per corpse
	local torso = corpse:FindFirstChild("Torso") or corpse:FindFirstChildWhichIsA("BasePart")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local at = torso.Position
	for _, p in corpse:GetDescendants() do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(corpse, 0.6)
	summon(owner, at, face, nil)
end

-- What each caster's skeletons should fight right now: enemies near the caster (further while the
-- caster is under attack), and hexed enemies from much further away.
local lastHealth: { [Player]: number } = {}
local threatUntil: { [Player]: number } = {}

type Foe = { model: Model, hum: Humanoid, root: BasePart, hexed: boolean }

local function foesOf(owner: Player, ownerRoot: BasePart, now: number): { Foe }
	local radius = (threatUntil[owner] or 0) > now and THREAT_RADIUS or GUARD_RADIUS
	local foes: { Foe } = {}
	for hum in humanoids do
		local m = hum.Parent
		local root = hum.RootPart
		if hum.Health > 0 and root and m and m:IsA("Model") and not isFriend(owner, m) then
			local d = (root.Position - ownerRoot.Position).Magnitude
			local hexed = (hexUntil[hum] or 0) > now
			if d <= radius or (hexed and d <= LEASH) then
				table.insert(foes, { model = m, hum = hum, root = root, hexed = hexed })
			end
		end
	end
	return foes
end

-- Guard spots in the caster's own space (x right, z back): a wedge with its point ahead of the
-- caster and the arms sweeping back on either side, the sixth covering the rear.
local WEDGE = {
	Vector3.new(0, 0, -7),
	Vector3.new(-3.5, 0, -3.5),
	Vector3.new(3.5, 0, -3.5),
	Vector3.new(-7, 0, 0),
	Vector3.new(7, 0, 0),
	Vector3.new(0, 0, 5),
}

local function think()
	local now = os.clock()
	local foesBy: { [Player]: { Foe } } = {}
	-- wedge slots by age, so the formation fills point-first and closes up as skeletons die
	local filled: { [Player]: number } = {}
	for _, mn in minions do
		if mn.ready and not mn.dead and not mn.assigned then
			filled[mn.owner] = (filled[mn.owner] or 0) + 1
			mn.slot = filled[mn.owner]
		end
	end
	for i = #minions, 1, -1 do
		local mn = minions[i]
		if not mn.ready or mn.dead then
			continue
		end
		local owner = mn.owner
		local _, ownerRoot = alive(owner.Character)
		if not ownerRoot or not owner.Parent or now - mn.born > SKELETON_LIFE or not mn.model.Parent then
			kill(mn) -- caster died or left, or its time is up
			continue
		end
		local foes = foesBy[owner]
		if not foes then
			local ownerHum = (owner.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
			if ownerHum.Health < (lastHealth[owner] or ownerHum.Health) then
				threatUntil[owner] = now + 4 -- someone hurt the caster: widen the guard
			end
			lastHealth[owner] = ownerHum.Health
			foes = foesOf(owner, ownerRoot, now)
			foesBy[owner] = foes
		end

		-- target: the person it was raised for, else the nearest foe (hexed ones first)
		local tHum, tRoot
		if mn.assigned then
			tHum, tRoot = alive(mn.assigned)
			if not tHum or isFriend(owner, mn.assigned) then
				mn.assigned, tHum, tRoot = nil, nil, nil
			end
		end
		if not tHum then
			local best = math.huge
			for _, f in foes do
				local score = (f.root.Position - mn.root.Position).Magnitude - (f.hexed and 1000 or 0)
				if score < best then
					best, tHum, tRoot = score, f.hum, f.root
				end
			end
		end

		if tHum and tRoot then
			mn.hum:MoveTo(tRoot.Position)
			local d = (tRoot.Position - mn.root.Position).Magnitude
			if d <= SWIPE_REACH and now - mn.lastSwipe >= SWIPE_EVERY then
				mn.lastSwipe = now
				mn.swipe:Play(0.05)
				hurt(tHum, SWIPE_DAMAGE)
			end
		else
			-- guard: hold its spot in the wedge, which turns with the caster
			local look = ownerRoot.CFrame.LookVector
			local yaw = CFrame.lookAt(ownerRoot.Position, ownerRoot.Position + Vector3.new(look.X, 0, look.Z))
			local spot = yaw * (WEDGE[mn.slot] or WEDGE[#WEDGE])
			local flat = Vector3.new(spot.X - mn.root.Position.X, 0, spot.Z - mn.root.Position.Z)
			mn.hum:MoveTo(flat.Magnitude > 3 and spot or mn.root.Position)
		end

		local v = mn.root.AssemblyLinearVelocity
		local moving = Vector3.new(v.X, 0, v.Z).Magnitude > 1.5
		if moving and not mn.walk.IsPlaying then
			mn.idle:Stop(0.2)
			mn.walk:Play(0.2)
		elseif not moving and not mn.idle.IsPlaying then
			mn.walk:Stop(0.2)
			mn.idle:Play(0.2)
		end
	end
end

local nextThink = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now >= nextThink and #minions > 0 then
		nextThink = now + THINK
		think()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for i = #minions, 1, -1 do
		if minions[i].owner == player then
			kill(minions[i])
		end
	end
	lastHealth[player], threatUntil[player] = nil, nil
end)

-- ===== Soul Rip: the target's soul is torn out and roams free for 10 seconds, then goes back in =====
-- A player steers their own soul (movement keys / stick, the camera follows it); an NPC's soul
-- wanders on its own. The empty body lies ragdolled meanwhile.

local RIP_DAMAGE = 30
local RIP_HOLD = 10 -- seconds the soul is out
local SOUL_SPEED = 18
local SOUL_HOVER = 3 -- studs above the floor under it
local SOUL_LEASH = 60 -- how far from its body it can go

-- The soul's owner sends where they want to go; the server moves the soul so everyone sees it.
local soulRemote = Instance.new("UnreliableRemoteEvent")
soulRemote.Name = "Dark Magic Soul"
soulRemote.Parent = ReplicatedStorage
local soulInput: { [Player]: Vector3 } = {}
soulRemote.OnServerEvent:Connect(function(player, dir: any)
	if soulInput[player] and typeof(dir) == "Vector3" and dir == dir then -- dir == dir drops NaN
		local flat = Vector3.new(dir.X, 0, dir.Z)
		soulInput[player] = flat.Magnitude > 1 and flat.Unit or flat
	end
end)
Players.PlayerRemoving:Connect(function(p)
	soulInput[p] = nil
end)

local function soulRip(caster: Player, model: Model, hum: Humanoid, root: BasePart, made: { Instance })
	local casterHum, casterRoot = alive(caster.Character)
	if not (casterHum and casterRoot) then
		return
	end

	-- the soul: a copy of their body made entirely of purple ForceField
	local ghost = Instance.new("Model")
	ghost.Name = "Soul"
	table.insert(made, ghost)
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, p in model:GetChildren() do
		-- headless: a ForceField head mesh renders solid or white, never as the body's shimmer
		local skip = p.Name == "HumanoidRootPart" or p.Name == "Head" or p.Name == "Eye"
		if p:IsA("BasePart") and not skip and p.Transparency < 1 then
			local g = p:Clone()
			for _, c in g:GetChildren() do
				if c:IsA("DataModelMesh") then
					c.VertexColor = Vector3.one
				else
					c:Destroy() -- faces, joints, scripts, effects
				end
			end
			g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch = true, false, false, false
			g.Material, g.Color, g.Transparency = Enum.Material.ForceField, PURPLE, 1
			if g:IsA("MeshPart") then
				g.TextureID = ""
			end
			g.Parent = ghost
			table.insert(parts, g)
			table.insert(offsets, root.CFrame:ToObjectSpace(p.CFrame))
		end
	end
	ghost.Parent = workspace
	local core = parts[1]
	if not core then
		return
	end
	-- wisps trailing off it
	local trail = emitter(core, made, {
		Texture = GLOW_TEX,
		Color = cs({ { 0, MAGENTA }, { 1, DEEP } }),
		Rate = 40,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		Size = ns({ { 0, 1.4 }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.5 }, { 1, 1 } }),
		Brightness = 2,
	})
	-- the body flashes as the soul is pulled out of it
	local hl = Instance.new("Highlight")
	hl.FillColor, hl.OutlineColor = WHITE_HOT, MAGENTA
	hl.FillTransparency, hl.OutlineTransparency = 0.2, 0
	hl.Parent = model
	table.insert(made, hl)
	TweenService:Create(hl, TweenInfo.new(1), { FillTransparency = 1, OutlineTransparency = 1 }):Play()

	local startRot = root.CFrame.Rotation
	local function place(cf: CFrame, fade: number)
		local cfs = table.create(#parts)
		for i, p in parts do
			cfs[i] = cf * offsets[i]
			p.Transparency = fade
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- fly from one spot to another along an arc; `to` is re-read each frame so it can chase a moving body
	local function fly(from: CFrame, to: () -> CFrame, over: number, fadeFrom: number, fadeTo: number)
		local t0 = os.clock()
		while true do
			local a = math.min((os.clock() - t0) / over, 1)
			local e = a * a * (3 - 2 * a)
			local goal = to()
			local cf = from:Lerp(goal, e) + Vector3.new(0, math.sin(a * math.pi) * 3, 0)
			place(cf, fadeFrom + (fadeTo - fadeFrom) * a)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end
	local torso = (model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or root) :: BasePart

	-- 1. tear: the soul strains up out of the body
	local t0 = os.clock()
	while os.clock() - t0 < 0.3 do
		local a = (os.clock() - t0) / 0.3
		local shake = Vector3.new(math.noise(a * 20, 1), math.noise(a * 20, 2), math.noise(a * 20, 3)) * 0.3
		place(CFrame.new(root.Position + Vector3.new(0, a * 1.5, 0) + shake) * startRot, 1 - a)
		task.wait()
	end
	local tornAt = os.clock()
	local before = hum.Health
	hurt(hum, RIP_DAMAGE)
	rumble(root.Position, 50, 0.5, 0.7)
	local dealt = math.max(before - hum.Health, 0)
	burst(root, made, {
		Texture = SPARK_TEX,
		Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Size = ns({ { 0, 0.4 }, { 1, 0 } }),
		Brightness = 4,
	}, 30)
	-- the empty body is knocked over backwards, away from the caster. The server owns its physics
	-- while it's down, so a player can't move their own body meanwhile.
	pcall(root.SetNetworkOwner, root, nil)
	local standUp = ragdoll(model)
	local away = root.Position - casterRoot.Position
	away = Vector3.new(away.X, 0, away.Z)
	away = away.Magnitude > 0.1 and away.Unit or -root.CFrame.LookVector
	root.AssemblyLinearVelocity = away * 12 + Vector3.new(0, 8, 0)
	root.AssemblyAngularVelocity = Vector3.yAxis:Cross(away) * 9 -- tips the top of the body away

	-- 2. it rises clear of the body; the caster drinks what the tear cost them
	local yaw = math.atan2(-away.X, -away.Z) -- start facing away from the caster
	local pos = root.Position + away * 3 + Vector3.new(0, SOUL_HOVER, 0)
	fly(CFrame.new(root.Position + Vector3.new(0, 1.5, 0)) * startRot, function()
		return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	end, 0.5, 0, 0)
	if casterHum.Parent and casterHum.Health > 0 then
		casterHum.Health = math.min(casterHum.MaxHealth, casterHum.Health + dealt)
	end

	-- 3. roam: the player steers it, or an NPC's soul wanders between nearby spots
	local owner = Players:GetPlayerFromCharacter(model)
	local link: ObjectValue? = nil
	if owner then
		soulInput[owner] = Vector3.zero
		-- the owner's client sees this, points the camera at the soul and starts sending input
		local v = Instance.new("ObjectValue")
		v.Name = "DarkMagicSoul"
		v.Value = core
		v:SetAttribute("EndsAt", workspace:GetServerTimeNow() + RIP_HOLD)
		v.Parent = owner
		table.insert(made, v) -- cleaned up even if the rip errors
		link = v
	end
	local returnAt = tornAt + RIP_HOLD
	local vel = Vector3.zero
	local floorY = pos.Y - SOUL_HOVER
	local nextFloor = 0
	local wanderTo: Vector3? = nil
	local last = os.clock()
	while os.clock() < returnAt and hum.Health > 0 and model.Parent ~= nil do
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		local want: Vector3
		if owner then
			want = (soulInput[owner] or Vector3.zero) * SOUL_SPEED
		else
			-- wander: drift to a random spot near the body, pick another once there
			if not wanderTo or (Vector3.new(wanderTo.X, 0, wanderTo.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 2 then
				local a = math.random() * math.pi * 2
				local r = 6 + math.random() * 14
				wanderTo = torso.Position + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			end
			local to = (wanderTo :: Vector3) - pos
			to = Vector3.new(to.X, 0, to.Z)
			want = to.Magnitude > 0.1 and to.Unit * SOUL_SPEED * 0.45 or Vector3.zero
		end
		vel = vel:Lerp(want, math.min(dt * 8, 1))
		pos += vel * dt
		-- leash: it can't stray too far from its body
		local fromBody = Vector3.new(pos.X - torso.Position.X, 0, pos.Z - torso.Position.Z)
		if fromBody.Magnitude > SOUL_LEASH then
			pos = Vector3.new(torso.Position.X, pos.Y, torso.Position.Z) + fromBody.Unit * SOUL_LEASH
		end
		-- glide over the ground (it passes through walls; it's a ghost)
		if now >= nextFloor then
			nextFloor = now + 0.1
			local g, found = groundBelow(pos + Vector3.new(0, 2, 0))
			if found then
				floorY = g.Y
			end
		end
		local hoverY = floorY + SOUL_HOVER
		pos = Vector3.new(pos.X, pos.Y + (hoverY - pos.Y) * math.min(dt * 6, 1), pos.Z)
		if vel.Magnitude > 1 then
			yaw = math.atan2(-vel.X, -vel.Z)
		end
		local bob = math.sin(now * 2.5) * 0.4
		local lean = CFrame.Angles(-math.min(vel.Magnitude / SOUL_SPEED, 1) * 0.35, 0, 0) -- tips forward at speed
		place(CFrame.new(pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, yaw, 0) * lean, 0)
		task.wait()
	end
	if owner then
		soulInput[owner] = nil
	end
	if link then
		link:Destroy()
	end

	local here = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	if hum.Health <= 0 or not model.Parent then
		-- the body died while it was out: the soul has nowhere to go and drifts up and fades away
		for k = 0, 1, 0.04 do
			place(here + Vector3.new(0, k * 5, 0), k)
			task.wait()
		end
		trail.Enabled = false
		task.wait(0.7)
		return
	end

	-- 4. return: it's dragged back across to its body and dives in, and the body gets up
	local back = math.clamp((torso.Position - pos).Magnitude / 30, 0.55, 1.4)
	fly(here, function()
		return CFrame.new(torso.Position) * startRot
	end, back, 0, 0.8)
	trail.Enabled = false
	for _, p in parts do
		p.Transparency = 1
	end
	burst(torso, made, {
		Texture = IMPLODE_TEX,
		Lifetime = NumberRange.new(0.3),
		Speed = NumberRange.new(0),
		Size = ns({ { 0, 7 }, { 1, 0.5 } }),
		Transparency = ns({ { 0, 1 }, { 0.3, 0.2 }, { 1, 1 } }),
		Color = cs({ { 0, MAGENTA }, { 1, WHITE_HOT } }),
		Brightness = 4,
	}, 1)
	standUp()
	pcall(root.SetNetworkOwnershipAuto, root) -- a player gets control of their body back
	task.wait(0.8)
end

-- ===== Shadow Step: the caster sinks into a pool of shadow and surfaces behind the target =====

local function shadowStep(char: Model, myRoot: BasePart, target: Model, tRoot: BasePart, made: { Instance })
	local floor = groundBelow(myRoot.Position)
	local standHeight = myRoot.Position.Y - floor.Y -- root height above the floor, for any rig
	local wasAnchored = myRoot.Anchored
	myRoot.Anchored = true

	local function sink(from: CFrame, to: CFrame, over: number)
		local t0 = os.clock()
		while true do
			local a = math.min((os.clock() - t0) / over, 1)
			char:PivotTo(from:Lerp(to, a * a * (3 - 2 * a)))
			if a >= 1 then
				break
			end
			task.wait()
		end
	end

	local ok, err = pcall(function()
		-- 1. down into the shadow
		local enter = hole(floor, 6, made)
		local mouth = enter[1].Parent :: Instance
		task.wait(0.1)
		local start = myRoot.CFrame
		afterimage(char, made, -start.LookVector * 1.5) -- a shadow of them is left standing, then blows away
		sink(start, start - Vector3.new(0, standHeight + 3.5, 0), 0.35)
		burst(mouth, made, with(FLAME, {
			Lifetime = NumberRange.new(0.3, 0.5),
			Speed = NumberRange.new(6, 10),
			SpreadAngle = Vector2.new(25, 25),
			Size = ns({ { 0, 0.6 }, { 0.3, 1.6 }, { 1, 0 } }),
			Color = cs({ { 0, MAGENTA }, { 1, SOOT } }),
			Brightness = 2,
		}), 16)
		disableAll(enter)

		-- 2. surface a few studs behind them, facing their back (stopping short of any wall)
		local back = -tRoot.CFrame.LookVector * 3.5
		rayParams.FilterDescendantsInstances = characters()
		local wall = workspace:Raycast(tRoot.Position, back, rayParams)
		local behind = wall and (wall.Position - back.Unit * 1.2) or (tRoot.Position + back)
		local spot = solidSpot(tRoot.Position, 3.5, behind) -- never surface over a drop
		local exitFloor = groundBelow(spot)
		local stand = CFrame.lookAt(
			exitFloor + Vector3.new(0, standHeight, 0),
			Vector3.new(tRoot.Position.X, exitFloor.Y + standHeight, tRoot.Position.Z)
		)
		local exit = hole(exitFloor, 6, made)
		local exitMouth = exit[1].Parent :: Instance
		char:PivotTo(stand - Vector3.new(0, standHeight + 3.5, 0))
		task.wait(0.2)
		sink(stand - Vector3.new(0, standHeight + 3.5, 0), stand, 0.65) -- slow enough to read as climbing out
		shockwave(exitFloor, 8, made)
		rumble(exitFloor, 35, 0.35, 0.3)
		burst(exitMouth, made, with(FLAT, {
			Texture = RING_TEX,
			Lifetime = NumberRange.new(0.35),
			Size = ns({ { 0, 1 }, { 1, 9 } }),
			Transparency = ns({ { 0, 0.2 }, { 1, 1 } }),
			Color = cs({ { 0, MAGENTA }, { 1, DEEP } }),
			Brightness = 3,
		}), 1)
		disableAll(exit)
	end)
	if myRoot.Parent then
		myRoot.Anchored = wasAnchored
	end
	if not ok then
		error(err, 0)
	end
	task.wait(1.4) -- the pools finish closing before cleanup
end

-- ===== Hex: a crown of purple flames; for 10 seconds every hit lands twice =====
-- One flame per second left. Each second a flame snuffs out in a puff of smoke, so everyone can
-- read how long the curse has; the last three burn hottest, and the final one collapses the
-- crown inward in a burst. Re-hexing relights the whole crown.

local HEX_TIME = 10
local CROWN_RADIUS = 1.3

local function hex(model: Model, hum: Humanoid)
	local head = (model:FindFirstChild("Head") or hum.RootPart) :: BasePart
	local made: { Instance } = {}
	local crownY = head.Size.Y / 2 + 0.45
	local center = Instance.new("Attachment")
	center.Position = Vector3.new(0, crownY, 0)
	center.Parent = head
	table.insert(made, center)
	-- cast: the crown snaps shut around the head
	burst(center, made, {
		Texture = IMPLODE_TEX,
		Lifetime = NumberRange.new(0.3),
		Speed = NumberRange.new(0),
		Size = ns({ { 0, 6 }, { 1, 0.5 } }),
		Transparency = ns({ { 0, 1 }, { 0.3, 0.2 }, { 1, 1 } }),
		Color = cs({ { 0, MAGENTA }, { 1, WHITE_HOT } }),
		Brightness = 4,
	}, 1)

	local already = hexUntil[hum] ~= nil
	hexUntil[hum] = os.clock() + HEX_TIME
	if already then -- re-hexing just refreshes the timer; the running crown relights itself
		task.wait(0.5)
		cleanup(made)
		return
	end

	local ok, err = pcall(function()
		local COOL = cs({ { 0, WHITE_HOT }, { 0.2, MAGENTA }, { 1, PURPLE } })
		local HOT = cs({ { 0, Color3.fromRGB(185, 90, 255) }, { 0.35, WHITE_HOT }, { 1, MAGENTA } }) -- hottest, still violet
		local flames: { ParticleEmitter } = {}
		local puffs: { ParticleEmitter } = {}
		for i = 1, HEX_TIME do
			local ang = (i - 1) / HEX_TIME * math.pi * 2
			local a = Instance.new("Attachment")
			a.Position = Vector3.new(math.cos(ang) * CROWN_RADIUS, crownY, math.sin(ang) * CROWN_RADIUS)
			a.Parent = head
			table.insert(made, a)
			flames[i] = emitter(a, made, with(FLAME, {
				Rate = 14,
				Lifetime = NumberRange.new(0.3, 0.45),
				Speed = NumberRange.new(1, 2),
				SpreadAngle = Vector2.new(8, 8),
				Acceleration = Vector3.new(0, 6, 0),
				Size = ns({ { 0, 0.3 }, { 0.3, 0.55 }, { 1, 0 } }),
				Transparency = ns({ { 0, 0.4 }, { 0.2, 0.05 }, { 1, 1 } }),
				Color = COOL,
				Brightness = 3,
			}))
			-- the puff of smoke a flame leaves when it's snuffed
			puffs[i] = emitter(a, made, {
				Texture = SMOKE_TEX,
				LightEmission = 0,
				Rate = 0,
				Color = cs({ { 0, DEEP }, { 1, SOOT } }),
				Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(1, 2),
				SpreadAngle = Vector2.new(20, 20),
				Size = ns({ { 0, 0.4 }, { 1, 1.4 } }),
				Transparency = ns({ { 0, 0.3 }, { 1, 1 } }),
			})
		end
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = MAGENTA, 9, 1.5
		light.Parent = head
		table.insert(made, light)

		-- double damage: whatever takes health off them takes the same amount again
		local last = hum.Health
		local conn = hum.HealthChanged:Connect(function(h)
			if h < last and h > 0 and hexUntil[hum] then
				last = math.max(h - (last - h), 0)
				killRagdoll(hum, last) -- fires HealthChanged again with h == last, which is ignored; ragdolls if lethal
				for i, f in flames do -- every lit flame flares
					if f.Enabled then
						f:Emit(3)
					end
				end
			else
				last = h
			end
		end)

		-- countdown: flame i burns while more than i-1 seconds are left
		local lit = HEX_TIME
		while (hexUntil[hum] or 0) > os.clock() and hum.Health > 0 and model.Parent do
			local left = math.ceil((hexUntil[hum] :: number) - os.clock())
			if left ~= lit then
				for i = 1, HEX_TIME do
					local on = i <= left
					if flames[i].Enabled and not on then
						flames[i].Enabled = false
						puffs[i]:Emit(4)
					elseif on and not flames[i].Enabled then
						flames[i].Enabled = true -- re-hexed: relight
						flames[i]:Emit(3)
					end
					flames[i].Color = left <= 3 and HOT or COOL
				end
				light.Brightness = left <= 3 and 3 or 1.5
				lit = left
			end
			task.wait(0.1)
		end
		conn:Disconnect()
		local expired = hum.Health > 0 and model.Parent ~= nil
		hexUntil[hum] = nil
		for i, f in flames do
			if f.Enabled then
				f.Enabled = false
				puffs[i]:Emit(4)
			end
		end
		if expired then
			-- the last flame dies and the crown collapses inward with a flash
			burst(center, made, {
				Texture = IMPLODE_TEX,
				Lifetime = NumberRange.new(0.25),
				Speed = NumberRange.new(0),
				Size = ns({ { 0, 5 }, { 1, 0.3 } }),
				Transparency = ns({ { 0, 1 }, { 0.3, 0.1 }, { 1, 1 } }),
				Color = cs({ { 0, MAGENTA }, { 1, WHITE_HOT } }),
				Brightness = 5,
			}, 1)
			task.wait(0.2)
			burst(center, made, {
				Texture = SPARK_TEX,
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(6, 11),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 3,
				Size = ns({ { 0, 0.35 }, { 1, 0 } }),
				Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
				Brightness = 4,
			}, 24)
			light.Brightness = 6
		end
		TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
		task.wait(1)
	end)
	if not ok then
		hexUntil[hum] = nil -- normal ends clear it inside; clearing here too would cancel a re-hex cast during the fade-out
	end
	cleanup(made)
	if not ok then
		error(err, 0)
	end
end

-- ===== Caster: hand effects and spell timing =====
-- The caster's animations (one per spell) play on their own client, from
-- DarkMagicClient. Here the server adds the hand fire everyone sees, timed to those animations, and
-- each spell waits for its animation's release frame so the effect lands when the hands do.

-- seconds from the click to the release frame of each spell's animation
local CAST_DELAY = { uniform = 0.73, melt = 0.57, raise = 0.83, rip = 0.47, step = 0.25, hex = 0.57 } -- hex plays the melt animation
-- which hands burn during the cast: arms, from, to (seconds), flame size
local HAND_FX: { [string]: { any } } = {
	uniform = { { "Right Arm", "Left Arm" }, 0.05, 0.75, 1.5 }, -- fire gathered overhead, hurled
	melt = { { "Right Arm", "Left Arm" }, 0.4, 1.5, 1 }, -- palms burning through the push
	raise = { { "Right Arm", "Left Arm" }, 0.2, 1.45, 1 }, -- palms over the ground, then lifted
	rip = { { "Right Arm" }, 0.15, 0.8, 0.7 }, -- the clawed hand crackles until the yank
	hex = { { "Right Arm", "Left Arm" }, 0.4, 1.5, 1 }, -- same push as melt
}

local function handAt(char: Model, arm: string, made: { Instance }): Attachment?
	local part = char:FindFirstChild(arm)
	if not (part and part:IsA("BasePart")) then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "DarkMagicHand"
	a.Position = Vector3.new(0, -part.Size.Y / 2 - 0.15, 0) -- just past the fingertips
	a.Parent = part
	table.insert(made, a)
	return a
end

-- a flame held in the hand, with violet wisps curling off it; `size` scales it
local function handFlame(at: Attachment, made: { Instance }, size: number)
	emitter(at, made, with(FLAME, {
		Rate = 30 * size,
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(0.5, 1.5),
		Acceleration = Vector3.new(0, 7, 0),
		Size = ns({ { 0, 0.35 * size }, { 0.3, 0.75 * size }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.5 }, { 0.2, 0.1 }, { 1, 1 } }),
		Brightness = 2,
	}))
	emitter(at, made, {
		Texture = SMOKE_TEX,
		LightEmission = 0, -- black smoke pouring off the hand
		Color = cs({ { 0, DEEP }, { 1, SOOT } }),
		Rate = 10 * size,
		Lifetime = NumberRange.new(0.9, 1.4),
		Speed = NumberRange.new(0.5, 1.2),
		Acceleration = Vector3.new(0, 2.5, 0),
		Size = ns({ { 0, 0.25 * size }, { 1, 0.9 * size } }),
		Transparency = ns({ { 0, 0.45 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(-40, 40),
	})
	-- no light: the caster isn't lit up purple when casting
end

-- Anticipation: dark motes sucked in from all around into the hand while it charges.
-- Shape emission needs a part, so an invisible ball rides on the hand.
local function gather(at: Attachment, made: { Instance }, size: number)
	local arm = at.Parent :: BasePart
	local radius = 2.2 * size
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * radius * 2
	ball.Transparency = 1
	ball.CanCollide, ball.CanQuery, ball.CanTouch, ball.Massless = false, false, false, true
	ball.CFrame = at.WorldCFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = ball, arm
	weld.Parent = ball
	ball.Parent = arm
	table.insert(made, ball)
	local life = 0.35
	emitter(ball, made, {
		LightEmission = 0.6, -- has to read against a black outfit
		Texture = SPARK_TEX,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		LockedToPart = true, -- the hand drags the whole swirl with it
		Orientation = Enum.ParticleOrientation.VelocityParallel, -- streaks pointing at the palm
		Rate = 40 * size,
		Lifetime = NumberRange.new(life),
		Speed = NumberRange.new(radius / life), -- they reach the palm as they die
		Size = ns({ { 0, 0.15 }, { 1, 0.45 * size } }),
		Transparency = ns({ { 0, 1 }, { 0.25, 0 }, { 1, 0.3 } }),
		Color = cs({ { 0, MAGENTA }, { 1, WHITE_HOT } }),
		Brightness = 3,
	})
end

local lastHandFx: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Lights the spell's hands for its window, then flings a spark burst off them and lets the fire die.
local function handEffect(char: Model, mode: string)
	local fx = HAND_FX[mode]
	local now = os.clock()
	if not fx or now - (lastHandFx[char] or 0) < 0.3 then
		return -- one cast on several targets fires several requests: light the hands once
	end
	lastHandFx[char] = now
	task.spawn(function()
		local made: { Instance } = {}
		-- anticipation: motes pour into the hands from the click until the release frame
		local charge: { Instance } = {}
		for _, arm in fx[1] do
			local at = handAt(char, arm, charge)
			if at then
				gather(at, charge, fx[4])
			end
		end
		task.delay(CAST_DELAY[mode], disableAll, charge)
		task.wait(fx[2])
		local hands = {}
		for _, arm in fx[1] do
			local at = char.Parent and handAt(char, arm, made)
			if at then
				handFlame(at, made, fx[4])
				table.insert(hands, at)
			end
		end
		task.wait(fx[3] - fx[2])
		for _, at in hands do
			burst(at, made, {
				Texture = SPARK_TEX,
				Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
				Lifetime = NumberRange.new(0.3, 0.5),
				Speed = NumberRange.new(8, 14),
				SpreadAngle = Vector2.new(60, 60),
				Drag = 4,
				Size = ns({ { 0, 0.35 * fx[4] }, { 1, 0 } }),
				Brightness = 4,
			}, math.floor(14 * fx[4]))
		end
		disableAll(made)
		task.wait(1.4) -- the last wisps drift off
		cleanup(made)
		cleanup(charge)
	end)
end

-- At the release frame something lashes from the caster's hands into the target's chest and holds
-- while the hands do: shadow tendrils, or for soul rip a chain that snaps as the soul tears. Seconds held:
local LINK: { [string]: number } = { melt = 0.9, hex = 0.5, rip = 0.3 } -- uniform: no tendrils, the fire is hurled

local function castLink(char: Model, target: Model, mode: string)
	local hold = LINK[mode]
	local torso = target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso") or target:FindFirstChild("HumanoidRootPart")
	if not (hold and HAND_FX[mode] and torso and torso:IsA("BasePart")) then
		return
	end
	if mode ~= "rip" then
		for _, arm in HAND_FX[mode][1] do
			local part = char:FindFirstChild(arm)
			if part and part:IsA("BasePart") then
				tendrilRemote:FireAllClients(part, torso, hold)
			end
		end
		-- impact: the tendrils bite (0.16 s = out in SoulControl) with a burst of soot and embers
		task.delay(0.16, function()
			if not torso.Parent then
				return
			end
			local made: { Instance } = {}
			burst(torso, made, {
				Texture = SMOKE_TEX,
				LightEmission = 0,
				Color = cs({ { 0, DEEP }, { 1, SOOT } }),
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(4, 8),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 5,
				Size = ns({ { 0, 0.8 }, { 1, 2.2 } }),
				Transparency = ns({ { 0, 0.3 }, { 1, 1 } }),
				RotSpeed = NumberRange.new(-60, 60),
			}, 10)
			burst(torso, made, {
				Texture = SPARK_TEX,
				Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
				Lifetime = NumberRange.new(0.25, 0.4),
				Speed = NumberRange.new(7, 12),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 4,
				Size = ns({ { 0, 0.3 }, { 1, 0 } }),
				Brightness = 4,
			}, 10)
			task.wait(0.8)
			cleanup(made)
		end)
		return
	end
	task.spawn(function()
		local made: { Instance } = {}
		local bite = Instance.new("Attachment")
		bite.Parent = torso
		table.insert(made, bite)
		local drops = {}
		for _, arm in HAND_FX[mode][1] do
			local at = char.Parent and handAt(char, arm, made)
			if at then
				table.insert(drops, link(at, bite, made))
			end
		end
		task.wait(hold)
		for _, drop in drops do
			drop(0.15)
		end
		do -- the chain snaps
			burst(bite, made, {
				Texture = SPARK_TEX,
				Color = cs({ { 0, WHITE_HOT }, { 1, MAGENTA } }),
				Lifetime = NumberRange.new(0.25, 0.4),
				Speed = NumberRange.new(8, 14),
				SpreadAngle = Vector2.new(70, 70),
				Drag = 4,
				Size = ns({ { 0, 0.3 }, { 1, 0 } }),
				Brightness = 4,
			}, 12)
		end
		task.wait(0.5)
		cleanup(made)
	end)
end

-- ===== Remote =====

-- FireServer(mode, target, shirtId?, pantsId?)
--   mode = "uniform" | "melt" | "rip" | "step" | "hex", target = one character
--   mode = "raise", target = a list of characters / melt corpses (empty = bodyguards)
local MODES = { uniform = true, melt = true, raise = true, rip = true, step = true, hex = true }
local lastRaise: { [Player]: number } = {}
local lastDownload: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(p)
	lastDownload[p] = nil
end)

local function raiseCommand(player: Player, myRoot: BasePart, targets: any)
	if typeof(targets) ~= "table" then
		return
	end
	local now = os.clock()
	if now - (lastRaise[player] or 0) < 1.5 then
		return -- each raise climbs out over a second; no stacking them
	end
	lastRaise[player] = now
	local char = myRoot.Parent :: Model
	handEffect(char, "raise")
	task.wait(CAST_DELAY.raise) -- the dead climb out as the arms come up
	if not (char.Parent and myRoot.Parent) then
		return
	end
	-- the caster's summoning circle flares under them as the arms come up
	local circle: { Instance } = {}
	local under = groundBelow(myRoot.Position)
	groundMark(under, 14, TEX_RUNES, circle, 2.2, -0.8)
	shockwave(under, 10, circle)
	task.delay(2.4, cleanup, circle)

	local picked: { Model } = {}
	for i = 1, math.min(#targets, SKELETON_CAP) do
		local t = rawget(targets, i)
		if typeof(t) == "Instance" and t:IsA("Model") and t:IsDescendantOf(workspace) and not isFriend(player, t) then
			local part = t:FindFirstChild("Torso") or t:FindFirstChildWhichIsA("BasePart")
			if part and part:IsA("BasePart") and (part.Position - myRoot.Position).Magnitude <= RANGE then
				table.insert(picked, t)
			end
		end
	end

	if #picked == 0 then
		-- they climb out already in wedge, facing where the caster faces
		local look = myRoot.CFrame.LookVector
		local yaw = CFrame.lookAt(myRoot.Position, myRoot.Position + Vector3.new(look.X, 0, look.Z))
		for i = 1, RAISE_GUARDS do
			local at = solidSpot(myRoot.Position, 5, yaw * WEDGE[i])
			task.spawn(summon, player, at, at + yaw.LookVector * 10, nil)
		end
		return
	end
	-- spread the cap across the targets: 2 each for up to 3 people, 1 each beyond that
	local each = math.max(1, math.floor(SKELETON_CAP / #picked))
	each = math.min(each, 2)
	for _, t in picked do
		if t:GetAttribute("MeltCorpse") then
			task.spawn(raiseCorpse, player, t, myRoot.Position)
		else
			local _, tRoot = alive(t)
			if tRoot then
				for _ = 1, each do
					task.spawn(summon, player, solidSpot(tRoot.Position, 4), tRoot.Position, t)
				end
			end
		end
	end
end

remote.OnServerEvent:Connect(function(player, mode: any, target: any, shirtId: any, pantsId: any)
	if typeof(mode) ~= "string" or not MODES[mode] then
		return
	end
	local char = player.Character
	local myRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local held = char and char:FindFirstChildWhichIsA("Tool")
	if not (char and myRoot and held and held:GetAttribute(TOOL_ATTRIBUTE)) then
		return
	end
	if mode == "raise" then
		raiseCommand(player, myRoot, target)
		return
	end
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not target:IsDescendantOf(workspace) then
		return
	end
	local hum = target:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0 and hum.RootPart) then
		return
	end
	if ((hum.RootPart :: BasePart).Position - myRoot.Position).Magnitude > RANGE then
		return
	end
	if target == char and (mode == "rip" or mode == "step" or mode == "hex") then
		return
	end
	if mode == "hex" then
		-- a mark, not a scene: it never locks the target, so other spells can land on them meanwhile
		handEffect(char, "hex")
		task.wait(CAST_DELAY.hex) -- the mark lands on the point
		if hum.Health <= 0 or not target:IsDescendantOf(workspace) then
			return
		end
		castLink(char, target, "hex")
		local ok, err = pcall(hex, target, hum)
		if not ok then
			warn("[DarkMagic]", err)
		end
		return
	end

	-- the step locks the caster (who is anchored mid-step); everything else locks the target
	local key = mode == "step" and char or target
	if busy[key] or (mode == "step" and busy[target]) then
		return
	end

	local run
	if mode == "melt" then
		run = function()
			playMelt(target, hum)
		end
	elseif mode == "rip" then
		run = function()
			local made: { Instance } = {}
			local ok, err = pcall(soulRip, player, target, hum, hum.RootPart :: BasePart, made)
			cleanup(made)
			if not ok then
				error(err, 0)
			end
		end
	elseif mode == "step" then
		run = function()
			local made: { Instance } = {}
			local ok, err = pcall(shadowStep, char, myRoot, target, hum.RootPart :: BasePart, made)
			cleanup(made)
			if not ok then
				error(err, 0)
			end
		end
	else
		local sId, pId = validId(shirtId), validId(pantsId)
		if not (sId or pId) then
			return
		end
		-- one asset download per caster per second; IDs already cached (same uniform on many targets) are free
		if (sId and not templateCache["Shirt" .. sId]) or (pId and not templateCache["Pants" .. pId]) then
			local now = os.clock()
			if now - (lastDownload[player] or 0) < 1 then
				return
			end
			lastDownload[player] = now
		end
		run = function()
			play(
				target,
				hum,
				resolveTemplate(sId, "Shirt", "ShirtTemplate"),
				resolveTemplate(pId, "Pants", "PantsTemplate")
			)
		end
	end

	busy[key] = true
	handEffect(char, mode)
	task.wait(CAST_DELAY[mode]) -- the spell lands on the animation's release frame
	if hum.Health <= 0 or not target:IsDescendantOf(workspace) or not myRoot:IsDescendantOf(workspace) then
		busy[key] = nil
		return
	end
	castLink(char, target, mode)
	local ok, err = pcall(run)
	busy[key] = nil
	if not ok then
		warn("[DarkMagic]", err)
	end
end)

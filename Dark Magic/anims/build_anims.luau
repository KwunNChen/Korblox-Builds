-- Builds the Dark Magic caster animations as KeyframeSequence .rbxm files, ready to upload as Animation assets.
--   ~/.rokit/bin/lune.exe run anims/build_anims.luau      (from the Dark Magic folder)
-- Pose language and keyframe building follow fwjelaa's AnimKit (FWJ studios): {x, y, z[, px, py, pz]} degrees in
-- the parent part's axes. +x arm forward / head up / torso back; +y turn left; +z right arm out, left arm across.
-- The same poses were previewed in Studio (ServerStorage.Animations) before upload.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local CFrame, Instance, Enum = roblox.CFrame, roblox.Instance, roblox.Enum

-- R6 rig (numbers measured in Studio, identical to the kit)
local function rot(...)
	return CFrame.new(0, 0, 0, ...)
end
local R6_ROOT = rot(-1, 0, 0, 0, 0, 1, 0, 1, 0)
local R6_R = rot(0, 0, 1, 0, 1, 0, -1, 0, 0)
local R6_L = rot(0, 0, -1, 0, 1, 0, 1, 0, 0)
local C0 = {
	Torso = R6_ROOT,
	Head = CFrame.new(0, 1, 0) * R6_ROOT,
	["Right Arm"] = CFrame.new(1, 0.5, 0) * R6_R,
	["Left Arm"] = CFrame.new(-1, 0.5, 0) * R6_L,
	["Right Leg"] = CFrame.new(1, -1, 0) * R6_R,
	["Left Leg"] = CFrame.new(-1, -1, 0) * R6_L,
}
local PARENT = {
	Torso = "HumanoidRootPart",
	Head = "Torso",
	["Right Arm"] = "Torso",
	["Left Arm"] = "Torso",
	["Right Leg"] = "Torso",
	["Left Leg"] = "Torso",
}
local ALL = { "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

local function poseCFrame(part: string, v: { number })
	local r = C0[part].Rotation
	local q = CFrame.Angles(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
	local t = CFrame.new(v[4] or 0, v[5] or 0, v[6] or 0)
	return r:Inverse() * t * q * r
end

-- ease name -> Roblox pose easing (kept as one key) or a curve baked into in-betweens
local NATIVE = {
	linear = { "Linear", "In" },
	constant = { "Constant", "Out" },
	cubic_in = { "CubicV2", "In" },
	cubic_out = { "CubicV2", "Out" },
	cubic_inout = { "CubicV2", "InOut" },
}
local CURVE = {
	linear = function(t) return t end,
	constant = function(t) return t >= 1 and 1 or 0 end,
	cubic_in = function(t) return t ^ 3 end,
	cubic_out = function(t) return 1 - (1 - t) ^ 3 end,
	cubic_inout = function(t) return t < 0.5 and 4 * t ^ 3 or 1 - (-2 * t + 2) ^ 3 / 2 end,
	sine_inout = function(t) return -(math.cos(math.pi * t) - 1) / 2 end,
	quad_in = function(t) return t * t end,
	quad_out = function(t) return 1 - (1 - t) ^ 2 end,
	quart_out = function(t) return 1 - (1 - t) ^ 4 end,
	expo_in = function(t) return t <= 0 and 0 or 2 ^ (10 * t - 10) end,
	expo_out = function(t) return t >= 1 and 1 or 1 - 2 ^ (-10 * t) end,
	back_out = function(t)
		local c1 = 1.70158
		return 1 + (c1 + 1) * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
	end,
}
local BAKE_STEP = 2

local Anim = {}
Anim.__index = Anim
local function new(name, opts)
	return setmetatable({
		name = name,
		length = opts.length,
		fps = 60,
		loop = opts.loop == true,
		priority = opts.priority or "Action",
		only = opts.joints,
		keys = {},
		markers = {},
	}, Anim)
end
function Anim:joints()
	return self.only or ALL
end
function Anim:key(frame, pose, ease)
	assert(CURVE[ease or "cubic_inout"], "unknown ease " .. tostring(ease))
	for part, v in pose do
		for i = #self.keys, 1, -1 do
			if self.keys[i][1] == frame and self.keys[i][2] == part then
				table.remove(self.keys, i)
			end
		end
		table.insert(self.keys, { frame, part, v, ease or "cubic_inout" })
	end
	return self
end
function Anim:valueAt(part, frame)
	local best, bestF = { 0, 0, 0 }, -math.huge
	for _, k in self.keys do
		if k[2] == part and k[1] <= frame and k[1] > bestF then
			best, bestF = k[3], k[1]
		end
	end
	return best
end
function Anim:full(frame, pose, ease)
	local all = {}
	for _, part in self:joints() do
		all[part] = pose[part] or self:valueAt(part, frame)
	end
	return self:key(frame, all, ease)
end
function Anim:offset(part, frames)
	local kept = {}
	for _, k in self.keys do
		if k[2] == part then
			if not (self.loop and k[1] == self.length) then
				local f = k[1] + frames
				f = self.loop and (f % self.length) or math.clamp(f, 0, self.length)
				table.insert(kept, { f, k[2], k[3], k[4] })
			end
		else
			table.insert(kept, k)
		end
	end
	self.keys = kept
	return self
end
-- Overlap: the part reaches every pose `frames` later than the body (start and end poses stay put),
-- so the torso leads and the arms and head drag behind it.
function Anim:lag(part, frames)
	for _, k in self.keys do
		if k[2] == part and k[1] > 0 and k[1] < self.length then
			k[1] = math.min(k[1] + frames, self.length - 1)
		end
	end
	return self
end
function Anim:marker(frame, name)
	table.insert(self.markers, { frame, name })
	return self
end
function Anim:track(part)
	local track = {}
	for _, k in self.keys do
		if k[2] == part then
			table.insert(track, k)
		end
	end
	table.sort(track, function(a, b) return a[1] < b[1] end)
	if self.loop and #track > 0 then -- periodic: one cycle before and after
		local L = self.length
		local period, hasZero = {}, false
		for _, k in track do
			hasZero = hasZero or k[1] == 0
		end
		for _, k in track do
			if k[1] >= 0 and k[1] < L then
				table.insert(period, k)
			elseif k[1] == L and not hasZero then
				table.insert(period, 1, { 0, k[2], k[3], k[4] })
			end
		end
		track = {}
		for _, shift in { -L, 0, L } do
			for _, k in period do
				table.insert(track, { k[1] + shift, k[2], k[3], k[4] })
			end
		end
	end
	return track
end
function Anim:evaluate(track, frame)
	for i = 1, #track - 1 do
		local a, b = track[i], track[i + 1]
		if frame >= a[1] and frame <= b[1] then
			local ca, cb = poseCFrame(a[2], a[3]), poseCFrame(b[2], b[3])
			if b[1] == a[1] then
				return cb
			end
			return ca:Lerp(cb, CURVE[a[4]]((frame - a[1]) / (b[1] - a[1])))
		end
	end
	local edge = frame <= track[1][1] and track[1] or track[#track]
	return poseCFrame(edge[2], edge[3])
end
function Anim:build()
	local frames = {}
	local function put(f, part, cf, style, dir)
		frames[f] = frames[f] or { poses = {}, markers = {} }
		frames[f].poses[part] = { cf, style, dir }
	end
	local L = self.length
	for _, part in self:joints() do
		local track = self:track(part)
		if #track > 0 then
			for i = 1, #track - 1 do
				local a, b = track[i], track[i + 1]
				local native = NATIVE[a[4]]
				local inside = a[1] >= 0 and b[1] <= L
				-- big steps are baked too: Roblox drifts from a true slerp on steps over ~30 degrees
				local _, ang = poseCFrame(part, a[3]):ToObjectSpace(poseCFrame(part, b[3])):ToAxisAngle()
				local big = math.deg(math.abs(ang)) > 30
				if inside and native and not big then
					put(a[1], part, poseCFrame(part, a[3]), native[1], native[2])
				else
					for f = math.max(a[1], 0), math.min(b[1], L) - 1, BAKE_STEP do
						put(f, part, self:evaluate(track, f), "Linear", "In")
					end
				end
			end
			local lastF = math.min(track[#track][1], L)
			put(lastF, part, self:evaluate(track, lastF), "Linear", "In")
		end
	end
	for _, m in self.markers do
		frames[m[1]] = frames[m[1]] or { poses = {}, markers = {} }
		table.insert(frames[m[1]].markers, m[2])
	end

	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = self.name
	kfs.Loop = self.loop
	kfs.Priority = (Enum.AnimationPriority :: any)[self.priority]
	local order = {}
	for f in frames do
		table.insert(order, f)
	end
	table.sort(order)
	for _, f in order do
		local data = frames[f]
		local kf = Instance.new("Keyframe")
		kf.Time = math.floor(f / self.fps * 1e5) / 1e5
		local made = {}
		local function poseFor(part)
			if made[part] then
				return made[part]
			end
			local p = Instance.new("Pose")
			p.Name = part
			p.Weight = 0 -- placeholder parent pose: ignored by playback
			local parent = PARENT[part]
			p.Parent = parent and poseFor(parent) or kf
			made[part] = p
			return p
		end
		for part, pose in data.poses do
			local p = poseFor(part)
			p.CFrame = pose[1]
			p.EasingStyle = (Enum.PoseEasingStyle :: any)[pose[2]]
			p.EasingDirection = (Enum.PoseEasingDirection :: any)[pose[3]]
			p.Weight = 1
		end
		if not made.HumanoidRootPart and next(data.poses) then
			poseFor("HumanoidRootPart")
		end
		for _, name in data.markers do
			local marker = Instance.new("KeyframeMarker")
			marker.Name = name
			marker.Parent = kf
		end
		kf.Parent = kfs
	end
	return kfs
end

-- one full-body pose: arms, head, torso lean (+ back / - forward), twist (+ left), crouch py, lunge pz.
-- Legs counter-rotate so the feet stay planted (fwjelaa's _lib.lean / _lib.twist).
-- o.step: degrees the left foot steps forward (the right swings back 0.7 as far); o.wide: extra stance width.
-- R6 has no knees, so a split or wide stance lowers the hips until the more upright leg reaches the floor.
local function P(rA, lA, head, leanX, o)
	o = o or {}
	local tw, step, wide = o.tw or 0, o.step or 0, o.wide or 0
	local front, back = step, -step * 0.7
	local upright = math.min(math.abs(front), math.abs(back))
	local drop = 2 * (1 - math.cos(math.rad(upright))) + 2 * (1 - math.cos(math.rad(4 + wide))) - 2 * (1 - math.cos(math.rad(4)))
	return {
		Torso = { leanX, tw, o.roll or 0, 0, (o.py or 0) - drop, o.pz or 0 },
		Head = { head[1], (head[2] or 0) - tw * 0.6, head[3] or 0 },
		["Right Arm"] = rA,
		["Left Arm"] = lA,
		["Right Leg"] = { -leanX + back, -tw, 4 + wide },
		["Left Leg"] = { -leanX + front, -tw, -4 - wide },
	}
end
-- Rest: arms hanging loose, a little out from the hips, head level.
local REST_R, REST_L, REST_H = { 4, 0, 6 }, { 4, 0, -6 }, { 0, 0, 0 }
local REST = P(REST_R, REST_L, REST_H, 0)
local anims = {}

-- Follow-through shared by every cast: the torso leads, the arms trail it, the head drags last.
local function overlap(a, leadArm)
	local trail = leadArm == "Right Arm" and "Left Arm" or "Right Arm"
	a:lag(leadArm, 1)
	a:lag(trail, 2)
	a:lag("Head", 3)
end

-- Uniform: dip, sweep both arms up and back overhead, coil, then hurl forward stepping into it.
do
	local a = new("DM_Uniform", { length = 115, priority = "Action2" })
	a:full(0, REST, "cubic_out")
	a:full(9, P({ -28, 20, 18 }, { -28, -20, -18 }, { -8 }, -8, { py = -0.12 }), "sine_inout")
	a:full(22, P({ 150, 30, 20 }, { 150, -30, -20 }, { 16 }, 10, { step = -8 }), "sine_inout")
	a:full(34, P({ 172, 38, 12 }, { 172, -38, -12 }, { 22 }, 15, { step = -10, py = 0.02 }), "quad_in")
	a:full(40, P({ 178, 40, 10 }, { 178, -40, -10 }, { 24 }, 17, { step = -11 }), "expo_in")
	a:full(44, P({ 100, -18, -6 }, { 100, 18, 6 }, { -8 }, -22, { step = 26, pz = -0.4 }), "linear")
	a:full(47, P({ 108, -24, -8 }, { 108, 24, 8 }, { -10 }, -26, { step = 28, pz = -0.46 }), "cubic_out")
	a:full(60, P({ 94, -14, -4 }, { 94, 14, 4 }, { -5 }, -16, { step = 26, pz = -0.32 }), "sine_inout")
	a:full(76, P({ 86, -8, -2 }, { 86, 8, 2 }, { -3 }, -11, { step = 24, pz = -0.24 }), "cubic_inout")
	a:full(96, P({ 30, 0, 10 }, { 30, 0, -10 }, { -1 }, -3, { step = 8, pz = -0.06 }), "sine_inout")
	a:full(115, REST)
	overlap(a, "Right Arm")
	a:marker(44, "Cast")
	table.insert(anims, a)
end

-- Melt (hex plays it too): hands drawn back low and coiled, palms shoved forward with a lunge,
-- arms tremble as the fire takes the victim while the caster leans harder into it, then slumps.
do
	local a = new("DM_Melt", { length = 130, priority = "Action2" })
	a:full(0, REST, "cubic_out")
	a:full(8, P({ 30, 0, 14 }, { 30, 0, -14 }, { 2 }, 2, { py = -0.04 }), "sine_inout")
	a:full(19, P({ -42, 24, 16 }, { -42, -24, -16 }, { -8 }, 8, { py = -0.14, step = -6, tw = 6 }), "sine_inout")
	a:full(27, P({ -50, 30, 18 }, { -50, -30, -18 }, { -10 }, 11, { py = -0.17, step = -8, tw = 8 }), "expo_in")
	a:full(34, P({ 94, 14, -8 }, { 94, -14, 8 }, { -4 }, -22, { step = 30, pz = -0.45 }), "linear")
	a:full(37, P({ 103, 18, -10 }, { 103, -18, 10 }, { -6 }, -26, { step = 32, pz = -0.5 }), "cubic_out")
	local f, s = 42, 1
	while f <= 90 do
		local k = (f - 42) / 48
		local j = (4.5 - 1.5 * k) * s -- the tremble eases a touch as the effort holds
		local press = -20 - 4 * k -- while the body leans harder into the push
		a:full(f, P({ 95 + j, 14, -6 - j * 0.5 }, { 95 - j, -14, 6 - j * 0.5 }, { -4 + j * 0.4, j * 0.5 }, press - j * 0.3,
			{ step = 30, pz = -0.42 - 0.06 * k, tw = j * 0.4 }), "linear")
		f += 3
		s = -s
	end
	a:full(95, P({ 80, 6, -4 }, { 80, -6, 4 }, { -14 }, -14, { step = 28, pz = -0.3 }), "cubic_inout")
	a:full(110, P({ 26, 0, 10 }, { 26, 0, -10 }, { -6 }, -4, { step = 10, pz = -0.08 }), "sine_inout")
	a:full(130, REST)
	overlap(a, "Right Arm")
	a:marker(34, "Cast")
	table.insert(anims, a)
end

-- Raise: wide stance, folded over the ground palms down, a straining hold, then both arms dragged up
-- as the dead climb out, the chest opening up to the sky.
do
	local a = new("DM_Raise", { length = 140, priority = "Action2" })
	a:full(0, REST, "cubic_inout")
	a:full(10, P({ 40, 0, 26 }, { 40, 0, -26 }, { 6 }, 6, { wide = 6 }), "sine_inout")
	a:full(24, P({ 12, -20, 26 }, { 12, 20, -26 }, { -16 }, -30, { wide = 14, py = -0.1 }), "sine_inout")
	a:full(34, P({ 6, -24, 30 }, { 6, 24, -30 }, { -20 }, -34, { wide = 15, py = -0.12 }), "linear")
	a:full(38, P({ 9, -24, 28 }, { 3, 24, -32 }, { -19 }, -33, { wide = 15, py = -0.12 }), "linear")
	a:full(42, P({ 4, -24, 31 }, { 8, 24, -29 }, { -21 }, -35, { wide = 15, py = -0.13 }), "linear")
	a:full(46, P({ 7, -24, 30 }, { 5, 24, -30 }, { -20 }, -34, { wide = 15, py = -0.12 }), "quad_in")
	a:full(58, P({ 60, -10, 32 }, { 60, 10, -32 }, { -6 }, -16, { wide = 13 }), "sine_inout")
	a:full(74, P({ 148, 10, 30 }, { 148, -10, -30 }, { 20 }, 6, { wide = 11 }), "sine_inout")
	a:full(84, P({ 174, 16, 30 }, { 174, -16, -30 }, { 30 }, 14, { wide = 10, py = 0.03 }), "cubic_out")
	a:full(90, P({ 178, 18, 34 }, { 178, -18, -34 }, { 32 }, 16, { wide = 10, py = 0.03 }), "sine_inout")
	a:full(106, P({ 166, 12, 26 }, { 166, -12, -26 }, { 26 }, 10, { wide = 8 }), "cubic_inout")
	a:full(122, P({ 50, 0, 16 }, { 50, 0, -16 }, { 4 }, 0, { wide = 3 }), "sine_inout")
	a:full(140, REST)
	overlap(a, "Right Arm")
	a:marker(50, "Rise")
	table.insert(anims, a)
end

-- Soul rip: a clawed reach stepping in, straining and shaking, then a yank back to the chest that
-- throws the weight onto the back foot and rocks the body.
do
	local a = new("DM_SoulRip", { length = 120, priority = "Action2" })
	a:full(0, REST, "cubic_out")
	a:full(6, P({ 20, 0, 4 }, { -6, 0, -10 }, { 2 }, 4, { tw = -6 }), "sine_inout")
	local function reach(j)
		return P({ 98 + j, -30, -4 - j * 0.6 }, { -24, 0, -18 }, { -2 + j * 0.3, j * 0.4 }, -10 - j * 0.2,
			{ tw = 16, step = 18, pz = -0.2 })
	end
	a:full(14, reach(0), "cubic_out")
	local f, s = 17, 1
	while f < 40 do
		a:full(f, reach((2 + (f - 17) / 12) * s), "linear") -- the shake grows as the soul resists
		f += 3
		s = -s
	end
	a:full(40, reach(0), "expo_in")
	a:full(47, P({ 50, 40, -48 }, { 58, 0, 36 }, { 12 }, 16, { tw = -12, step = -6, py = -0.05, pz = 0.2 }), "linear")
	a:full(50, P({ 44, 46, -54 }, { 62, 0, 40 }, { 15 }, 20, { tw = -14, step = -8, py = -0.07, pz = 0.24 }), "cubic_out")
	a:full(64, P({ 52, 36, -46 }, { 52, 0, 32 }, { 7 }, 9, { tw = -8, step = -6, pz = 0.12 }), "sine_inout")
	a:full(84, P({ 56, 28, -40 }, { 46, 0, 26 }, { 4 }, 6, { tw = -5, step = -4, pz = 0.06 }), "cubic_inout")
	a:full(102, P({ 26, 8, -14 }, { 22, 0, 8 }, { 1 }, 2, { tw = -2 }), "sine_inout")
	a:full(120, REST)
	overlap(a, "Right Arm")
	a:marker(47, "Rip")
	table.insert(anims, a)
end

-- Shadow step: arms wrapped tight across the chest, hunched low while sinking; then climbing back
-- out of the ground: reach up, grab the rim, haul the body over the lip with a knee coming up, stand.
-- Timed to the server (shadowStep): sunk by ~f42, rising f54-f93.
do
	local a = new("DM_ShadowStep", { length = 130, priority = "Action2" })
	a:full(0, REST, "cubic_out")
	a:full(5, P({ 40, 0, -20 }, { 40, 0, 20 }, { 4 }, 4, { py = 0.02 }), "quad_in")
	a:full(14, P({ 84, -20, -60 }, { 84, 20, 60 }, { -20 }, -20, { wide = 12, py = -0.12 }), "cubic_out")
	a:full(40, P({ 86, -22, -62 }, { 86, 22, 62 }, { -24 }, -24, { wide = 14, py = -0.16 }), "sine_inout")
	-- under the ground: reach up for the rim
	a:full(52, P({ 170, 10, 22 }, { 166, -10, -18 }, { 24 }, -4), "cubic_out")
	a:full(58, P({ 158, 0, 24 }, { 162, 0, -24 }, { 20 }, -8), "quad_in")
	-- hands planted on the rim: as the body comes up past them the arms swing down into a push
	a:full(68, P({ 112, 0, 26 }, { 118, 0, -26 }, { 6 }, -30, { step = 30 }), "linear")
	a:full(76, P({ 62, 0, 28 }, { 70, 0, -28 }, { -2 }, -34, { step = 62 }), "linear") -- knee up over the lip
	a:full(86, P({ 8, 0, 26 }, { 14, 0, -26 }, { -6 }, -24, { step = 40 }), "cubic_out") -- pushing off the ground
	a:full(96, P({ -14, 0, 22 }, { -10, 0, -22 }, { 2 }, -10, { step = 16 }), "sine_inout") -- standing up
	a:full(110, P({ 14, 0, 12 }, { 14, 0, -12 }, { 4 }, -2, { step = 4 }), "sine_inout")
	a:full(130, REST)
	overlap(a, "Right Arm")
	a:marker(54, "Climb")
	table.insert(anims, a)
end

local dir = (process.args[1] or "anims") .. "/"
for _, a in anims do
	local kfs = a:build()
	fs.writeFile(dir .. a.name .. ".rbxm", roblox.serializeModel({ kfs }))
	print(a.name, #kfs:GetChildren() .. " keyframes")
end

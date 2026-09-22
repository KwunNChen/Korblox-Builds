--[[
	GasVisuals
	The cloud you can see.

	Built with Instance.new rather than cloned from a staged model. Every vanilla
	TREK effect clones a `Particle` instance parented inside its own module, and
	this deliberately does not: the entire look answers to GasConfig.Visual, so
	tuning the gas never means opening Studio and hunting for an emitter.

	Created on the server and parented into the world, so every client sees the
	same cloud in the same place. A client-built cloud would drift out of
	agreement with the server's damage volume, which is the one thing a player
	must never be wrong about.

	The emitters ring the centre instead of stacking on it. A single emitter
	large enough to fill CloudRadius visibly pulses as individual particles are
	born and die; several smaller ones offset from each other average that out.
]]

local GasVisuals = {}
GasVisuals.__index = GasVisuals

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

export type Handle = {
	setDensity: (Handle, number) -> (),
	destroy: (Handle) -> (),
}

local function buildEmitter(visual, share: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")

	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = ColorSequence.new(visual.Colour)
	emitter.Lifetime = visual.ParticleLifetime
	emitter.Speed = visual.Speed
	emitter.Rate = share
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-14, 14)

	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, visual.SizeStart),
		NumberSequenceKeypoint.new(1, visual.SizeEnd),
	})

	--[[
		Fade in and out rather than appearing at full opacity.

		A particle that pops into existence at its final alpha makes the cloud
		edge crawl visibly as individual puffs spawn. The 0.15/0.75 shoulders are
		wide enough to hide that and narrow enough that the gas still looks thick
		through the middle of its life.
	]]
	local peak = 1 - math.clamp(visual.Opacity, 0, 1)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, peak),
		NumberSequenceKeypoint.new(0.75, peak),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- Gas is heavier than air, so it barely rises. Drag settles it rather than
	-- letting puffs coast outward forever.
	emitter.Acceleration = Vector3.new(0, visual.Rise, 0)
	emitter.Drag = 1.4

	-- Self-lit and uninfluenced: gas should read the same colour in a dark interior
	-- as it does in the open, otherwise it disappears exactly where it is most
	-- dangerous.
	emitter.LightEmission = visual.Glow
	emitter.LightInfluence = 0

	return emitter
end

--[[
	Spawn a cloud at `position`.

	The anchor part is invisible, non-collidable and unqueryable -- it exists
	only to carry attachments. It is parented into IgnoreList because TREK's
	explosion sweep excludes that folder, so a later blast in the same area does
	not try to damage the cloud.
]]
function GasVisuals.create(position: Vector3, config): Handle
	local visual = config.Visual

	local anchor = Instance.new("Part")
	anchor.Name = "GasCloud"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)

	local count = math.max(1, visual.EmitterCount)
	local share = visual.Rate / count
	local emitters: { ParticleEmitter } = {}

	-- Ring radius is a fraction of the damage radius: far enough apart to break
	-- up the pulsing, close enough that the visible gas still reads as one cloud
	-- rather than a circle of separate puffs.
	local ringRadius = config.CloudRadius * 0.35

	for index = 1, count do
		local attachment = Instance.new("Attachment")

		if index == 1 then
			attachment.Position = Vector3.zero
		else
			local angle = ((index - 1) / (count - 1)) * math.pi * 2
			attachment.Position = Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius)
		end

		local emitter = buildEmitter(visual, share)
		emitter.Parent = attachment
		attachment.Parent = anchor
		table.insert(emitters, emitter)
	end

	--[[
		The hiss.

		Parented to the anchor part rather than played globally, which is what
		makes it positional -- gas is the one thing here that can hurt you from
		outside your field of view, so being able to hear roughly where it is
		matters.

		Starts silent and is brought up by setDensity along with the particles,
		so it fades in with the cloud instead of snapping to full the instant the
		fuse blows.
	]]
	local sound: Sound? = nil
	local soundConfig = config.Sound

	if soundConfig and soundConfig.Hiss and soundConfig.Hiss ~= "" then
		local created = Instance.new("Sound")
		created.Name = "GasHiss"
		created.SoundId = soundConfig.Hiss
		created.Looped = soundConfig.Looped ~= false
		created.Volume = 0
		created.RollOffMode = Enum.RollOffMode.InverseTapered
		created.RollOffMinDistance = soundConfig.RollOffMin
		created.RollOffMaxDistance = soundConfig.RollOffMax
		created.Parent = anchor
		created:Play()
		sound = created
	end

	anchor.Parent = workspace:FindFirstChild("IgnoreList") or workspace

	local self = setmetatable({
		_anchor = anchor,
		_emitters = emitters,
		_share = share,
		_visual = visual,
		_sound = sound,
		_soundConfig = soundConfig,
		_dead = false,
	}, GasVisuals)

	return (self :: any) :: Handle
end

--[[
	Scale the cloud between nothing and full strength.

	Called every tick with the same build-up curve the damage uses, so what a
	player sees and what hurts them stay in step.
]]
function GasVisuals:setDensity(density: number)
	if self._dead then
		return
	end

	local clamped = math.clamp(density, 0, 1)
	local scaled = self._share * clamped

	for _, emitter in ipairs(self._emitters) do
		emitter.Rate = scaled
	end

	-- The hiss rides the same curve, so what you hear and what you see agree.
	if self._sound and self._soundConfig then
		self._sound.Volume = self._soundConfig.Volume * clamped
	end
end

--[[
	Stop producing gas, then clean up once the last puff has aged out.

	Destroying the anchor immediately would delete every live particle with it
	and the cloud would vanish between frames. Rate goes to zero, the existing
	puffs finish their lifetime, and only then does the instance go away.
]]
function GasVisuals:destroy()
	if self._dead then
		return
	end
	self._dead = true

	for _, emitter in ipairs(self._emitters) do
		emitter.Enabled = false
		emitter.Rate = 0
	end

	--[[
		Fade the hiss rather than cutting it.

		The particles keep drifting for several seconds after the gas stops
		damaging, and a hiss that stopped dead on the same frame would announce
		the cloud as harmless while it still looked dangerous. Tweened so it
		thins out with them.
	]]
	if self._sound and self._soundConfig then
		local fade = self._soundConfig.FadeOut or 0

		if fade > 0 then
			game:GetService("TweenService")
				:Create(self._sound, TweenInfo.new(fade), { Volume = 0 })
				:Play()
		else
			self._sound.Volume = 0
		end
	end

	local anchor = self._anchor
	local linger = self._visual.LingerAfterExpiry + self._visual.ParticleLifetime.Max

	task.delay(linger, function()
		if anchor and anchor.Parent then
			anchor:Destroy()
		end
	end)
end

return GasVisuals

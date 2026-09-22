--[[
	GasNerve
	What a lungful of nerve agent does, from the first breath to the body.

	One dose is the whole story. The cloud reports contact; everything after that
	happens here and cannot be stopped by leaving the cloud, by a medic, or by
	the gas expiring. That is the point of the weapon -- the cloud is not what
	kills you, it is only where you were standing when you were killed.

	The sequence:

	    dose      the moment contact is registered. Irreversible from here.
	    seize     the body goes limp and starts convulsing
	    bleed     blood from the mouth, a little after the convulsions start
	    death     health drains to zero across TimeToDeath and stays there

	Health is drained rather than set, so a player watching their own bar sees it
	fall. A kill that simply set Health to 0 would read as a disconnect.

	Server-only, like everything that decides anything in this package.
]]

local GasNerve = {}

--[[
	Bounded, and loud when it fails -- the same helper every other module in the
	package uses.

	This was the one require in the package that did not: it passed the result of
	a timed WaitForChild straight into require, so a missing GasRagdoll produced
	"invalid argument" rather than a message naming the file and the install. The
	distinction matters because this module is the newest in the chain, which
	makes it exactly the one an older install will be missing.
]]
local function expect(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name) or parent:WaitForChild(name, 10)

	if not child then
		error(string.format(
			"[TREKGasGrenade] %s has no child %q -- the install is incomplete. "
				.. "Check every folder moved out of the staging folder, including "
				.. "any added since you last installed.",
			parent:GetFullName(), name
		), 0)
	end

	return child
end

local GasRagdoll = require(expect(script.Parent, "GasRagdoll"))

--[[
	Everyone currently dying, so a second lungful does not start a second
	countdown on the same person.

	Weak-keyed so a character destroyed mid-sequence drops out rather than being
	held alive here.
]]
local dying: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--[[
	How long this character has been breathing it, against the threshold that
	dooms them.

	Separate from the dying set because it is the BEFORE state: accumulating, and
	still escapable right up until it crosses the line.
]]
local contact: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function bloodEmitter(config): ParticleEmitter
	local nerve = config.Nerve
	local emitter = Instance.new("ParticleEmitter")

	emitter.Name = "GasBlood"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(nerve.BloodColour)
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = nerve.BloodRate
	emitter.Speed = NumberRange.new(2, 6)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Acceleration = Vector3.new(0, -workspace.Gravity * 0.35, 0)

	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, nerve.BloodSize),
		NumberSequenceKeypoint.new(1, nerve.BloodSize * 0.4),
	})

	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})

	return emitter
end

--[[
	Shove the limbs about.

	Angular velocity rather than a force: a limp limb on a ball socket answers to
	spin immediately and settles on its own, where a force has to fight the
	constraint and ends up either invisible or launching the body across the
	room. The torso is deliberately included -- convulsions that leave the trunk
	perfectly still read as a puppet with loose arms.
]]
local function twitch(limbs: { BasePart }, strength: number)
	for _, part in ipairs(limbs) do
		if not part.Parent then
			continue
		end

		local kicked = part.AssemblyAngularVelocity + Vector3.new(
			(math.random() - 0.5) * 2 * strength,
			(math.random() - 0.5) * 2 * strength,
			(math.random() - 0.5) * 2 * strength
		)

		--[[
			Capped, because this adds without ever subtracting.

			A tick every quarter second for twelve seconds is forty-eight kicks
			onto whatever spin the limb already had. Roblox damps angular
			velocity, but not reliably faster than this tops it up, and a limb
			that has wound up to several times TwitchStrength stops reading as a
			convulsion and starts driving itself through the floor -- which it
			does by violating its own constraint hard enough for the solver to
			teleport it out the other side.

			Clamping the total rather than lowering the per-tick kick keeps the
			convulsion looking the same when the body is still and only bites
			once it has wound up.
		]]
		if kicked.Magnitude > strength then
			kicked = kicked.Unit * strength
		end

		part.AssemblyAngularVelocity = kicked
	end
end

--[[
	The convulsion that puts them down.

	One impulse on the ROOT assembly, not on every limb.

	Shoving each limb separately looks like it should produce a more violent
	collapse and does the opposite: the six limbs are six separate assemblies
	tied together by ball sockets with a 60 degree limit, and handing each one
	its own velocity asks the solver to reconcile six conflicting bodies in a
	single step. It answers with corrective impulses big enough to push parts
	through the floor, which is what "goes into the ground" was.

	SkiRagdoll and the place's own RagdollDeath both drive the root alone and
	let the constraints carry the limbs. They work. This does the same.
]]
local function shove(character: Model, nerve)
	if nerve.CollapseImpulse <= 0 then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if not root or not root:IsA("BasePart") then
		return
	end

	--[[
		A random heading, lifted out of the floor.

		Built from an angle rather than three random components so the
		horizontal direction is uniform: three random axes cluster into a cube's
		corners, which would make bodies fall diagonally more often than
		straight. That is the kind of bias you notice without being able to name
		it.
	]]
	local heading = math.random() * 2 * math.pi
	local lift = math.clamp(nerve.CollapseLift, 0, 1)

	local direction = Vector3.new(
		math.cos(heading) * (1 - lift),
		lift,
		math.sin(heading) * (1 - lift)
	)

	-- A lift of exactly 1 leaves no horizontal part, which is still a perfectly
	-- good direction -- straight up -- but Unit on a zero vector is not, so the
	-- magnitude is checked rather than assumed.
	if direction.Magnitude < 1e-3 then
		direction = Vector3.yAxis
	end

	--[[
		Assigned rather than added, unlike the twitch.

		The twitch accumulates onto whatever the body is already doing because it
		is a flutter on top of existing motion. This one has to look the same
		whether the victim was sprinting or standing still -- a running player who
		kept their momentum would be thrown twice as far as a stationary one, for
		no reason anyone watching could account for.
	]]
	local part = root :: BasePart

	part.AssemblyLinearVelocity = direction.Unit * nerve.CollapseImpulse
	part.AssemblyAngularVelocity = Vector3.new(
		(math.random() - 0.5) * 2 * nerve.CollapseSpin,
		(math.random() - 0.5) * 2 * nerve.CollapseSpin,
		(math.random() - 0.5) * 2 * nerve.CollapseSpin
	)
end

--[[
	Start the sound the victim makes, and hand back a way to stop it.

	Parented to the Head rather than played from the cloud: the body walks,
	staggers and is thrown by the collapse, and a sound anchored where they were
	dosed would separate from them within a second. It also has to outlive the
	cloud, which expires long before a slow death does.

	Returns a closure rather than the Sound so the caller cannot accidentally
	leave a looped sound playing on a corpse by forgetting one of the exits.
]]
local function voice(character: Model, nerve): () -> ()
	local settings = nerve.Sound

	if not settings or not settings.Id or settings.Id == "" then
		return function() end
	end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return function() end
	end

	local sound = Instance.new("Sound")
	sound.Name = "GasNerveVoice"
	sound.SoundId = settings.Id
	sound.Volume = settings.Volume
	sound.Looped = true
	sound.RollOffMinDistance = settings.RollOffMin
	sound.RollOffMaxDistance = settings.RollOffMax
	sound.Parent = head
	sound:Play()

	local stopped = false

	return function()
		if stopped then
			return
		end
		stopped = true

		if not sound.Parent then
			return
		end

		local fade = settings.FadeOut or 0

		if fade <= 0 then
			sound:Destroy()
			return
		end

		--[[
			Fade, then destroy -- and destroy on a timer rather than on the
			tween finishing.

			A tween Completed callback never fires if the Sound is destroyed
			first, which is exactly what happens when the character respawns
			mid-fade. The timer runs regardless and a Destroy on an
			already-destroyed instance is harmless.
		]]
		game:GetService("TweenService")
			:Create(sound, TweenInfo.new(fade), { Volume = 0 })
			:Play()

		task.delay(fade, function()
			sound:Destroy()
		end)
	end
end

--[[
	Has this character taken enough to be doomed?

	The threshold is per-character because the thrower gets a longer one. Nobody
	else gets any grace at all: a single tick inside the cloud is a dose, which
	is what makes the gas a wall rather than an area you can push through.

	The thrower's grace is not mercy so much as playability -- a throw that
	bounced badly should be survivable if you turn and run immediately, because
	otherwise the weapon is as dangerous to carry as to face.
]]
local function thresholdFor(character: Model, thrower: Player?, config): number
	local nerve = config.Nerve

	if thrower and thrower.Character == character then
		return nerve.ThrowerGrace
	end

	return nerve.DoseThreshold
end

--[[
	Run one character from dose to death.

	Deliberately a single linear routine rather than a state machine: the whole
	sequence is one path with no branches, because nothing can interrupt it.
]]
local function collapse(character: Model, humanoid: Humanoid, thrower: Player?, config)
	local nerve = config.Nerve

	--[[
		Mark it the way TREK marks conditions, so anything else in the game --
		a HUD, a spectator overlay, a medic system that wants to fail loudly --
		can see this character is gone without knowing about this module.
	]]
	humanoid:SetAttribute(nerve.ConditionAttribute, true)

	--[[
		Silence the ordinary pain noises before a single tick of damage lands.

		Set here rather than after the seizure because the drain and the barks
		it triggers both begin below, and an attribute set even one frame late
		lets the first "ow" through -- which is the one the player actually
		notices, because it is the one that overlaps the gas sound starting.
	]]
	character:SetAttribute(nerve.SuppressHurtAttribute, true)

	local silence = voice(character, nerve)

	if nerve.SeizeDelay > 0 then
		task.wait(nerve.SeizeDelay)
	end

	if not character.Parent or humanoid.Health <= 0 then
		-- Killed by something else during the seize delay. They still get no
		-- hurt barks, but the loop has to go with them.
		silence()
		return
	end

	local limbs = GasRagdoll.start(character)

	--[[
		Immediately, in the same frame the joints are released.

		Deferring it by even a tick lets the body begin falling under gravity
		first, and the shove then reads as a corpse being kicked rather than as
		the seizure that dropped them.
	]]
	shove(character, nerve)

	--[[
		Blood starts after the convulsions, not with them.

		Simultaneous reads as one indistinguishable mess; a beat between them
		reads as a body losing one fight and then another.
	]]
	task.delay(nerve.BloodDelay, function()
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") or humanoid.Health <= 0 then
			return
		end

		local attachment = Instance.new("Attachment")
		attachment.Name = "GasBloodPoint"
		attachment.Position = Vector3.new(0, -0.3, -0.6)
		attachment.Parent = head

		local emitter = bloodEmitter(config)
		emitter.Parent = attachment
	end)

	--[[
		Drain, tick by tick, rather than killing outright.

		Each step is a fraction of max health so the fall takes TimeToDeath
		regardless of how much the victim started with -- a wounded player and a
		healthy one both die on the same schedule, which is what "the dose is
		lethal" means.
	]]
	local step = nerve.TickInterval
	local ticks = math.max(1, math.floor(nerve.TimeToDeath / step))
	local perTick = humanoid.MaxHealth / ticks

	local elapsed = 0

	while elapsed < nerve.TimeToDeath do
		if not character.Parent or humanoid.Health <= 0 then
			break
		end

		if #limbs > 0 and nerve.TwitchStrength > 0 then
			twitch(limbs, nerve.TwitchStrength)
		end

		humanoid.Health = math.max(humanoid.Health - perTick, 0)

		task.wait(step)
		elapsed += step
	end

	--[[
		Make sure of it.

		The loop exits on time rather than on health, and rounding across a few
		dozen ticks can leave a sliver behind. A nerve agent that left someone on
		two health would be worse than one that did nothing.
	]]
	if character.Parent and humanoid.Health > 0 then
		humanoid.Health = 0
	end

	silence()

	dying[character] = nil
end

--[[
	Report contact with the cloud.

	Called once per cloud tick for everyone inside, whatever their distance --
	the whole radius doses at the same rate, so the damage falloff that shapes
	the old gas does not apply here. Either you are breathing it or you are not.
]]
function GasNerve.expose(character: Model, humanoid: Humanoid, thrower: Player?, config)
	local nerve = config.Nerve

	if not nerve.Enabled or dying[character] or humanoid.Health <= 0 then
		return
	end

	local taken = (contact[character] or 0) + config.TickInterval
	contact[character] = taken

	if taken < thresholdFor(character, thrower, config) then
		return
	end

	dying[character] = true
	contact[character] = nil

	task.spawn(collapse, character, humanoid, thrower, config)
end

--[[
	Forget a character's partial exposure.

	Called when they leave the cloud, so sub-threshold contact does not
	accumulate across separate clouds hours apart. Does nothing to anyone already
	dosed -- there is no clearing that.
]]
function GasNerve.clear(character: Model)
	if not dying[character] then
		contact[character] = nil
	end
end

return GasNerve

--[[
	GasExposure
	How gassed each character currently is, as one number from 0 to 1.

	The server owns this because the server is the only thing that knows who is
	standing in gas. It is published as an attribute on the victim's Humanoid,
	which the client reads to drive the blur, tint, ring and muffle. Publishing a
	value rather than firing effect remotes means a client cannot be told to
	blind someone else -- the worst a tampered client can do is blind itself.

	It also makes the state readable by anything else in the game. A HUD, a medic
	system, a spectator overlay or a future gas mask can all watch the same
	attribute without this module knowing they exist.

	Exposure climbs while a cloud keeps topping it up and decays once the
	top-ups stop, which is what produces "builds while you stand in it, fades
	once you are out" without either side tracking who left when.
]]

local GasExposure = {}

-- How often the decay loop runs. Fine enough that the fade reads as smooth
-- after the client's own smoothing, coarse enough to be free.
local STEP = 0.1

local tracked: { [Humanoid]: { value: number, lastTopUp: number } } = {}
local running = false

local function publish(humanoid: Humanoid, name: string, value: number)
	--[[
		Cleared rather than set to zero when it runs out.

		An attribute that lingers at 0 is indistinguishable from one that is
		being actively held at 0 by a cloud, and it leaves a value on every
		character who has ever been gassed. Nil means "not gassed".
	]]
	if value <= 0.001 then
		humanoid:SetAttribute(name, nil)
	else
		humanoid:SetAttribute(name, value)
	end
end

local function run(config)
	running = true

	local settings = config.Disorient
	local name = settings.AttributeName

	--[[
		How long without a top-up before decay starts.

		A character standing in gas is only topped up once per cloud tick, so
		decaying the moment a frame passes without one would fight the build-up
		between every tick. The grace is a little longer than a tick so only
		genuinely leaving the cloud starts the fade.
	]]
	local grace = config.TickInterval * 1.6

	while next(tracked) ~= nil do
		local dt = task.wait(STEP)
		local now = os.clock()

		for humanoid, state in pairs(tracked) do
			if not humanoid.Parent then
				tracked[humanoid] = nil
				continue
			end

			-- Dying clears it outright. Respawning into a lingering blur would
			-- read as the new character being gassed on spawn.
			if humanoid.Health <= 0 then
				publish(humanoid, name, 0)
				tracked[humanoid] = nil
				continue
			end

			if now - state.lastTopUp > grace then
				state.value -= dt / math.max(settings.FadeTime, 0.01)
			end

			if state.value <= 0 then
				publish(humanoid, name, 0)
				tracked[humanoid] = nil
				continue
			end

			publish(humanoid, name, state.value)
		end
	end

	running = false
end

--[[
	Top up one character's exposure by a tick's worth.

	Called by the cloud for everyone inside it, once per TickInterval, so the
	rate of climb is set by BuildTime rather than by how often the cloud happens
	to tick.
]]
function GasExposure.add(humanoid: Humanoid, config)
	local settings = config.Disorient
	if not settings.Enabled then
		return
	end

	local state = tracked[humanoid]
	if not state then
		state = { value = 0, lastTopUp = 0 }
		tracked[humanoid] = state
	end

	local gain = config.TickInterval / math.max(settings.BuildTime, 0.01)
	state.value = math.min(state.value + gain, 1)
	state.lastTopUp = os.clock()

	publish(humanoid, settings.AttributeName, state.value)

	-- One loop for everyone, started on demand and exiting when the last
	-- exposure clears. Nothing runs while nobody is gassed.
	if not running then
		task.spawn(run, config)
	end
end

return GasExposure

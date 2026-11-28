--[[
	GasDisorient
	Renders being gassed: blurred, tinted vision and muffled hearing with a ring.

	LocalScript in StarterPlayerScripts. It decides nothing -- it reads one
	number, GasExposure, off the local character's Humanoid and maps it onto
	effects. The server writes that number, so a tampered client can only blind
	itself.

	Everything is built once and left at zero rather than created and destroyed
	per cloud. A BlurEffect appearing in Lighting mid-fight causes a visible
	hitch on some machines; one that has been sitting there at Size 0 does not.

	Muffle reuses TREK's own arrangement: an EqualizerSoundEffect on a SoundGroup
	called Muffle in SoundService, which is what its concussion effect already
	drives. If the place has no such group the muffle is skipped and everything
	else still works, exactly as TREK guards it.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

--[[
	Bounded, and loud when it fails.

	An unbounded WaitForChild in a require chain does not fail, it hangs -- and
	every module waiting on this one hangs with it, silently. Ten seconds is far
	longer than replication ever needs and far shorter than a playtest, so a
	missing file announces itself instead of stalling the package.
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

local package = expect(ReplicatedStorage, "TREKGasGrenade")
local Config = require(expect(package, "GasConfig"))
local settings = Config.Disorient

if not settings.Enabled then
	return
end

local player = Players.LocalPlayer

-- White is ColorCorrection's neutral: TintColor multiplies the frame, so this
-- is the "no tint" end that every tint value is measured from.
local NO_TINT = Color3.new(1, 1, 1)

-- ---------------------------------------------------------------------------
-- EFFECTS
-- ---------------------------------------------------------------------------

local blur = Instance.new("BlurEffect")
blur.Name = "GasBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

--[[
	Created neutral, not orange.

	Every channel starts at its no-effect value so the instant it is enabled it
	renders whatever the loop sets that same frame. Built holding the gas colour
	-- as this was -- it would flash full orange for one frame on the first
	exposure, before the lerp took over.
]]
local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "GasTint"
tint.TintColor = NO_TINT
tint.Saturation = 0
tint.Brightness = 0
tint.Contrast = 0
tint.Enabled = false
tint.Parent = Lighting

--[[
	The ring.

	Prefers TREK's own staged Tinnitus sound so gas and blasts ring with the same
	tone, and falls back to a configured id. If neither exists there is simply no
	ring -- the blur and tint carry it.
]]
local ring: Sound? = nil

do
	local source = nil
	local trek = shared.S

	if settings.Ring == "" and typeof(trek) == "table" and trek.TREK_EffectsStorage then
		local sounds = trek.TREK_EffectsStorage:FindFirstChild("Sounds")
		local staged = sounds and sounds:FindFirstChild("Tinnitus")
		if staged and staged:IsA("Sound") then
			source = staged.SoundId
		end
	end

	source = source or (settings.Ring ~= "" and settings.Ring or nil)

	if source then
		local created = Instance.new("Sound")
		created.Name = "GasRing"
		created.SoundId = source
		created.Looped = true
		created.Volume = 0
		created.Parent = SoundService
		created:Play()
		ring = created
	end
end

--[[
	The muffle.

	Parented into SoundService.Muffle rather than created alongside it, because
	an EqualizerSoundEffect only affects the SoundGroup it lives in -- one
	parented to SoundService itself would silently do nothing.
]]
local muffle: EqualizerSoundEffect? = nil

do
	local group = SoundService:FindFirstChild("Muffle")

	if group and group:IsA("SoundGroup") then
		local created = Instance.new("EqualizerSoundEffect")
		created.Name = "GasMuffle"
		created.HighGain = 0
		created.MidGain = 0
		created.LowGain = 0
		created.Enabled = false
		created.Parent = group
		muffle = created
	end
end

-- ---------------------------------------------------------------------------
-- DRIVE
-- ---------------------------------------------------------------------------

local shown = 0

local function targetExposure(): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	local value = humanoid:GetAttribute(settings.AttributeName)
	return (type(value) == "number") and math.clamp(value, 0, 1) or 0
end

RunService.RenderStepped:Connect(function(dt)
	local target = targetExposure()

	--[[
		Chased rather than assigned.

		The server only writes on each cloud tick, so the raw value arrives in
		steps of a few tenths. Without this the blur visibly jumps every tick
		instead of thickening.
	]]
	shown += (target - shown) * math.clamp(dt * settings.SmoothSpeed, 0, 1)

	if shown < 0.002 then
		shown = 0
	end

	local active = shown > 0

	blur.Enabled = active
	tint.Enabled = active

	if active then
		blur.Size = settings.MaxBlur * shown

		--[[
			Lerped from white, NOT assigned.

			TintColor multiplies the frame, so white is "no tint" and the gas
			colour is full strength. Assigning the gas colour directly -- which
			this did -- meant the orange slammed to maximum the instant any
			exposure existed and stayed pinned there for the whole fade, while
			the blur decayed around it. The only thing that ever removed it was
			`active` flicking false at the very end, so it switched off rather
			than faded.

			Scaled by MaxTint as well as exposure so the ceiling is tunable
			without touching the colour itself.
		]]
		tint.TintColor = NO_TINT:Lerp(settings.TintColour, settings.MaxTint * shown)
		tint.Saturation = settings.MaxSaturation * shown
		tint.Brightness = settings.MaxBrightness * shown
		tint.Contrast = settings.MaxContrast * shown
	end

	if ring then
		ring.Volume = settings.RingVolume * shown
	end

	if muffle then
		muffle.Enabled = active
		if active then
			muffle.HighGain = settings.MuffleGain * shown
			muffle.MidGain = settings.MuffleGain * shown * 0.6
		end
	end
end)

--[[
	Respawning clears it instantly rather than fading.

	The server drops the attribute on death, but the local value is still part
	way through its fade -- and a fresh character blinking into a blur reads as
	spawning already gassed.
]]
player.CharacterAdded:Connect(function()
	shown = 0
	blur.Size = 0
	blur.Enabled = false

	-- Reset every channel, not just Enabled. A disabled effect keeps its
	-- properties, so re-enabling it mid-fade would flash the old values for a
	-- frame before the loop caught up.
	tint.Enabled = false
	tint.TintColor = NO_TINT
	tint.Saturation = 0
	tint.Brightness = 0
	tint.Contrast = 0

	if ring then
		ring.Volume = 0
	end

	if muffle then
		muffle.Enabled = false
	end
end)

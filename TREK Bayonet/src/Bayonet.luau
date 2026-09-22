--!strict
--[[
	The bayonet fire mode, as a TREK Custom Bullets bullet type.

	Install at:
		ReplicatedStorage > TREK_SERVICES > TREK_Modules > BulletTypes > Bayonet

	and reference it from the weapon's [2] block as BulletType = "Bayonet".

	--------------------------------------------------------------------------
	WHAT THIS DOES, AND WHAT IT DELIBERATELY DOES NOT
	--------------------------------------------------------------------------

	It sends one empty message to the server and restores your sprint. That is
	the whole client half.

	It does NOT decide who was hit. The pack's own Melee type uses ShapecastHitbox
	on the client and then calls the handler's damage function, which fires
	TREK_Remotes.Damage with a client-supplied origin -- and TREK does not check
	it, because ServerRays is false in GlobalConfigs. That is fine for a rifle
	you can see down the sights of; for a melee attack whose entire balance is
	its reach, it means the reach is enforced on the attacker's machine.

	Instead the server sweeps the real bayonet part, which is welded to the
	character and therefore already in a position the server owns. There is no
	claimed position here, so there is nothing to validate and nothing to spoof.

	--------------------------------------------------------------------------
	THIS MODULE MUST NEVER THROW AT REQUIRE TIME
	--------------------------------------------------------------------------

	BulletModule requires every module in BulletTypes at load. If this one
	errors, that require fails, the gun handler's `bulletTypes` is never built,
	and -- worse -- the handler's setup loop

		for i,mode in pairs(modeStuff) do
			local bulletType = bulletTypes[config[i].BulletType]
			if not(bulletType) then return end

	does `return` at SCRIPT scope. It exits before UIS.InputBegan is connected,
	so EVERY weapon in the place silently stops responding to the mouse.

	So: no unbounded waits, no assumptions, nothing outside a pcall that could
	fail. A broken bayonet must cost you the bayonet and nothing else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bayonet = {}

-- Bounded, because an unbounded WaitForChild here would hang the require and
-- take the handler down with it -- see the note above.
local WAIT = 10

local package = ReplicatedStorage:WaitForChild("TREKBayonet", WAIT)
local Config = nil

if package then
	local configModule = package:WaitForChild("BayonetConfig", WAIT)
	if configModule then
		local ok, result = pcall(require, configModule)
		Config = ok and result or nil
		if not ok then
			warn("[TREKBayonet] BayonetConfig failed to load: " .. tostring(result))
		end
	end
else
	warn("[TREKBayonet] ReplicatedStorage.TREKBayonet is missing -- the bayonet fire mode "
		.. "will swing but do nothing. Is the package installed?")
end

--[[
	The remote is created at runtime by BayonetService, so it may not exist yet
	when the handler builds its bullet objects on spawn. Resolved lazily on the
	first swing rather than here, and cached once found.
]]
local stabRemote: RemoteEvent? = nil

local function resolveRemote(): RemoteEvent?
	if stabRemote then
		return stabRemote
	end
	if not package then
		return nil
	end

	local found = package:FindFirstChild("BayonetStab")
	if found and found:IsA("RemoteEvent") then
		stabRemote = found
	end

	return stabRemote
end

--[[
	bulletData carries Config, ModeStuff, Character, Player, Mode, Tool and
	DamageFunction. This type uses none of them at fire time -- the server reads
	everything it needs from the attacker -- but Character is kept for the sprint
	flag, which lives on the character rather than the player.
]]
function bayonet.new(data: any)
	local object = {}

	--[[
		Announced unconditionally, like the service's ready line, and for the
		same reason: if this never prints, this bullet type was never chosen for
		that mode, and nothing in the weapon config will show you why. Working
		that out from symptoms alone took most of an evening.

		One line per bayonet mode per spawn, not per swing -- the handler builds
		one of these per mode when it loads.
	]]
	print(string.format(
		"[TREKBayonet] bullet type constructed for mode %s on %s",
		tostring(data and data.Mode), tostring(data and data.Tool and data.Tool.Name)
	))

	function object.fire(barrel: any, _spread: any)
		-- Per swing, so it is behind Debug. Proves handleRays reached THIS type
		-- rather than Hitscan, and names the barrel GFX will fire from -- which
		-- is how a missing 2Barrel shows up, as the rifle's muzzle flashing on
		-- a melee swing.
		if Config and Config.Debug then
			print(string.format(
				"[TREKBayonet] swing -- barrel %s",
				tostring(barrel and barrel.Name)
			))
		end

		local remote = resolveRemote()

		if not remote then
			warn("[TREKBayonet] BayonetStab remote not found -- the ServerScriptService "
				.. "half of the package is missing, or BayonetService errored before "
				.. "creating it. The swing will animate and do nothing.")
			return
		end

		-- No arguments, and none are needed: the hitbox is the bayonet itself,
		-- welded to the character, so the server can see exactly where it is.
		remote:FireServer()

		--[[
			Put sprint back.

			shoot() clears SprintEnabled a few lines before it calls us:

				if controls.sprinting.Value then plrconfig.SprintEnabled.Value = false end

			which is correct for firing a rifle and wrong for a bayonet charge.
			Restoring it here keeps the charge without touching the gun handler,
			and only while the player is genuinely still sprinting -- checking
			`sprinting` rather than forcing the flag on means letting go of the
			sprint key still stops you.
		]]
		if not Config or not Config.RestoreSprint then
			return
		end

		local character = data.Character or (data.Player and data.Player.Character)
		if not character then
			return
		end

		-- Both flags live on the character, not the player. Sprinting is the
		-- player's intent, SprintEnabled is whether the movement handler is
		-- acting on it -- shoot() clears the second and leaves the first alone,
		-- which is exactly what makes this recoverable.
		local plrconfig = character:FindFirstChild("TREK_PlrConfig")
		if not plrconfig then
			return
		end

		local sprinting = plrconfig:FindFirstChild("Sprinting")
		local enabled = plrconfig:FindFirstChild("SprintEnabled")
		if not sprinting or not enabled then
			return
		end

		if (sprinting :: BoolValue).Value then
			(enabled :: BoolValue).Value = true
		end
	end

	return object
end

return bayonet

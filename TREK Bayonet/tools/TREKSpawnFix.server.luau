--!strict
--[[
	TREK SPAWN REPAIR

	Not part of the bayonet. It lives here because this is where it got written;
	put it wherever you keep TREK fixes. Drop it in ServerScriptService.

	--------------------------------------------------------------------------
	THE BUG IT WORKS AROUND
	--------------------------------------------------------------------------

	TREKServerGeneral's chrAdded runs on CharacterAdded:

		local function chrAdded(chr, plr)
			createMotor(chr)                                    -- line 1
			chr.ChildAdded:Connect(checkForGun)                 -- line 2
			chr.ChildRemoved:Connect(...)                       -- line 3
			repeat wait() until chr:FindFirstChild('Humanoid')  -- line 5
			...

	and createMotor opens with an unguarded index:

		if chr.Humanoid.RigType == Enum.HumanoidRigType.R6 then
			M6D.Parent = chr.Torso

	The wait-for-Humanoid guard is four lines later than the code that needs it.
	When the character model replicates before its Humanoid does, chr.Humanoid
	throws and chrAdded dies on its first line. Two things then never happen:

	  * no 'toolAnim' Motor6D exists, so updateMotor's
	        if not chr.Torso:FindFirstChild('toolAnim') then return end
	    gives up silently and the weapon is never jointed to the torso;

	  * ChildAdded is never connected, so checkForGun never runs -- nothing
	    clones the ToolType handler and nothing builds TAmmo. The gun has no
	    script and no ammo.

	Hence a weapon that works most spawns and is completely inert on others.

	--------------------------------------------------------------------------
	WHAT THIS DOES
	--------------------------------------------------------------------------

	Waits properly for Humanoid and Torso, then fills in ONLY what is missing.
	On a healthy spawn every check passes and it does nothing at all -- so it is
	safe to leave in permanently, and safe even if the real cause turns out to be
	something else.

	It does not edit any TREK script.
]]

repeat
	task.wait()
until game:GetService("ReplicatedStorage"):WaitForChild("TREK_INSTALLED").Value

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local WAIT = 15

-- How long to let TREK do its own setup before checking for gaps. Long enough
-- that a healthy spawn has finished and we touch nothing.
local GRACE = 1.5

local function log(message: string)
	warn("[TREKSpawnFix] " .. message)
end

--[[
	TREK's createAmmoStore, reimplemented.

	It is a local inside TREKServerGeneral with no export, so there is no way to
	call the original. Kept deliberately identical, including the ReservedAmmo
	== 'INF' string comparison, which differs from the client's == math.huge --
	that asymmetry is TREK's and copying it is safer than correcting it.
]]
local function createAmmoStore(tool: Instance)
	local reqmod = (shared :: any).S.trekServerFuncs.checkForModule(tool)
	if not reqmod then
		return
	end

	local f = Instance.new("Folder")
	f.Name = "TAmmo"
	f.Parent = tool

	for name, config in pairs(reqmod) do
		if typeof(config) ~= "table" then
			continue
		end
		if not config["MagCapacity"] then
			continue
		end

		local w = Instance.new("Folder")
		w.Name = tostring(name)
		w.Parent = f

		local ammo = Instance.new("DoubleConstrainedValue")
		ammo.Name = "Ammo"
		ammo.MaxValue = config.MagCapacity
		ammo.MinValue = 0
		ammo.Value = config.MagCapacity
		ammo.Parent = w

		local reserved = (config.ReservedAmmo == "INF" and math.huge) or config.ReservedAmmo
		local stored = Instance.new("DoubleConstrainedValue")
		stored.Name = "Stored"
		stored.MaxValue = reserved
		stored.MinValue = 0
		stored.Value = reserved
		stored.Parent = w
	end
end

-- Fill in whatever TREK failed to set up on this weapon. Every branch is
-- guarded, so a weapon that came up correctly is left untouched.
local function repairTool(chr: Model, torso: BasePart, tool: Instance)
	if not tool:IsA("Tool") or not tool:IsDescendantOf(chr) then
		return
	end

	local reqmod = (shared :: any).S.trekServerFuncs.checkForModule(tool)
	if not reqmod then
		return -- not a TREK weapon
	end

	-- The joint that holds the weapon on the body.
	local animPart = tool:FindFirstChild("AnimPart")
	local motor = torso:FindFirstChild("toolAnim") :: Motor6D?
	if animPart and motor and motor.Part1 ~= animPart then
		motor.Part0 = torso
		motor.Part1 = animPart :: BasePart
		log(("re-jointed %s on %s"):format(tool.Name, chr.Name))
	end

	-- The client handler that makes the weapon work at all.
	if not tool:FindFirstChild(reqmod.ToolType) then
		local handlers = ServerStorage:FindFirstChild("TREKToolHandlers")
		local handler = handlers and handlers:FindFirstChild(reqmod.ToolType)
		if handler then
			handler:Clone().Parent = tool
			log(("cloned missing %s handler into %s on %s"):format(reqmod.ToolType, tool.Name, chr.Name))
		end
	end

	if not tool:FindFirstChild("TAmmo") then
		createAmmoStore(tool)
		log(("rebuilt TAmmo for %s on %s"):format(tool.Name, chr.Name))
	end
end

local function onCharacter(chr: Model)
	local humanoid = chr:WaitForChild("Humanoid", WAIT) :: Humanoid?
	if not humanoid then
		log("no Humanoid on " .. chr.Name .. " -- giving up")
		return
	end

	-- Waited for, not indexed. This is the whole point.
	local torsoName = if humanoid.RigType == Enum.HumanoidRigType.R6 then "Torso" else "UpperTorso"
	local torso = chr:WaitForChild(torsoName, WAIT) :: BasePart?
	if not torso then
		log("no " .. torsoName .. " on " .. chr.Name .. " -- giving up")
		return
	end

	-- The Motor6D TREK may have failed to create. Part1 is left nil exactly as
	-- createMotor leaves it; updateMotor (or repairTool below) fills it in when
	-- a weapon actually arrives.
	if not torso:FindFirstChild("toolAnim") then
		local m = Instance.new("Motor6D")
		m.Name = "toolAnim"
		m.Part0 = torso
		m.Parent = torso
		log("recreated the missing toolAnim Motor6D on " .. chr.Name)
	end

	local function later(child: Instance)
		task.delay(GRACE, function()
			repairTool(chr, torso :: BasePart, child)
		end)
	end

	for _, child in ipairs(chr:GetChildren()) do
		later(child)
	end
	chr.ChildAdded:Connect(later)
end

local function onPlayer(player: Player)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)

log("armed -- it will say so whenever it has to repair something")

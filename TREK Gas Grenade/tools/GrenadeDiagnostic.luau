--[[
	GrenadeDiagnostic
	Reports what the grenade tool actually is, right now.

		Press Play, equip the grenade, then paste this into the command bar
		with the SERVER context selected.

	Written because "it does not appear in my hand" has at least six distinct
	causes that look identical from the outside: TREK never found the config, the
	handler was never cloned, the rig never ran, the grip joint was never made,
	the parts are welded to the wrong thing, or it is gripped fine and simply
	sitting somewhere you cannot see. Each one needs a different fix, and
	guessing between them costs a Studio round-trip every time.

	Read-only. It changes nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TOOL_NAME = "Gas Grenade"

local function line(...)
	print("[GrenadeDiag]", ...)
end

local function yn(value): string
	return value and "yes" or "NO"
end

line("================================================")

--[[
	Refuse to run on the client.

	ServerScriptService, ServerStorage and shared.S do not replicate. Run from
	the client context and every check against them reports "NO" -- which reads
	as a catastrophically broken install and sends you hunting for files that
	are sitting exactly where they should be. Three of this script's loudest
	failure lines are unreachable from the client and cannot be made honest
	there, so the only safe thing is to stop.

	The command bar's context is a dropdown next to the input, and it does not
	always remember what you picked last time.
]]
if not game:GetService("RunService"):IsServer() then
	line("")
	line(">>> WRONG CONTEXT. This is running on the CLIENT.")
	line(">>> ServerScriptService, ServerStorage and shared.S do not replicate,")
	line(">>> so those checks would all report NO whether or not anything is wrong.")
	line(">>> Switch the command bar's context dropdown to Server and run it again.")
	line("================================================")
	return
end

-- ---------------------------------------------------------------
-- INSTALL
-- ---------------------------------------------------------------

local installed = ReplicatedStorage:FindFirstChild("TREK_INSTALLED")
line("TREK_INSTALLED present:", yn(installed), installed and ("value=" .. tostring(installed.Value)) or "")

local package = ReplicatedStorage:FindFirstChild("TREKGasGrenade")
line("ReplicatedStorage.TREKGasGrenade:", yn(package))
if package then
	line("  GasConfig:", yn(package:FindFirstChild("GasConfig")))
	line("  GasShared:", yn(package:FindFirstChild("GasShared")))
	line("  ThrowGrenade:", yn(package:FindFirstChild("ThrowGrenade")))
end

--[[
	The server half.

	Listed individually because these load as a chain -- GasRuntime requires
	GasService requires GasCloud requires GasExposure -- and one missing module
	stalls every module above it. "ServiceRunning" is the only proof that chain
	completed; everything downstream of it, including the grip that holds the
	grenade, depends on start() having been reached.
]]
--[[
	Every folder with that name, not just the first.

	FindFirstChild returns one of them and GetFullName() prints the same string
	for all of them, so a stale hand-installed folder sitting beside a
	Rojo-synced one is completely invisible from an error message -- and Roblox
	runs BOTH. The stale one errors on a module it has never heard of while the
	good one works perfectly, which reads as the package being broken.

	This is the difference between "Rojo is not serving the new files" and
	"Rojo is serving them fine, into a folder that is not the one erroring".
]]
local serverFolders = {}
for _, child in ipairs(game:GetService("ServerScriptService"):GetChildren()) do
	if child.Name == "TREKGasGrenade" then
		table.insert(serverFolders, child)
	end
end

local serverFolder = serverFolders[1]
line("ServerScriptService.TREKGasGrenade:", yn(serverFolder), "count=" .. #serverFolders)

if #serverFolders > 1 then
	line("")
	line("  >>> " .. #serverFolders .. " FOLDERS SHARE THAT NAME. Roblox runs all of them.")
	line("  >>> One is almost certainly a stale hand install; the other is Rojo's.")
	line("  >>> Contents of each, so you can tell which to delete:")

	for index, folder in ipairs(serverFolders) do
		local names = {}
		for _, child in ipairs(folder:GetChildren()) do
			table.insert(names, child.Name)
		end
		table.sort(names)
		line(string.format("  >>>   [%d] %d children: %s", index, #names, table.concat(names, ", ")))
	end

	line("  >>> Delete the one MISSING modules. Keep the complete one.")
	line("")
end

--[[
	Every server module, and a loud verdict when one is absent.

	This list has to be kept current with the project files, and it going stale
	is not a cosmetic problem: the whole value of this section is naming the one
	file that is missing. A module added to the package but not added here
	produces a diagnostic that reports all-present while the chain is broken --
	which is worse than no diagnostic, because it sends you looking elsewhere.
]]
local SERVER_MODULES = {
	"GasRuntime",
	"GasService",
	"GasCloud",
	"GasVisuals",
	"GasExposure",
	"GasNerve",
	"GasRagdoll",
}

if serverFolder then
	local missing = {}

	for _, name in ipairs(SERVER_MODULES) do
		local found = serverFolder:FindFirstChild(name)
		line("  " .. name .. ":", yn(found))
		if not found then
			table.insert(missing, name)
		end
	end

	if #missing > 0 then
		line("")
		line("  >>> INCOMPLETE INSTALL. Missing: " .. table.concat(missing, ", "))
		line("  >>> GasCloud requires GasNerve requires GasRagdoll, so one absent file")
		line("  >>> stops GasService starting -- which is what leaves the grenade")
		line("  >>> unrigged, unattached, and falling out of the world on equip.")
		line("  >>> Delete ServerScriptService.TREKGasGrenade entirely and reinstall.")
		line("")
	end
end

line(
	"GasService reached start():",
	yn(_G.__GasServiceStarted),
	_G.__GasServiceStarted and "" or "  <-- the require chain stalled, or TREK_INSTALLED never flipped"
)

local handlers = ServerStorage:FindFirstChild("TREKToolHandlers")
line("ServerStorage.TREKToolHandlers:", yn(handlers))
if handlers then
	local throwable = handlers:FindFirstChild("Throwable")
	line("  Throwable:", yn(throwable), throwable and ("class=" .. throwable.ClassName) or "")
	line("  Gun (proves this is the real TREK folder):", yn(handlers:FindFirstChild("Gun")))
end

--[[
	GunConfigs is the gate. checkForGun looks the tool up by name here, and a
	tool with no entry is ignored completely -- no handler, no ammo store.
]]
local configs = shared.S and shared.S.GunConfigs
line("shared.S.GunConfigs reachable:", yn(configs))
if configs then
	local entry = configs:FindFirstChild(TOOL_NAME, true)
	line("  " .. TOOL_NAME .. " entry:", yn(entry), entry and entry:GetFullName() or "")
	if entry then
		local ok, result = pcall(require, entry)
		line("  requires cleanly:", yn(ok), ok and ("ToolType=" .. tostring(result.ToolType)) or tostring(result))
		if ok and result[1] then
			line("  mode[1].MagCapacity:", tostring(result[1].MagCapacity))
			line("  mode[1].ReservedAmmo:", tostring(result[1].ReservedAmmo))
		end
	end
end

-- ---------------------------------------------------------------
-- THE TOOL
-- ---------------------------------------------------------------

for _, player in ipairs(Players:GetPlayers()) do
	line("------------------------------------------------")
	line("player:", player.Name)

	local character = player.Character
	if not character then
		line("  no character")
		continue
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rig = humanoid and humanoid.RigType.Name or "?"
	line("  rig:", rig)

	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	line("  torso part:", torso and torso.Name or "NONE")

	--[[
		The grenade is joined to the HAND by its own Motor6D, not to the torso by
		TREK's toolAnim. A torso joint is what made it hover beside the chest
		instead of following the arm, so toolAnim pointing at the grenade is now
		a fault rather than the goal.
	]]
	local handName = (rig == "R6") and "Right Arm" or "RightHand"
	local hand = character:FindFirstChild(handName)
	line("  hand part (" .. handName .. "):", yn(hand))

	local grip = hand and hand:FindFirstChild("GasGrenadeGrip")
	line("  GasGrenadeGrip motor:", yn(grip), grip and "" or "  <-- nothing is holding it")
	if grip and grip:IsA("Motor6D") then
		line("    Part0:", grip.Part0 and grip.Part0:GetFullName() or "nil")
		line("    Part1:", grip.Part1 and grip.Part1:GetFullName() or "nil  <-- joint points nowhere")
		line("    C0:", tostring(grip.C0))
	end

	local toolAnim = torso and torso:FindFirstChild("toolAnim")
	if toolAnim and toolAnim:IsA("Motor6D") and toolAnim.Part1 then
		local owner = toolAnim.Part1:FindFirstAncestorOfClass("Tool")
		if owner and owner.Name == TOOL_NAME then
			line("  WARNING: toolAnim is also gripping the grenade --", toolAnim.Part1:GetFullName())
			line("           two joints on one part. The grenade still has an AnimPart.")
		end
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		line("  no tool equipped -- equip the grenade and run this again")
		continue
	end

	line("  equipped tool:", tool.Name, tool.Name == TOOL_NAME and "" or "  <-- not the grenade")
	if tool.Name ~= TOOL_NAME then
		continue
	end

	line("  RequiresHandle:", tostring(tool.RequiresHandle), tool.RequiresHandle and " <-- must be false" or "")
	line("  NoHolster attribute:", tostring(tool:GetAttribute("NoHolster")))

	-- Proof TREK dispatched. No Throwable child means checkForGun never matched
	-- the config, and nothing downstream of that can possibly work.
	local handler = tool:FindFirstChild("Throwable")
	line("  Throwable handler inside tool:", yn(handler), handler and ("class=" .. handler.ClassName) or "  <-- TREK never dispatched")

	local ammo = tool:FindFirstChild("TAmmo")
	line("  TAmmo store:", yn(ammo))
	if ammo then
		local mode = ammo:FindFirstChild("1")
		if mode then
			local a, s = mode:FindFirstChild("Ammo"), mode:FindFirstChild("Stored")
			line("    Ammo:", a and tostring(a.Value) or "MISSING")
			line("    Stored:", s and tostring(s.Value) or "MISSING  <-- old ReservedAmmo bug")
		else
			line("    mode folder '1' MISSING")
		end
	end

	--[[
		There should be NO AnimPart. Its presence makes checkForGun call
		updateMotor, which joins the grenade to the torso -- and a torso-joined
		grenade hovers beside the chest rather than following the arm.
	]]
	local animAnywhere = tool:FindFirstChild("AnimPart", true)
	line("  AnimPart present:", animAnywhere and "YES  <-- should be none" or "no (correct)")
	if animAnywhere then
		line("    at:", animAnywhere:GetFullName())
	end

	local model = tool:FindFirstChild("InactiveGasGrenade")
	line("  InactiveGasGrenade model:", yn(model))

	if not model then
		continue
	end

	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	line("  mesh parts:", #parts)

	--[[
		Distance from the HAND is the number that matters now. A grenade sitting
		a couple of studs from the hand is gripped; one sitting a fixed distance
		from the torso but metres from the hand is the old torso joint, and one
		that never changes as you move is anchored.
	]]
	local handPos = hand and (hand :: BasePart).Position
	local root = model.PrimaryPart
	line("  PrimaryPart:", root and root.Name or "NONE  <-- nothing to grip")

	if root and handPos then
		line("  root distance from hand:", string.format("%.2f studs", (root.Position - handPos).Magnitude))
	end

	for _, part in ipairs(parts) do
		local weld = part:FindFirstChild("GasRigWeld")
		local target = "NONE  <-- unwelded, will fall"
		if weld and weld:IsA("WeldConstraint") then
			target = (weld.Part0 and weld.Part0:GetFullName() or "nil") .. "  ->  " .. (weld.Part1 and weld.Part1.Name or "nil")
		end

		local distance = handPos and string.format("%.1f studs from hand", (part.Position - handPos).Magnitude) or "?"

		line(string.format(
			"    %-14s anchored=%-5s transparency=%.2f  %s",
			part.Name, tostring(part.Anchored), part.Transparency, distance
		))
		line("        weld: " .. target)
	end
end

line("================================================")

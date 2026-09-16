--[[
	TREK HOLSTER

	Server Script. Put it in ServerScriptService. Standalone -- not part of the
	bayonet package, and it works on a plain TREK install with no bayonet
	anywhere. It lives here because this is where it got written.

	--------------------------------------------------------------------------
	WHAT IT DOES
	--------------------------------------------------------------------------

	When you unequip a TREK weapon it stays visible, slung on your back,
	instead of vanishing into the backpack. Equip it and the slung copy goes
	away.

	TREK has no holster support of its own: the only mention of "holstering" in
	the whole source is a comment about TurnToTarget. On unequip,
	TREKServerGeneral clears chr.Torso.toolAnim.Part1 and the Tool moves to the
	Backpack, where nothing renders it.

	--------------------------------------------------------------------------
	WHY A COPY RATHER THAN THE TOOL ITSELF
	--------------------------------------------------------------------------

	The obvious approach is to keep the real Tool parented to the character and
	just re-weld it. Do not: TREK decides a weapon is equipped by finding a Tool
	inside the character. trekServerFuncs.returnTool, the gun handler, the
	bayonet service and the damage path all use that test. A Tool left in the
	character to look pretty is a Tool the whole system thinks you are holding.

	So this clones the weapon's geometry into a plain Model. A Model is not a
	Tool, nothing mistakes it for one, and it can be destroyed the moment you
	equip again.

	Scripts are deliberately not copied -- a second Gun handler running from a
	decorative model is exactly the duplicate-handler problem that makes sprint
	stop working.
]]

local Players = game:GetService("Players")

--[[
	Where the weapon sits when slung, relative to the Torso.

	THE AXES, in the torso's own frame:

		+X  the character's right          +Y  up          +Z  BEHIND them

	(Roblox faces -Z, so +Z is the back. That is the one that catches people.)

	The gun starts out aligned with the torso, barrel forward. Each preset below
	turns it from there:

		Angles(0, 90deg, 0)   lays the barrel across the back, left to right
		Angles(0, 0, R)       then tilts it within the plane of the back

	The tilt is written BEFORE the yaw in the multiplication, which is what makes
	it happen in the torso's frame rather than the gun's -- otherwise it rolls
	the rifle about its own barrel and nothing appears to move.

	Tuning is live: edit, save, unequip again. No restart.
]]
--[[
	TUNE IT HERE.

	Rojo pushes edits live: change a number, save, unequip the weapon again and
	look. No restart, no command bar, no separate tool.

	Every unequip prints the resulting position and rotation in exactly these
	units, so you can read where it landed and nudge from there.

	Set STYLE to nil to use TUNING below instead of one of the named presets.
]]
local STYLE = nil

local TUNING = {
	X = 0.95,        -- + is their right
	Y = 0.1,         -- + is up
	Z = 0.5,         -- + is BEHIND them
	LEAN = 0,      -- tilts it around the body, in the torso's frame
	PITCH = 90,      -- 90 stands the barrel up, -90 points it down
	YAW = 0,         -- 90 lays the barrel across the back
	ROLL = 180,      -- spins the gun about its own barrel
}

local STYLES = {
	--[[
		Slung across the body: muzzle up past the RIGHT shoulder, stock down at
		the LEFT hip, so the weapon lies diagonally over the back the way it does
		when the sling runs across the torso and under the far arm.

		The lean is what makes it cross rather than hang down one side. Checked
		against the transform: the muzzle sits 2.3 right and 2.6 up, the stock
		1.1 LEFT and 2.4 down -- opposite sides of the spine, which is the test
		for whether it crosses at all.

		Raise the lean toward -55 to lay it flatter across the back; drop it
		toward -12 and it stands up vertically on the right side instead.
	]]
	CrossBody = CFrame.new(0.6, 0.1, 0.6)
		* CFrame.Angles(0, 0, math.rad(-35))
		* CFrame.Angles(math.rad(90), 0, 0)
		* CFrame.Angles(0, 0, math.rad(-90)),

	-- Mirrored: muzzle past the left shoulder, stock at the right hip.
	CrossBodyLeft = CFrame.new(-0.6, 0.1, 0.6)
		* CFrame.Angles(0, 0, math.rad(35))
		* CFrame.Angles(math.rad(90), 0, 0)
		* CFrame.Angles(0, 0, math.rad(90)),

	--[[
		A real two-point sling carry: rifle vertical down one side, muzzle up
		past the shoulder, stock down by the hip, flat of the receiver facing
		away from the body.

		Built in three turns rather than one set of angles, because each one is
		separately adjustable:

			Angles(0, 0, LEAN)     leans it in the torso's frame -- positive
			                       swings the muzzle OUTBOARD and tucks the
			                       stock in against the hip
			Angles(90deg, 0, 0)    stands the rifle up, barrel skyward
			Angles(0, 0, 90deg)    rolls it so the receiver's flat faces out,
			                       which is what you see side-on

		Checked against the transform, not by eye: the muzzle lands 3.0 studs up
		and 1.6 out, the stock 2.8 down and 0.3 out.
	]]
	SideSling = CFrame.new(-0.95, 0.1, 0.5)
		* CFrame.Angles(0, 0, math.rad(12))
		* CFrame.Angles(math.rad(90), 0, 0)
		* CFrame.Angles(0, 0, math.rad(90)),

	-- The same carry on the right hip. Mirrored in X and in the lean.
	SideSlingRight = CFrame.new(0.95, 0.1, 0.5)
		* CFrame.Angles(0, 0, math.rad(-12))
		* CFrame.Angles(math.rad(90), 0, 0)
		* CFrame.Angles(0, 0, math.rad(-90)),

	-- Horizontal across the lower back. The first thing this shipped with.
	AcrossBack = CFrame.new(0, -0.35, 0.85)
		* CFrame.Angles(0, math.rad(90), math.rad(15)),

	-- Muzzle up past the right shoulder, stock down by the left hip.
	OverShoulder = CFrame.new(0, 0.15, 0.9)
		* CFrame.Angles(0, 0, math.rad(-35))
		* CFrame.Angles(0, math.rad(90), 0),

	-- The same idea, mirrored, for a left-shoulder sling.
	OverShoulderLeft = CFrame.new(0, 0.15, 0.9)
		* CFrame.Angles(0, 0, math.rad(35))
		* CFrame.Angles(0, math.rad(90), 0),

	-- Steeper, closer to vertical along the spine.
	Upright = CFrame.new(0, 0.1, 0.9)
		* CFrame.Angles(0, 0, math.rad(-70))
		* CFrame.Angles(0, math.rad(90), 0),
}

local HOLSTER_OFFSET = (STYLE and STYLES[STYLE])
	or CFrame.new(TUNING.X, TUNING.Y, TUNING.Z)
		* CFrame.Angles(0, 0, math.rad(TUNING.LEAN))
		* CFrame.Angles(math.rad(TUNING.PITCH), math.rad(TUNING.YAW), math.rad(TUNING.ROLL))

-- The part TREK joins a weapon to the body by. A Tool without one is not a
-- TREK weapon and is left alone.
local WEAPON_ROOT = "AnimPart"

local HOLSTER_NAME = "HolsteredWeapon"

-- Report every decision. Leave on until it looks right on someone's back --
-- a holster that silently does nothing and a holster placed inside the torso
-- look identical from the outside.
local DEBUG = true

-- R15 keeps the torso under a different name.
local function torsoOf(character: Model): BasePart?
	local part = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	return (part and part:IsA("BasePart")) and part or nil
end

local function clearHolster(character: Model)
	local existing = character:FindFirstChild(HOLSTER_NAME)
	if existing then
		existing:Destroy()
	end
end

--[[
	Build the slung copy.

	The weapon's own Motor6Ds all hang off AnimPart and carry the C0/C1 that
	hold the gun together, so the clone keeps its shape for free -- moving
	AnimPart moves everything joined to it. Only AnimPart needs welding to the
	body.
]]
local function showHolster(character: Model, tool: Tool)
	local torso = torsoOf(character)
	if not torso then
		if DEBUG then
			print("[TREKHolster] " .. character.Name .. " has no Torso or UpperTorso")
		end
		return
	end

	local source = tool:FindFirstChild(WEAPON_ROOT)
	if not source or not source:IsA("BasePart") then
		if DEBUG then
			print(string.format(
				"[TREKHolster] %s has no %s part, so it is not a TREK weapon -- skipped",
				tool.Name, WEAPON_ROOT
			))
		end
		return
	end

	clearHolster(character)

	--[[
		Clone the WHOLE Tool, then lift the geometry out of the copy.

		Cloning each child separately -- AnimPart, then Weapon -- looks
		equivalent and is not. Every Motor6D inside Weapon has Part0 = AnimPart,
		and a separate clone leaves those joints pointing at the ORIGINAL
		AnimPart, which by then is sitting in the backpack. The result is one
		welded AnimPart on your back and sixty-nine parts joined to a weapon
		that is nowhere: a holster that reports success and shows nothing.

		Cloning the parent first keeps every internal reference inside the copy,
		and reparenting afterwards does not disturb them.
	]]
	local toolCopy = tool:Clone()

	local holster = Instance.new("Model")
	holster.Name = HOLSTER_NAME

	for _, child in ipairs(toolCopy:GetChildren()) do
		-- Geometry only. A cloned LocalScript would be a second gun handler,
		-- and cloned sounds would fire alongside the real weapon's.
		if child:IsA("BasePart") or child:IsA("Model") then
			child.Parent = holster
		end
	end

	toolCopy:Destroy()

	local root = holster:FindFirstChild(WEAPON_ROOT)
	if not root or not root:IsA("BasePart") then
		holster:Destroy()
		return
	end

	holster.PrimaryPart = root

	for _, d in ipairs(holster:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			d.Transparency = math.min(d.Transparency, 1)
		end
	end

	--[[
		Parent, THEN pivot, THEN weld. That order matters.

		A WeldConstraint captures the relative transform of its two parts when
		it becomes active. Building it while the model is still parented to nil
		-- with Part1 already in the workspace -- means it can latch onto a
		position the model never actually occupied, and the gun ends up
		somewhere arbitrary or not at all.
	]]
	holster.Parent = character
	holster:PivotTo(torso.CFrame * HOLSTER_OFFSET)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = torso
	weld.Parent = root

	if DEBUG then
		local parts = 0
		for _, d in ipairs(holster:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end

		--[[
			The bounding box is the check that matters, not the part count.

			A count only says instances exist. If the joints inside the copy
			point at the original weapon, the parts scatter and the box comes
			out enormous -- which is exactly how the separate-clone bug looked
			from the outside: "70 parts" and nothing visible.

			A KR-61 should measure roughly 4 x 1 x 1 studs. Anything in the
			hundreds means the copy is not assembled.
		]]
		local _, size = holster:GetBoundingBox()
		print(string.format(
			"[TREKHolster] slung %s on %s (%s) -- %d parts, bounding box %.1f x %.1f x %.1f",
			tool.Name, character.Name, STYLE or "custom tuning", parts, size.X, size.Y, size.Z
		))

		--[[
			The numbers to edit, printed in the units you would edit them in.

			Decomposed from where the gun actually ended up rather than echoed
			back from the constant, so it stays honest if anything moves it
			afterwards. ToOrientation folds the lean into the three angles, so
			what prints is the COMBINED rotation, not the four separate turns
			the preset is written as.
		]]
		local current = torso.CFrame:ToObjectSpace(root.CFrame)
		local rx, ry, rz = current:ToOrientation()
		local muzzle = current * CFrame.new(0, 0, -3)
		local stock = current * CFrame.new(0, 0, 3)

		print(string.format(
			"              position %.2f, %.2f, %.2f   rotation %.0f, %.0f, %.0f degrees",
			current.X, current.Y, current.Z,
			math.deg(rx), math.deg(ry), math.deg(rz)
		))
		print(string.format(
			"              muzzle %.1f, %.1f, %.1f   stock %.1f, %.1f, %.1f   (+X right, +Y up, +Z behind)",
			muzzle.X, muzzle.Y, muzzle.Z, stock.X, stock.Y, stock.Z
		))
	end
end

--[[
	A Tool moving out of the character is an unequip; moving in is an equip.

	Both are watched rather than the Tool's own Equipped/Unequipped events,
	because those fire on the client that owns the tool and this needs to be the
	server's view -- everyone should see the sling, not just its owner.
]]
local function watch(player: Player, character: Model)
	clearHolster(character)

	local function onEquip(child: Instance)
		if child:IsA("Tool") then
			clearHolster(character)
		end
	end

	local function onUnequip(child: Instance)
		if not child:IsA("Tool") then
			return
		end

		-- Dropped tools and tools destroyed on death should not leave a ghost
		-- slung on the back, so only a tool that actually went to the backpack
		-- counts as holstered.
		task.defer(function()
			local wentToBackpack = child.Parent == player.Backpack

			if DEBUG then
				print(string.format(
					"[TREKHolster] %s left %s -- now in %s%s",
					child.Name, character.Name,
					child.Parent and child.Parent:GetFullName() or "nil",
					wentToBackpack and "" or "  (not the backpack, so not holstered)"
				))
			end

			if wentToBackpack and character.Parent then
				showHolster(character, child)
			end
		end)
	end

	character.ChildAdded:Connect(onEquip)
	character.ChildRemoved:Connect(onUnequip)

	-- Spawning with a weapon already in the backpack should show it slung.
	task.defer(function()
		if not character:FindFirstChildOfClass("Tool") then
			for _, item in ipairs(player.Backpack:GetChildren()) do
				if item:IsA("Tool") and item:FindFirstChild(WEAPON_ROOT) then
					showHolster(character, item)
					break
				end
			end
		end
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			clearHolster(character)
		end)
	end
end

local function onPlayer(player: Player)
	if player.Character then
		watch(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watch(player, character)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)

print("[TREKHolster] ready -- unequipped TREK weapons stay slung")

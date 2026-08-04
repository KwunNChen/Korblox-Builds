--[[
	AnimationRig
	A Studio-only helper for whoever is making the animations.

	It bolts the real skis and poles onto a plain R6 dummy, so they can be seen
	while animating rather than imagined. Animating a ski stance blind is how you
	end up with a pose that looks right on a bare rig and puts the skis through
	the character's shins.

	This is not part of the running game. Nothing requires it, and it can be
	deleted from a live place once the animations exist.


	========================================================
	HOW TO USE IT
	========================================================

	1. Avatar tab > Rig Builder > R6 > Block Rig. A "Dummy" appears in Workspace.

	2. Paste this into the command bar and press enter:

	       require(game.ServerStorage.KorbloxSki.Tools.AnimationRig).attach(workspace.Dummy)

	   Skis and poles appear on the dummy. If the package is installed somewhere
	   other than ServerStorage, change the path to match.

	3. Select the Dummy, open the Animation Editor, and animate normally.

	4. Publish each one, then send the asset ids back. They go into
	   SkiConfig.Animations.

	To take the gear off again:

	       require(game.ServerStorage.KorbloxSki.Tools.AnimationRig).detach(workspace.Dummy)


	========================================================
	WHAT TO ANIMATE
	========================================================

	Five slots, all LOOPING, and each replaces a built-in procedural pose. Fill
	in as many or as few as you like; anything left empty keeps the procedural
	one, so they can arrive one at a time.

	    Stance   riding normally. Weight forward, hands ahead. This is what you
	             are in most of the time, so it matters most.

	    Carve    turning. Note that the game already rolls the body and the skis
	             into the turn on its own, continuously, based on how hard you
	             are steering -- so this wants to be about the ARMS and the
	             upper body, not about leaning. Leaning is handled.

	    Tuck     folded down small for speed.

	    Brake    snowplow. The tips come together and the character sits back.

	    Air      off a jump. Hands out in front, poles up near horizontal.

	TWO THINGS ABOUT THE RIG THAT WILL SAVE YOU TIME.

	R6 has no knees and no ankles. A leg is one rigid piece from hip to sole, so
	a crouch has to come from the waist and the hips. Bending a leg is not
	available.

	And tipping a leg sideways swings the FOOT through an arc, because there is
	no ankle to absorb it. Past about 0.25 radians the boot leaves the ski
	entirely. If a pose looks good but the skis have drifted out from under the
	character, that is why.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local AnimationRig = {}

local function findGearModule()
	local ski = ServerScriptService:FindFirstChild("Ski")
	local module = ski and ski:FindFirstChild("SkiGear")

	if not module then
		error("[Ski] ServerScriptService.Ski.SkiGear not found. Install the package first -- this tool builds the same gear the game does rather than a copy, so it needs the real thing.", 0)
	end

	return require(module)
end

function AnimationRig.attach(rig: Model)
	if not rig or not rig:IsA("Model") then
		error("[Ski] pass the rig itself, e.g. attach(workspace.Dummy)", 0)
	end

	if not rig:FindFirstChild("Torso") then
		error("[Ski] " .. rig.Name .. " does not look like an R6 rig -- no Torso. Rig Builder > R6 > Block Rig.", 0)
	end

	local SkiGear = findGearModule()
	SkiGear.build(rig)
	SkiGear.setStowed(rig, false)

	print("[Ski] gear attached to " .. rig.Name .. ". Open the Animation Editor and go.")
end

function AnimationRig.detach(rig: Model)
	if not rig or not rig:IsA("Model") then
		error("[Ski] pass the rig itself, e.g. detach(workspace.Dummy)", 0)
	end

	findGearModule().destroy(rig)
	print("[Ski] gear removed from " .. rig.Name .. ".")
end

return AnimationRig

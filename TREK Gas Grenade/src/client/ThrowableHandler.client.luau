--[[
	Throwable -- TREK tool handler

	TREK clones this LocalScript into the tool itself. `checkForGun` reads
	ToolType off the config in GunConfigs, finds the matching child of
	ServerStorage.TREKToolHandlers, and parents a copy inside the Tool. Only this
	script is cloned -- not its siblings -- so anything it needs comes from
	ReplicatedStorage or is written inline.

	It decides nothing. Press and release are reported to the server, which owns
	the fuse clock and every question about damage. The arc drawn here is a
	prediction using the same numbers the server throws with; if the two ever
	disagree, the server is right and this is a cosmetic bug.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--[[
	Bounded, and loud when it fails.

	An unbounded WaitForChild inside a require chain does not fail -- it hangs
	the module forever, and every module waiting on THIS one hangs with it.
	Adding one new file to this chain once killed the entire service that way:
	the grenade quietly stopped being held, with nothing in the output to say
	why, because nothing had errored. It was still waiting.

	Ten seconds is far longer than replication or install ever needs and far
	shorter than a playtest, so a missing file announces itself instead.
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
local throwRemote = expect(package, "ThrowGrenade") :: RemoteEvent

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local tool = script.Parent :: Tool

local equipped = false
local cooking = false
local cookStart = 0

-- Number of sample points in the predicted arc. Twenty is enough to read as a
-- curve at grenade ranges without the dots visibly separating near the apex.
local ARC_POINTS = 20
local ARC_STEP = 0.09

local arcFolder: Folder? = nil
local arcParts: { BasePart } = {}

--[[
	Where the player is aiming.

	mouse.Hit is used in preference to the raw camera look vector because it
	accounts for the offset between the camera and the character -- aiming at a
	doorway from behind cover otherwise throws the grenade at the wall the camera
	is looking over.
]]
local function aimDirection(origin: Vector3): Vector3
	local target = mouse.Hit and mouse.Hit.Position

	if target then
		local delta = target - origin
		if delta.Magnitude > 1e-3 then
			return delta.Unit
		end
	end

	return camera.CFrame.LookVector
end

--[[
	The same loft the server applies. Kept in sync by reading the same config,
	not by trusting these two functions to be edited together.
]]
local function launchVector(direction: Vector3): Vector3
	local axis = direction:Cross(Vector3.yAxis)

	if axis.Magnitude < 1e-3 then
		return direction * Config.ThrowPower
	end

	local lofted = CFrame.fromAxisAngle(axis.Unit, math.rad(Config.ThrowAngle)) * direction
	return lofted.Unit * Config.ThrowPower
end

local function buildArc()
	if arcFolder then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "GasThrowArc"

	for index = 1, ARC_POINTS do
		local dot = Instance.new("Part")
		dot.Name = "ArcPoint"
		dot.Shape = Enum.PartType.Ball
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.Material = Enum.Material.Neon
		dot.Color = Config.Visual.ArcColour
		-- Dots shrink along the arc so the far end reads as further away rather
		-- than as a wall of identical spheres.
		local taper = 1 - (index / ARC_POINTS) * 0.6
		dot.Size = Vector3.one * (0.35 * taper)
		dot.Transparency = 0.35
		dot.Parent = folder
		table.insert(arcParts, dot)
	end

	--[[
		Parented to the camera, which keeps the arc strictly local. A preview
		parented into workspace replicates, and every other player would watch a
		line of glowing dots tell them exactly where the grenade is about to go.
	]]
	folder.Parent = camera
	arcFolder = folder
end

local function hideArc()
	for _, dot in ipairs(arcParts) do
		dot.Transparency = 1
	end
end

local function destroyArc()
	if arcFolder then
		arcFolder:Destroy()
		arcFolder = nil
		table.clear(arcParts)
	end
end

--[[
	Plot the arc by stepping the same ballistic the physics engine will run.

	Stops early on the first sample that ends up inside geometry, so the preview
	terminates at the wall rather than drawing through it.
]]
local function updateArc()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		hideArc()
		return
	end

	local origin = (root :: BasePart).Position + Vector3.new(0, 1, 0)
	local direction = aimDirection(origin)
	local velocity = launchVector(direction) + (root :: BasePart).AssemblyLinearVelocity
	local gravity = Vector3.new(0, -workspace.Gravity, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		character :: Instance,
		camera,
		workspace:FindFirstChild("IgnoreList") :: Instance,
	}

	local previous = origin + direction * 2
	local stopped = false

	for index, dot in ipairs(arcParts) do
		if stopped then
			dot.Transparency = 1
			continue
		end

		local t = index * ARC_STEP
		local point = origin + direction * 2 + velocity * t + gravity * 0.5 * t * t

		local hit = workspace:Raycast(previous, point - previous, params)
		if hit then
			dot.Position = hit.Position
			dot.Transparency = 0.35
			stopped = true
		else
			dot.Position = point
			dot.Transparency = 0.35
		end

		previous = point
	end
end

--[[
	Cook feedback.

	The arc reddens as the fuse burns down. With CookKillsYou on, that colour is
	the only warning a player gets before it goes off in their hand, so it ramps
	across the whole fuse rather than flashing at the end.
]]
local function updateCookTint()
	local progress = math.clamp((os.clock() - cookStart) / Config.FuseTime, 0, 1)
	local tint = Config.Visual.ArcColour:Lerp(Config.Visual.ArcWarnColour, progress)

	for _, dot in ipairs(arcParts) do
		dot.Color = tint
	end
end

local function startCook()
	if cooking or not equipped then
		return
	end

	cooking = true
	cookStart = os.clock()
	buildArc()
	throwRemote:FireServer("cook")
end

local throwTrack: AnimationTrack? = nil
local throwTrackFailed = false

-- True from the moment a throw is released until its animation has finished, so
-- the tool being destroyed underneath it does not cut the animation short.
local throwing = false

--[[
	Load the throw animation, once, lazily.

	Lazily because the Animator is not guaranteed to exist the moment this
	handler is cloned into the tool, and once because LoadAnimation on every
	throw leaks a track per press.

	Built from an id rather than an Animation instance in an Animations folder,
	which is TREK's convention -- so nothing raises its priority for us and it is
	set here explicitly. See the note in GasConfig.
]]
local function loadThrowTrack(): AnimationTrack?
	if throwTrack or throwTrackFailed then
		return throwTrack
	end

	local id = Config.Animation and Config.Animation.Throw
	if not id or id == "" then
		throwTrackFailed = true
		return nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = id

	--[[
		Fetch the asset before anyone needs it.

		LoadAnimation hands back a track straight away, but the animation data
		behind it is still being downloaded. Playing that track does nothing
		visible until the download lands -- so a throw animation loaded at the
		moment of the throw fires late, after the grenade has already left, which
		looks like the animation is reacting to the throw rather than causing it.

		PreloadAsync yields until it is resident, which is why this whole
		function is called ahead of time rather than on release.
	]]
	pcall(function()
		ContentProvider:PreloadAsync({ animation })
	end)

	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)

	if not ok or not result then
		--[[
			The usual cause is ownership: an animation has to belong to the place
			owner or its group to load at all. Flagged once rather than every
			throw, and the grenade still works without it.
		]]
		throwTrackFailed = true
		warn(("[GasGrenade] could not load throw animation %s -- %s"):format(tostring(id), tostring(result)))
		return nil
	end

	local track = result :: AnimationTrack
	track.Priority = Config.Animation.Priority
	throwTrack = track

	return track
end

local function stopThrowTrack()
	if throwTrack and throwTrack.IsPlaying then
		throwTrack:Stop(Config.Animation.FadeTime)
	end
end

local function releaseThrow()
	if not cooking then
		return
	end

	cooking = false
	hideArc()

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	--[[
		Aim is sampled at release, not when the hand opens.

		The grenade goes where you were pointing when you let go. Sampling again
		after the wind-up would mean turning during the animation silently
		re-aims the throw, which is not something the player asked for.
	]]
	local origin = (root :: BasePart).Position + Vector3.new(0, 1, 0)
	local direction = aimDirection(origin)

	--[[
		Guarded because a Speed of zero would freeze the animation on its first
		frame AND make the release delay infinite, so the grenade would never
		leave at all.
	]]
	local speed = math.max(Config.Animation.Speed or 1, 0.01)

	local track = loadThrowTrack()
	if track then
		throwing = true
		track:Play(Config.Animation.FadeTime, 1, speed)

		--[[
			Cleared when the track actually ends rather than on a timer, so it
			does not matter how long the animation turns out to be.

			Once is enough: the connection releases itself, and a fresh throw
			just sets the flag again.
		]]
		track.Stopped:Once(function()
			throwing = false
		end)
	end

	-- Scaled by playback rate so the release tracks the same FRAME of the
	-- animation rather than the same wall-clock delay.
	local wait = (track and (Config.Animation.ReleaseDelay / speed)) or 0

	if wait <= 0 then
		throwRemote:FireServer("throw", direction)
		return
	end

	task.delay(wait, function()
		--[[
			Re-check before firing. A quarter of a second is long enough to die
			in, and a corpse should not complete its throw.

			Not gated on `equipped`: the server's fuse is already burning, so
			swallowing the throw here would leave the player holding a live
			grenade with no way to get rid of it.
		]]
		local liveCharacter = player.Character
		local humanoid = liveCharacter and liveCharacter:FindFirstChildOfClass("Humanoid")

		if not humanoid or humanoid.Health <= 0 then
			return
		end

		throwRemote:FireServer("throw", direction)
	end)
end

local function onEquip()
	equipped = true

	--[[
		Warm the animation on equip as well as at startup.

		Startup can be too early -- the Animator may not exist yet when TREK
		clones this handler into the tool -- and loadThrowTrack returns nil
		without latching in that case, so this is the retry. By the time anyone
		can throw, the track is resident and plays on the frame it is asked to.
	]]
	task.spawn(loadThrowTrack)
end

--[[
	Unequipping does not cancel a cook, and must not.

	The fuse is burning on the server from the moment the player pressed. Letting
	them put the grenade away to stop it would make cooking free, so the local
	state is torn down here and the server's watchdog is left to do what it was
	always going to do.
]]
local function onUnequip()
	equipped = false
	cooking = false
	hideArc()

	--[[
		A throw in flight is allowed to finish.

		Spending your last grenade destroys the Tool, and destroying a Tool fires
		Unequipped -- so the unconditional Stop() here was cutting the throw
		animation off a fraction of a second after it started, every single time.
		The track lives on the character's Animator rather than the tool, so it
		plays out perfectly well once nothing stops it.

		Switching weapons mid-cook still stops it, which is what should happen.
	]]
	if not throwing then
		stopThrowTrack()
	end
end

-- Fetch the throw animation now, not on the first throw. PreloadAsync yields,
-- so it runs off the main thread.
task.spawn(loadThrowTrack)

tool.Equipped:Connect(onEquip)
tool.Unequipped:Connect(onUnequip)

--[[
	Reload, through TREK's own remote.

	The server handler for this -- handleReload in TREKServerGeneral -- is fully
	generic: it resolves the tool's config, reads TAmmo, and moves rounds from
	Stored into Ammo. It never asks whether the tool is a gun. So firing the
	remote TREK already owns is all a throwable has to do to get reloading, and
	reimplementing it here would mean a second code path that could disagree
	with the guns about how reserve ammo works.

	Guarded because shared.S is TREK's global and this handler has to survive a
	place where the core has not finished loading.
]]
local function requestReload()
	local trek = shared.S
	if typeof(trek) ~= "table" then
		return
	end

	local remotes = trek.TREK_Remotes
	local reload = remotes and remotes:FindFirstChild("Reload")
	if reload then
		reload:FireServer(1)
	end
end

local function reloadKey(): Enum.KeyCode
	local trek = shared.S
	local global = typeof(trek) == "table" and trek.globalConfig or nil

	return (global and global.ReloadKey) or Enum.KeyCode.R
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not equipped then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		startCook()
	elseif input.KeyCode == reloadKey() then
		--[[
			Deliberately allowed mid-cook. The fuse is already burning on the
			server and reloading does not touch it, so this tops up the reserve
			without cancelling the throw -- which is the same thing pressing R
			does on a gun mid-burst.
		]]
		requestReload()
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	-- Deliberately not gated on `processed`: a release swallowed by the UI would
	-- otherwise leave the player holding a live grenade with no way to let go.
	releaseThrow()
end)

RunService.RenderStepped:Connect(function()
	if not equipped or not cooking then
		return
	end

	updateArc()
	updateCookTint()
end)

tool.AncestryChanged:Connect(function()
	if not tool:IsDescendantOf(game) then
		destroyArc()
	end
end)

--[[
	Losing the arm that holds the grenade ends the throw, matching what the Gun
	handler does when a weapon's carrying arm is removed.
]]
local character = player.Character
if character then
	character.ChildRemoved:Connect(function(child)
		if child.Name == "Right Arm" or child.Name == "RightHand" then
			onUnequip()
		end
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			onUnequip()
			destroyArc()
		end)
	end
end

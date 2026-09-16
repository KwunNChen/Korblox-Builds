--[[
	PARKOUR RIG -- a dummy with the real obstacles next to it, for animating.

	NOT a lune script and not game code. Paste the require line into the Studio
	COMMAND BAR.

	--------------------------------------------------------------------------
	USING IT
	--------------------------------------------------------------------------

	1. Avatar tab > Rig Builder > R6 > Block Rig. A "Dummy" appears in Workspace.
	2. Command bar:

	       require(game.ServerStorage.TREKParkour.Tools.ParkourRig).attach(workspace.Dummy)

	3. Four blocks and two markers appear beside it. Select the Dummy, open the
	   Animation Editor, and animate against them.
	4. Publish each animation, then put the ids into ParkourConfig.Animations.

	       require(game.ServerStorage.TREKParkour.Tools.ParkourRig).detach(workspace.Dummy)

	--------------------------------------------------------------------------
	WHY THE BLOCKS ARE THERE
	--------------------------------------------------------------------------

	They are built from the live ParkourConfig, not from numbers typed in here.
	If someone retunes a threshold, re-running attach moves the blocks with it,
	so you are always posing against the heights the game actually uses. A
	pull-up animated for a five-stud ledge has the hands a stud inside a
	four-stud one, and that is the sort of thing nobody notices until it ships.

	    VaultBar      the tallest thing a vault will take
	    MantleLow     the lowest lip a mantle will grab
	    MantleHigh    the tallest thing a mantle will climb
	    TooHigh       just past the limit -- where the feature stops

	    GrabMarker    where the root is at the hang, mid-mantle
	    LandMarker    where the root ends up standing on top

	The two markers matter most. The game drives the root through those exact
	points, so a hand that does not reach GrabMarker will visibly miss the ledge.

	--------------------------------------------------------------------------
	FOR WHOEVER IS ANIMATING
	--------------------------------------------------------------------------

	AUTHOR FOR R6. An R6 sequence loaded onto an R15 rig gives you zero tracks
	and an empty timeline, with no error to tell you why.

	R6 HAS NO KNEES AND NO ANKLES. A pull-up has to come from the waist, the
	hips and the shoulders. You have six joints: RootJoint, Neck, both
	Shoulders, both Hips.

	DO NOT ANIMATE THE ROOT. The game writes HumanoidRootPart.CFrame every frame
	during a move. Any root motion baked into your track fights that write and
	reads as jitter. Animate the limbs against a stationary root -- the game
	moves the body.

	The three slots, and roughly what each has to cover:

	    Vault         0.45s. A hand plant on the lip, legs swinging through.
	    MantleCatch   the grab. Plays as the hands reach the lip.
	    MantlePull    the haul up, the knee over, and standing.

	Publish under the account that owns the game, or a group it belongs to. An
	animation the place cannot read loads as zero tracks and plays nothing, with
	no error -- which looks exactly like a broken feature.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParkourRig = {}

local FOLDER_NAME = "ParkourRigObstacles"

local function shared()
	local package = ReplicatedStorage:FindFirstChild("TREKParkour")
	local module = package and package:FindFirstChild("ParkourShared")
	if not module then
		error("[ParkourRig] no ReplicatedStorage.TREKParkour.ParkourShared -- is the package installed?", 0)
	end
	return require(module) :: any
end

local function config()
	local package = ReplicatedStorage:FindFirstChild("TREKParkour")
	local module = package and package:FindFirstChild("ParkourConfig")
	if not module then
		error(
			"[ParkourRig] no ReplicatedStorage.TREKParkour.ParkourConfig -- the package is not installed, "
				.. "or you are running this on the client. Use the Server command bar.",
			0
		)
	end
	return require(module) :: any
end

local function check(rig: Instance?): Model
	if typeof(rig) ~= "Instance" or not rig:IsA("Model") then
		error("[ParkourRig] pass the rig itself, e.g. attach(workspace.Dummy)", 0)
	end

	local model = rig :: Model
	if not model:FindFirstChild("Torso") then
		error("[ParkourRig] that does not look like an R6 rig -- no Torso. Rig Builder > R6 > Block Rig.", 0)
	end

	if not model.PrimaryPart and not model:FindFirstChild("HumanoidRootPart") then
		error("[ParkourRig] the rig has no HumanoidRootPart to measure from.", 0)
	end

	return model
end

local function label(parent: BasePart, text: string, above: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(180, 30)
	billboard.StudsOffset = Vector3.new(0, above, 0)
	billboard.AlwaysOnTop = true

	local gui = Instance.new("TextLabel")
	gui.Size = UDim2.fromScale(1, 1)
	gui.BackgroundTransparency = 1
	gui.Font = Enum.Font.Code
	gui.TextScaled = true
	gui.TextColor3 = Color3.new(1, 1, 1)
	gui.TextStrokeTransparency = 0.4
	gui.Text = text
	gui.Parent = billboard

	billboard.Parent = parent
end

local function block(folder: Folder, name: string, text: string, height: number, soles: number, origin: CFrame, side: number)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = Vector3.new(6, math.max(height, 0.2), 2)
	part.Color = Color3.fromRGB(125, 125, 135)
	part.Material = Enum.Material.SmoothPlastic

	local spot = origin * CFrame.new(side, 0, -10)
	part.Position = Vector3.new(spot.Position.X, soles + height / 2, spot.Position.Z)
	part.Parent = folder

	label(part, text, height / 2 + 1)
	return part
end

local function marker(folder: Folder, name: string, position: Vector3, colour: Color3, text: string)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.8, 0.8, 0.8)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.25
	part.Color = colour
	part.Position = position
	part.Parent = folder

	label(part, text, 1)
end

function ParkourRig.attach(rig: Instance?)
	local model = check(rig)
	local Config = config()
	local Shared = shared()

	ParkourRig.detach(model)

	local root = (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) :: BasePart
	local soles = root.Position.Y - Config.RootToSoles
	local origin = CFrame.new(root.Position.X, soles, root.Position.Z) * (root.CFrame - root.CFrame.Position)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = model

	-- Sitting exactly on the band edges, so what you see is where the feature
	-- changes behaviour rather than a round number somebody liked.
	block(folder, "VaultBar", ("Vault max  %.1f"):format(Config.VaultMaxHeight), Config.VaultMaxHeight, soles, origin, -12)

	local mantleLow = Config.VaultMaxHeight + 0.5
	block(folder, "MantleLow", ("Mantle low  %.1f"):format(mantleLow), mantleLow, soles, origin, -4)

	local mantleHigh = block(
		folder,
		"MantleHigh",
		("Mantle max  %.1f"):format(Config.MantleMaxHeight),
		Config.MantleMaxHeight,
		soles,
		origin,
		4
	)

	local tooHigh = Config.MantleMaxHeight + 1
	block(folder, "TooHigh", ("Refused  %.1f"):format(tooHigh), tooHigh, soles, origin, 12)

	--[[
		The two points the game actually drives the root through, taken off the
		MantleHigh block. Everything the animation has to line up with is here.
	]]
	local face = mantleHigh.Position + origin.LookVector * (mantleHigh.Size.Z / 2)
	local topY = soles + Config.MantleMaxHeight

	--[[
		Both points come from ParkourShared, not from formulas repeated here.

		This tool exists to show an animator where the game actually drives the
		root. A second copy of the arithmetic defeats that the moment anyone
		retunes it -- the markers would keep pointing at the old place and the
		hands would miss the ledge, which is precisely the failure this is
		supposed to prevent.
	]]
	marker(folder, "GrabMarker", Shared.grabPoint(face, topY, origin.LookVector), Color3.fromRGB(240, 200, 80), "root at the hang")
	marker(folder, "LandMarker", Shared.landPoint(face, topY, origin.LookVector), Color3.fromRGB(80, 220, 120), "root when standing")

	print(("[ParkourRig] attached to %s -- vault to %.1f, mantle %.1f to %.1f, refused above %.1f")
		:format(model.Name, Config.VaultMaxHeight, mantleLow, Config.MantleMaxHeight, Config.MantleMaxHeight))
	print("[ParkourRig] animate the limbs only -- the game moves the root.")
end

function ParkourRig.detach(rig: Instance?)
	local model = check(rig)
	local folder = model:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
		print("[ParkourRig] detached from " .. model.Name)
	end
end

return ParkourRig

local trouble = {}

local myModel = script.Parent.Parent
local myRoot = myModel.HumanoidRootPart

local mySettings = script.Parent.Parent.Settings
local debugOption = mySettings.Debug.Value

function trouble.visualizePath(path)
	if not debugOption then return end
	local waypoints = path:GetWaypoints()
	for i,waypoint in ipairs(waypoints) do
		local p = Instance.new("Part")
		p.Size = Vector3.new(1,1,1)
		p.CanCollide = false
		p.Shape = Enum.PartType.Ball
		p.Transparency = 0.5
		p.Material = Enum.Material.Neon
		p.BrickColor = BrickColor.Random()
		p.Anchored = true
		p.Position = waypoint.Position
		p.Name = i
		p.Parent = script
	end
end

local p = Instance.new("Part")
if debugOption then
	p.Size = Vector3.new(3,3,3)
	p.CanCollide = false
	p.Shape = Enum.PartType.Ball
	p.Transparency = 0.5
	p.Material = Enum.Material.Neon
	p.BrickColor = BrickColor.new("Bright bluish green")
	p.Anchored = true
	p.Parent = script
end
function trouble.waypoint(pos)
	if not debugOption then return end
	p.Position = pos
end

function trouble.mark(pos)
	if not debugOption then return end
	local p = Instance.new("Part")
	p.Size = Vector3.new(2,2,2)
	p.CanCollide = false
	p.Shape = Enum.PartType.Ball
	p.Transparency = 0.5
	p.Material = Enum.Material.Neon
	p.BrickColor = BrickColor.new("Really red")
	p.Anchored = true
	p.Parent = script
	p.Position = pos
end

local beams = {}
function initBeams()
	for i = 1, 100 do
		local attach0 = Instance.new("Attachment")
		attach0.Parent = workspace.Terrain

		local attach1 = Instance.new("Attachment")
		attach1.Parent = workspace.Terrain

		local b = Instance.new("Beam")
		b.FaceCamera = true
		b.Color = ColorSequence.new(Color3.new(0,1,0))
		b.Parent = myModel.Beams
		b.Width0 = 0.3
		b.Width1 = 0.3
		b.Attachment0 = attach0
		b.Attachment1 = attach1
		table.insert(beams,{
			beam = b,
			a0 = attach0,
			a1 = attach1
		})
	end
end
if debugOption then
	initBeams()
end

local currentBeam = 1
function trouble.createBeam(origin,direction)

	currentBeam = currentBeam + 1
	if currentBeam > #beams then
		currentBeam = 1
	end

	beams[currentBeam].a0.WorldPosition = origin
	beams[currentBeam].a1.WorldPosition = origin+direction

	return beams[currentBeam].beam
end

function trouble.newBeam(origin,direction)
	
	
	local a0 = Instance.new("Attachment")
	a0.Parent = workspace.Terrain
	
	local a1 = Instance.new("Attachment")
	a1.Parent = workspace.Terrain

	a0.WorldPosition = origin
	a1.WorldPosition = origin+direction
	
	local beam = Instance.new("Beam")
	beam.Width0 = 0.2
	beam.Width1 = 0.2
	beam.Parent = workspace
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	
	game:GetService("Debris"):AddItem(beam,3)
end

local sb = Instance.new("SelectionBox")
if debugOption then
	sb.Parent = myModel
	sb.Color3 = Color3.new(1,0,0)
	sb.LineThickness = 0.1	
end
function trouble.selectionBox(instance)
	if not debugOption then return end
	sb.Adornee = instance
end

local lineEnd = Instance.new("Attachment")
function trouble.createLine(instance)
	if not debugOption then return end
	lineEnd.Parent = instance
end

return trouble

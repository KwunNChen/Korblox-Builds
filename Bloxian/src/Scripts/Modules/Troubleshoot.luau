local trouble = {}

local debrisService = game:GetService("Debris")

local myModel = script.Parent.Parent.Parent

local mySettings = myModel.Settings
local debugOption = mySettings.Debug.Value
local printValue = mySettings:FindFirstChild("PrintDebug")

--Tells soldiers apart in Output, they all share one name.
local tag = myModel.Name.."#"..math.random(100,999)

--Whether debug lines print. Check it before building an expensive message.
function trouble.printing()
	return printValue ~= nil and printValue.Value
end

--Prints to Output when Settings.PrintDebug is on. A line only prints when its
--message changes for that key, or again after `every` seconds if given.
local lastLines = {}
function trouble.log(key,message,every)
	if not printValue or not printValue.Value then return end

	local now = os.clock()
	local last = lastLines[key]
	if last and last.message == message and (not every or now - last.time < every) then
		return
	end
	lastLines[key] = {message = message, time = now}
	print(string.format("[%s %.1f] %s: %s",tag,now % 1000,key,message))
end

--Seconds before a crashed loop starts again.
local RESTART_DELAY = 1

--Runs a loop, and restarts it if it crashes while the soldier is still alive.
--Each different crash prints once in Output.
function trouble.guard(name,loop)
	return function()
		local lastError
		while true do
			local ok,err = xpcall(loop,debug.traceback)
			if ok then
				return
			end
			if err ~= lastError then
				lastError = err
				warn(string.format("[%s] %s loop crashed, restarting: %s",tag,name,tostring(err)))
			end

			task.wait(RESTART_DELAY)
			local human = myModel:FindFirstChildOfClass("Humanoid")
			if not myModel.Parent or not human or human.Health <= 0 then
				return
			end
		end
	end
end

local function makeBall(size,color,parent)
	local p = Instance.new("Part")
	p.Size = Vector3.new(size,size,size)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Ball
	p.Transparency = 0.5
	p.Material = Enum.Material.Neon
	p.BrickColor = color
	p.Anchored = true
	p.Parent = parent
	return p
end

local pathMarkers = {}
function trouble.visualizePath(waypoints)
	if not debugOption then return end

	for _,marker in ipairs(pathMarkers) do
		marker:Destroy()
	end
	table.clear(pathMarkers)

	for i,waypoint in ipairs(waypoints) do
		local p = makeBall(1,BrickColor.Random(),script)
		p.Position = waypoint.Position
		p.Name = tostring(i)
		pathMarkers[i] = p
	end
end

local waypointMarker
function trouble.waypoint(pos)
	if not debugOption then return end
	waypointMarker = waypointMarker or makeBall(3,BrickColor.new("Bright bluish green"),script)
	waypointMarker.Position = pos
end

function trouble.mark(pos)
	if not debugOption then return end
	makeBall(2,BrickColor.new("Really red"),script).Position = pos
end

local beams = {}
local currentBeam = 1
local function initBeams()
	for _ = 1, 100 do
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

	myModel.Destroying:Connect(function()
		for _,entry in ipairs(beams) do
			entry.a0:Destroy()
			entry.a1:Destroy()
		end
	end)
end
if debugOption then
	initBeams()
end

function trouble.createBeam(origin,direction)
	if not debugOption then return end

	currentBeam = currentBeam + 1
	if currentBeam > #beams then
		currentBeam = 1
	end

	beams[currentBeam].a0.WorldPosition = origin
	beams[currentBeam].a1.WorldPosition = origin+direction

	return beams[currentBeam].beam
end

function trouble.newBeam(origin,direction)
	if not debugOption then return end

	local a0 = Instance.new("Attachment")
	a0.Parent = workspace.Terrain

	local a1 = Instance.new("Attachment")
	a1.Parent = workspace.Terrain

	a0.WorldPosition = origin
	a1.WorldPosition = origin+direction

	local beam = Instance.new("Beam")
	beam.Width0 = 0.2
	beam.Width1 = 0.2
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Parent = workspace

	debrisService:AddItem(beam,3)
	debrisService:AddItem(a0,3)
	debrisService:AddItem(a1,3)
end

local selectionBox
function trouble.selectionBox(instance)
	if not debugOption then return end
	if not selectionBox then
		selectionBox = Instance.new("SelectionBox")
		selectionBox.Color3 = Color3.new(1,0,0)
		selectionBox.LineThickness = 0.1
		selectionBox.Parent = myModel
	end
	selectionBox.Adornee = instance
end

local lineEnd
function trouble.createLine(instance)
	if not debugOption then return end
	lineEnd = lineEnd or Instance.new("Attachment")
	lineEnd.Parent = instance
end

return trouble

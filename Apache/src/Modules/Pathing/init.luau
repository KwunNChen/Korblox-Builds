--Y3llow Mustang 2/21/21--

local pathing = {}

--Distance between each waypoint--
local navGaps = 20

--Modules--
local modules = script.Parent
local troubleshoot = require(modules.Troubleshoot)

--Folder for physical nodes--
local nodesFolder = workspace:FindFirstChild("Nodes")
if not nodesFolder and script.Visual.Value then
	nodesFolder = Instance.new("Folder",workspace)
	nodesFolder.Name = "Nodes"
end

--Apache parts--
local myModel = script.Parent.Parent
local myRoot = myModel.HumanoidRootPart

local nodes = {}
if _G.ApachePathing then
	nodes = _G.ApachePathing.nodes
end

--Changes node color--
function setNodeColor(node,color3)
	if script.Visual.Value then
		node.Instance.Color = color3
	end
end

--Updates score GUI--
function setNodeScore(node,enabled)
	if script.Visual.Value then
		node.Instance.BillboardGui.Frame.Top.Text = "G: "..node.g.." H: "..node.h
		node.Instance.BillboardGui.Frame.Bottom.Text = "F: "..node.f
		node.Instance.BillboardGui.Enabled = enabled
	end
end

--Creates a beam from one node to another--
function createNodeBeam(node0,node1)
	if script.Visual.Value then
		local beam = Instance.new("Beam")
		beam.Attachment0 = node0.Instance.Attachment
		beam.Attachment1 = node1.Instance.Attachment
		beam.Width0 = 0.3
		beam.Width1 = 0.3
		beam.Parent = node0.Instance
	end
end

--Clears node of any beams--
function cleanNodeBeams(node)
	if script.Visual.Value then
		for _,obj in ipairs(node.Instance:GetChildren()) do
			if obj:IsA("Beam") then
				obj:Destroy()
			end
		end
	end
end

--Ensures nodes are not too close to parts or terrain--
function checkNodeSpace(node)
	
	if not node.Collisions and node.Checked and tick() - node.Checked < 35 then
		return true
	elseif node.Collisions and node.Checked and tick() - node.Checked < 35 then
		return false 
	end
	
	for i = 0, 360, 45 do
		i = math.rad(i)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {myModel,nodesFolder}
		local x = math.cos(i)
		local y = math.sin(i)
		local z = math.sin(0)
		local dir = Vector3.new(y,z,x) * script.Space.Value
		local result = workspace:Raycast(node.Position,dir,params)
		if result and result.Instance then
			setNodeColor(node,Color3.new(0,0,0))
			node.Collisions = true
			node.Checked = tick()
			return false
		end
	end
	
	node.Collisions = false
	node.Checked = tick()
	
	return true
end

--Checks if there is a path from one node to another--
function pathing.checkSight(node,node2)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {myModel,node.Instance}
	
	local dist = (node.Position - node2.Position).Magnitude

	local result = workspace:Raycast(node.Position,(node2.Position - node.Position).Unit*dist,params)
	if not result or (result.Instance and result.Instance == node2.Instance) then
		return true
	end
end

--Checks if there are parts or terrain under the current position--
--Used to determine where to generate waypoints--
function checkGround(pos)
	local result = workspace:Raycast(pos,Vector3.new(0,-1000,0))
	if result then
		return true
	end
end

--Finds closest node to a given position--
--Used for finding start and end node--
function findNodeNear(pos)
	local closestNode = nil
	local blacklist = {}
	
	while not closestNode do
		
		local dist = math.huge
		
		
		for _,node in ipairs(nodes) do
			local tempDist = (pos - node.Position).Magnitude
			if tempDist < dist and not table.find(blacklist,node) then
				closestNode = node
				dist = tempDist
			end
		end
		if not checkNodeSpace(closestNode) then
			table.insert(blacklist,closestNode)
			closestNode = nil
		end
	end
	return closestNode
end

--Creates a new node object at given position--
function createNode(pos)
	
	local node
	if script.Visual.Value then
		node = Instance.new("Part")
		node.Size = Vector3.new(2,1,2)
		node.Anchored = true
		node.Position = pos
		node.Material = Enum.Material.Neon
		node.Color = Color3.new(0,1,1)
		node.Transparency = 0.5
		node.Parent = nodesFolder
		
		local gui = script.BillboardGui
		gui:Clone().Parent = node

		Instance.new("Attachment",node)
	end

	
	return {
		Position = pos,
		Instance = node,
		g = math.huge,
		h = math.huge,
		f = math.huge,
		Collisions = false,
		Checked = nil
	}
end

--Returns all neighbor nodes around a given node--
--Must have a direct line of sight to neighbor--
--Neighbor must minimum distance from parts and terrain--
function findNeighbors(node)
	local neighbors = {}
	local dist = navGaps * 1.5
	for _,node2 in ipairs(nodes) do

		local tempDist = (node.Position - node2.Position).Magnitude

		--Distance range modifier
		--If navGaps is 50 then there is a 25 stud difference
		--This is for including diagnal nodes as neighbors
		local diff = navGaps/2

		if node ~= node2 and tempDist < dist then

			if pathing.checkSight(node,node2,tempDist) and checkNodeSpace(node2) then
				table.insert(neighbors,node2)
			end

		end
	end

	return neighbors
end

--Recreated A* for Roblox LuaU--
--Ported from a Python version--
--Not 1:1, made minor adjustments--
function pathing.findPath(startPos,endPos)
	
	if not _G.ApachePathing.ready then
		warn("Tried to path before prepared")
		return false
	else
		nodes = _G.ApachePathing.nodes
	end
	
	--Reset node colors
	for i,node in ipairs(nodes) do
		
		node.f = math.huge
		node.g = math.huge
		node.h = math.huge
		
		node.Parent = nil
		
		setNodeColor(node,Color3.new(0,1,1))
		setNodeScore(node,false)
		cleanNodeBeams(node)
	end

	--Create start and end node
	local startNode = findNodeNear(startPos)
	local endNode = findNodeNear(endPos)

	startNode.f = 0
	startNode.g = 0
	startNode.h = 0

	endNode.f = 0
	endNode.g = 0
	endNode.h = 0

	--Initialize both open and closed list
	local open_list = {}
	local closted_list = {}

	--Add the start node
	table.insert(open_list,startNode)

	--Loop until you find the end
	while #open_list > 0 do

		--Get the current node
		local currentNode = open_list[1]
		local currentIndex = 1
		for i,node in ipairs(open_list) do
			if node.f < currentNode.f then
				currentNode = node
				currentIndex = i
			end
		end

		--Pop current off open list, add to closed list
		table.remove(open_list,currentIndex)
		table.insert(closted_list,currentNode)

		--Found the goal
		if currentNode == endNode then
			local path = {}
			local current = currentNode

			while current do
				table.insert(path,current)
				
				if current.Parent then
					createNodeBeam(current,current.Parent)
				end
				setNodeColor(current,Color3.new(1,1,0))
				
				current = current.Parent
			end
			
			for i,v in ipairs(path) do
				v.Parent = nil
			end

			local reversePath = {}
			for i = #path, 1, -1 do
				table.insert(reversePath,path[i])
			end
			return reversePath
		end

		--Loop through neighbors
		for i,node in ipairs(findNeighbors(currentNode)) do

			local closed = false

			--Child is on the closed list
			for _,closedChild in ipairs(closted_list) do
				if closedChild == node then
					setNodeColor(currentNode,Color3.new(1,0,0))
					closed = true
					break
				end
			end

			if not closed then

				local open = false
				--Create the f, g, and h values
				--F is the total cost of the node
				--G is the distance between the current node and start node
				--H is the heuristic - etimated distance from the current node to
				--the end node
				node.g = math.floor((startNode.Position - node.Position).Magnitude)
				node.h = math.floor((endNode.Position - node.Position).Magnitude*2)
				node.f = node.g + node.h

				setNodeScore(node,true)

				--Child is already in the open list
				for _,openNode in ipairs(open_list) do
					if openNode == node and node.g >= openNode.g then
						open = true
						break
					end
				end

				if not open then

					--Add the child to the open list
					node.Parent = currentNode
					setNodeColor(node,Color3.new(0,1,0))
					table.insert(open_list,node)
				end
			end
		end
	end
	
	--Failed to generate path
	return false
end

--Generates nodes once per server--
function pathing.init()

	--Global variable for tracking nodes so all apaches can utilize them--
	_G.ApachePathing = {
		nodes = {},
		loading = true,
		ready = false
	}

	--Starting point for generating nodes--
	local origin = myRoot.Position + Vector3.new(0,myModel.Settings.Height.Value,0)


	--Generate all nodes along z axis until edge of map--
	local offsetZ = 0
	while true do

		local forward = false
		local backward = false

		--Check foward
		local pos = origin + Vector3.new(0,0,offsetZ)
		if checkGround(pos) then
			table.insert(nodes,createNode(pos))
			forward = true
		end

		--Check backwards
		pos = origin - Vector3.new(0,0,offsetZ)
		if checkGround(pos) and offsetZ > 0 then
			table.insert(nodes,createNode(pos))
			backward = true
		end

		--If there are no parts at the furthest z values we have reached the edge of the map--
		if not backward and not forward then
			break
		end

		offsetZ = offsetZ + navGaps

		game:GetService("RunService").Heartbeat:Wait()
	end

	--Generate all nodes along x axis--
	--Using zNodes run that same function except now check the x/-x for each node--
	local tempNodes = nodes

	for i=1, #nodes do

		local node = nodes[i]

		local offsetX = navGaps

		while true do

			local left = false
			local right = false

			--Check foward
			local pos = node.Position + Vector3.new(offsetX,0,0)
			if checkGround(pos) then
				table.insert(nodes,createNode(pos))
				right = true
			end

			--Check backwards
			pos = node.Position - Vector3.new(offsetX,0,0)
			if checkGround(pos) then
				table.insert(nodes,createNode(pos))
				left = true
			end

			if not left and not right then
				break
			end

			offsetX = offsetX + navGaps


		end
		game:GetService("RunService").Heartbeat:Wait()
	end

	_G.ApachePathing.nodes = nodes
	_G.ApachePathing.ready = true
end

return pathing

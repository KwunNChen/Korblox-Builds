--[[
	Runs on each client (RunContext Client): spins the road wheels and runs a belt
	of tread links round each track, at the speed that side's track is moving.
	The track meshes use a SurfaceAppearance, which cannot scroll, so the links
	are what shows the track moving. Purely visual: nothing here replicates.

	The links are welded to the hull and live inside the tank, so they move with
	it exactly and go when it goes; only each weld's offset round the loop is
	changed per frame. They stop when the tank is wrecked and fade out with it.
]]

local runService = game:GetService("RunService")

--Gap between tread links (studs), how thick the track is past the wheels, and
--the links' colour.
local LINK_SPACING = 1.1
local TRACK_THICKNESS = 0.45
local LINK_COLOR = Color3.fromRGB(48,46,42)

--Further from the camera than this the tracks are left still.
local ANIMATE_DISTANCE = 300

--Seconds the links take to fade out with the wreck.
local FADE_TIME = 1

local tank = script.Parent
if not tank:GetAttribute("Rigged") then
	tank:GetAttributeChangedSignal("Rigged"):Wait()
end
local hull = tank:WaitForChild("Hull")
local wheelsModel = tank:WaitForChild("Mesh"):WaitForChild("Wheels")

local folder = Instance.new("Folder")
folder.Name = "TreadLinks"
folder.Parent = tank

--A belt loop round the wheels that carry the track, in the hull's Z (back) and
--Y (up) plane, as straight runs and arcs walked counterclockwise: along the
--bottom towards the back, up over the drive wheel, forward along the top, down
--round the idler.
local function buildLoop(pulleys)
	local segments = {}
	local length = 0
	local count = #pulleys
	local tangents = {}
	for i = 1,count do
		local a,b = pulleys[i],pulleys[i % count + 1]
		local d = b.center - a.center
		local angle = math.atan2(d.Y,d.X) + math.asin(math.clamp((a.radius - b.radius)/d.Magnitude,-1,1))
		local t = Vector2.new(math.cos(angle),math.sin(angle))
		local n = Vector2.new(t.Y,-t.X)
		tangents[i] = {from = a.center + n*a.radius,to = b.center + n*b.radius,normal = n}
	end
	for i = 1,count do
		local run = tangents[i]
		local runLength = (run.to - run.from).Magnitude
		segments[#segments+1] = {kind = "run",from = run.from,to = run.to,normal = run.normal,length = runLength}
		length += runLength

		local pulley = pulleys[i % count + 1]
		local nextRun = tangents[i % count + 1]
		local startAngle = math.atan2(run.normal.Y,run.normal.X)
		local endAngle = math.atan2(nextRun.normal.Y,nextRun.normal.X)
		local sweep = (endAngle - startAngle) % (2*math.pi)
		segments[#segments+1] = {kind = "arc",center = pulley.center,radius = pulley.radius,start = startAngle,sweep = sweep,length = sweep*pulley.radius}
		length += sweep*pulley.radius
	end
	return segments,length
end

--Point and outward normal at distance s round the loop.
local function pointAt(segments,s)
	for _,segment in ipairs(segments) do
		if s <= segment.length then
			if segment.kind == "run" then
				local alpha = segment.length > 0 and s/segment.length or 0
				return segment.from:Lerp(segment.to,alpha),segment.normal
			else
				local angle = segment.start + (segment.radius > 0 and s/segment.radius or 0)
				local normal = Vector2.new(math.cos(angle),math.sin(angle))
				return segment.center + normal*segment.radius,normal
			end
		end
		s -= segment.length
	end
	local last = segments[#segments]
	return last.center or last.to,last.normal or Vector2.new(0,-1)
end

local sides = {}
for _,sideName in ipairs({"L","R"}) do
	local wheelFolder = wheelsModel:WaitForChild("Wheels "..sideName)
	local track = wheelsModel:WaitForChild("Track "..sideName)
	local side = {wheels = {},links = {},welds = {},offset = 0}

	local idler,sprocket,firstRoad,lastRoad
	for _,wheel in ipairs(wheelFolder:GetChildren()) do
		if wheel:IsA("BasePart") then
			local motor = wheel:WaitForChild("WheelMotor",10)
			local center = hull.CFrame:PointToObjectSpace(wheel.Position)
			local radius = wheel.Size.Y/2
			local entry = {motor = motor,base = motor and motor.C0,radius = radius,angle = 0,center = Vector2.new(center.Z,center.Y)}
			table.insert(side.wheels,entry)
			if wheel.Name:find("Front") then
				idler = entry
			elseif wheel.Name:find("Drive") then
				sprocket = entry
			else
				if not firstRoad or entry.center.X < firstRoad.center.X then firstRoad = entry end
				if not lastRoad or entry.center.X > lastRoad.center.X then lastRoad = entry end
			end
		end
	end

	local trackOffset = hull.CFrame:PointToObjectSpace(track.Position)
	side.x = trackOffset.X
	if idler and sprocket and firstRoad and lastRoad then
		local pulleys = {}
		for _,wheel in ipairs({idler,firstRoad,lastRoad,sprocket}) do
			table.insert(pulleys,{center = wheel.center,radius = wheel.radius + TRACK_THICKNESS})
		end
		side.segments,side.length = buildLoop(pulleys)

		for _ = 1,math.floor(side.length/LINK_SPACING) do
			local link = Instance.new("Part")
			link.Size = Vector3.new(track.Size.X + 0.1,0.15,LINK_SPACING*0.55)
			link.Color = LINK_COLOR
			link.Material = Enum.Material.Metal
			link.Anchored = false
			link.Massless = true
			link.CanCollide = false
			link.CanQuery = false
			link.CanTouch = false
			link.CastShadow = false
			link.CFrame = hull.CFrame
			local weld = Instance.new("Weld")
			weld.Part0 = hull
			weld.Part1 = link
			weld.Parent = link
			link.Parent = folder
			table.insert(side.links,link)
			table.insert(side.welds,weld)
		end
	end
	sides[sideName] = side
end

local function trackSpeeds()
	local cf = hull.CFrame
	local forward = hull.AssemblyLinearVelocity:Dot(cf.LookVector)
	local turn = hull.AssemblyAngularVelocity:Dot(cf.UpVector)
	return forward + turn*sides.L.x,forward + turn*sides.R.x
end

local function place(dt)
	local leftSpeed,rightSpeed = trackSpeeds()
	for sideName,side in pairs(sides) do
		local travel = (sideName == "L" and leftSpeed or rightSpeed)*dt
		for _,wheel in ipairs(side.wheels) do
			if wheel.motor then
				wheel.angle -= travel/wheel.radius
				wheel.motor.C0 = wheel.base * CFrame.Angles(wheel.angle,0,0)
			end
		end
		if side.segments then
			side.offset = (side.offset + travel) % side.length
			for i,weld in ipairs(side.welds) do
				local point,normal = pointAt(side.segments,(side.offset + (i - 1)*LINK_SPACING) % side.length)
				local position = Vector3.new(side.x,point.Y,point.X)
				local up = Vector3.new(0,normal.Y,normal.X)
				local along = Vector3.new(0,normal.X,-normal.Y)
				weld.C0 = CFrame.fromMatrix(position,along:Cross(up),up)
			end
		end
	end
end

--Laid round the wheels straight away, still.
place(0)

local connection
connection = runService.RenderStepped:Connect(function(dt)
	if not hull.Parent or tank:GetAttribute("Wrecked") then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - hull.Position).Magnitude > ANIMATE_DISTANCE then return end
	place(dt)
end)

tank:GetAttributeChangedSignal("Fading"):Connect(function()
	local info = TweenInfo.new(FADE_TIME)
	for _,side in pairs(sides) do
		for _,link in ipairs(side.links) do
			game:GetService("TweenService"):Create(link,info,{Transparency = 1}):Play()
		end
	end
end)

tank.Destroying:Connect(function()
	connection:Disconnect()
end)
tank.AncestryChanged:Connect(function()
	if not tank:IsDescendantOf(workspace) then
		connection:Disconnect()
	end
end)

local flight = {}

--Modules--
local modules = script.Parent
local core = require(modules.Core)
local troubleshoot = require(modules.Troubleshoot)

local myModel = script.Parent.Parent
local myRoot = myModel.HumanoidRootPart

--Settings--
local mySettings = myModel.Settings
local debugOption = mySettings.Debug.Value

local dodgingObstacles = myModel.DodgingObstacles

local bg = myRoot.BodyGyro
local bp = myModel.Body.BodyPosition

local flightDir = 0

--Tilts aircraft in a direction based on given pitch, yaw, roll in degrees
function flight.flyTowards(pitch,yaw,roll)
	
	local currentPitch,currentYaw,currentRoll = bg.CFrame:ToEulerAnglesYXZ()
	
	if yaw then
		yaw = math.clamp(yaw,-65,65)
		yaw = myRoot.Orientation.Y + yaw
		yaw = math.rad(yaw)
	else
		yaw = currentYaw
	end
	
	if pitch then
		pitch = math.rad(pitch)
	else
		pitch = currentPitch
	end
	
	if roll then
		roll = math.rad(roll)
	else
		if yaw then
			roll = math.clamp(yaw,-45,45)
			roll = math.rad(roll)
		else
			roll = currentRoll
		end
	end
	
	--NaN (Not a Number) Prevention--
	if pitch ~= pitch then
		pitch = 0
		warn("Pitch NaN prevented.")
	end
	if yaw ~= yaw then
		yaw = 0
		warn("Yaw NaN prevented.")
	end
	if roll ~= roll then
		roll = 0
		warn("Roll NaN prevented.")
	end
	
	bg.CFrame = CFrame.fromEulerAnglesYXZ(pitch,yaw,roll)
end

function flight.flyToPos(pos)

	--Calculate 2D distance, ignore Y
	local pos2d = Vector2.new(pos.X,pos.Z)
	local myPos2d = Vector2.new(myRoot.Position.X,myRoot.Position.Z)
	local dist2D = (pos2d - myPos2d).Magnitude

	--Find direction we will fly
	local yaw = -core.findAngle(myRoot.Position, pos, myRoot)

	--Slow down the closer we get
	local pitch = math.clamp(-dist2D,-35,-10)

	if dist2D < 10 then
		return true
	end

	flight.flyTowards(pitch,yaw)
end

--Calculates velocity based off the heli rotation
local speed = 2 --Acceleration and max speed
function flight.physics()

	--Momentum control
	local pitch = myRoot.Orientation.X
	local roll = -myRoot.Orientation.Z
	
	--Calculates how much we should increase our position
	pitch = pitch/50*speed
	roll = roll/50*speed
	
	--Prevent NaN (Not a Number)
	if pitch ~= pitch then
		pitch = 0
		warn("Pitch NaN prevented.")
	end
	if roll ~= roll then
		roll = 0
		warn("Roll NaN prevented.")
	end
	
	--Applys the increase in position and the change in height to body position
	bp.Position = (CFrame.new(bp.Position) * CFrame.Angles(0,math.rad(myRoot.Orientation.Y),0) * CFrame.new(roll,0,pitch)).Position
	
	--Calculates which yaw direction we are heading
	flightDir = math.atan2(roll,pitch)
	flightDir = math.deg(flightDir) + myRoot.Orientation.Y + 180
	if flightDir > 180 then
		flightDir = -(360-flightDir)
	elseif flightDir <-180 then
		flightDir = 360+flightDir
	end	
end

--Maintain consistent height--
function flight.maintainHeight(height,target)
	
	local heightChange = 0
	
	if target then
		
		if target.Position.Y + height > myRoot.Position.Y or flight.checkHeight(height) == 1 then
			heightChange = 1 
		elseif target.Position.Y + height < myRoot.Position.Y - 15 and flight.checkHeight(height) ~= 1 then
			heightChange = -1
		end
	else
		heightChange = flight.checkHeight(height)
	end
	
	bp.Position = bp.Position + Vector3.new(0,heightChange,0)
end

function flight.checkHeight(goalHeight)
	--Height check--
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {myModel}

	local result = workspace:Raycast(myRoot.Position,Vector3.new(0,-1000,0),rayParams)

	--Maintain consistent height--
	local heightChange = 0
	if result and dodgingObstacles.Value == false then
		if result.Position.Y < myRoot.Position.Y - goalHeight then
			return -1
		elseif result.Position.Y > myRoot.Position.Y - goalHeight+30 then
			return 1
		else
			return 0
		end
	end
end


function flight.checkObjs(dir,offset)

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {myModel}
	
	--50 raycasts spread apart in a circle
	for i = -25, 25, 1 do
		
		--Circle math
		local radius = 10 --15
		local angle = math.pi*2 / 25 * i
		local xPos = math.cos(angle) * radius*2
		local zPos = math.sin(angle) * radius*2
		local newPos = Vector3.new(xPos,0,zPos)
		
		--Origin of the raycast
		local startPos = Vector3.new(myRoot.Position.X,myModel.Body.Nose.WorldPosition.Y,myRoot.Position.Z)
		
		--If there is a offset apply it
		if offset then
			startPos = CFrame.new(startPos + newPos) * offset * CFrame.Angles(0,math.rad(myRoot.Orientation.Y),0).Position
		else
			startPos = CFrame.new(startPos + newPos) * CFrame.Angles(0,math.rad(myRoot.Orientation.Y),0).Position
		end
		
		--Direction and length of the raycast
		--This is based off the flightDir velocity
		local dir = (CFrame.new(startPos) * CFrame.Angles(0,math.rad(flightDir),0) * CFrame.Angles(0,math.rad(dir),0)).LookVector
		local length = math.clamp(myRoot.Velocity.Magnitude,20,150)
		
		--Combine length and direction
		local dirLength = dir * length
		
		--Raycast based off the information given
		local result = workspace:Raycast(startPos,dirLength,rayParams)
		
		--Pretty beams for visualizing the raycasting
		if debugOption then
			local beam = troubleshoot.createBeam(startPos,dirLength)
			if result then
				beam.Color = ColorSequence.new(Color3.new(1,0,0))
			end
			beam.Color = ColorSequence.new(Color3.new(0,1,0))
		end
		
		--Returns the result if something is blocking our path
		if result then
			return result
		end
			
	end

	return false
end

local order
function flight.checkCollisions()
	
	local obstacle = flight.checkObjs(0)
	
	if obstacle then
		
		dodgingObstacles.Value = true
		
		--Find if we can fly over the object
		local raise = nil
		for i = 1, 9 do
			if not flight.checkObjs(0,CFrame.new(0,i,0)) then
				raise = i
				break
			end
		end
		if raise then
			for i = 1, raise do
				bp.Position = bp.Position + Vector3.new(0,1,0)
				flight.flyTowards(-35+raise*3)
				wait()
			end
		else
			--If we can't fly above the obstacle, find an angle we can fly towards to avoid
			
			--Fly the opposite direction of where the obstacle is hit
			
			local pitch = myRoot.Orientation.X
			local roll = -myRoot.Orientation.Z
			
			local flightDir = math.atan2(roll,pitch)
			flightDir = math.deg(flightDir) - 180
			if flightDir > 180 then
				flightDir = -(360-flightDir)
			elseif flightDir <-180 then
				flightDir = 360+flightDir
			end	
			

			local pitch,roll = nil,nil
			for i = 0, 180, 10 do
				
				if not flight.checkObjs(i)then
					pitch = math.abs(i)*1.5
					roll = i
					break
				elseif not flight.checkObjs(-i) then
					pitch = math.abs(i)*1.5
					roll = -i
					break
				end
			end
			if pitch and roll then
				flight.flyTowards(pitch,nil,roll)
			else
				
				if flightDir < 90 and flightDir > -90 then
					pitch = 30
				else
					pitch = -30
				end

				if flightDir > 0 then
					roll = 30
				else
					roll = -30
				end

				flight.flyTowards(pitch,nil,roll)
			end--]]
		end--]]
		
		order = tick()
		task.spawn(function()
			local currentOrder = order
			wait(1)
			if currentOrder == order then
				dodgingObstacles.Value = false
			end
		end)
		wait(0.2)
	end		
end

--Levels out where it is, keeping its heading.
function flight.level()
	bg.CFrame = CFrame.fromEulerAnglesYXZ(0,math.rad(myRoot.Orientation.Y),0)
end

function flight.land(cframe)
	bg.CFrame = cframe
	wait(2)
	while cframe.Position.Y < myModel.Body.Position.Y-0.7 do
		wait()
		bp.Position = bp.Position - Vector3.new(0,0.2,0)
	end
end

return flight

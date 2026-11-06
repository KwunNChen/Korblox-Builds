local trouble = {}

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

function trouble.mark(pos)
	if not debugOption then return end
	makeBall(2,BrickColor.new("Really red"),script).Position = pos
end

return trouble

--[[
	Runs on each client (RunContext Client): rolls the truck's wheels at the speed
	it is going (its Rolling attribute, negative backing up). Purely visual:
	nothing here replicates.
]]

local runService = game:GetService("RunService")

--Further from the camera than this the wheels are left still.
local ANIMATE_DISTANCE = 300

local truck = script.Parent
if not truck:GetAttribute("Rigged") then
	truck:GetAttributeChangedSignal("Rigged"):Wait()
end
local hull = truck:WaitForChild("Hull")

local wheels = {}
for _,wheel in ipairs(truck:WaitForChild("Mesh"):WaitForChild("Wheels"):GetChildren()) do
	local hub = wheel:WaitForChild("Hub")
	local motor = hub:WaitForChild("WheelMotor")
	wheels[#wheels+1] = {motor = motor,base = motor.C0,radius = hub:GetAttribute("Radius") or 2.3}
end

local turned = 0
local connection
connection = runService.RenderStepped:Connect(function(dt)
	if not truck.Parent then
		connection:Disconnect()
		return
	end
	if truck:GetAttribute("Wrecked") then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - hull.Position).Magnitude > ANIMATE_DISTANCE then return end
	local rolling = truck:GetAttribute("Rolling") or 0
	if rolling == 0 then return end
	turned -= rolling*dt
	for _,wheel in ipairs(wheels) do
		wheel.motor.C0 = wheel.base * CFrame.Angles(turned/wheel.radius,0,0)
	end
end)

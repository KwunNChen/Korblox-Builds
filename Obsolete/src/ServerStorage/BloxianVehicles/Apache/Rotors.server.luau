--[[
	Runs on each client (RunContext Client): spins the Apache's rotors on their
	RotorMotor joints. Nothing about the spin is simulated or sent (the C0 it
	turns is this client's own copy), and once the Apache is wrecked they run down.
]]

local runService = game:GetService("RunService")

--Main rotor spin (radians/s; each motor's Rate attribute multiplies it), how long
--they take to run down once wrecked (seconds), and how far away (studs) they
--still turn.
local ROTOR_SPEED = 25
local SPIN_DOWN = 4
local ANIMATE_DISTANCE = 600

local heli = script.Parent

--Each motor and the C0 it was rigged with. C0 is turned, not Transform: the
--Humanoid's Animator resets Transform every frame.
local motors = {}
local function add(item)
	if item:IsA("Motor6D") and item.Name == "RotorMotor" then
		table.insert(motors,{motor = item,base = item.C0})
	end
end
for _,item in ipairs(heli:GetDescendants()) do
	add(item)
end
heli.DescendantAdded:Connect(add)

local angle = 0
local spin = ROTOR_SPEED
local connection
connection = runService.RenderStepped:Connect(function(dt)
	if not heli.Parent then
		connection:Disconnect()
		return
	end
	if heli:GetAttribute("Wrecked") then
		spin = math.max(spin - ROTOR_SPEED/SPIN_DOWN*dt,0)
	end
	if spin <= 0 then return end
	local camera = workspace.CurrentCamera
	local body = heli.PrimaryPart
	if camera and body and (camera.CFrame.Position - body.Position).Magnitude > ANIMATE_DISTANCE then return end

	angle = (angle + spin*dt) % (2*math.pi*16)
	for _,entry in ipairs(motors) do
		local motor = entry.motor
		if motor.Parent then
			motor.C0 = entry.base * CFrame.Angles(angle*(motor:GetAttribute("Rate") or 1),0,0)
		end
	end
end)

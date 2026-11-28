local replicatedStorage = game:GetService("ReplicatedStorage")
local debris = game:GetService("Debris")
local runService = game:GetService("RunService")

local bindableEvent = replicatedStorage:FindFirstChild("Suppression") or Instance.new("BindableEvent",replicatedStorage)
bindableEvent.Name = "Suppression"

local crackSounds = replicatedStorage.SPH_Assets.Sounds.BulletCrack:GetChildren()
local tunnelVision = script.Parent
tunnelVision.ImageTransparency = 1

local function LerpNumber(number:number, target:number, speed:number)
	return number + (target-number) * speed
end

bindableEvent.Event:Connect(function(suppressionLevel)
	local newSound = crackSounds[math.random(#crackSounds)]:Clone()
	local distortion = Instance.new("DistortionSoundEffect",newSound)
	newSound.Parent = script
	newSound.Volume = suppressionLevel
	newSound:Play()
	debris:AddItem(newSound,newSound.TimeLength)
	
	script.Parent.ImageTransparency -= suppressionLevel / 10
end)

runService.Heartbeat:Connect(function(dt)
	tunnelVision.ImageTransparency = tunnelVision.ImageTransparency + (1 - tunnelVision.ImageTransparency) * 0.003 * 60 * dt
end)
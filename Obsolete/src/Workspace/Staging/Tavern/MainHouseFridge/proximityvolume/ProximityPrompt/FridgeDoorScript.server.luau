local Prompt = script.Parent
local fridgedoor = script.Parent.Parent.Parent.FridgeDoor
local fridgeopensound = script.Parent.Parent.Parent.fridge_dooropen
local fridgelight = script.Parent.Parent.Parent.FridgeLight.SpotLight

local function dooropen()
	Prompt.Enabled = false
	fridgeopensound:Play()
	fridgelight.Enabled = true
	fridgedoor.door.CanCollide = false
	for i = 1, 20 do
		fridgedoor:SetPrimaryPartCFrame(fridgedoor.PrimaryPart.CFrame * CFrame.Angles(0, math.rad(-6), 0)) --turns 120 degrees
		wait()
	end
	fridgedoor.door.CanCollide = true
	Prompt.ObjectText = "Close"
	Prompt.Enabled = true
end

local function doorclose()
	Prompt.Enabled = false
	fridgeopensound:Play()
	fridgelight.Enabled = false
	fridgedoor.door.CanCollide = false
	for i = 1, 20 do
		fridgedoor:SetPrimaryPartCFrame(fridgedoor.PrimaryPart.CFrame * CFrame.Angles(0, math.rad(6), 0)) --turns back 120 degrees
		wait()
	end
	fridgedoor.door.CanCollide = true
	Prompt.ObjectText = "see what's inside"
	Prompt.Enabled = true
end



--took me quite a long time to find solution but here we aree D:
Prompt.Triggered:Connect(function()
	if Prompt.ObjectText == "see what's inside" then
		dooropen()
	else
		doorclose()
	end
end)
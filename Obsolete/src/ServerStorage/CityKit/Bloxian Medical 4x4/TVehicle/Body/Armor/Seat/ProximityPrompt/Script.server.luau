local proximityPrompt = script.Parent
local seat = proximityPrompt.Parent

local lastOcc = nil

seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	if seat.Occupant then
		proximityPrompt.Enabled = false
		lastOcc = seat.Occupant
	else
		proximityPrompt.Enabled = true
		wait()
		lastOcc.Parent:SetPrimaryPartCFrame(lastOcc.Parent.PrimaryPart.CFrame * CFrame.new(0,7,0))		
	end
end)

proximityPrompt.Triggered:Connect(function(player)
	seat:Sit(player.Character.Humanoid)
end)
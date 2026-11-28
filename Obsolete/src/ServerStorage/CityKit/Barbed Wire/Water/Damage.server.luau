script.Parent.Touched:connect(function(part)
	local humanoid = part.Parent:FindFirstChild("Humanoid") 
	if (humanoid ~= nil) then
		humanoid.Health = 15
	end 
end)
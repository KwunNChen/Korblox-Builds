-- Tavern patrons and the staging Korblox squad are set dressing: nothing (guns, gas, Medical) may kill them.
local staging = workspace:WaitForChild("Staging")

local function protect(m)
	local hum = m:FindFirstChildOfClass("Humanoid") or m:WaitForChild("Humanoid", 10)
	if not hum then return end
	hum.BreakJointsOnDeath = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	hum.HealthChanged:Connect(function(h)
		if h < hum.MaxHealth then hum.Health = hum.MaxHealth end
	end)
	m:SetAttribute("Invincible", true)
end

for _, name in { "Patrons", "StagingSoldiers" } do
	local folder = staging:WaitForChild(name)
	for _, m in folder:GetChildren() do task.spawn(protect, m) end
	folder.ChildAdded:Connect(protect)
end

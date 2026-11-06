local physicsService = game:GetService("PhysicsService")

pcall(function() physicsService:RegisterCollisionGroup("CarBody") end)
pcall(function() physicsService:RegisterCollisionGroup("CarWheel") end)
pcall(function() physicsService:RegisterCollisionGroup("Passengers") end)
pcall(function() physicsService:CollisionGroupSetCollidable("CarBody","CarWheel",false) end)
pcall(function() physicsService:CollisionGroupSetCollidable("CarBody","Passengers",false) end)
	


local body = script.Parent.Body

--Add wheels to collision group
for _,obj in ipairs(body:GetChildren()) do
	if obj:IsA("Model") then
		obj.PhysicalWheel.CollisionGroup = "CarWheel"
	end
end

--Add body to collision group
body.Body.CollisionGroup = "CarBody"
--physicsService:SetPartCollisionGroup(body.Hitbox,"CarBody")

local bullets = {}

local bulletsPath = shared.S.TREK_Modules:WaitForChild('BulletTypes')

for i, module in pairs(bulletsPath:GetChildren()) do
	if not module:IsA('ModuleScript') then continue end
	bullets[module.Name] = require(module)
end

return bullets

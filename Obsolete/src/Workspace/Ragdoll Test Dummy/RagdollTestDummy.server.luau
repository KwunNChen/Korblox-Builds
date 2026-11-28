-- Ragdoll test dummy: shoot it and it ragdolls like a dead NPC (RagdollMod.LimitR6), then a fresh one
-- stands up in the same spot after RESPAWN seconds. Copy or move the whole model to put more around.
local RESPAWN = 6
local dummy = script.Parent
local template = dummy:Clone() -- taken before anything changes, so every respawn starts clean
local hum = dummy:WaitForChild("Humanoid")
local RagdollMod = require(game:GetService("ReplicatedStorage").SPH_Assets.Modules.RagdollMod)

hum.BreakJointsOnDeath = false
-- server owns it, so the ragdoll isn't simulated on whichever client happens to be nearby
for _, p in dummy:GetDescendants() do
	if p:IsA("BasePart") then pcall(p.SetNetworkOwner, p, nil) end
end

hum.Died:Connect(function()
	RagdollMod.LimitR6(dummy)
	-- only the body collides (as Bloxian HumanoidHandler); solid gear shoves the limbs and the body spazzes
	for _, name in {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"} do
		local p = dummy:FindFirstChild(name)
		if p then p.CanCollide = true end
	end
	task.wait(RESPAWN)
	template:Clone().Parent = dummy.Parent
	dummy:Destroy()
end)

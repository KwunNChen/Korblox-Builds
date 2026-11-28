-- Roblox's Popper only stops the camera on parts under 0.25 transparency, so it zoomed out through the
-- 0.35 tower windows. After the camera updates each frame, pull it back in front of any window glass.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local params = RaycastParams.new()
params.RespectCanCollide = true

RunService:BindToRenderStep("WindowCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = workspace.CurrentCamera
	local focus = cam.Focus.Position
	local offset = cam.CFrame.Position - focus
	if offset.Magnitude < 0.5 then return end -- first person
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(focus, offset, params)
	if hit and (hit.Instance.Name == "Window" or hit.Material == Enum.Material.Glass) then
		cam.CFrame = cam.CFrame.Rotation + hit.Position - offset.Unit * 0.3
	end
end)

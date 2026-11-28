local players = game:GetService("Players")
local runService = game:GetService("RunService")
local assets = game:GetService("ReplicatedStorage").SPH_Assets
local player = players.LocalPlayer
local character = player.Character or player.CharacterAppearanceLoaded:Wait()
local tool, magAmmo, ammoPool
local dead = false
local wepStats

local ammoUI = script.Parent.Ammo

script.Parent.Version.Text = "Spearhead "..require(assets.GameConfig).version

local ammoCounter = ammoUI.MagAmmo
local ammoPoolUI = ammoUI.AmmoPool
local bulletType = ammoUI.AmmoType
local fireMode = ammoUI.FireMode
local chambered = ammoCounter.Chambered

local fireModeNames = {"SAFE", "[S]", "[F]", "[B]", "[M]"}

character.ChildAdded:Connect(function(newChild)
	if newChild:FindFirstChild("SPH_Weapon") and assets.WeaponModels:FindFirstChild(newChild.Name) and not dead then
		tool = newChild
		magAmmo = tool:WaitForChild("Ammo").MagAmmo
		ammoPool = tool.Ammo.ArcadeAmmoPool
		wepStats = require(tool.SPH_Weapon.WeaponStats)
		bulletType.Text = wepStats.ammoType
	end
end)

character.ChildRemoved:Connect(function(oldChild)
	if oldChild == tool then
		tool = nil
	end
end)

runService.Heartbeat:Connect(function()
	if tool and (tool:FindFirstChild("Chambered") or wepStats.openBolt) and magAmmo and not dead then
		ammoUI.Visible = true
		if not wepStats.operationType or type(wepStats.operationType) == "string" then wepStats.operationType = 1 end
		if wepStats.operationType == 4 and tool.Chambered.Value then
			ammoCounter.AmmoCount.Text = magAmmo.Value + 1
		else
			ammoCounter.AmmoCount.Text = magAmmo.Value
		end
		ammoPoolUI.Text = "/"
		if wepStats.infiniteAmmo then
			ammoPoolUI.Text = ammoPoolUI.Text.."INF"
		else
			ammoPoolUI.Text = ammoPoolUI.Text..ammoPool.Value
		end
		if tool.FireMode.Value == 0 then
			ammoCounter.AmmoCount.TextColor3 = Color3.new(0.5,0.5,0.5)
		elseif wepStats.openBolt and magAmmo.Value > 0 or not wepStats.openBolt and tool.Chambered.Value then
			if not wepStats.openBolt then
				chambered.Visible = true
			else
				chambered.Visible = false
			end
			ammoCounter.AmmoCount.TextColor3 = Color3.new(1, 1, 1)
		else
			chambered.Visible = false
			ammoCounter.AmmoCount.TextColor3 = Color3.new(1, 0, 0)
		end
		fireMode.Text = fireModeNames[tool.FireMode.Value + 1]
	else
		ammoUI.Visible = false
	end
end)

character.Humanoid.Died:Connect(function()
	dead = true
end)

local userInputService = game:GetService("UserInputService")
local playerOnMobile = userInputService.TouchEnabled
if playerOnMobile then
	ammoUI.Position = UDim2.new(1, -30, 1, -100)
end
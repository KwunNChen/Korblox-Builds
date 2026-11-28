local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAppearanceLoaded:Wait()
local humanoid:Humanoid = character:WaitForChild("Humanoid")
local tweenService = game:GetService("TweenService")
local tweenInfo = TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.In)

local lightingFX = game.Lighting:FindFirstChild("DamageColorCorrection") or Instance.new("ColorCorrectionEffect",game.Lighting)
lightingFX.Name = "DamageColorCorrection"

local heartBeat = script.Parent.Heartbeat
heartBeat.Volume = 0
heartBeat:Play()

local damage2d = script.Parent.Damage2d
damage2d.BackgroundTransparency = 1
damage2d.ImageTransparency = 1

local threshold = 50 -- Effects appear below this amount of health

local prevHealth = humanoid.Health

if require(game.ReplicatedStorage.SPH_Assets.GameConfig).lowHealthEffects then

	local function UpdateHealthFX()
		local healthDiff = prevHealth - humanoid.Health
		if healthDiff > 15 then
			damage2d.ImageTransparency = 0
		end
		
		local health = humanoid.Health
		local scale = health / threshold
		
		if scale >= 1 or health <= 0 then
			tweenService:Create(damage2d,tweenInfo,{
				--BackgroundTransparency = 1,
				ImageTransparency = 1
			}):Play()
			tweenService:Create(heartBeat,tweenInfo,{
				Volume = 0
			}):Play()
			tweenService:Create(lightingFX,tweenInfo,{
				Brightness = 0,
				Contrast = 0,
				Saturation = 0
			}):Play()
		else
			tweenService:Create(damage2d,tweenInfo,{
				--BackgroundTransparency = transparency,
				ImageTransparency = scale
			}):Play()
			tweenService:Create(heartBeat,tweenInfo,{
				Volume = 1 - scale
			}):Play()
			tweenService:Create(lightingFX,tweenInfo,{
				Brightness = -0.2 + 0.2 * scale,
				Contrast = 0.2 - 0.2 * scale,
				Saturation = -1 + scale
			}):Play()
		end
	end

	humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		UpdateHealthFX()
		prevHealth = humanoid.Health
	end)

	UpdateHealthFX()
end
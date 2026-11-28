local tweenService = game:GetService("TweenService")

--
local easingStyle = Enum.EasingStyle.Linear
local easingDirection = Enum.EasingDirection.InOut
local repeats = 0
local reverse = true
local delayTime = 0
--

local function tweenModel(model, CF, tweenTime)
	local info = TweenInfo.new(tweenTime, easingStyle, easingDirection, repeats, reverse, delayTime)
	local CFrameValue = Instance.new("CFrameValue")
	CFrameValue.Value = model:GetPrimaryPartCFrame()

	CFrameValue:GetPropertyChangedSignal("Value"):Connect(function()
		model:SetPrimaryPartCFrame(CFrameValue.Value)
	end)

	local tween = tweenService:Create(CFrameValue, info, {Value = CF})
	tween:Play()

	tween.Completed:Connect(function()
		CFrameValue:Destroy()
	end)
end

repeat
	tweenModel(script.Parent.Cat, script.Parent.Handle_left.CFrame,script.Seconds.Value)
	wait(script.Seconds.Value+0.1)
	tweenModel(script.Parent.Cat, script.Parent.Handle_normal.CFrame,0.2)
	wait(0.2)
	tweenModel(script.Parent.Cat, script.Parent.Handle_right.CFrame,script.Seconds.Value)
	wait(script.Seconds.Value+0.1)
	tweenModel(script.Parent.Cat, script.Parent.Handle_normal.CFrame,0.2)
	wait(0.2)
until script.DoTween.Value == false
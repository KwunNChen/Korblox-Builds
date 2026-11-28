-- VARIABLES
local p = script.Parent
local h = p.THealth
local t = p:FindFirstChild('Team')

-- FUNCTIONS
local function onDeath()
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.Break:Play()
end

local function healthCheck()
	if h.Value <= h.MinValue then
		onDeath()
	end
end

-- EXECUTION
h:GetPropertyChangedSignal('Value'):Connect(healthCheck)
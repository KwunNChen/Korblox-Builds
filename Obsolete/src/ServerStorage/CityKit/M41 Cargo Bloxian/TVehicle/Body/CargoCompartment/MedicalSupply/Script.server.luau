-- VARIABLES
local SS = game:GetService('ServerStorage')

local Title = 'Medical Supplies'
local Tool = 'IFAK'
if not SS:FindFirstChild(Tool) then error('No '..Tool..' Found in ServerStorage for: '..script:GetFullName()) end

local AllowMultiple = false
local InStock = 200

local Prompt = script.Parent.ProximityPrompt
local Source = script.Parent.Parent

-- FUNCTIONS
local function CheckIfAlreadyExists(Player:Player)
	if AllowMultiple then return true end
	
	if Player.Backpack:FindFirstChild(Tool) then return false end
	if Player.Character:FindFirstChild(Tool) then return false end
	
	return true
end

local function PromptTriggered(Player:Player)
	local May = CheckIfAlreadyExists(Player)
	if not May then return end
	
 	SS[Tool]:Clone().Parent = Player.Backpack
	
	InStock -= 1
	Prompt.ObjectText = Title..' ['..tostring(InStock)..']'
	
	if InStock <= 0 then
		Source:Destroy()
	end
end

-- EXECUTION
Prompt.ObjectText = Title..' ['..tostring(InStock)..']'
Prompt.Triggered:Connect(PromptTriggered)
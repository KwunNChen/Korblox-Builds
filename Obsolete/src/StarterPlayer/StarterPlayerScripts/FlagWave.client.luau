--[[
	FlagWave

	Plays the flipbook flags: every model tagged "FlipbookFlag" holds numbered
	MeshPart frames (1..N), one visible at a time. Runs on each client, so the
	frame swaps are not replicated from the server.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local FPS = 24

local flags = {} -- [model] = {frames = {...}, shown = index, time = seconds}

local function add(model)
	local frames = {}
	for _, p in model:GetChildren() do
		local i = tonumber(p.Name)
		if i and p:IsA("BasePart") then frames[i] = p end
	end
	if #frames < 2 then return end
	for i, p in frames do p.Transparency = 1 end
	local start = math.random(1, #frames) -- flags out of step with each other
	frames[start].Transparency = 0
	flags[model] = {frames = frames, shown = start, time = 0}
end

local function remove(model)
	flags[model] = nil
end

CollectionService:GetInstanceAddedSignal("FlipbookFlag"):Connect(add)
CollectionService:GetInstanceRemovedSignal("FlipbookFlag"):Connect(remove)
for _, model in CollectionService:GetTagged("FlipbookFlag") do add(model) end

RunService.RenderStepped:Connect(function(dt)
	for model, f in flags do
		f.time += dt
		if f.time >= 1 / FPS then
			f.time = 0
			local nextIndex = f.shown % #f.frames + 1
			local a, b = f.frames[f.shown], f.frames[nextIndex]
			if a and b then
				a.Transparency = 1
				b.Transparency = 0
			end
			f.shown = nextIndex
		end
	end
end)

--[[
	Radiomen and the radio net.

	About one soldier in ten spawns as a radioman. Every soldier of his team
	within RADIO_RANGE of him is on his net, whatever squad they are in:

		Contacts   anything one of them spots or fires at, the whole net knows
		           about and can go after.
		Platoon    the squads link up into one formation. The radioman's squad
		           leads; every other squad's leader takes a slot in a wedge of
		           squads behind it, and his men follow him as usual.

	Settings.Role forces "Radioman" or "Rifleman"; "Random" rolls.
]]

local radioNet = {}

local modules = script.Parent
local log = require(modules.Troubleshoot).log
require(modules.UniformModule)

local marine = modules.Parent.Parent
local myRoot = marine.HumanoidRootPart
local mySettings = marine.Settings
local teamValue = mySettings.Team

--Chance a soldier spawns as the radioman when Settings.Role is "Random".
local RADIOMAN_CHANCE = 0.1

--How far a radioman's net reaches.
local RADIO_RANGE = 300

--Platoon formation: the gap between squads, side to side and front to back.
local PLATOON_SPACING = 30

local function chooseRole()
	local roleValue = mySettings:FindFirstChild("Role")
	local wanted = roleValue and roleValue.Value
	if wanted == "Radioman" or wanted == "Rifleman" then
		return wanted
	end
	return math.random() < RADIOMAN_CHANCE and "Radioman" or "Rifleman"
end

radioNet.role = chooseRole()
marine:SetAttribute("Role",radioNet.role)
log("role",radioNet.role)

local function soldiers()
	return _G.BloxianRadio or {}
end

local function onMyTeam(entry)
	return entry.root.Parent and entry.human.Health > 0 and entry.team.Value == teamValue.Value
end

--The radioman whose net this soldier is on: the nearest one in range (it can be
--himself), or nil.
function radioNet.myRadioman()
	local best,bestDist = nil,RADIO_RANGE
	for model,entry in pairs(soldiers()) do
		if model:GetAttribute("Role") == "Radioman" and onMyTeam(entry) then
			local dist = (entry.root.Position - myRoot.Position).Magnitude
			if dist <= bestDist then
				best,bestDist = model,dist
			end
		end
	end
	return best
end

function radioNet.inNet()
	return radioNet.myRadioman() ~= nil
end

--Everyone else on the same net.
function radioNet.netMembers()
	local radioman = radioNet.myRadioman()
	local radiomanEntry = radioman and soldiers()[radioman]
	if not radiomanEntry then return {} end

	local list = {}
	for model,entry in pairs(soldiers()) do
		if model ~= marine and onMyTeam(entry)
			and (entry.root.Position - radiomanEntry.root.Position).Magnitude <= RADIO_RANGE then
			list[#list+1] = entry
		end
	end
	return list
end

--Where this squad's leader belongs in the platoon, or nil when his squad is
--the one leading (the radioman's) or there is no net. Squads are ordered by
--squad id, so every leader works out the same slots.
function radioNet.platoonSlot(myEntry)
	local radioman = radioNet.myRadioman()
	local radiomanEntry = radioman and soldiers()[radioman]
	if not radiomanEntry then return nil end

	local hqId = radiomanEntry.squadId
	if not hqId or myEntry.squadId == hqId then return nil end

	local hqLeader = nil
	local squadIds,seen = {},{}
	for model,entry in pairs(soldiers()) do
		local unit = model:GetAttribute("Unit")
		if onMyTeam(entry) and entry.squadId and (unit == nil or unit == "Infantry")
			and (entry.root.Position - radiomanEntry.root.Position).Magnitude <= RADIO_RANGE then
			if entry.squadId == hqId then
				if not hqLeader or (entry.rank or 0) > (hqLeader.rank or 0) then
					hqLeader = entry
				end
			elseif not seen[entry.squadId] then
				seen[entry.squadId] = true
				squadIds[#squadIds+1] = entry.squadId
			end
		end
	end
	if not hqLeader then return nil end

	table.sort(squadIds,function(a,b) return a > b end)
	local k = table.find(squadIds,myEntry.squadId)
	if not k then return nil end

	--A wedge of squads behind the lead squad, facing the way it is walking.
	local root = hqLeader.root
	local velocity = Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z)
	local forward = velocity.Magnitude > 2 and velocity or Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z)
	if forward.Magnitude < 0.01 then forward = Vector3.new(0,0,-1) end
	local frame = CFrame.lookAt(root.Position,root.Position + forward.Unit)

	local row = math.ceil(k/2)
	local side = k % 2 == 1 and -1 or 1
	return frame:PointToWorldSpace(Vector3.new(side*PLATOON_SPACING*row,0,PLATOON_SPACING*row)),velocity.Magnitude > 2
end

return radioNet

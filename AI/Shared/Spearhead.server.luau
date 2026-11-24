--Spearhead guns damage this vehicle. Does nothing in a game without spearhead.
--One copy, built into each vehicle package (next to a Sides).

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local debris = game:GetService("Debris")

local assets = replicatedStorage:FindFirstChild("SPH_Assets")
if not assets then return end

--The folder spearhead's bullets treat as vehicles.
local VEHICLE_FOLDER = "Vehicles"
--Explosive rounds (RPG) multiply their damage by this against a vehicle, and
--ignore its SmallArmsScale.
local EXPLOSIVE_SCALE = 3
--Share of that damage a vehicle takes when only caught in the blast.
local EXPLOSIVE_SPLASH = 0.5
--How far (studs) a reported hit may be from the part it claims to hit.
local HIT_TOLERANCE = 3

local car = script.Parent
local human = car:FindFirstChildOfClass("Humanoid")
local bridgeNet = require(assets.Modules.BridgeNet)
local config = require(assets.GameConfig)
local bulletHit = bridgeNet.CreateBridge("BulletHit")

if car.Parent == workspace then
	local folder = workspace:FindFirstChild(VEHICLE_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = VEHICLE_FOLDER
		folder.Parent = workspace
	end
	car.Parent = folder
end

local sideOf = require(car:WaitForChild("Sides")).sideOf

local function crew()
	local list = {}
	for _,name in ipairs({"VehicleSeat","Seat"}) do
		local seat = car:FindFirstChild(name)
		local occupant = seat and seat.Occupant
		if occupant and occupant.Parent then
			table.insert(list,occupant.Parent)
		end
	end
	return list
end

local function canHurt(player)
	if human.Health <= 0 or car:GetAttribute("Wrecked") then return false end
	local side = sideOf(player.Character)
	local settings = car:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	if side and team and team.Value == side and not config.teamKill then return false end
	for _,member in ipairs(crew()) do
		if member == player.Character then return false end
		if side and sideOf(member) == side and not config.teamKill then return false end
		local memberSettings = member:FindFirstChild("Settings")
		local attackPlayers = memberSettings and memberSettings:FindFirstChild("AttackPlayers")
		if attackPlayers and not attackPlayers.Value and sideOf(member) ~= "Hostile" then return false end
	end
	return true
end

local function damage(player,amount)
	local creator = Instance.new("ObjectValue")
	creator.Name = "creator"
	creator.Value = player
	creator.Parent = human
	debris:AddItem(creator,2)
	human:TakeDamage(amount)
end

local function isOurs(hitPart)
	if hitPart:IsDescendantOf(car) then return true end
	local character = hitPart:FindFirstAncestorOfClass("Model")
	local victim = character and character:FindFirstChildOfClass("Humanoid")
	return victim ~= nil and victim.SeatPart ~= nil and victim.SeatPart:IsDescendantOf(car)
end

local function distanceTo(position)
	local box,size = car:GetBoundingBox()
	local offset = box:PointToObjectSpace(position)
	local half = size/2
	local outside = Vector3.new(
		math.max(math.abs(offset.X) - half.X,0),
		math.max(math.abs(offset.Y) - half.Y,0),
		math.max(math.abs(offset.Z) - half.Z,0)
	)
	return outside.Magnitude
end

local lastRound = {}

bulletHit:Connect(function(player,tool,rayResult)
	if typeof(tool) ~= "Instance" or not tool:FindFirstChild("SPH_Weapon") then return end
	if tool.Parent ~= player.Character and tool.Parent ~= player:FindFirstChild("Backpack") then return end
	if config.requireEquippedGun and tool.Parent ~= player.Character then return end
	if typeof(rayResult) ~= "table" or typeof(rayResult.Position) ~= "Vector3" then return end
	local hitPart = rayResult.Instance
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then return end
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head or (head.Position - rayResult.Position).Magnitude > config.maxBulletDistance then return end

	--One hit per round fired, explosive or not: a client cannot report the same round twice.
	local magAmmo = tool:FindFirstChild("Ammo") and tool.Ammo:FindFirstChild("MagAmmo")
	if config.ammoCountCheck and magAmmo then
		local round = tool.Name..magAmmo.Value
		if lastRound[player] == round then return end
		lastRound[player] = round
	end

	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	local amount = wepStats.damage.Other or 0
	local hitUs = isOurs(hitPart)

	if wepStats.explosiveAmmo then
		local reach = distanceTo(rayResult.Position)
		if not hitUs and reach > (wepStats.explosionRadius or 0) then return end
		if not canHurt(player) then return end
		amount *= EXPLOSIVE_SCALE
		damage(player,hitUs and amount or amount*EXPLOSIVE_SPLASH*(1 - reach/wepStats.explosionRadius))
		return
	end

	if not hitUs then return end
	if hitPart.Parent == car then return end
	local offset = hitPart.CFrame:PointToObjectSpace(rayResult.Position)
	local half = hitPart.Size/2 + Vector3.one*HIT_TOLERANCE
	if math.abs(offset.X) > half.X or math.abs(offset.Y) > half.Y or math.abs(offset.Z) > half.Z then return end
	if not canHurt(player) then return end
	damage(player,amount*(car:GetAttribute("SmallArmsScale") or 1))
end)

players.PlayerRemoving:Connect(function(player)
	lastRound[player] = nil
end)

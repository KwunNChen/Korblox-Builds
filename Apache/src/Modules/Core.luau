local core = {}

local myModel = script.Parent.Parent
local myRoot = myModel.HumanoidRootPart
local mySettings = script.Parent.Parent.Settings

local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local debrisService = game:GetService("Debris")

function core.checkDist(pos1,pos2)
	if typeof(pos1) ~= "Vector3" then pos1 = pos1.Position end
	if typeof(pos2) ~= "Vector3" then pos2 = pos2.Position end
	return (pos1-pos2).Magnitude
end

function core.checkDistXZ(pos1,pos2)
	if typeof(pos1) ~= "Vector3" then pos1 = pos1.Position end
	if typeof(pos2) ~= "Vector3" then pos2 = pos2.Position end
	pos1 = Vector2.new(pos1.X,pos1.Z)
	pos2 = Vector2.new(pos2.X,pos2.Z)
	return (pos1-pos2).Magnitude
end

--What a hit part belongs to: a vehicle (also when the part is someone seated
--in one), or a character.
function core.vehicleOf(instance)
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if collectionService:HasTag(model,"BloxianVehicle") or collectionService:HasTag(model,"MarineVehicle") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function core.ownerOf(part)
	local car = core.vehicleOf(part)
	if car then
		return car,car:FindFirstChildOfClass("Humanoid"),true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local human = model:FindFirstChildOfClass("Humanoid")
		if human then
			car = human.SeatPart and core.vehicleOf(human.SeatPart)
			if car then
				return car,car:FindFirstChildOfClass("Humanoid"),true
			end
			return model,human,false
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--The character or vehicle a target part stands for.
function core.modelOf(target)
	return core.vehicleOf(target) or target.Parent
end

function core.humanOf(target)
	local model = target and target.Parent and core.modelOf(target)
	return model and model:FindFirstChildOfClass("Humanoid")
end

function core.crewOf(car)
	local crew = {}
	for _,name in ipairs({"VehicleSeat","Seat"}) do
		local seat = car:FindFirstChild(name)
		local occupant = seat and seat.Occupant
		if occupant and occupant.Parent and occupant.Health > 0 then
			table.insert(crew,occupant.Parent)
		end
	end
	return crew
end

--Crewed by an enemy and by no friend, or kept to another team.
function core.isHostile(car)
	local crew = core.crewOf(car)
	for _,member in ipairs(crew) do
		if core.checkTeam(member) then
			return false
		end
	end
	if #crew > 0 then
		return true
	end
	local settings = car:FindFirstChild("Settings")
	local team = settings and settings:FindFirstChild("Team")
	return team ~= nil and team.Value ~= "" and (mySettings.Team.FFA.Value or team.Value ~= mySettings.Team.Value)
end

--Bullets (bullet true) are cut by a vehicle's SmallArmsScale; missiles are not.
function core.damage(part,dmg,bullet)
	local owner,human,isVehicle = core.ownerOf(part)
	if not owner or owner == myModel or not human or human.Health <= 0 then return false end
	if isVehicle then
		if not core.isHostile(owner) or owner:GetAttribute("Wrecked") then return false end
		if bullet then
			dmg = dmg*(owner:GetAttribute("SmallArmsScale") or 1)
		end
	elseif core.checkTeam(owner) then
		return false
	end
	human:TakeDamage(dmg)
	return true
end

--Everyone and every vehicle within radius takes dmg once. Drawn by Effects,
--with no Roblox Explosion, so terrain is never cratered.
function core.blast(position,radius,dmg,kind)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myModel}
	local done = {}
	for _,part in ipairs(workspace:GetPartBoundsInRadius(position,radius,params)) do
		local owner = core.ownerOf(part)
		if owner and not done[owner] then
			done[owner] = true
			core.damage(part,dmg)
		end
	end
	local vehicleFx = myModel:FindFirstChild("VehicleFx")
	if vehicleFx then
		vehicleFx:FireAllClients(kind or "impact",position)
	end
end

local function consider(obj,seen,best)
	if seen[obj] or obj == myModel or not obj:IsA("Model") then return end
	seen[obj] = true
	local human = obj:FindFirstChild("Humanoid")
	local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
	if not human or human.Health <= 0 or not root then return end

	--Someone in a vehicle is fought as the vehicle.
	local car = human.SeatPart and core.vehicleOf(human.SeatPart)
	if car then
		local carHuman = car:FindFirstChildOfClass("Humanoid")
		local aim = car.PrimaryPart or root
		if not seen[car] and carHuman and carHuman.Health > 0 and not car:GetAttribute("Wrecked") and core.isHostile(car) then
			seen[car] = true
			local newDist = core.checkDist(myRoot,aim)
			if newDist < best.dist then
				best.dist = newDist
				best.target = aim
			end
		end
		return
	end

	if core.checkTeam(obj) then return end

	--Check if target is outside
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {obj}
	local result = workspace:Raycast(root.Position,Vector3.new(0,200,0),rayParams)

	local newDist = core.checkDist(myRoot,root)
	if newDist < best.dist and not result then
		best.dist = newDist
		best.target = root
	end
end

--Players, every Bloxian (even inside folders) and anything else with a
--Humanoid at the top of Workspace.
function core.findTarget()
	local seen = {}
	local best = {dist = mySettings.Distance.Value}
	for _,player in ipairs(players:GetPlayers()) do
		if player.Character then
			consider(player.Character,seen,best)
		end
	end
	for soldier in pairs(_G.BloxianRadio or {}) do
		if soldier.Parent then
			consider(soldier,seen,best)
		end
	end
	for _,obj in ipairs(workspace:GetChildren()) do
		consider(obj,seen,best)
	end
	return best.target
end

function core.checkSight(target,ignoredInstance)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {myModel,ignoredInstance}
	local result = workspace:Raycast(myModel.Head.Position,(target.Position - myModel.Head.Position).Unit*500,raycastParams)
	if result and result.Instance.Parent then
		if result.Instance:IsDescendantOf(core.modelOf(target)) then
			return true
		else
			local human = result.Instance.Parent:FindFirstChild("Humanoid")
			if human and human.Health>0 then
				return true
			end
		end
	end
	return false
end

function core.checkTeam(char)

	--If Free For All is enabled don't bother checking for team values.
	if mySettings.Team.FFA.Value then
		return false
	end

	local player = players:GetPlayerFromCharacter(char)
	if player then
		--If AttackPlayers is disabled consider all players on their team.
		if not mySettings.AttackPlayers.Value then
			return true
		end
		--Players on the Roblox team named in Settings.Team are on its side.
		return not player.Neutral and player.Team ~= nil and player.Team.Name == mySettings.Team.Value
	end

	for i,v in ipairs(char:GetDescendants()) do
		if v.Name == "Team" and v:IsA("StringValue") then
			if v.Value == mySettings.Team.Value then
				return true
			end
		end
	end
	return false
end

--Calculates an angle in relation to another part.
function core.findAngle(pos1,pos2,part)
	local yOrientation = part.Orientation.Y
	local rot = math.atan2(pos2.Z-pos1.Z, pos2.X-pos1.X)


	local desiredAngle = math.deg(rot)+yOrientation+90
	if desiredAngle > 180 then
		desiredAngle = -(360-desiredAngle)
	elseif desiredAngle <-180 then
		desiredAngle = 360+desiredAngle
	end	

	return desiredAngle
end

function core.findPitch(pos1,pos2,part)
	local xOrientation = part.Orientation.X
	local rot = math.atan2(pos2.Y-pos1.Y, math.abs(pos2.Z-pos1.Z))
	
	local desiredAngle = math.deg(rot)+xOrientation
	if desiredAngle > 180 then
		desiredAngle = -(360-desiredAngle)
	elseif desiredAngle <-180 then
		desiredAngle = 360+desiredAngle
	end	

	return desiredAngle
end

function core.tempAttach(pos,life)
	local attach = Instance.new("Attachment")
	attach.WorldPosition = pos
	attach.Parent = workspace.Terrain
	
	debrisService:AddItem(attach,life)
	
	return attach
end

function core.playSound(sound,pos)
	local attach = core.tempAttach(pos,sound.TimeLength)
	local soundClone = sound:Clone()
	soundClone.Parent = attach
	soundClone:Play()
end




return core

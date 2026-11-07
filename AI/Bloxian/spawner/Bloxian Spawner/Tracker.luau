--[[
	The Track all tags: one over every aircraft and vehicle, and one over every
	unit, drawn on this client through walls. The spawner tool's panel turns it on
	and off. style is the panel's look and helpers; onRefresh runs after each
	refresh, for the panel's count.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--Seconds between tracker refreshes.
local TRACK_INTERVAL = 0.2

--Soldiers, the aircraft (Phantoms, AC-130s, Apaches) and the land vehicles,
--and what an aircraft's tag is shown as (a land vehicle shows its name).
local TRACKED_TAGS = {"Bloxian","BloxianJet","BloxianGunship","BloxianAircraft","BloxianVehicle","MarineVehicle"}
local AIRCRAFT_NAMES = {BloxianJet = "F-4 Phantom",BloxianGunship = "AC-130",BloxianAircraft = "Apache"}
local VEHICLE_TAGS = {"BloxianVehicle","MarineVehicle"}
--How far above an aircraft's or a vehicle's root its tag floats (studs).
local AIRCRAFT_TAG_HEIGHT = 14
local VEHICLE_TAG_HEIGHT = 9
local TRACKER_NAME = "BloxianTracker"

--NATO unit-size mark for each echelon (the unit's SquadEchelon).
local ECHELON_MARKS = {["Fire team"] = "Ø", Squad = "●", Section = "●●", Platoon = "●●●", ["SOF Fireteam"] = "Ø", Recce = "Ø"}
--A sniper or AT team's mark and how many men it starts with.
local PAIR_MARK = "Ø"
local PAIR_SIZE = 2
--How far above the middle of a squad its tag floats (studs).
local SQUAD_TAG_HEIGHT = 35

return function(style,onRefresh)
	local make,outline,teamColor = style.make,style.outline,style.teamColor
	local BOX,BOX_TRANSPARENCY,INK,INK_DIM,DANGER = style.BOX,style.BOX_TRANSPARENCY,style.INK,style.INK_DIM,style.DANGER
	local BOLD,MONO = style.BOLD,style.MONO

	local trackers = {}
	local trackConnections = {}
	local trackRun = 0

	local function untrack(model)
		local tracker = trackers[model]
		if tracker then
			tracker:Destroy()
			trackers[model] = nil
		end
	end

	--What a machine is tracked as, and whether it flies. nil for a soldier.
	local function machineName(model)
		for tag,name in pairs(AIRCRAFT_NAMES) do
			if model:HasTag(tag) then
				return name,true
			end
		end
		for _,tag in ipairs(VEHICLE_TAGS) do
			if model:HasTag(tag) then
				return model.Name,false
			end
		end
		return nil
	end

	--The most AirHealth each plane has been seen with, for its health bar.
	local airHealthMax = setmetatable({},{__mode = "k"})

	local function track(model)
		if trackers[model] or not model:IsDescendantOf(workspace) then
			return
		end
		local name,flies = machineName(model)
		local machine = name ~= nil
		--A model can arrive before its parts stream in, or lose them streaming out:
		--the refresh points the tag at whatever is there now.
		local anchor = if machine then model.PrimaryPart else model:FindFirstChild("Head")

		--Hidden until the first refresh has filled it in and found where it goes.
		local tracker = make("BillboardGui",{
			Name = TRACKER_NAME,
			Adornee = anchor,
			Enabled = false,
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = math.huge,
			ResetOnSpawn = false,
			Size = UDim2.fromOffset(150,48),
			StudsOffsetWorldSpace = Vector3.new(0,if not machine then 2.6 elseif flies then AIRCRAFT_TAG_HEIGHT else VEHICLE_TAG_HEIGHT,0),
		},nil)

		local box = make("Frame",{
			Name = "Box",
			Size = UDim2.fromScale(1,1),
			BackgroundColor3 = BOX,
			BackgroundTransparency = BOX_TRANSPARENCY,
			BorderSizePixel = 0,
		},tracker)
		outline(box,1,0.4)
		make("Frame",{
			Name = "Swatch",
			Position = UDim2.fromOffset(8,8),
			Size = UDim2.fromOffset(8,8),
			BorderSizePixel = 0,
		},box)
		make("TextLabel",{
			Name = "Title",
			Text = "",
			Position = UDim2.fromOffset(22,3),
			Size = UDim2.new(1,-28,0,18),
			BackgroundTransparency = 1,
			FontFace = BOLD,
			TextSize = 12,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		},box)
		make("TextLabel",{
			Name = "Detail",
			Text = "",
			Position = UDim2.fromOffset(8,20),
			Size = UDim2.new(1,-16,0,16),
			BackgroundTransparency = 1,
			FontFace = MONO,
			TextSize = 12,
			TextColor3 = INK_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
		},box)
		local bar = make("Frame",{
			Name = "Health",
			Position = UDim2.new(0,8,1,-9),
			Size = UDim2.new(1,-16,0,3),
			BackgroundColor3 = Color3.fromRGB(60,60,60),
			BorderSizePixel = 0,
		},box)
		make("Frame",{
			Name = "Fill",
			Size = UDim2.fromScale(1,1),
			BorderSizePixel = 0,
		},bar)

		tracker.Parent = playerGui
		trackers[model] = tracker
	end

	--Who is in a vehicle's seats: how many, and the team of the first.
	local function crewOf(model)
		local count,team = 0,nil
		for _,seatName in ipairs({"VehicleSeat","Seat"}) do
			local seat = model:FindFirstChild(seatName)
			local occupant = seat and seat.Occupant
			if occupant and occupant.Health > 0 then
				count += 1
				local crewSettings = occupant.Parent and occupant.Parent:FindFirstChild("Settings")
				local crewTeam = crewSettings and crewSettings:FindFirstChild("Team")
				local player = Players:GetPlayerFromCharacter(occupant.Parent)
				team = team or (crewTeam and crewTeam.Value ~= "" and crewTeam.Value) or (player and player.Team and player.Team.Name)
			end
		end
		return count,team
	end

	--An aircraft's or vehicle's tag: its team, what it is, what it is doing and how far off.
	local function refreshMachine(model,tracker,kind,flies)
		local root = model.PrimaryPart
		local human = model:FindFirstChildOfClass("Humanoid")
		local down = model:GetAttribute("ShotDown") or model:GetAttribute("Wrecked") or (human and human.Health <= 0)
		tracker.Adornee = root
		tracker.Enabled = root ~= nil and model:IsDescendantOf(workspace)
		if not tracker.Enabled then
			return
		end

		local crew,crewTeam = crewOf(model)
		local settings = model:FindFirstChild("Settings")
		local teamValue = settings and settings:FindFirstChild("Team")
		local teamName = model:GetAttribute("Team") or crewTeam or (teamValue and teamValue.Value ~= "" and teamValue.Value)
			or (model:HasTag("BloxianJet") and "Friendly") or "Any"
		local color = down and DANGER or teamColor(teamName)

		local status = model:GetAttribute("Status")
		if down then
			status = flies and "Down" or "Wrecked"
		elseif not status then
			if model:GetAttribute("OnMission") then
				status = "Fire mission"
			elseif model:HasTag("BloxianGunship") then
				status = "On station"
			elseif flies and crew == 0 and human then
				status = "Empty"
			elseif flies then
				status = "Flying"
			else
				status = crew == 0 and "Empty" or ("Crew "..crew)
			end
		end

		local camera = workspace.CurrentCamera
		local distance = camera and math.floor((camera.CFrame.Position - root.Position).Magnitude) or 0

		local box = tracker.Box
		box.Swatch.BackgroundColor3 = color
		box.Title.Text = string.upper(teamName.." / "..kind)
		box.Detail.Text = string.format("%-10s%5dM",string.upper(status),distance)
		box.Health.Fill.BackgroundColor3 = color
		local airHealth = model:GetAttribute("AirHealth")
		if airHealth then
			airHealthMax[model] = math.max(airHealthMax[model] or 0,airHealth)
		end
		local health = if down then 0
			elseif human then human.Health/human.MaxHealth
			elseif airHealth then airHealth/math.max(airHealthMax[model],1)
			else 1
		box.Health.Fill.Size = UDim2.fromScale(math.clamp(health,0,1),1)
	end

	local function refreshTracker(model,tracker)
		local kind,flies = machineName(model)
		if kind then
			refreshMachine(model,tracker,kind,flies)
			return
		end
		--Soldiers have no tag of their own: their unit's tag, or their vehicle's, stands for them.
		local human = model:FindFirstChildOfClass("Humanoid")
		tracker:SetAttribute("Alive",human ~= nil and human.Health > 0 and model:IsDescendantOf(workspace))
		tracker.Enabled = false
	end

	--One tag per squad (by SquadId) high over the middle of its soldiers on foot:
	--its NATO size mark above its name and strength. Anyone seated in a vehicle
	--still counts toward the squad but is left out of where the tag sits.
	--squadTags[id] = {gui, anchor (an invisible client-side part), heads}
	local squadTags = {}

	local function newSquadTag()
		local anchor = make("Part",{
			Name = "BloxianSquadAnchor",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
			Size = Vector3.new(0.2,0.2,0.2),
		},workspace.CurrentCamera)
		local tag = make("BillboardGui",{
			Name = TRACKER_NAME,
			Adornee = anchor,
			Enabled = false,
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = math.huge,
			ResetOnSpawn = false,
			Size = UDim2.fromOffset(160,42),
			StudsOffsetWorldSpace = Vector3.new(0,SQUAD_TAG_HEIGHT,0),
		},nil)
		local box = make("Frame",{
			Name = "Box",
			Size = UDim2.fromScale(1,1),
			BackgroundColor3 = BOX,
			BackgroundTransparency = BOX_TRANSPARENCY,
			BorderSizePixel = 0,
		},tag)
		outline(box,1,0.4)
		make("TextLabel",{
			Name = "Mark",
			Position = UDim2.fromOffset(0,3),
			Size = UDim2.new(1,0,0,18),
			BackgroundTransparency = 1,
			FontFace = BOLD,
			TextSize = 16,
			Text = "",
		},box)
		make("TextLabel",{
			Name = "Label",
			Position = UDim2.fromOffset(0,21),
			Size = UDim2.new(1,0,0,16),
			BackgroundTransparency = 1,
			FontFace = MONO,
			TextSize = 12,
			Text = "",
		},box)
		tag.Parent = playerGui
		return {gui = tag, anchor = anchor, heads = {}}
	end

	local function dropSquadTag(id)
		local entry = squadTags[id]
		entry.gui:Destroy()
		entry.anchor:Destroy()
		squadTags[id] = nil
	end

	--Every frame: each tag's anchor to the middle of its squad's heads.
	local function placeSquadTags()
		for _,entry in pairs(squadTags) do
			local sum,count = Vector3.zero,0
			for _,head in ipairs(entry.heads) do
				if head.Parent then
					sum += head.Position
					count += 1
				end
			end
			entry.gui.Enabled = count > 0
			if count > 0 then
				entry.anchor.CFrame = CFrame.new(sum/count)
			end
		end
	end

	--Every refresh: who is in each squad, and its mark, name and strength.
	local function refreshSquads()
		local squads = {}
		for model,tracker in pairs(trackers) do
			local id = (tracker.Enabled or tracker:GetAttribute("Alive"))
				and (model:GetAttribute("TeamLabel") or model:GetAttribute("SquadName") and model:GetAttribute("SquadId"))
			local human = id and model:FindFirstChildOfClass("Humanoid")
			local head = human and model:FindFirstChild("Head")
			if head then
				local squad = squads[id]
				if not squad then
					squad = {alive = 0,heads = {},model = model}
					squads[id] = squad
				end
				squad.alive += 1
				if not human.SeatPart then
					squad.heads[#squad.heads+1] = head
				end
			end
		end

		for id in pairs(squadTags) do
			if not squads[id] then
				dropSquadTag(id)
			end
		end

		for id,squad in pairs(squads) do
			local entry = squadTags[id] or newSquadTag()
			squadTags[id] = entry
			entry.heads = squad.heads

			local model = squad.model
			local echelon = model:GetAttribute("SquadEchelon") or "Squad"
			local settings = model:FindFirstChild("Settings")
			local teamValue = settings and settings:FindFirstChild("Team")
			local label = model:GetAttribute("TeamLabel")
			local size = label and PAIR_SIZE or model:GetAttribute("SquadSize") or squad.alive
			local strength = math.floor(squad.alive/math.max(size,1)*100 + 0.5)
			local box = entry.gui.Box
			box.Mark.Text = label and PAIR_MARK or ECHELON_MARKS[echelon] or ""
			box.Mark.TextColor3 = teamColor(teamValue and teamValue.Value or "?")
			if label then
				box.Label.Text = string.format("%s %d%%",string.upper(label),strength)
			else
				local number = model:GetAttribute("SquadNumber")
				local name = string.upper(model:GetAttribute("SquadName"))
				box.Label.Text = string.format("%s %s%s %d%%",name,string.upper(echelon),number and " "..number or "",strength)
			end
			box.Label.TextColor3 = model:GetAttribute("Demoralized") and DANGER or INK
		end
	end

	local function stopTracking()
		trackRun += 1
		for id in pairs(squadTags) do
			dropSquadTag(id)
		end
		for _,connection in ipairs(trackConnections) do
			connection:Disconnect()
		end
		table.clear(trackConnections)
		for model in pairs(trackers) do
			untrack(model)
		end
	end

	local function startTracking()
		stopTracking()
		for _,tag in ipairs(TRACKED_TAGS) do
			for _,model in ipairs(CollectionService:GetTagged(tag)) do
				track(model)
			end
			table.insert(trackConnections,CollectionService:GetInstanceAddedSignal(tag):Connect(track))
			table.insert(trackConnections,CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack))
		end
		table.insert(trackConnections,RunService.RenderStepped:Connect(placeSquadTags))

		local run = trackRun
		task.spawn(function()
			while run == trackRun and script.Parent do
				for model,tracker in pairs(trackers) do
					if model.Parent then
						refreshTracker(model,tracker)
					else
						untrack(model)
					end
				end
				refreshSquads()
				onRefresh()
				task.wait(TRACK_INTERVAL)
			end
		end)
	end

	--Tracking stays on through respawns; the last life's tags are left over in PlayerGui.
	for _,leftover in ipairs(playerGui:GetChildren()) do
		if leftover.Name == TRACKER_NAME then
			leftover:Destroy()
		end
	end

	return {
		start = startTracking,
		stop = stopTracking,
		alive = function()
			local count = 0
			for _,tracker in pairs(trackers) do
				if tracker.Enabled or tracker:GetAttribute("Alive") then
					count += 1
				end
			end
			return count
		end,
	}
end

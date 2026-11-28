-- Team morphs: a player whose team has a folder in ServerStorage.TeamMorphs gets its clothes, skin
-- and gear. Gear is in SPH "conventional morph" models (named after a body part, welded via Middle)
-- so SPH's first-person view shows torso gear and hides head gear. The player keeps hair and face.
local Players = game:GetService("Players")
local morphs = game:GetService("ServerStorage"):WaitForChild("TeamMorphs")

-- Random human skin per spawn: team name -> { colour, weight } (weights are relative odds)
local SKIN_TONES = {
	["Bloxian Commonwealth"] = {
		{ Color3.fromRGB(234, 184, 146), 35 }, -- light
		{ Color3.fromRGB(204, 142, 105), 35 }, -- tan
		{ Color3.fromRGB(160, 102, 68), 15 }, -- brown
		{ Color3.fromRGB(117, 72, 45), 10 }, -- dark brown
		{ Color3.fromRGB(78, 50, 34), 5 }, -- deep brown
	},
}

local function pickTone(tones): Color3
	local total = 0
	for _, t in tones do total += t[2] end
	local r = math.random() * total
	for _, t in tones do
		r -= t[2]
		if r <= 0 then return t[1] end
	end
	return tones[#tones][1]
end

local function apply(char: Model, morph: Instance)
	for _, c in char:GetChildren() do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") or c:IsA("BodyColors")
			or (c:IsA("Accessory") and c.AccessoryType ~= Enum.AccessoryType.Hair) then
			c:Destroy()
		end
	end
	for _, item in morph:GetChildren() do
		if item:IsA("Model") then
			local partName = item.Name:gsub("Gear$", "")
			local body = char:FindFirstChild(partName)
				or (partName == "Torso" and char:FindFirstChild("UpperTorso"))
			if not body then continue end
			local m = item:Clone()
			m:PivotTo(body.CFrame)
			local w = Instance.new("WeldConstraint")
			w.Part0 = body; w.Part1 = m.Middle; w.Parent = m.Middle
			m.Parent = char
		else
			local c = item:Clone()
			local tones = SKIN_TONES[morph.Name]
			if tones and c:IsA("BodyColors") then
				local tone = pickTone(tones)
				c.HeadColor3, c.TorsoColor3, c.LeftArmColor3, c.RightArmColor3, c.LeftLegColor3, c.RightLegColor3 =
					tone, tone, tone, tone, tone, tone
			end
			c.Parent = char
		end
	end
end

-- Medical's Studio test dummies wear a team's morph too: ServerStorage.ApplyTeamMorph:Invoke(model, teamName)
local applyFn = Instance.new("BindableFunction")
applyFn.Name = "ApplyTeamMorph"
applyFn.OnInvoke = function(char: Model, teamName: string)
	local morph = morphs:FindFirstChild(teamName)
	if morph then apply(char, morph) end
end
applyFn.Parent = game:GetService("ServerStorage")

-- CharacterAppearanceLoaded, not CharacterAdded: on respawn HasAppearanceLoaded() is still true from
-- the old body, so the avatar would load after the morph and overwrite its skin and clothes.
local function onAppearance(player: Player, char: Model)
	local morph = player.Team and morphs:FindFirstChild(player.Team.Name)
	if morph and char.Parent then apply(char, morph) end
end

local function onPlayer(player: Player)
	player.CharacterAppearanceLoaded:Connect(function(char) onAppearance(player, char) end)
	if player.Character and player:HasAppearanceLoaded() then task.spawn(onAppearance, player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end

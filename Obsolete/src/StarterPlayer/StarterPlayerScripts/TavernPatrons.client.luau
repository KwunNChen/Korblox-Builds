-- Tavern patrons: local-only life for the staging NPCs (workspace.Staging.Patrons).
-- Roblox R6 stock anims for the base pose; eating/drinking/talking are Motor6D C0 offsets layered on top.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local staging = workspace:WaitForChild("Staging")
local FOLDERS = { "Patrons", "StagingSoldiers" } -- civilians + the Korblox squad gearing up

local ANIM = {
	sit = "rbxassetid://178130996",
	idle = "rbxassetid://180435571",
	laugh = "rbxassetid://129423131",
	cheer = "rbxassetid://129423030",
	point = "rbxassetid://128853357",
}
local rad = math.rad
local ACTIVE_RANGE = 160 -- only animate while someone is near the tavern

local function track(hum, id, prio, looped)
	local a = Instance.new("Animation")
	a.AnimationId = id
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local t = animator:LoadAnimation(a)
	t.Priority = prio
	t.Looped = looped
	return t
end

local function tweenC0(joint, base, offset, time)
	TweenService:Create(joint, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { C0 = base * offset }):Play()
end

local function near(model)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	local p = model:GetPivot().Position
	return (root and (root.Position - p).Magnitude < ACTIVE_RANGE) or (cam and (cam.CFrame.Position - p).Magnitude < ACTIVE_RANGE)
end

local function setup(m)
	local hum = m:WaitForChild("Humanoid", 10)
	local torso = m:WaitForChild("Torso", 10)
	if not (hum and torso) then return end
	local rs, ls, neck = torso:WaitForChild("Right Shoulder", 10), torso:WaitForChild("Left Shoulder", 10), torso:WaitForChild("Neck", 10)
	if not (rs and ls and neck) then return end
	local rs0, ls0, neck0 = rs.C0, ls.C0, neck.C0
	local seated = m:GetAttribute("Seated") == true
	local role = m:GetAttribute("Role")
	local rng = Random.new(#m.Name * 7919 + (tonumber(m.Name:match("%d+")) or 0))

	local base = track(hum, seated and ANIM.sit or ANIM.idle, Enum.AnimationPriority.Idle, true)
	base:Play(0)
	local gestures = { track(hum, ANIM.laugh, Enum.AnimationPriority.Action, false), track(hum, ANIM.point, Enum.AnimationPriority.Action, false) }
	if not seated then table.insert(gestures, track(hum, ANIM.cheer, Enum.AnimationPriority.Action, false)) end
	if role ~= "Talk" or seated then gestures = {} end -- emotes move the legs (through the chair) and swing the mug arm

	-- arm angles are absolute degrees forward from hanging; the R6 sit anim already holds arms out at 90
	local BASE = seated and 90 or 0
	local function raise(deg, roll)
		return CFrame.Angles(rad(roll or 0), 0, rad(deg - BASE))
	end
	local REST = raise(role == "Drink" and 75 or role == "Polish" and 55 or role == "Read" and 75 or role == "Hold" and 20 or (seated and 80 or 45)) -- keep in sync with the mug grip angle (TavernPatrons build)
	local MOUTH = raise(140, -20)
	if role ~= "Talk" then tweenC0(rs, rs0, REST, 0.01) end
	if seated and role == "Talk" then tweenC0(rs, rs0, raise(70), 0.01) end
	local LREST = role == "Polish" and 50 or role == "Read" and 70 or (seated and 70 or 0)
	local LDOWN = CFrame.Angles(0, 0, -rad(LREST - BASE))
	tweenC0(ls, ls0, LDOWN, 0.01)

	local function look(yawDeg, pitchDeg, t)
		tweenC0(neck, neck0, CFrame.Angles(rad(pitchDeg), 0, rad(yawDeg)), t)
	end

	task.wait(rng:NextNumber(0, 4)) -- desync the crowd
	while m.Parent do
		if not near(m) then
			task.wait(2)
		else
			local roll = rng:NextNumber()
			if role == "Polish" then
				-- rub the blade with the free hand, now and then hold it up to check it
				look(-8, -28, 0.5)
				if roll < 0.7 then
					-- rag strokes along the blade: hand slides out to the tip and back, knife hand turns with it
					for _ = 1, rng:NextInteger(5, 9) do
						tweenC0(ls, ls0, CFrame.Angles(rad(-30), 0, -rad(48)), 0.35)
						tweenC0(rs, rs0, raise(52, 8), 0.35)
						task.wait(0.37)
						tweenC0(ls, ls0, CFrame.Angles(rad(-5), 0, -rad(72)), 0.35)
						tweenC0(rs, rs0, raise(58, -4), 0.35)
						task.wait(0.37)
					end
					tweenC0(ls, ls0, LDOWN, 0.4)
					tweenC0(rs, rs0, REST, 0.4)
				else
					-- hold it up to the light, turn it over, back to work
					tweenC0(ls, ls0, CFrame.Angles(0, 0, -rad(15)), 0.5)
					tweenC0(rs, rs0, raise(115, -25), 0.7) look(12, 25, 0.7) task.wait(0.9)
					tweenC0(rs, rs0, raise(115, 15), 0.5) task.wait(0.8)
					tweenC0(rs, rs0, REST, 0.6) tweenC0(ls, ls0, LDOWN, 0.6)
				end
			elseif role == "Read" then
				-- head in the briefing; flip a page or glance up at the others
				look(0, -22, 0.6)
				if roll < 0.45 then
					-- run a finger down the page, then flip it
					for _ = 1, rng:NextInteger(2, 4) do
						tweenC0(ls, ls0, CFrame.Angles(rad(-20), 0, -rad(70)), 0.5) look(-4, -26, 0.5) task.wait(0.55)
						tweenC0(ls, ls0, CFrame.Angles(rad(-12), 0, -rad(58)), 0.5) look(4, -18, 0.5) task.wait(0.55)
					end
					tweenC0(ls, ls0, CFrame.Angles(rad(-45), 0, -rad(85)), 0.3) task.wait(0.35)
					tweenC0(ls, ls0, LDOWN, 0.4) task.wait(0.4)
				elseif roll < 0.8 then
					-- lower the board and brief whoever is across the table, tapping it
					tweenC0(rs, rs0, raise(40), 0.5) look(rng:NextNumber(-30, 30), 4, 0.5)
					for _ = 1, rng:NextInteger(2, 4) do
						tweenC0(ls, ls0, CFrame.Angles(rad(-10), 0, -rad(rng:NextNumber(50, 90))), 0.4) task.wait(rng:NextNumber(0.5, 0.9))
					end
					tweenC0(rs, rs0, REST, 0.5) tweenC0(ls, ls0, LDOWN, 0.5) look(0, -22, 0.5)
				else
					tweenC0(rs, rs0, raise(78), 1.2) look(0, -10, 1.2) task.wait(1.4) tweenC0(rs, rs0, REST, 1) -- bring it up close
				end
			elseif role ~= "Talk" and role ~= "Hold" and roll < 0.45 then
				-- bite / sip
				local bites = role == "Eat" and rng:NextInteger(1, 3) or 1
				for _ = 1, bites do
					tweenC0(rs, rs0, MOUTH, 0.6)
					look(0, role == "Drink" and 18 or -6, 0.6)
					task.wait(role == "Drink" and rng:NextNumber(1.2, 2.2) or 0.7)
					tweenC0(rs, rs0, REST, 0.6)
					look(0, 0, 0.6)
					task.wait(0.7)
				end
			elseif roll < 0.8 or #gestures == 0 then
				-- turn to a neighbour and talk: head turns, free hand gestures
				local yaw = rng:NextNumber(-55, 55)
				look(yaw, rng:NextNumber(-5, 8), 0.5)
				for _ = 1, rng:NextInteger(2, 4) do
					tweenC0(ls, ls0, CFrame.Angles(rad(rng:NextNumber(-15, 15)), 0, -rad(rng:NextNumber(35, 95) - BASE)), 0.45)
					if role == "Talk" then tweenC0(rs, rs0, raise(rng:NextNumber(30, 85)), 0.45) end
					task.wait(rng:NextNumber(0.5, 1.1))
				end
				tweenC0(ls, ls0, LDOWN, 0.6)
				if #gestures == 0 and rng:NextNumber() < 0.35 then
					for _ = 1, rng:NextInteger(3, 5) do look(0, 16, 0.15) task.wait(0.18) look(0, 6, 0.15) task.wait(0.18) end
					look(0, 0, 0.4)
				end
				if role == "Talk" then tweenC0(rs, rs0, raise(seated and 70 or 0), 0.6) end
			else
				-- laugh / point / cheer
				local g = gestures[rng:NextInteger(1, #gestures)]
				g:Play(0.2)
				task.wait(g.Length > 0 and g.Length or 1.5)
				look(0, 0, 0.6)
			end
			task.wait(rng:NextNumber(1.5, 4))
		end
	end
end

for _, name in FOLDERS do
	local folder = staging:WaitForChild(name)
	for _, m in ipairs(folder:GetChildren()) do task.spawn(setup, m) end
	folder.ChildAdded:Connect(function(m) task.spawn(setup, m) end)
end

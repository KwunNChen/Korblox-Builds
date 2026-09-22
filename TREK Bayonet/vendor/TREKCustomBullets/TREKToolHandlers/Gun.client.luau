-- PLAYER VARIABLES 
if not game.Players.LocalPlayer.Character then
	game.Players.LocalPlayer.CharacterAdded:Wait()
end

game.Players.LocalPlayer.Character:WaitForChild('Humanoid')
game.Players.LocalPlayer.Character:WaitForChild('TREK_PlrConfig')
game.Players.LocalPlayer.PlayerGui:WaitForChild('GunHud')

local UIS = game:GetService('UserInputService')
local RUNSERV = game:GetService('RunService')
local PService = game:GetService("PhysicsService")
local mouseModule = require(shared.S.TREK_Modules.MouseModuleV2)

-- GLOBALS
local plr = game.Players.LocalPlayer
local chr = plr.Character
local plrconfig = chr:WaitForChild('TREK_PlrConfig')
local mouse = mouseModule.new()
local mouseLegacy = plr:GetMouse()
local defaultZoomOut = plr.CameraMaxZoomDistance
local defaultZoomIn = plr.CameraMinZoomDistance
local defaultFov = workspace.CurrentCamera.FieldOfView

mouse.TargetFilters:Set({workspace:WaitForChild('IgnoreList'), chr})
mouse:SetCollisionGroup('Default')

if shared.S.globalConfig['collisionGroupConfigs'] then
	if shared.S.globalConfig.collisionGroupConfigs['TMouseCollGroup'] then
		mouse:SetCollisionGroup('TMouseCollGroup')
	end
end
--mouse.TargetFilter = workspace:WaitForChild("IgnoreList")

-- GUN VARIABLES
local tool = script.Parent

local module
if tool:GetAttribute('TConfigToUse') then
	module = shared.S.GunConfigs:FindFirstChild(tool:GetAttribute('TConfigToUse'), true)
else
	module = shared.S.GunConfigs:FindFirstChild(tool.Name, true)
end

local config = require(module)

local currentMode = 1
local currentBarelIndex = 1
local currentZoomLevel = 1
local FOVToUse = 40

local currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)

-- AMMO VARIABLES
local sharedClip = config[1].MagCapacity
local sharedCap = sharedClip
local tammo = tool:FindFirstChild('TAmmo')

-- INTERFACE VARIABLES
local hud = plr.PlayerGui:WaitForChild('GunHud')
local ammohud = plr.PlayerGui:WaitForChild('AmmoCounter')
local scope = plr.PlayerGui:WaitForChild('Scope')

local main = module:WaitForChild('MainHud')
local ammobar = hud:WaitForChild('AmmoBar')
local marker = hud:WaitForChild('Hitmarker')

local currentmain = main:Clone()

-- BOOLS
local zoomed = false
local patrolling = false
local equipped = false
local firing = false
local canfire = true
local reloading = false
local mouseClick = false
local charging = false
local chargecooldown = false
local animsLoaded = false

-- RAY STUFF
local raypar = RaycastParams.new()
raypar.FilterType = Enum.RaycastFilterType.Exclude
raypar.FilterDescendantsInstances = {workspace:WaitForChild('IgnoreList'), plr.Character}
raypar.IgnoreWater = true

-- MELEE


-- TABLES
local transparencies = {}
local ignoreList = {workspace.IgnoreList,chr}
local animations = {}
local localcontrols = {}
local modeStuff = {}
local activeProgressBars = {}

local handleDamaging

for name,tabl in pairs(config) do
	if type(tabl) ~= 'table' then continue end
	
	modeStuff[name] = {
		['clip'] = tabl.MagCapacity;
		['currentclip'] = tabl.MagCapacity;
		['stored'] = tabl.ReservedAmmo;
		['zoomLevels'] = string.split(tostring(tabl.ZoomFov), ";");
		['rayParams'] = RaycastParams.new();
	}
	
	modeStuff[name].rayParams.FilterType = Enum.RaycastFilterType.Exclude
	modeStuff[name].rayParams.FilterDescendantsInstances = {workspace:WaitForChild('IgnoreList'), plr.Character}
	modeStuff[name].rayParams.IgnoreWater = true
	modeStuff[name].rayParams.CollisionGroup = tabl['CollisionGroup'] or 'Default'
	
	modeStuff[name].bulletObject = nil
end

-- MISC
local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end
local lastanim 

-- MODULES
local controls = require(chr:WaitForChild('OneLifeScripts'):WaitForChild('ControlsModule'))
local effects = require(shared.S.TREK_Modules.EffectsModule)
local impactEffects = require(shared.S.TREK_Modules.ImpactParticlesModule)
local bulletTypes = require(shared.S.TREK_Modules.BulletModule)
local universalFuncs = require(shared.S.TREK_Modules:WaitForChild('TREKUniversalFunctions'))
local HeadArmsModule = require(shared.S.TREK_Modules.HeadAndArmsController)

local shakeModule = require(shared.S.TREK_Modules.CameraShaker)

local camShake = shakeModule.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
	workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * shakeCf
end)

camShake:Start()

local Spring = require(shared.S.TREK_Modules:WaitForChild('Spring'))
local RecoilSpring = Spring.New(Vector3.new())

RecoilSpring.Speed	= 20
RecoilSpring.Damper	= 0.5

-- UNIVERSAL FUNCTIONS
local function findPlrAndChar(part)
	if not part then return nil end
	if not part.Parent then return nil end
	
	local object = part
	local hum
	
	while object and object.Parent ~= nil do
		hum = object:FindFirstChild("Humanoid")
		
		if hum or object.Parent == workspace then break end
		
		object = object.Parent
	end
	
	if not hum then return nil, nil end
	
	local plr2 = game.Players:GetPlayerFromCharacter(object.Parent)
	
	if plr2 then return plr2, object.Parent end
	
	return nil, object
end

-- GUI FUNCTIONS
local function updateAmmo()
	if not currentmain:FindFirstChild('Main') then return end

	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	local maxAmmo = (config[mode].ReservedAmmo == math.huge and config[mode].MagCapacity) or tool.LocalTAmmo[mode].Stored.Value
	
	currentmain.Main:WaitForChild('Ammo').Text = tostring(tool.LocalTAmmo[mode].Ammo.Value)
	currentmain.Main:WaitForChild('MaxAmmo').Text = tostring(maxAmmo)
	
	--[[if config[currentMode].useSharedClip then
		currentmain.Main:WaitForChild('Ammo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', tool.LocalTAmmo[mode].Ammo.Value)
		currentmain.Main:WaitForChild('MaxAmmo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', maxAmmo)
	else
		currentmain.Main:WaitForChild('Ammo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', tool.LocalTAmmo[mode].Ammo.Value)
		currentmain.Main:WaitForChild('MaxAmmo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', maxAmmo)
	end]]
end


local function hitmarker(type)
	local marker,box = hud.Hitmarker.Marker:Clone(), hud.Hitmarker.Box:Clone()
	
	if type then
		if type == 'armr' then
			box.UIStroke.Color = Color3.fromRGB(21, 0, 255)
		elseif type == 'plr' then
			box.UIStroke.Color = Color3.fromRGB(255, 32, 32)
		end
	end
	
	marker.Parent = hud.Hitmarker
	box.Parent = hud.Hitmarker
	
	marker.Visible = true
	box.Visible = true
	
	tween(box,{Size = UDim2.new(0,80,0,80)},0.25,"Cubic","Out"):Play()
	tween(box.UIStroke,{Transparency = 1},0.25,"Linear","Out"):Play()
	tween(box.UIStroke,{Thickness = 0},0.25,"Cubic","In"):Play()
	tween(marker,{Size = UDim2.new(0,50,0,50)},0.2,"Quint","Out"):Play()
	tween(marker,{ImageTransparency = 1},0.2,"Linear","Out"):Play()
	
	universalFuncs.DestroyDelayed(box, 0.5)
	universalFuncs.DestroyDelayed(marker, 0.5)
end

local function damageIndicator(damage,part,type)
	local dmg = hud.Hitmarker.Damage
	local c = dmg:Clone()
	
	if type == 'plr' then
		c.TextColor3 = Color3.fromRGB(229,0,0)
	elseif type == 'armr' then
		c.TextColor3 = Color3.fromRGB(21, 0, 255)
	end
	
	local sounds = shared.S.TREK_EffectsStorage.Sounds.DamageSounds:GetChildren()
	local s = sounds[math.random(1, #sounds)]:Clone()
	
	c.Parent = hud.Hitmarker
	c.Visible = true
	c.Text = damage
	
	s.Parent = tool
	s:Play()
	
	--local newPosX = x + math.random(-150,150)
	--local newPosY = y + math.random(-100,100)
	
	tween(c,{Position = UDim2.new(1,math.random(15,30),0,-math.random(15,30))},1,'Quart','Out'):Play()
	tween(c,{Size = UDim2.new(0,80,0,20)},0.5,'Quint','Out'):Play()
	tween(c,{TextTransparency = 1},1,'Linear','Out'):Play()
	
	task.delay(s.TimeLength + 5, function()
		if s then s:Destroy() end
	end)
	task.delay(2, function()
		if c then c:Destroy() end
	end)
end

--[[
local function determinteClip()
	return ((config[currentMode].useSharedClip and sharedClip) or modeStuff[currentMode].clip)
end

local function determineCap()
	return ((config[currentMode].useSharedClip and sharedCap) or modeStuff[currentMode].MagCapacity)
end
]]

local function showHud()
	currentmain = main:Clone()
	currentmain.Parent = ammohud
	updateAmmo()
	
	for i = 1,5 do 
		if not equipped then currentmain.Visible = false break end
		currentmain.Visible = not currentmain.Visible
		task.wait(.06)
	end
end

local function hideHud()
	if not currentmain then return end
	currentmain:Destroy()
end

local function startReloadGui()
	
end

local function endReloadGui()
	updateAmmo()
end

-- FUNCTIONS 1
local function createAmmoStore()
	local f = Instance.new('Folder')
	f.Parent = tool
	f.Name = 'LocalTAmmo'

	for name, config in pairs(config) do		
		if not config then continue end
		if not (typeof(config) == 'table') then continue end
		if not config['MagCapacity'] then continue end

		local w = Instance.new('Folder')
		w.Parent = f
		w.Name = name

		local v1,v2 = Instance.new('DoubleConstrainedValue'),Instance.new('DoubleConstrainedValue')
		v1.Name = 'Ammo'
		v1.MaxValue = config.MagCapacity
		v1.MinValue = 0
		v1.Value = config.MagCapacity
		v1.Parent = w

		v2.Name = 'Stored'
		v2.MaxValue = (config.ReservedAmmo == math.huge and math.huge) or config.ReservedAmmo
		v2.MinValue = 0
		v2.Value = (config.ReservedAmmo == math.huge and math.huge) or config.ReservedAmmo
		v2.Parent = w
	end
end
local function handleMotor()
	if not tool:FindFirstChild('AnimPart') then return end
	
	if chr:WaitForChild('Humanoid').RigType == Enum.HumanoidRigType.R6 then
		chr.Torso.toolAnim.Part0 = chr.Torso
		chr.Torso.toolAnim.Part1 = tool.AnimPart
	elseif chr:WaitForChild('Humanoid').RigType == Enum.HumanoidRigType.R15 then
		chr.UpperTorso.toolAnim.Part0 = chr.UpperTorso
		chr.UpperTorso.toolAnim.Part1 = tool.AnimPart
	end
end

local function loadAnimations()
	if animsLoaded then return end
	for i,anim in pairs(module.Animations:GetChildren()) do
		animations[anim.Name] = chr.Humanoid:LoadAnimation(anim)
	end
end

local function clearAnimations()
	table.clear(animations)
end

local function determineAnim(anim, action, returnanim)
	local anim:AnimationTrack = (animations[tostring(currentMode)..anim] ~= nil and animations[tostring(currentMode)..anim]) or animations[anim]	
	if not anim then return end
	
	if action == 'play' then
		--[[if lastanim then lastanim:Stop() end
		lastanim = anim]]
		anim:Play()
	else
		anim:Stop()
	end	
	
	if returnanim then return anim end
end

local function onEquip()
	if not tool:FindFirstChild('LocalTAmmo') then createAmmoStore() end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R6 and not chr:FindFirstChild('Right Arm')) then
		tool:Destroy()
	end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R15 and not chr:FindFirstChild('RightHand')) then
		tool:Destroy()
	end
	
	equipped = true
	charging = false
	chargecooldown = false
	
	loadAnimations()
	handleMotor()
	
	if config[currentMode].TurnToTarget then
		HeadArmsModule:Start(plr.Character, config[currentMode].VerticalTurning)
	end
	
	if not controls.sprinting.Value then
		determineAnim('Idle','play')
		--animations.Patrol:Play()
	else
		determineAnim('SprintHold','play')
		HeadArmsModule:Pause()
	end
	
	mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Main

	showHud()
end

local function onUnEquip()
	equipped = false
	
	if zoomed then localcontrols.zoom() end
	if patrolling then localcontrols.patrol() end
	
	determineAnim('Idle','stop')
	if controls.sprinting then determineAnim('SprintHold','stop') end
	if reloading then determineAnim('Reload', 'stop') end

	--mouseLegacy.Icon = 'rbxasset://Cursors/KeyboardMouse/ArrowFarCursor'
	mouseLegacy.Icon = ''
	
	hideHud()
	clearAnimations()
	HeadArmsModule:Stop()
end

local function WindDown()
	if charging and equipped then
		--makePercCounter(config[currentMode].WindDownTime)
		shared.S.TREK_Remotes.GFX:FireServer('WindDown', currentMode, 'Main')
		determineAnim('WindDown','play')
		
		task.delay(config[currentMode].WindDownTime, function()
			charging = false
			chargecooldown = false
		end)

	end
end

local function switchModes()
	if reloading then return end
	if firing then return end
	if not equipped then return end
		
	if (currentMode == 1 and not config[currentMode + 1]) then return end
	
	if controls.sprinting.Value then
		determineAnim('SprintHold','stop')
	else
		determineAnim('Idle','stop')
	end
		
	if not config[currentMode + 1] then
		currentMode = 1
	else
		currentMode += 1
	end
		
	if patrolling then localcontrols.patrol() end
	
	if controls.sprinting.Value then
		determineAnim('SprintHold','play')
	else
		determineAnim('Idle','play')
	end
	
	if config[currentMode].TurnToTarget then
		if HeadArmsModule:ReturnConfiguredStatus() then
			HeadArmsModule:Continue(config[currentMode].VerticalTurning)
		else
			HeadArmsModule:Start(plr.Character, config[currentMode].VerticalTurning)
		end
	else
		HeadArmsModule:Pause()
	end
	
	local s = module.Switch:Clone()
	s.Parent = tool.Main
	s:Play()
	universalFuncs.DestroyDelayed(s,1)
	
	updateAmmo()
	currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)	
end

-- FUNCTIONS 2
local function classicZoom()
	currentZoomLevel = 1
	FOVToUse = (modeStuff[currentMode].zoomLevels and tonumber(modeStuff[currentMode].zoomLevels[1]) or config[currentMode].ZoomFov)
	
	if zoomed then	
		tween(workspace.CurrentCamera,{FieldOfView = FOVToUse},0.2,'Quint','Out'):Play()
	else
		tween(workspace.CurrentCamera,{FieldOfView = defaultFov},0.2,'Quint','Out'):Play()
	end
end

local function scopeZoom()
	if not scope:FindFirstChild(config[currentMode].ScopeType) then warn('Invalid scope!') return end
	currentZoomLevel = 1
	FOVToUse = (modeStuff[currentMode].zoomLevels and tonumber(modeStuff[currentMode].zoomLevels[1]) or config[currentMode].ZoomFov)
	
	UIS.MouseIconEnabled = not zoomed
	scope.Blackout.BackgroundTransparency = 0
	
	plr.CameraMaxZoomDistance = (zoomed and 0) or defaultZoomOut
	plr.CameraMinZoomDistance = (zoomed and 0) or defaultZoomIn
	workspace.CurrentCamera.FieldOfView = (zoomed and FOVToUse) or defaultFov
	
	scope[config[currentMode].ScopeType].Visible = zoomed
	UIS.MouseDeltaSensitivity = (zoomed and (workspace.CurrentCamera.FieldOfView/100) * 0.5) or 1
	
	tween(scope.Blackout,{BackgroundTransparency = 1},0.5,'Quint','Out'):Play()

	if zoomed then		
		for i,part in pairs(tool:GetDescendants()) do
			if not part:IsA('BasePart') then continue end
			transparencies[part] = part.Transparency
			part.Transparency = 1
		end
	else
		for part,value in pairs(transparencies) do
			part.Transparency = value
			part = nil
		end
	end
end

function localcontrols.zoom()
	if not config[currentMode].CanZoom then return end
	if patrolling then localcontrols.patrol() end
	
	zoomed = not zoomed
	
	if config[currentMode].Scope then
		scopeZoom()
	else
		classicZoom()
	end	
end

function localcontrols.patrol()
	if reloading then return end
	if controls.sprinting.Value then controls.sprinting.Value = false end
	if zoomed then localcontrols.zoom() end

	patrolling = not patrolling

	if patrolling then
		HeadArmsModule:Pause()
		determineAnim('Patrol','play')
		determineAnim('Idle','stop')
	else
		HeadArmsModule:Continue()
		determineAnim('Patrol','stop')
		if (not reloading and equipped) then determineAnim('Idle','play') end
	end
end

-- FUNCTIONS 3
local function handleFallOff(result, damage, distance)	
	local fostart = config[currentMode].fallOffStart
	local foend = config[currentMode].fallOffEnd

	if distance < fostart then
		result = damage
	elseif distance > foend then
		result = 0
	else
		distance -= fostart
		local Middle = damage / (foend - fostart)
		result = math.round(damage - (Middle * distance))
	end

	return result
end

local function setDamage(Origin, Target, ArmorDamage)	
	local distance = (Origin - Target.Position).Magnitude
	local damage = (ArmorDamage and config[currentMode].ArmourDamage) or config[currentMode].Damage
	local result

	result = handleFallOff(result, damage, distance)

	if (ArmorDamage and Target:FindFirstChild('RequiredArmourDamage')) then
		if result < Target.RequiredArmourDamage.Value then return 0 end
	end

	if (ArmorDamage and Target:FindFirstChild('ArmourDamageResist')) then
		result = math.clamp(0, (result - Target.ArmourDamageResist.Value), math.huge)
	end

	if (Target.Name == 'Head' or Target:FindFirstAncestor('Head')) then
		result *= config[currentMode].headShotMultiplier
	end

	return result
end

local function getSpread(part)
	local pos = mouse.Hit.Position
	local inter = (part.Position - pos).Magnitude
	
	local spread = config[currentMode].baseSpread
	
	if (controls.crouching.Value and chr:WaitForChild('Humanoid'):GetState() ~= Enum.HumanoidStateType.Freefall) then
		spread += config[currentMode].crouchSpreadAddition
	end
	if chr:WaitForChild('Humanoid'):GetState() == Enum.HumanoidStateType.Freefall then
		spread += config[currentMode].jumpSpreadAddition
	end
	if ((shared.S.globalConfig.EnableMedical) and (not chr:FindFirstChild('Left Arm'))) then 
		spread += config[currentMode].oneHandedSpreadAddition
	end
	if zoomed then 
		spread += config[currentMode].zoomSpreadAddition
	end
	
	spread = math.clamp(spread,0,math.huge)
	
	local min = -(spread/100)*inter
	local max = (spread/100)*inter
	
	local aim = Vector3.new(
		pos.X + math.random(min,max),
		pos.Y + math.random(min,max),
		pos.Z + math.random(min,max)
	)

	return aim
end

local function handleDamaging(part)
	if not part then return end

	local isPlayer = false
	local mat = part.Color

	local enplr, enchr = findPlrAndChar(part)
	local isTHealth = part:FindFirstChild('THealth')
	local isTVehicle = part:FindFirstAncestor('TVehicle')

	if enplr and enchr then
		local IsImmune = false

		local ImmunityValue = enchr.Humanoid:FindFirstChild("IsImmune")

		if ImmunityValue then
			IsImmune = ImmunityValue.Value
		end
		
		if not IsImmune then
			shared.S.TREK_Remotes.Damage:FireServer(currentBarrel.Position, part, part.Size, currentMode)
			isPlayer = true

			if (enplr.Team ~= plr.Team) or (plr.Team == nil) or (config[currentMode].TeamKill) then
				local dmg = setDamage(currentBarrel.Position, part, false)
				if dmg <= 0 then return end

				damageIndicator(dmg, part, 'plr')
				hitmarker('plr')
			end
		end
	elseif enchr then
		local IsImmune = false
		
		local ImmunityValue = enchr.Humanoid:FindFirstChild("IsImmune")
		
		if ImmunityValue then
			IsImmune = ImmunityValue.Value
		end
		
		if not IsImmune then -- if boolvalue and not boolvalue.value == true
			shared.S.TREK_Remotes.Damage:FireServer(currentBarrel.Position, part, part.Size, currentMode)
			local dmg = setDamage(currentBarrel.Position, part, false)
			if dmg <= 0 then return end

			damageIndicator(dmg, part, 'plr')
			hitmarker('plr')
		end

	elseif isTHealth then
		shared.S.TREK_Remotes.Damage:FireServer(currentBarrel.Position, part, part.Size, currentMode)

		local dmg = setDamage(currentBarrel.Position, part, true)
		if dmg <= 0 then return end

		if part:FindFirstChild('Team') then
			if (part.Team.Value ~= plr.Team) or (plr.Team == nil) or (config[currentMode].TeamKill) then
				damageIndicator(dmg, part, 'armr')
				hitmarker('armr')
			end
		else
			damageIndicator(dmg, part, 'armr')
			hitmarker('armr')
		end

	elseif (isTVehicle and not isTHealth) then
		shared.S.TREK_Remotes.Damage:FireServer(currentBarrel.Position, part, part.Size, currentMode)

		local dmg = setDamage(currentBarrel.Position, part, true)
		if dmg <= 0 then return end

		if not isTVehicle:FindFirstChild('Stats') then return end

		if (isTVehicle.Stats.Team.Value ~= plr.Team) or (plr.Team == nil) or (config[currentMode].TeamKill) then
			damageIndicator(dmg, part, 'armr')
			hitmarker('armr')
		else
			damageIndicator(dmg, part, 'armr')
			hitmarker('armr')
		end	
	end
end





local function handleRays()
	local bulletType = bulletTypes[config[currentMode].BulletType]
	if not(bulletType and modeStuff[currentMode].bulletObject) then return end
	
	for i, barrel in pairs(tool:GetChildren()) do		
		if barrel.Name ~= currentBarrel.Name then continue end
		
		modeStuff[currentMode].bulletObject.fire(barrel, getSpread(barrel))
		
		
		
	end
end

local function handleAmmo()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	if config[mode].ReservedAmmo == math.huge then return config[mode].MagCapacity end
	
	local difference = (config[mode].MagCapacity - tool.LocalTAmmo[mode].Ammo.Value)
	local possible
	
	local possible = (difference > tool.LocalTAmmo[mode].Stored.Value) and tool.LocalTAmmo[mode].Stored.Value or difference

	return possible,mode
end

local function handleReloadSound(sound)
	local s = sound:Clone()
	s.Parent = tool.Main
	s:Play()
	universalFuncs.DestroyDelayed(s, s.TimeLength + 1)
end

local function makePercCounter(thetime)
	task.spawn(function()
		local c = ammobar:WaitForChild('OGBar'):Clone()
		c.Name = 'Bar'
		c.LayoutOrder = 0

		c.Parent = ammobar
		c.Visible = true
		
		activeProgressBars[c] = true
		
		tween(c,{BackgroundTransparency = 0.3, Size = UDim2.new(1,0,0,12)},0.5,'Quint','Out'):Play()
		tween(c.Perc,{Size = UDim2.new(1,0,1,0)},thetime,'Linear','Out'):Play()
		task.delay(thetime, function()
			tween(c,{BackgroundTransparency = 1},0.5,'Quint','Out'):Play()
			tween(c.Perc,{BackgroundTransparency = 1},0.5,'Quint','Out'):Play()
		end)
		
		universalFuncs.DestroyDelayed(c,thetime+0.5)
	end)
end

local function reloadTypeTwo()
	canfire = false
	reloading = true
	local reload:AnimationTrack
	
	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	
	task.wait(.2)
	
	local startanim:AnimationTrack = determineAnim('RechargeStart', 'play', true)
	if startanim then task.wait(startanim.Length) end
	
	repeat
		handleReloadSound((module:FindFirstChild(tostring(currentMode)..'Recharge') and module[(tostring(currentMode)..'Recharge')]) or module.Recharge)
		reload = determineAnim('Reload','play', true)

		if tool.LocalTAmmo[mode].Stored.Value <= 0 then break end		
		
		tool.LocalTAmmo[mode].Stored.Value -= 1
		tool.LocalTAmmo[mode].Ammo.Value += 1
		updateAmmo()
		
		if tool.LocalTAmmo[mode].Ammo.Value >= config[mode].MagCapacity then break end
		
		task.wait(config[currentMode].ReloadSpeed)

	until tool.LocalTAmmo[mode].Ammo.Value == config[mode].MagCapacity
	
	task.wait((reload and reload.Length) or config[currentMode].ReloadSpeed)

	determineAnim('RechargeEnd', 'play')
	
	canfire = true
	reloading = false
end

local function reloadTypeOne()
	canfire = false
	reloading = true
	
	local number = handleAmmo()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	
	if (controls.sprinting.Value and animations['SprintReload']) then
		determineAnim('SprintReload','play')
	else
		determineAnim('Reload','play')
	end
	makePercCounter(config[currentMode].ReloadSpeed)
	shared.S.TREK_Remotes.GFX:FireServer('Reload', currentMode, 'Main')

	task.wait(config[currentMode].ReloadSpeed)
	
	if config[mode].ReservedAmmo == math.huge then 
		tool.LocalTAmmo[mode].Ammo.Value = number
	else
		tool.LocalTAmmo[mode].Stored.Value -= number
		tool.LocalTAmmo[mode].Ammo.Value += number
	end	
	
	updateAmmo()

	canfire = true
	reloading = false
end

local function reloadSecurityChecks()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R6 and not chr:FindFirstChild('Left Arm')) then
		return
	end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R15 and not chr:FindFirstChild('LeftHand')) then
		return
	end
	
	if not config[currentMode].CanReload then return end
	if tool.LocalTAmmo[mode].Stored.Value <= 0 then return end
	if tool.TAmmo[mode].Stored.Value <= 0 then return end
	if reloading then return end
	
	return true
end

local function Reload()
	if not reloadSecurityChecks() then return end
	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	
	if config[mode].ReloadOnlyWithEmptyMag then
		if tool.LocalTAmmo[mode].Ammo.Value > 0 then warn('local tammo check') return end
		if tool.TAmmo[mode].Ammo.Value > 0 then warn('tammo check') return end
	end
	
	if tool.LocalTAmmo[mode].Ammo.Value >= config[mode].MagCapacity then return end

	if config[currentMode].ReloadType == 1 then
		reloadTypeOne()
	elseif config[currentMode].ReloadType == 2 then
		reloadTypeTwo()
	end
	
	shared.S.TREK_Remotes.Reload:FireServer(currentMode)
end

local function handleFireRate()
	task.wait(60/config[currentMode].RoundsPerMinute)
	firing = false
	canfire = true
end

local function findNearestAlly()
	for i,player in pairs(plr.Team:GetPlayers()) do
		local char = player.Character

		if player == plr then return end
		if not char then return end
		if not char:FindFirstChild('HumanoidRootPart') then return end

		if char.Humanoid.Health > 0 and (char.HumanoidRootPart.Position - plr.Character.HumanoidRootPart.Position).Magnitude<=config.Range then
			return player, char
		end

	end
end

local function windUp()
	if chargecooldown then return end

	if ((config[currentMode].useSharedClip and tool.LocalTAmmo[1].Ammo.Value) or tool.LocalTAmmo[currentMode].Ammo.Value) <= 0 then Reload() return end

	shared.S.TREK_Remotes.GFX:FireServer('WindUp', currentMode, 'Main')

	determineAnim('WindUp','play')

	chargecooldown = true
	charging = true
	task.wait(config[currentMode].ChargeTime)

	if not equipped then return end
end

local function CameraShakeFunction()
	--[[
		if (controls.crouching.Value and chr:WaitForChild('Humanoid'):GetState() ~= Enum.HumanoidStateType.Freefall) then
		spread += config[currentMode].crouchSpreadAddition
	end
	if chr:WaitForChild('Humanoid'):GetState() == Enum.HumanoidStateType.Freefall then
		spread += config[currentMode].jumpSpreadAddition
	end
	if ((shared.S.globalConfig.EnableMedical) and (not chr:FindFirstChild('Left Arm'))) then 
		spread += config[currentMode].oneHandedSpreadAddition
	end
	if zoomed then 
		spread += config[currentMode].zoomSpreadAddition
	end
	]]
	local crouchMultiplier = (controls.crouching.Value and config[currentMode].CameraShakeCrouchMultiplier) or 1
	local zoomMultiplier = (zoomed and config[currentMode].CameraShakeZoomMultiplier) or 1
	
	local m = config[currentMode].CameraShakeMagnitude * crouchMultiplier * zoomMultiplier
	local r = config[currentMode].CameraShakeRoughness * crouchMultiplier * zoomMultiplier
	local fi = config[currentMode].CameraShakeFadeInTime
	local fo = config[currentMode].CameraShakeFadeOutTime
	
	camShake:ShakeOnce(m,r,fi,fo)
end

local function CamRecoilFunction()    
	local X,Y,Z = config[currentMode].RecoilX, config[currentMode].RecoilY, config[currentMode].RecoilZ
	local crouchMultiplier = (controls.crouching.Value and config[currentMode].RecoilCrouchMultiplier) or 1
	local zoomMultiplier = (zoomed and config[currentMode].RecoilZoomMultiplier) or 1
	
	if typeof(X) == 'table' then
		local rnd = math.random(X[1],X[2])

		X = rnd
	end
	if typeof(Y) == 'table' then
		local rnd = math.random(Y[1],Y[2])

		Y = rnd
	end
	if typeof(Z) == 'table' then
		local rnd = math.random(Z[1],Z[2])

		Z = rnd 
	end

	X = math.rad(X * crouchMultiplier * zoomMultiplier)
	Y = math.rad(Y * crouchMultiplier * zoomMultiplier)
	Z = math.rad(Z * crouchMultiplier * zoomMultiplier)

	RecoilSpring:Impulse(Vector3.new(X, Y, Z))
end

local function shoot()
	firing = true
	canfire = false

	if controls.sprinting.Value then
		plrconfig.SprintEnabled.Value = false
	end
	
	shared.S.TREK_Remotes.GFX:FireServer('GunFire', currentMode, currentBarrel.Name)
	
	for i = 1,config[currentMode].RaysPerShot do
		handleRays()
		if config[currentMode].FiringShakesCamera then CameraShakeFunction() end
		if config[currentMode].CameraRecoil then CamRecoilFunction() end
	end
	
	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	tool.LocalTAmmo[mode].Ammo.Value -= 1
	
	shared.S.TREK_Remotes.AmmoRemote:FireServer(currentMode)

	--determineAnim('Idle'):Stop()
	determineAnim('Recoil','play')
	
	updateAmmo()
	handleFireRate()
	--determineAnim('Idle'):Play()
end

local function Burst()
	local number
	local sharedClip = tool.LocalTAmmo[1].Ammo
	local modeClip = tool.LocalTAmmo[currentMode].Ammo.Value
	
	if config[currentMode].useSharedClip then
		number = ((sharedClip.Value - config[currentMode].BurstAmount > 0 and config[currentMode].BurstAmount) or sharedClip.Value)
	else
		number = (modeClip.Value - config[currentMode].BurstAmount > 0 and config[currentMode].BurstAmount or modeClip.Value)
	end
	
	if config[currentMode].Charged then windUp() end
	
	for i = 1, number do
		shoot()
	end
	
	if config[currentMode].Charged then WindDown() end
end

local function Auto()
	if config[currentMode].Charged then windUp() end

	while mouseClick and equipped and not reloading and canfire do
		if not equipped then break end
		if not mouseClick then break end
		if not canfire then break end
		
		if config[currentMode].useSharedClip then
			if tool.LocalTAmmo[1].Ammo.Value <= 0 then Reload() break end
		else
			if tool.LocalTAmmo[currentMode].Ammo.Value <= 0 then Reload() break end
		end
		
		shoot()
	end
	
	if config[currentMode].Charged then WindDown() end
end

local function Semi()
	if config[currentMode].Charged then windUp() end
	shoot()
	
	if config[currentMode].Charged then WindDown() end
end

local function mousePress()
	if not equipped then return end
	if ((config[currentMode].useSharedClip and tool.LocalTAmmo[1].Ammo.Value) or tool.LocalTAmmo[currentMode].Ammo.Value) <= 0 then Reload() return end
	if not canfire then return end
	if reloading then return end
	if charging then return end
	if chargecooldown then return end
	if chr:WaitForChild('Humanoid').Health <= 0 then return end
	
	mouseClick = true
	
	if patrolling then localcontrols.patrol() end
	
	local types = { -- gun types
		[1] = Auto;
		[2] = Semi;
		[3] = Burst;
	}
	local func = types[config[currentMode].GunType]
	func()
end

local function mouseRelease()
	if not equipped then return end
	
	mouseClick = false
end

--zoomLevels
--currentZoomLevel
--table[index]
local function zoomIncrease()
	if not zoomed then return end
	if typeof(config[currentMode].ZoomFov) == 'number' then return end
	
	if modeStuff[currentMode].zoomLevels[currentZoomLevel + 1] then
		currentZoomLevel += 1
	else
		currentZoomLevel = #modeStuff[currentMode].zoomLevels
	end
	
	FOVToUse = tonumber((currentZoomLevel and modeStuff[currentMode].zoomLevels[currentZoomLevel]) or config[currentMode].ZoomFov)
	
	if config[currentMode].Scope then
		UIS.MouseDeltaSensitivity = workspace.CurrentCamera.FieldOfView/100 * 0.5
	end
	
	workspace.CurrentCamera.FieldOfView = FOVToUse
end

local function zoomDecrease()
	if not zoomed then return end
	if typeof(config[currentMode].ZoomFov) == 'number' then return end

	if modeStuff[currentMode].zoomLevels[currentZoomLevel - 1] then
		currentZoomLevel -= 1
	else
		currentZoomLevel = 1
	end

	FOVToUse = tonumber((currentZoomLevel and modeStuff[currentMode].zoomLevels[currentZoomLevel]) or config[currentMode].ZoomFov)	
	
	if config[currentMode].Scope then
		UIS.MouseDeltaSensitivity = workspace.CurrentCamera.FieldOfView/100 * 0.5
	end
	
	workspace.CurrentCamera.FieldOfView = FOVToUse
end

local function TurnToTarget()
	if not chr then return end
	if chr.Humanoid.SeatPart then return end
	if controls.sprinting.Value then return end
	if patrolling then return end
	if reloading then return end
	
	local corePart:BasePart = chr:FindFirstChild('HumanoidRootPart')
	if not corePart then return end
	
	local lookAt = Vector3.new(mouse.Hit.Position.X, corePart.Position.Y, mouse.Hit.Position.Z)
	local cf = CFrame.new(corePart.Position, lookAt)
	
	--corePart.CFrame = cf
	corePart:PivotTo(cf)
end

local function CameraRecoilLoop()
	workspace.CurrentCamera.CFrame *= CFrame.Angles(RecoilSpring.Position.X,RecoilSpring.Position.Y,RecoilSpring.Position.Z)
end

local function mouseMoved()
	local t = mouse.Target
	marker.Position = UDim2.new(0, mouse.X, 0, mouse.Y) + UDim2.new(0,0,0,9)
	ammobar.Position = UDim2.new(0, mouse.X, 0, mouse.Y) + UDim2.new(0,0,0,64)
	
	if t ~= nil then
		if t.Parent:FindFirstChild('Humanoid') or t.Parent.Parent:FindFirstChild('Humanoid') then
			local player = (t.Parent:FindFirstChild('Humanoid') and game.Players:GetPlayerFromCharacter(t.Parent) or game.Players:GetPlayerFromCharacter(t.Parent.Parent))
			if player then
				if (player.Team == plr.Team and not config[currentMode].TeamKill) then
					mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Friendly
					return
				else
					mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Enemy
					return
				end
			end
		end
	end
	mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Main
end

local function input(input,done)
	if equipped and not done then
		local inputs = {
			[shared.S.globalConfig.ReloadKey] = Reload;
			[shared.S.globalConfig.ZoomKey] = localcontrols.zoom;
			[shared.S.globalConfig.PatrolKey] = localcontrols.patrol;
			[shared.S.globalConfig.modeKey] = switchModes;
			[shared.S.globalConfig.zoomIncrease] = zoomIncrease;
			[shared.S.globalConfig.zoomDecrease] = zoomDecrease;
		}
		local func = inputs[input.KeyCode]
		if func then
			func()
		end
	end
end

-- EXECUTION
tool.Equipped:Connect(onEquip)
tool.Unequipped:Connect(onUnEquip)

mouse.Button1Down:Connect(mousePress)
mouse.Button1Up:Connect(mouseRelease)

mouse.Move:Connect(function()
	if equipped then
		mouseMoved()
	end
end)

RUNSERV.RenderStepped:Connect(function()
	if not equipped then return end
	if config[currentMode].TurnToTarget then
		TurnToTarget()
	end
	
	CameraRecoilLoop()
end)

for i,mode in pairs(modeStuff) do -- create bullet objects
	local bulletType = bulletTypes[config[i].BulletType]
	if not(bulletType) then return end

	local bulletData = {}
	bulletData.Config = config[i]
	bulletData.ModeStuff = mode
	bulletData.Character = chr
	bulletData.Player = plr
	bulletData.Mode = i
	bulletData.DamageFunction = handleDamaging
	bulletData.Tool = tool
	
	--print(bulletData)
	
	mode.bulletObject = bulletType.new(bulletData)
end

UIS.InputBegan:Connect(input)

chr.ChildRemoved:Connect(function(child)
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R6 and child.Name == 'Right Arm') then
		tool.Parent = plr.Backpack
		tool:Destroy()
	end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R15 and child.Name == 'RightHand') then
		tool.Parent = plr.Backpack
		tool:Destroy()
	end
end)

chr:WaitForChild('Humanoid').Died:Connect(function()
	onUnEquip()
	
	canfire	= false
	--reloading = true
	
	for bar, _ in pairs(activeProgressBars) do
		if bar then bar:Destroy() end
		bar = nil
	end
	
	if zoomed then localcontrols.zoom() end
	if controls.sprinting.Value then controls.sprint() end
	if patrolling then localcontrols.patrol() end
end)

shared.S.TREK_Remotes.Reload.OnClientEvent:Connect(function()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	if tool.LocalTAmmo[mode].Stored.MaxValue ~= math.huge then
		tool.LocalTAmmo[mode].Stored.Value = tool.LocalTAmmo[mode].Stored.MaxValue
		Reload()
	end
end)

controls.sprinting:GetPropertyChangedSignal('Value'):Connect(function()
	if equipped then
		if controls.sprinting.Value then
			if patrolling then localcontrols.patrol() end
			HeadArmsModule:Pause()
			determineAnim('Idle','stop')
			determineAnim('SprintHold','play')
		else
			determineAnim('Idle','play')
			determineAnim('SprintHold','stop')
			HeadArmsModule:Continue()
		end
	end
end)

task.spawn(function()
	if config[currentMode].ReloadType == 3 then
		while true do
			local mode = (config[currentMode].useSharedClip and 1) or currentMode

			if tool.LocalTAmmo[mode].Ammo.Value < config[mode].MagCapacity and not firing then
				if tool.LocalTAmmo[mode].Stored.Value <= 0 then continue end		
				
				tool.LocalTAmmo[mode].Ammo.Value += 1
				if config[mode].ReservedAmmo ~= math.huge then tool.LocalTAmmo[mode].Stored.Value -= 1 end
				updateAmmo()
				
				if tool.LocalTAmmo[mode].Ammo.Value >= config[mode].MagCapacity then continue end
			end
			
			task.wait(config[currentMode].ReloadSpeed)
		end
	end
end)
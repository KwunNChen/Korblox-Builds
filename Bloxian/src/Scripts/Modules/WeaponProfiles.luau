--[[
	The guns a soldier can spawn with. They use the M4 model unless GunModels
	has one of their own; what changes is how they fire, how they sound, and
	their tracer.

	Settings.Weapon picks one by name ("Rifle", "DMR", "Carbine", "LMG",
	"Sniper"), or "Random" rolls one by weight on every spawn. The Rifle reads its numbers
	from Settings.MagSize, Settings.M4.Delay and Settings.M4.Range, so older
	setups behave the same.

	Per weapon:
		weight          spawn odds against the others
		damage          {min, max} per bullet
		burstNear/Far   shots per trigger pull, closer / further than farDistance
		shotInterval    seconds between shots in a burst
		delay           seconds between bursts
		magSize         rounds per magazine
		range           studs he will shoot at, and how far bullets fly
		spread          degrees of random inaccuracy per bullet
		bulletSpeed     studs per second
		reloadTime      reload length, 1 is the rifle's
		soundSpeed      pitch of the shot, lower is heavier
		sound           asset id of its own shot sound (optional; the M4's otherwise)
		tracer          bullet colour
]]

local weapons = {}

local settings = script.Parent.Parent.Parent.Settings

--The FN FAL shot ("FN-FAL [Free]"), for the guns that show the FAL.
local FAL_SOUND = 154619598

weapons.list = {
	{
		name = "Rifle",
		weight = 50,
		damage = {5, 15},
		burstNear = 3, burstFar = 1, farDistance = 60,
		shotInterval = 0.1,
		delay = settings.M4.Delay.Value,
		magSize = settings.MagSize.Value,
		range = settings.M4.Range.Value,
		spread = 1.5,
		bulletSpeed = 420,
		reloadTime = 1,
		soundSpeed = 1,
		sound = FAL_SOUND,
		tracer = Color3.fromRGB(255,255,0),
	},
	{
		name = "DMR",
		weight = 20,
		damage = {25, 35},
		burstNear = 1, burstFar = 1, farDistance = 60,
		shotInterval = 0.1,
		delay = 1.1,
		magSize = 15,
		range = 250,
		spread = 0.3,
		bulletSpeed = 650,
		reloadTime = 1.2,
		soundSpeed = 0.75,
		tracer = Color3.fromRGB(255,140,40),
	},
	{
		name = "Carbine",
		weight = 20,
		damage = {4, 9},
		burstNear = 5, burstFar = 3, farDistance = 45,
		shotInterval = 0.07,
		delay = 0.35,
		magSize = 35,
		range = 90,
		spread = 3,
		bulletSpeed = 380,
		reloadTime = 0.8,
		soundSpeed = 1.25,
		sound = FAL_SOUND,
		tracer = Color3.fromRGB(255,255,170),
	},
	{
		name = "LMG",
		weight = 10,
		damage = {6, 12},
		burstNear = 6, burstFar = 4, farDistance = 70,
		shotInterval = 0.09,
		delay = 0.5,
		magSize = 100,
		range = 180,
		spread = 2.5,
		bulletSpeed = 450,
		reloadTime = 1.6,
		soundSpeed = 0.9,
		sound = FAL_SOUND,
		tracer = Color3.fromRGB(255,80,60),
	},
	{
		name = "Sniper",
		weight = 0,
		damage = {80, 110},
		burstNear = 1, burstFar = 1, farDistance = 60,
		shotInterval = 0.1,
		delay = 2.8,
		magSize = 5,
		range = 575,
		spread = 0.08,
		bulletSpeed = 1200,
		reloadTime = 1.8,
		soundSpeed = 1,
		sound = 130570662564570,
		tracer = Color3.fromRGB(230,230,255),
	},
}

local function roll()
	local total = 0
	for _,weapon in ipairs(weapons.list) do
		total += weapon.weight
	end

	local pick = math.random()*total
	for _,weapon in ipairs(weapons.list) do
		pick -= weapon.weight
		if pick <= 0 and weapon.weight > 0 then
			return weapon
		end
	end
	return weapons.list[1]
end

local function choose()
	local wanted = settings:FindFirstChild("Weapon")
	if wanted then
		for _,weapon in ipairs(weapons.list) do
			if weapon.name == wanted.Value then
				return weapon
			end
		end
	end
	return roll()
end

--Chosen once per soldier; every script in him shares this module, so they agree.
weapons.current = choose()
local marine = script.Parent.Parent.Parent
marine:SetAttribute("Weapon",weapons.current.name)

--Waits for the respawn copy to be taken first, or it would carry the model too.
task.spawn(function()
	local waited = 0
	while not marine:GetAttribute("BloxianCloned") and waited < 5 do
		waited += task.wait()
	end
	require(script.Parent.GunModels).fit(weapons.current.name)
end)

return weapons

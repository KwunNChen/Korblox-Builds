--[[
	InsertService:LoadAsset is a blocking web request. The original ran one or
	two of them on every single spawn, so every respawn stalled on the network.

	Assets are now downloaded once per server and cached in _G, then cloned.
	First spawn pays the download; every respawn after that is instant.
]]

local hair = {32278814,13477818,80922374,16157972,376548738,16630147,15913837,5064651922,83013207,12270248,26658141,
	188003563,13655562,4735347390,4735346175}
local facial = {5355727732,5355564336,4510537113,5164598367,4528880486,4545294588,11884330,20642008,74970669,
	4507911797,5231192146,158066137,5030224026,5031008665,4102114619,4995497755,987022351,5414672551,4875925250,
	4238241252,4904398878,5231324178,4940496302,5167393248,4933549649,4786863817,5063784744,4708784614,74221074,
	5166827175,4524490255,4875895114,5197016342}
local skinOptions = {"Wheat","Cashmere","Beige","Khaki","Buttermilk","Pastel yellow"}

local marine = script.Parent.Parent.Parent

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

_G.BloxianAccessoryCache = _G.BloxianAccessoryCache or {}
local cache = _G.BloxianAccessoryCache

--Soldiers that spawn together share one download instead of each starting their own.
_G.BloxianAccessoryLoading = _G.BloxianAccessoryLoading or {}
local loading = _G.BloxianAccessoryLoading

local function getTemplate(id)
	local cached = cache[id]
	if cached then
		return cached
	end

	if loading[id] then
		while loading[id] do
			task.wait(0.1)
		end
		return cache[id]
	end
	loading[id] = true

	local ok, model = pcall(function()
		return InsertService:LoadAsset(id)
	end)

	local accessory
	if ok and model then
		accessory = model:FindFirstChildWhichIsA("Accessory")
		if accessory then
			--Held out of the world so it is never rendered or simulated.
			accessory.Parent = nil
			cache[id] = accessory
		else
			warn("[RandomizeAppearance] asset", id, "has no Accessory")
		end
		model:Destroy()
	else
		warn("[RandomizeAppearance] could not load asset", id)
	end

	loading[id] = nil
	return accessory
end

--isFace marks a face accessory, which a uniform with face = false takes off.
local function applyAsset(id,isFace)
	local template = getTemplate(id)
	if not template or not marine.Parent then return end
	if isFace and marine:GetAttribute("NoFaceAccessory") then return end

	--Parenting a real Accessory lets Roblox position it off its HatAttachment;
	--the Handle is then stolen and welded rigidly in that pose.
	local accessory = template:Clone()
	accessory.Parent = marine

	RunService.Heartbeat:Wait()

	local handle = accessory:FindFirstChild("Handle")
	if handle then
		handle.Parent = marine
		handle.Name = tostring(id)
		if isFace then
			handle:SetAttribute("FaceAccessory",true)
		end
		handle.Massless = true
		handle.CanCollide = false
		handle.CanTouch = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = marine.Head
		weld.Part1 = handle
		weld.Parent = handle
	end

	accessory:Destroy()
end

if marine.Settings.RandomAppearance.Value then
	local waited = 0
	while not marine:GetAttribute("BloxianCloned") and waited < 5 do
		waited += task.wait()
	end

	applyAsset(facial[math.random(#facial)],true)

	if math.random(4) == 1 then
		for _,name in ipairs({"Accessory (K-Pot Covered)","ACH"}) do
			local helmet = marine:FindFirstChild(name)
			if helmet then
				helmet:Destroy()
			end
		end
		applyAsset(hair[math.random(#hair)])
	end

	local randomSkin = BrickColor.new(skinOptions[math.random(#skinOptions)])
	local bc = marine["Body Colors"]
	bc.HeadColor = randomSkin
	bc.LeftArmColor = randomSkin
	bc.RightArmColor = randomSkin
	bc.LeftLegColor = randomSkin
	bc.RightLegColor = randomSkin
	bc.TorsoColor = randomSkin
end

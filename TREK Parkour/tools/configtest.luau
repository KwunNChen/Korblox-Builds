--[[
	Headless checks on the config and the pure maths.

		lune run tools/configtest.luau

	These are not style preferences. Each one is a value that would otherwise be
	found by a player: a band with a hole in it that silently refuses a height,
	an easing curve that does not reach its endpoint so a mantle finishes a stud
	short, or a config key deleted while the source still reads it.

	The last block is the one that has earned its place most often -- a static
	cross-check that every Config.X the source reads is actually defined. Delete
	a key from ParkourConfig and the game does not complain until someone jumps
	at a wall.

	Nothing here touches Roblox. Enough of the globals are stubbed below for the
	modules to load, which is why only the pure parts can be tested -- anything
	that casts or touches an Instance is out of scope and belongs in Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

-- ============================================================
-- HARNESS
-- ============================================================

local passed, failed = 0, 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		print("pass  " .. name)
	else
		failed += 1
		print("FAIL  " .. name .. (if detail then "  -- " .. detail else ""))
	end
end

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

-- ============================================================
-- JUST ENOUGH ROBLOX
-- ============================================================

local vectorMethods = {}

local vectorMeta
vectorMeta = {
	__index = function(self, key)
		if key == "Magnitude" then
			return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		elseif key == "Unit" then
			local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
			return setmetatable({ X = self.X / m, Y = self.Y / m, Z = self.Z / m }, vectorMeta)
		end
		return vectorMethods[key]
	end,
	__add = function(a, b)
		return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, vectorMeta)
	end,
	__sub = function(a, b)
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vectorMeta)
	end,
	__mul = function(a, b)
		if type(b) == "number" then
			return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, vectorMeta)
		end
		return setmetatable({ X = a.X * b.X, Y = a.Y * b.Y, Z = a.Z * b.Z }, vectorMeta)
	end,
	__tostring = function(self)
		return string.format("(%.3f, %.3f, %.3f)", self.X, self.Y, self.Z)
	end,
}

function vectorMethods:Lerp(other, t)
	return setmetatable({
		X = self.X + (other.X - self.X) * t,
		Y = self.Y + (other.Y - self.Y) * t,
		Z = self.Z + (other.Z - self.Z) * t,
	}, vectorMeta)
end

local Vector3 = {
	new = function(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vectorMeta)
	end,
}

-- Enum.Anything.Anything resolves to a distinct table, which is all the config
-- needs of it.
local function autoTable()
	local meta
	meta = {
		__index = function(self, key)
			local value = setmetatable({ Name = key }, meta)
			rawset(self, key, value)
			return value
		end,
	}
	return setmetatable({}, meta)
end

local stubInstance = {
	FindFirstChild = function()
		return nil
	end,
	WaitForChild = function()
		return nil
	end,
}

local loaded: { [string]: any } = {}
local loadModule

local function makeEnv()
	local env
	env = {
		-- standard library
		math = math,
		string = string,
		table = table,
		os = os,
		type = type,
		tostring = tostring,
		tonumber = tonumber,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		select = select,
		rawget = rawget,
		rawset = rawset,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		pcall = pcall,
		error = error,
		assert = assert,
		print = print,
		warn = print,

		-- Roblox, stubbed
		Vector3 = Vector3,
		Enum = autoTable(),
		typeof = function(value)
			if type(value) == "table" and getmetatable(value) == vectorMeta then
				return "Vector3"
			end
			return type(value)
		end,
		game = {
			GetService = function()
				return stubInstance
			end,
		},
		workspace = stubInstance,
		script = {
			Parent = {
				WaitForChild = function(_, name: string)
					return { __module = name }
				end,
			},
		},
		require = function(target)
			if type(target) == "table" and target.__module then
				return loadModule(target.__module)
			end
			error("configtest: unexpected require target", 0)
		end,
	}
	return env
end

local SEARCH = { "src/shared", "src/client", "src/server" }

function loadModule(name: string): any
	if loaded[name] then
		return loaded[name]
	end

	for _, dir in SEARCH do
		local path = dir .. "/" .. name .. ".luau"
		if fs.isFile(path) then
			local chunk = luau.load(luau.compile(fs.readFile(path)), { environment = makeEnv() })
			local result = chunk()
			loaded[name] = result
			return result
		end
	end

	error("configtest: no module named " .. name, 0)
end

-- ============================================================
-- THE STATIC CROSS-CHECK
-- ============================================================

--[[
	This runs FIRST, deliberately.

	A key deleted from the config makes every later assertion that reads it die
	with "attempt to compare number < nil", which is true but useless -- it names
	neither the key nor the file that wanted it. Running the scrape up front
	means the precise diagnosis is already on screen before anything can crash
	on the same missing value.
]]
local function crossCheck()
	print("-- every Config.X the source reads is defined --")

	local defined: { [string]: boolean } = {}
	for key in string.gmatch(fs.readFile("src/shared/ParkourConfig.luau"), "[\n]ParkourConfig%.([A-Za-z][A-Za-z0-9]*)%s*=") do
		defined[key] = true
	end

	local used: { [string]: boolean } = {}

	local count = 0
	for _ in defined do
		count += 1
	end
	check("the config defines something at all", count > 10, tostring(count) .. " keys found")

	local function scan(path: string)
		-- The config cannot fail to define what it defines, and this file talks
		-- about Config.X in prose, which would match itself forever.
		if path:match("ParkourConfig%.luau$") or path:match("configtest%.luau$") then
			return
		end

		--[[
			%f[%w] is a frontier pattern: it asserts a transition into a word
			character, so "Config." only matches at the start of a word. Without
			it, TREK's own "TREK_PlrConfig.UsingAbility" matches as
			"Config.UsingAbility" and reports a key that was never a key.
		]]
		local source = fs.readFile(path)
		for key in string.gmatch(source, "%f[%w]Config%.([A-Za-z][A-Za-z0-9]*)") do
			used[key] = true
			if not defined[key] then
				check(path .. " reads Config." .. key, false, "not defined in ParkourConfig")
			end
		end
	end

	local function walk(dir: string)
		if not fs.isDir(dir) then
			return
		end
		for _, entry in fs.readDir(dir) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				walk(path)
			elseif entry:match("%.luau$") then
				scan(path)
			end
		end
	end

	local before = failed
	walk("src")
	walk("tools")
	check("no source file reads an undefined config key", failed == before)

	--[[
		And the other direction, which the check above cannot see.

		A key nothing reads is a lie in the package's primary interface: someone
		tunes it, nothing happens, and they go looking for the bug in the code.
		This catches the far commoner version -- a setting left behind when the
		feature that read it was rewritten.
	]]
	local orphans = {}
	for key in defined do
		if not used[key] then
			table.insert(orphans, key)
		end
	end
	table.sort(orphans)

	check(
		"every config key is read by something",
		#orphans == 0,
		#orphans > 0 and ("nothing reads: " .. table.concat(orphans, ", ")) or nil
	)
end

-- ============================================================
-- THE CHECKS
-- ============================================================

crossCheck()

local Config = loadModule("ParkourConfig")
local Shared = loadModule("ParkourShared")
local Detect = loadModule("ParkourDetect")

print("\n-- config sanity --")

check("StepHeight is positive", Config.StepHeight > 0)
check("RootToSoles is positive", Config.RootToSoles > 0)

--[[
	Ordered AND contiguous. A gap between two bands is a height where the player
	gets no move and no explanation, which is the worst kind of bug to be told
	about second-hand.
]]
check(
	"height bands ascend",
	Config.StepHeight < Config.VaultMaxHeight and Config.VaultMaxHeight < Config.MantleMaxHeight,
	string.format("%.1f / %.1f / %.1f", Config.StepHeight, Config.VaultMaxHeight, Config.MantleMaxHeight)
)

check(
	"mantle grab band ascends",
	Config.MantleGrabLow < Config.MantleGrabHigh,
	string.format("%.1f .. %.1f", Config.MantleGrabLow, Config.MantleGrabHigh)
)

check("durations are positive", Config.VaultDuration > 0 and Config.MantleDuration > 0)
check("HangFraction is strictly inside 0..1", Config.HangFraction > 0 and Config.HangFraction < 1)
check("ArcHeight is not negative", Config.ArcHeight >= 0)
check("Cooldown is not negative", Config.Cooldown >= 0)
check("WatchdogGrace is positive", Config.WatchdogGrace > 0, "a zero grace fires the watchdog mid-move")
check("ProbeRate is positive", Config.ProbeRate > 0)
check("ProbeDistance is positive", Config.ProbeDistance > 0)
check("mantle window ascends", Config.MantleWindowMin <= Config.MantleWindowMax)
check("MaxFaceTilt is a normal component", Config.MaxFaceTilt > 0 and Config.MaxFaceTilt < 1)
check("MinTopFlatness is a normal component", Config.MinTopFlatness > 0 and Config.MinTopFlatness <= 1)
check("MinApproachDot is a dot product", Config.MinApproachDot > 0 and Config.MinApproachDot <= 1)
check("LandInset is positive", Config.LandInset > 0, "landing on the lip itself balances you on the edge")
check(
	"ClearanceSize is a real box",
	Config.ClearanceSize.X > 0 and Config.ClearanceSize.Y > 0 and Config.ClearanceSize.Z > 0
)
check("StartTolerance is positive", Config.StartTolerance > 0, "zero refuses every claim")
check("MaxReach is positive", Config.MaxReach > 0)
check("ArrivalTolerance is positive", Config.ArrivalTolerance > 0)

do
	local slots = { "Vault", "MantleCatch", "MantlePull" }
	local ok = true
	local missing = ""
	for _, slot in slots do
		if type(Config.Animations[slot]) ~= "string" then
			ok = false
			missing ..= slot .. " "
		end
	end
	check("every animation slot exists and is a string", ok, missing)
end

print("\n-- classify: the vault's bands --")

local R = Detect.Result

check("below StepHeight is a step", Detect.classify(Config.StepHeight - 0.01) == R.Step)
check("StepHeight itself vaults", Detect.classify(Config.StepHeight) == R.Vault)
check("VaultMaxHeight still vaults", Detect.classify(Config.VaultMaxHeight) == R.Vault)
check("just above VaultMaxHeight mantles", Detect.classify(Config.VaultMaxHeight + 0.01) == R.Mantle)
check("MantleMaxHeight still mantles", Detect.classify(Config.MantleMaxHeight) == R.Mantle)
check("just above MantleMaxHeight refuses", Detect.classify(Config.MantleMaxHeight + 0.01) == R.TooHigh)
check("a negative height is a step", Detect.classify(-2) == R.Step, "standing above the thing you probed")

print("\n-- classifyReach: the mantle's band --")

local midReach = (Config.MantleGrabLow + Config.MantleGrabHigh) / 2
local okHeight = Config.MantleMaxHeight - 0.5

check("a lip in the middle of the band is a mantle", (Detect.classifyReach(midReach, okHeight)) == R.Mantle)
check("the top of the band still grabs", (Detect.classifyReach(Config.MantleGrabHigh, okHeight)) == R.Mantle)
check("the bottom of the band still grabs", (Detect.classifyReach(Config.MantleGrabLow, okHeight)) == R.Mantle)
check("out of reach above refuses", (Detect.classifyReach(Config.MantleGrabHigh + 0.1, okHeight)) == R.TooHigh)
check("already above the lip refuses", (Detect.classifyReach(Config.MantleGrabLow - 0.1, okHeight)) == R.None)

check(
	"too tall refuses even with a perfect lip",
	(Detect.classifyReach(midReach, Config.MantleMaxHeight + 1)) == R.TooHigh,
	"the absolute ceiling has to beat a well-placed lip"
)

do
	local _, reason = Detect.classifyReach(Config.MantleGrabHigh + 5, okHeight)
	check("a refusal carries a reason", type(reason) == "string" and #reason > 0)
end

print("\n-- the curves --")

check("smoothstep starts at 0", near(Shared.smoothstep(0), 0))
check("smoothstep ends at 1", near(Shared.smoothstep(1), 1))
check("smoothstep is clamped below", near(Shared.smoothstep(-5), 0))
check("smoothstep is clamped above", near(Shared.smoothstep(5), 1))

do
	local rising = true
	local last = -1
	for i = 0, 20 do
		local value = Shared.smoothstep(i / 20)
		if value < last then
			rising = false
		end
		last = value
	end
	check("smoothstep never goes backwards", rising, "a non-monotonic ease reads as a stutter")
end

do
	local from, to = Vector3.new(0, 0, 0), Vector3.new(10, 5, 0)

	local start = Shared.arcPoint(from, to, 0, Config.ArcHeight)
	local finish = Shared.arcPoint(from, to, 1, Config.ArcHeight)

	check("the vault arc starts where it should", near(start.X, 0) and near(start.Y, 0))
	check(
		"the vault arc reaches its destination",
		near(finish.X, 10) and near(finish.Y, 5),
		"a curve that stops short lands the player inside the wall"
	)

	local middle = Shared.arcPoint(from, to, 0.5, Config.ArcHeight)
	check("the vault arc bulges upward", middle.Y > 2.5, string.format("midpoint Y %.2f", middle.Y))
end

do
	local from = Vector3.new(0, 0, 0)
	local grab = Vector3.new(2, 5, 0)
	local to = Vector3.new(4, 8, 0)
	local hang = Config.HangFraction

	local start = Shared.mantlePoint(from, grab, to, 0, hang)
	local lip = Shared.mantlePoint(from, grab, to, hang, hang)
	local finish = Shared.mantlePoint(from, grab, to, 1, hang)

	check("the mantle starts at the start", near(start.X, 0) and near(start.Y, 0))
	check(
		"the mantle passes through the grab point",
		near(lip.X, 2) and near(lip.Y, 5),
		"the hang is where the two segments meet -- missing it clips the corner"
	)
	check("the mantle reaches the landing", near(finish.X, 4) and near(finish.Y, 8))

	local early = Shared.mantlePoint(from, grab, to, hang / 2, hang)
	check("the first segment climbs", early.Y > 0 and early.Y < 5)
end

-- ============================================================

print(string.format("\n%d passed, %d failed", passed, failed))

if failed > 0 then
	process.exit(1)
end

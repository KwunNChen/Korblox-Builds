--!strict
-- Every tunable for the bayonet.
--
-- Animation ids ship empty. Roblox assets are private to the place that owns
-- them, so an id lifted from another game silently does nothing -- upload your
-- own and paste the ids in below.

export type AssetId = number | string

local Config = {}

--[[
	The key that stabs.

	F is the obvious melee key and it is NOT available: TREK binds it to sprint
	in GlobalConfigs, alongside C (crouch), R (reload), Q (zoom), T (patrol),
	N (cursor), V (fire mode), LeftShift and LeftControl (zoom steps). G, X and
	B are the free ones.
]]
Config.Key = "G"

--[[
	Where the bayonet's stats live inside the weapon module.

	9, not 2, and the number is load-bearing. TREK's switchModes walks fire
	modes by INCREMENT:

		if (currentMode == 1 and not config[currentMode + 1]) then return end

	so a block at [2] would drop the bayonet straight into the V cycle. With
	nothing at [2] that walk stops dead and the player can never switch into it,
	while this system can still look the block up directly by index.
]]
Config.ConfigIndex = 9

--[[
	A weapon has a bayonet if its Tool contains something with this name.

	Detection is by instance rather than by a weapon whitelist on purpose:
	putting a bayonet on another rifle is then a modelling job, not a config
	edit.

	Only the NAME is checked, and the search is recursive. A loose Part under the
	Tool, a Model of several parts, nested or not, all count -- the class and the
	depth are yours to decide.

	This instance's position AND size are the hitbox. A longer blade genuinely
	reaches further and a wider one genuinely catches more, with no config to
	update -- the geometry is the weapon.
]]
Config.BayonetPartName = "Bayonet"

--[[
	Slack added around the blade before testing for overlap.

	Measured in the ATTACKER'S frame -- level, facing where they face -- not in
	the blade's own axes. The blade's axes roll with the thrust animation, which
	made "vertical" mean something different at every point in the swing. These
	three always mean what they say:

		SIDE      how far off-centre your aim can be
		VERTICAL  how much height difference is forgiven
		FORWARD   reach past the tip

	A bayonet needs a lot of this. The KR-61's blade is 0.19 x 0.53 x 1.94 studs
	-- a sliver -- and a character is a 5 stud pillar. Padding is not a fudge
	factor here; it is most of the hitbox.

	These values were picked against the real model rather than by feel. The
	blade centre sits 2.66 studs ahead of the torso and is 1.94 long, so FORWARD
	1.5 puts the reach at about 5.1 studs -- just past the tip. SIDE 1.25 lets
	someone 1.5 studs off-centre be hit but not someone 4 studs to your left.
	VERTICAL 2.5 covers a whole character from a stab aimed at the chest.

	Raise VERTICAL first if stabs feel like they should have landed.
]]
Config.HitPadSide = 1.25
Config.HitPadVertical = 2.5
Config.HitPadForward = 1.5

-- No separate range setting. The three numbers above ARE the range: the box is
-- built around the blade and reaches exactly as far as they say. A second
-- distance check would only be another number to keep in sync with them.

--[[
	How long after the keypress the blade keeps being tested, in seconds.

	NOT a delay -- a sweep. The blade is sampled repeatedly across this window as
	the thrust animation drives it forward, and the first valid overlap wins. It
	is what makes the hit land when the blade actually arrives rather than at the
	instant the key went down.

	Should comfortably cover the extend portion of your thrust animation.
]]
Config.HitWindow = 0.35

-- Seconds between samples inside that window. Small enough that a fast blade
-- cannot pass through a torso between two tests, which is the tunnelling that
-- makes Touched unreliable for melee.
Config.HitSampleInterval = 0.03

-- Seconds between thrusts.
Config.Cooldown = 1.2

--[[
	The server allows a thrust slightly sooner than the client asks for one.

	Both sides measure the same Cooldown from their own clock, so without a
	little slack, network jitter alone would have the server reject presses the
	player made in good time. The client is the one that paces the attack; this
	is only here so honest presses are not thrown away.
]]
Config.ServerCooldownTolerance = 0.9

-- Require the player to already be sprinting. Off by default: the bayonet is
-- usable standing still, and sprinting is what changes the pose rather than
-- what unlocks the attack.
Config.RequireSprint = false

-- The pose held while sprinting with a bayonet fitted. Plays at Action
-- priority, so it outranks the gun's own SprintHold without this system
-- touching TREK's animation code.
Config.ChargeAnimation = "PLACEHOLDER"

-- The stab itself.
Config.ThrustAnimation = 130508149089530

-- How long the thrust animation is allowed to run before it is stopped, as a
-- backstop for a clip that never reports Stopped.
Config.ThrustLength = 1

--[[
	Print what the server decided on every stab. Off unless you are debugging.

	Turn it on when a thrust is not landing. Every stab then reports itself, and
	the three outcomes are told apart on purpose:

		REFUSED   the stab never got as far as detection, and why
		MISS      it swept, and how many studs outside the box the nearest
		          person was -- so the padding above becomes arithmetic
		hit       what was hit, in which limb, on which sample

	A miss also reports how far the blade travelled during the sweep. A stud or
	more means the server watched a real thrust and the box was short; close to
	zero means the server never saw the animation, which padding cannot fix.
]]
Config.Debug = false

--[[
	Turn whatever went into an animation field into a usable asset url.

	All of these are accepted, because all of them are things you get from
	copying an id out of Studio or off the website:

		18237274
		"18237274"
		"rbxassetid://18237274"
		"http://www.roblox.com/asset/?id=18237274"

	Blindly prefixing instead would turn an already-prefixed entry into
	"rbxassetid://rbxassetid://18237274", which fails to load and reports only
	"asset was not found".
]]
function Config.toAssetUrl(id: AssetId): string
	if type(id) == "number" then
		return "rbxassetid://" .. id
	end

	local text = tostring(id):match("^%s*(.-)%s*$") or ""

	if text:match("^%d+$") then
		return "rbxassetid://" .. text
	end

	-- Peel any number of rbxassetid:// prefixes. The loop rather than a single
	-- strip is what recovers the doubled form.
	local stripped = text
	while true do
		local rest = stripped:match("^rbxassetid://(.*)$")
		if not rest then
			break
		end
		stripped = rest
	end
	if stripped:match("^%d+$") then
		return "rbxassetid://" .. stripped
	end

	local fromQuery = text:match("[?&]id=(%d+)")
	if fromQuery then
		return "rbxassetid://" .. fromQuery
	end

	local fromLibrary = text:match("roblox%.com/[%w]+/(%d+)")
	if fromLibrary then
		return "rbxassetid://" .. fromLibrary
	end

	-- Anything else is passed through untouched. Matching a trailing digit run
	-- here would mangle a path like "sounds/x.mp3" into asset id 3.
	return text
end

-- A slot deliberately left empty and waiting for a real id.
Config.Placeholder = "PLACEHOLDER"

function Config.isPlaceholder(id: AssetId): boolean
	return type(id) == "string" and id:upper():match("^%s*PLACEHOLDER") ~= nil
end

-- The url for an animation field, or nil if it is unset or unusable. Callers
-- treat nil as "this animation is not configured" and carry on without it -- a
-- missing pose must not stop the bayonet from doing damage.
function Config.animationUrl(id: AssetId): string?
	if Config.isPlaceholder(id) then
		return nil
	end

	local url = Config.toAssetUrl(id)
	if not url:match("^rbxassetid://%d+$") then
		return nil
	end

	return url
end

--[[
	The configured key, resolved once.

	Walks GetEnumItems rather than indexing Enum.KeyCode directly: an
	unrecognised name throws ("The enum item 'X' does not exist for enum
	'KeyCode'"), so the obvious `Enum.KeyCode[name] or default` guard protects
	nothing and the error lands at require time, taking the controller with it.
]]
function Config.resolveKey(): Enum.KeyCode
	for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
		if item.Name == Config.Key then
			return item
		end
	end

	warn(string.format(
		"[TREKBayonet] Config.Key %q is not a real KeyCode -- falling back to G",
		tostring(Config.Key)
	))
	return Enum.KeyCode.G
end

return Config

--[[
	GasRuntime
	Boots the gas grenade service, once TREK is actually there.

	The core Installer relocates a large part of the DataModel on startup and
	only then sets ReplicatedStorage.TREK_INSTALLED. Requiring
	ServerStorage.TREKDamageModule before that flag flips is a race that usually
	wins in Studio and loses on a live server under load, which is the worst
	possible failure mode to debug.

	Gating here rather than inside GasService keeps the service itself testable
	without a live TREK install.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[
	Bounded, and loud when it fails.

	An unbounded WaitForChild inside a require chain does not fail -- it hangs
	the module forever, and every module waiting on THIS one hangs with it.
	Adding one new file to this chain once killed the entire service that way:
	the grenade quietly stopped being held, with nothing in the output to say
	why, because nothing had errored. It was still waiting.

	Ten seconds is far longer than replication or install ever needs and far
	shorter than a playtest, so a missing file announces itself instead.
]]
local function expect(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name) or parent:WaitForChild(name, 10)

	if not child then
		error(string.format(
			"[TREKGasGrenade] %s has no child %q -- the install is incomplete. "
				.. "Check every folder moved out of the staging folder, including "
				.. "any added since you last installed.",
			parent:GetFullName(), name
		), 0)
	end

	return child
end

local package = expect(ReplicatedStorage, "TREKGasGrenade")
local GasShared = require(expect(package, "GasShared"))

GasShared.waitForTREK()

local GasService = require(expect(script.Parent, "GasService"))

GasService.start()

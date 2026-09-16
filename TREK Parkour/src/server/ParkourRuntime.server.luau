--!strict
--[[
	The only Script in this package. Everything else is a module.

	If this file is not in ServerScriptService, nothing runs. If it is somewhere
	the server does not execute scripts -- ServerStorage, for instance -- nothing
	runs and nothing complains, which is the single most common bad install.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[
	Wait for TREK to finish installing itself before touching anything.

	TREK_INSTALLED is set true by TREKServerGeneral only after shared.S is fully
	populated, so this is the earliest moment TREK's own values are safe to read.
	It is the same gate TREK Bayonet and TREK Voicelines use, verbatim.

	Note this never times out. That is deliberate and it is the one hard
	dependency in the package: a place without TREK has no TREK_PlrConfig, no
	CanSprint and no weapons to holster, so there is nothing here to degrade to.
]]
repeat
	task.wait()
until ReplicatedStorage:WaitForChild("TREK_INSTALLED").Value

local ParkourShared = require(ReplicatedStorage:WaitForChild("TREKParkour"):WaitForChild("ParkourShared"))
local ParkourService = require(script.Parent:WaitForChild("ParkourService"))

ParkourService.init(ParkourShared.ensureRemotes())

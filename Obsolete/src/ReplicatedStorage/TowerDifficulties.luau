-- Raid difficulties, picked at the tavern table (F) and read by ServerScriptService.TowerRun,
-- StarterPlayerScripts.Staging and RaidReport. A wave is one cleared floor.
--   floors        floors before the roof (TowerRun's Floors attribute still overrides, for Studio tests)
--   respawnWaves  cleared floors a killed player sits out
--   kit           tools given on every spawn (templates in ServerStorage); medics get a Medkit on top
--   friendlyFire  true: teammates' bullets and explosions hurt each other (SPH GameConfig.teamKill, set by TowerRun)
--   bossFloors    floors that hold a mini-boss (ServerStorage.TowerBosses); bossPool = the boss ids one is picked from
return {
	order = { "Extensive Support", "Frontline", "Behind Enemy Lines" }, -- easiest to hardest; F cycles in this order
	default = "Frontline",
	["Extensive Support"] = { floors = 5, respawnWaves = 1, kit = { Bandage = 2, Medkit = 1 }, bossFloors = { 5 }, bossPool = { "Signals", "Jammer" }, accent = Color3.fromRGB(110, 200, 120) },
	Frontline = { floors = 10, respawnWaves = 2, kit = { Bandage = 2, Medkit = 1 }, bossFloors = { 5, 10 }, bossPool = { "Signals", "Jammer", "Juggernaut" }, accent = Color3.fromRGB(235, 192, 92) },
	-- shortcut: same floors and enemies as Frontline for now; harder enemies come later
	["Behind Enemy Lines"] = { friendlyFire = true, floors = 12, respawnWaves = 2, kit = { Bandage = 2, Medkit = 1 }, bossFloors = { 3, 6, 9, 12 }, bossPool = { "CBRN", "Signals", "Jammer", "Juggernaut" }, accent = Color3.fromRGB(215, 75, 65) },
}

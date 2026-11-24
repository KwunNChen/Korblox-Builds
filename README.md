# OPEN-SOURCE

All my Roblox builds for Korblox are open-sourced, anyone wanting to build their
own games can go ahead and utilize the assets I built!

## ALL MADE BY PLAGUEBYTE (pb6008 on discord for inquiries!)

---

## The packages

| | Model file | What it is | Needs |
|---|---|---|---|
| [AA Truck](AI/AA%20Truck) | `AA Truck.rbxm` | BM-21 truck firing homing anti-air rockets: Bloxian crews shoot down enemy Phantoms, AC-130s and Apaches | Bloxian (for NPC crews), Vehicle Spawner (to spawn it crewed) |
| [AC130](AI/AC130) | `AC130.rbxm` | AC-130 gunship: it circles high up and fires artillery barrages at targets it picks | Bloxian, Random Arty |
| [Abrams](AI/Abrams) | `Abrams.rbxm` | M1A2 tank that Bloxians crew: crushes, machine-guns and shells you | Bloxian (for NPC crews) |
| [Apache](AI/Apache) | `Apache.rbxm` | AH-64 that Bloxians fly and gun: M230 and Hellfires; the crew parachute out when it is shot up | Bloxian (for NPC crews) |
| [F4](AI/F4) | `F4.rbxm` | Self-flying F-4 Phantom from the Vehicle Spawner: clears enemy AC-130s, Phantoms and Apaches from the sky, then strafes the enemy near its own troops with its gun | Vehicle Spawner (to spawn it) |
| [Door system](Door%20system) | `BlastDoor.rbxm` | Tagged blast doors that split down the middle | - |
| [KorbloxAI](AI/KorbloxAI) | `KorbloxAI.rbxm` | The whole AI system in one file: soldiers, spawner, every vehicle and artillery, with a one-line installer | R6 for gore |
| [Objective System](Objective%20System) | `ObjectiveSystem.rbxm` | Capture points with terminals and a round timer | - |
| [Random Arty](AI/Random%20Arty) | `RandomArtillery.rbxm` | Randomised artillery barrages, with gore | R6 |
| [Ski](Ski) | `Ski.rbxm` | Skiing: physics, poses, ragdoll wipeouts | - |
| [Skull Death Screen](Skull%20Death%20Screen) | `SkullDeathScreen.rbxm` | Death screen: the Evil Skull Man and a clip, respawn when it ends | - |
| [TREK Bayonet](TREK%20Bayonet) | `TREKBayonet.rbxm` | Bayonet melee for TREK rifles | TREK 4 |
| [TREK Gas Grenade](TREK%20Gas%20Grenade) | `TREKGasGrenade.rbxm` | Cookable gas grenades that deny ground | TREK 4 |
| [TREK Parkour](TREK%20Parkour) | `TREKParkour.rbxm` | Vaulting and ledge mantling | TREK 4 |
| [TREK Voicelines](TREK%20Voicelines) | `TREKVoicelines.rbxm` | Spatial voice barks for TREK | TREK 4 |
| [Warthog](AI/Warthog) | `Warthog.rbxm` | Turret buggy that players can drive and Bloxians will crew | Bloxian (for NPC crews) |
| [Variable Snowstorm](Variable%20Snowstorm) | `VariableSnowstorm.rbxm` | Weather that builds and breaks, with lightning | - |

---

## How installing works

Every package is the same shape, so learn it once.

**1. Drag the `.rbxm` into ServerStorage.** Always ServerStorage. Scripts do not
execute there, and that is what you want. Drop it into ServerScriptService or
Workspace and the server scripts start running before the modules they need
exist, and it fails in ways that look like bugs.

**2. The folders inside are signposts, not things to move.** A folder called
`ServerScriptService` is a label telling you where its *contents* belong. You
open it and move the folder **inside** it into the real service.

```
KorbloxSki                  <- staging folder, delete when done
|-- README                     read me, not installed
|-- ReplicatedStorage          <- SIGNPOST, do not move this
|   |-- Ski                    <- move THIS into game.ReplicatedStorage
|   `-- SkiRemotes             <- and THIS
`-- ServerScriptService        <- SIGNPOST
    |-- Ski                    <- move THIS into game.ServerScriptService
    `-- Common                 <- and THIS
```

Moving the signpost itself gives you `ReplicatedStorage.ReplicatedStorage.Ski`,
and nothing finds anything.

**3. Delete the empty staging folder** once everything is out of it.

Then press Play.

---

## Where every folder goes

`SPS` is `game.StarterPlayer.StarterPlayerScripts`.

### Door system - `BlastDoor.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `BlastDoor` | ReplicatedStorage |
| `ServerScriptService/` | `BlastDoor` | ServerScriptService |
| `Tools/` | `BuildExampleDoor` | *optional* - leave in ServerStorage, it is a command-bar helper |

Then tag any Model containing parts named `Left` and `Right` with the tag
`BlastDoor`.

### Objective System - `ObjectiveSystem.rbxm`

| From | Move | Into |
|---|---|---|
| `Workspace/` | `TObjectiveSystem` | **Workspace** |

The only one that installs into Workspace. It has to live there - the scripts
resolve their config by folder position, and the terminals are real parts.

### Random Arty - `RandomArtillery.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `Artillery`, `ArtilleryState`, `ArtilleryShell` | ReplicatedStorage |
| `ServerScriptService/` | `Artillery`, `Common` | ServerScriptService |
| `StarterPlayerScripts/` | `Artillery` | SPS |

Miss `ArtilleryShell` and it disables itself with a warning. Miss the SPS half
and barrages still land and still kill, but nothing draws - which looks exactly
like a broken install.

### Ski - `Ski.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `Ski`, `SkiRemotes` | ReplicatedStorage |
| `ServerScriptService/` | `Ski`, `Common` | ServerScriptService |
| `StarterPlayerScripts/` | `Ski` | SPS |
| `Tools/` | `AnimationRig` | *optional* - leave in ServerStorage |

`SkiRemotes` is a convenience: the server rebuilds any missing remote at start.

### Skull Death Screen - `SkullDeathScreen.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `SkullDeathScreen` | ReplicatedStorage |
| `ServerScriptService/` | `SkullDeathScreen` | ServerScriptService |
| `StarterPlayerScripts/` | `SkullDeathScreen` | SPS |

**It turns `CharacterAutoLoads` off** and spawns every character itself, so the
respawn waits for the clip to finish. Don't pair it with another custom respawn
script. Like Voicelines, the sound id is mine - replace it with your own upload.

### TREK Bayonet - `TREKBayonet.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `TREKBayonet` | ReplicatedStorage |
| `ServerScriptService/` | `TREKBayonet` | ServerScriptService |
| `StarterPlayerScripts/` | `TREKBayonet` | SPS |
| `ServerStorage/` | `TREKBayonetPoses` | *optional* - ServerStorage, only to edit the animations |
| - | `BayonetWeaponMode` | **not installed** - a snippet you paste into a weapon module |

Its README has a command-bar script that does all four moves for you.

### TREK Gas Grenade - `TREKGasGrenade.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `TREKGasGrenade` | ReplicatedStorage |
| `ServerScriptService/` | `TREKGasGrenade` | ServerScriptService |
| `ServerStorage/TREKToolHandlers/` | `Throwable` | your existing `ServerStorage.TREKToolHandlers`, alongside `Gun` |
| `GunConfigs/` | `Gas Grenade` | your existing `GunConfigs`, alongside your weapons |

The only package that installs into `TREKToolHandlers`. Vanilla TREK ships one
tool handler, `Gun`, and this adds the second - which is why it is the one TREK
package whose tool is not a weapon module.

**The `Gas Grenade` config must keep that exact name**, matching the Tool. Several
TREK paths resolve a tool's config by `tool.Name` and ignore the `TConfigToUse`
attribute, so identical names are the only arrangement every lookup agrees on.

The meshes ship separately in `GasGrenades.rbxm` - drop both models into
`ServerStorage.TREKGasGrenade` and run `tools/PrepareGrenadeRig` from the command
bar, which rigs them and leaves a finished tool in StarterPack. You never need to
weld or unanchor anything by hand; the rig is rebuilt at runtime on every spawn,
because the art exports anchored and unwelded every time.

### TREK Parkour - `TREKParkour.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `TREKParkour` | ReplicatedStorage |
| `ServerScriptService/` | `TREKParkour` | ServerScriptService |
| `StarterPlayerScripts/` | `TREKParkour` | SPS |
| `Tools/` | `ParkourRig` | *optional* - leave in ServerStorage, it is the animator's helper |

The only TREK package with no `Common` folder. It holds a climbing player with
`PlatformStand` rather than a WalkSpeed modifier, and its one WalkSpeed write -
the brief boost for landing a vault - multiplies whatever value is already there
and restores it, so a Ski or Variable Snowstorm modifier still gets its say.

Install TREK Bayonet alongside it if you can: its `HolsterService` slings the
weapon on the player's back during a mantle instead of it vanishing. Nothing
breaks without it.

### TREK Voicelines - `TREKVoicelines.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `TREKVoicelines` | ReplicatedStorage |
| `ServerScriptService/` | `TREKVoicelines` | ServerScriptService |
| `StarterPlayerScripts/` | `TREKVoicelines` | SPS |

The SPS half is only the audio preloader - skip it and everything still works,
the first use of each clip is just late.

**The sound ids in the config are mine and will not play in your game.** Roblox
audio is private to the place that owns it; replace them with your own uploads.

### Variable Snowstorm - `VariableSnowstorm.rbxm`

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `Weather`, `WeatherState`, `ThunderStrike` | ReplicatedStorage |
| `ServerScriptService/` | `Weather`, `Common` | ServerScriptService |
| `StarterPlayerScripts/` | `Weather` | SPS |

Miss `ThunderStrike` and lightning disables itself with a warning; everything
else runs. Miss the SPS half and the storm still slows players but nothing draws.

---

## Installing more than one

**Three packages ship a `Common` folder** - Random Arty, Ski and Variable
Snowstorm - each holding `CharacterCache` and `SpeedService`.

If your game already has one, **do not replace it.** Open the new package's
`Common` and drag those two modules into your existing folder, skipping any that
are already there. The code in all three copies is identical (only the header
comments differ), so whichever you keep is fine.

`SpeedService` exists precisely so these can coexist: it is the single owner of
`Humanoid.WalkSpeed`, and systems register named modifiers with it rather than
assigning the property. Two systems both writing `WalkSpeed` directly would fight
each other - a skier caught in a snowstorm is the obvious case.

## Which ones need TREK

**TREK Bayonet**, **TREK Parkour** and **TREK Voicelines** hook into a TREK 4
install and do nothing without one. None of them modifies TREK: they add
listeners to remotes and values TREK already owns, so removing the folder leaves
your install byte-for-byte as it was.

They also know about each other. With both installed, a bayonet thrust gets its
own hit and miss barks; with only Voicelines, that event stays silent and nothing
errors. Voicelines does the same with Objective System for capture barks.

Everything else is standalone.

## Editing after install

Each package has exactly one config file, and it is the only thing you should
need to touch:

| Package | Config |
|---|---|
| Door system | `ReplicatedStorage.BlastDoor.DoorConfig` |
| Objective System | inside `Workspace.TObjectiveSystem` |
| Random Arty | `ReplicatedStorage.Artillery.ArtilleryConfig` |
| Ski | `ReplicatedStorage.Ski.SkiConfig` |
| Skull Death Screen | `ReplicatedStorage.SkullDeathScreen.DeathScreenConfig` |
| TREK Bayonet | `ReplicatedStorage.TREKBayonet.BayonetConfig` |
| TREK Parkour | `ReplicatedStorage.TREKParkour.ParkourConfig` |
| TREK Voicelines | `ReplicatedStorage.TREKVoicelines.VoicelineConfig` |
| Variable Snowstorm | `ReplicatedStorage.Weather.WeatherConfig` |

Every package also carries its full README as a ModuleScript inside the model, so
the instructions travel with the file even if it gets separated from this repo.

## Shared code

`AI/Shared/` holds code that several combat packages build in as children
of their model, so each `.rbxm` still works on its own:

| Module | What it is | Built into |
|---|---|---|
| `Sides` | Who is on which side: a Bloxian's or player's team, an aircraft's side, enemy aircraft | F4, AA Truck, Abrams, Apache, Warthog, AC130 |
| `VehicleKit` | Crew armour, who a vehicle may hurt, kill counters, an aircraft going down and its wreck, parachutes, blasts | F4, AA Truck, Abrams, Apache, Warthog, AC130 |
| `AirDefense` | Flares, how they fool missiles, aircraft health and damage | F4, AA Truck |
| `Effects` | Vehicle effects on each client, such as dust | Abrams, AA Truck, Apache, Warthog |
| `Spearhead` | Lets SPEARHEAD guns damage the vehicle (one hit per round fired) | Abrams, AA Truck, Apache, Warthog |

Change the rules there once, then rebuild each package. Check the side rules
and who hears radio calls with:

```bash
cd AI && /c/Users/pbche/.rokit/bin/lune.exe run Shared/tests/sides.test.luau
```

```bash
cd AI && /c/Users/pbche/.rokit/bin/lune.exe run Shared/tests/radio.test.luau
```

The other tests (`nav`, `idle`, `chatter`, `squad`, `sight`, `vehicle`) run the same way. To
check that every script still compiles:

```bash
cd AI && /c/Users/pbche/.rokit/bin/lune.exe run Shared/tools/check.luau Bloxian .
```

The Bloxian and Vehicle spawners share `AI/Bloxian/spawner/BloxianSpawner/SpawnerKit.luau`.

## Live-syncing the combat packages with Rojo

The Rojo plugin syncs one project at a time, so serving `Abrams` alone leaves
the Bloxian in ServerStorage stale. `default.project.json` in this folder serves
Bloxian, the Warthog, Abrams, AA Truck, Apache, F4 and AC130, Random Arty, and the spawner tool with both its server scripts together. Run this from this folder, with any other
`rojo serve` stopped:

```bash
/c/Users/pbche/.rokit/bin/rojo.exe serve
```

| Synced to | From |
|---|---|
| `ServerStorage.BLOXIAN` (the spawner's template) | `AI/Bloxian/src` |
| `ServerScriptService.BloxianSpawner`, `StarterPack.Bloxian Spawner` | `AI/Bloxian/spawner` |
| `ServerStorage.BloxianVehicles.Warthog` / `.Abrams` / `.Apache` / `.F4 Phantom` / `.AA Truck` (the vehicle spawner's templates) | `Warthog/package.project.json`, `Abrams/package.project.json`, `Apache/package.project.json`, `F4/package.project.json`, `AA Truck/package.project.json` |
| `ServerScriptService.VehicleSpawner` (Vehicles mode of the Bloxian Spawner) | `AI/Vehicle Spawner/spawner` |
| `ServerStorage.BloxianVehicles.AC130` | `AI/AC130/package.project.json` |
| `ReplicatedStorage.Artillery`, `.ArtilleryState`, `.ArtilleryShell`, `.ArtilleryBlast`, `ServerScriptService.Artillery`, `StarterPlayer.StarterPlayerScripts.Artillery` (Random Arty) | `Random Arty/src` |

Random Arty's `ServerScriptService.Common` syncs too. Anything else already in
that folder, such as Ski's or Variable Snowstorm's modules, stays.

Before the first sync, delete any hand-inserted copies of these from the place
(for Random Arty: the six listed above, not `Common`):
Rojo only manages the ones it created. Soldiers and vehicles already standing
in Workspace are clones and do not update; clear them and spawn fresh ones with
the spawners.

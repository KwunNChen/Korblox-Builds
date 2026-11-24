# Skull Death Screen

When you die, the screen fades to black and the Evil Skull Man fades in, skull
first, then pulls back to show his top half. A clip plays, and the screen holds
until it finishes. Then you respawn behind the black and it fades away.

The rig renders in a ViewportFrame, so it never exists in Workspace.

## Install

**1. Drag `SkullDeathScreen.rbxm` into ServerStorage.** Always ServerStorage -
scripts do not execute there.

**2. The folders inside are signposts, not things to move.** Open each one and
move the folder *inside* it into the real service:

```
KorbloxSkullDeathScreen     <- staging folder, delete when done
|-- README                     read me, not installed
|-- ReplicatedStorage          <- SIGNPOST, do not move this
|   `-- SkullDeathScreen       <- move THIS into game.ReplicatedStorage
|-- ServerScriptService        <- SIGNPOST
|   `-- SkullDeathScreen       <- move THIS into game.ServerScriptService
`-- StarterPlayerScripts       <- SIGNPOST
    `-- SkullDeathScreen       <- move THIS into StarterPlayer.StarterPlayerScripts
```

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `SkullDeathScreen` | ReplicatedStorage |
| `ServerScriptService/` | `SkullDeathScreen` | ServerScriptService |
| `StarterPlayerScripts/` | `SkullDeathScreen` | SPS |

**3. Delete the staging folder.**

**4. Replace the sound id.** The one in the config is mine, and Roblox audio is
private to the place that owns it - in your game it plays as silence. If it
fails to load, the screen holds for `FallbackDuration` and warns in Output.

## What's here

| | |
|---|---|
| `src/shared` | `DeathScreenConfig` holds every tunable. `Evil Skull Man` is the rig on screen |
| `src/server` | `DeathScreenRuntime` holds respawns until the screen finishes, and owns the `Finished` remote |
| `src/client` | `DeathScreenClient` builds and plays the screen |

## Tuning: `ReplicatedStorage.SkullDeathScreen.DeathScreenConfig`

| | |
|---|---|
| `SoundId`, `Volume` | the clip. The screen lasts as long as it does |
| `ModelName`, `FocusPartName` | which rig, and which part the close-up frames (falls back to `Head`) |
| `FieldOfView`, `CloseUpPadding`, `WidePadding` | framing - bigger padding pulls the camera back |
| `FadeTime`, `ZoomTime` | the fades and the pull-back |
| `SwayHeight`, `SwayAngle`, `SwayTime` | the slow drift while the clip plays. Zero both for a still shot |
| `LoadTimeout`, `FallbackDuration` | what happens when the clip will not load |
| `MaxRespawnWait` | server safety net - respawns anyway after this long. Keep it longer than the clip |
| `Ambient`, `LightColor`, `LightDirection` | lighting inside the viewport |

To use a different rig, drop it into `ReplicatedStorage.SkullDeathScreen` and
set `ModelName`. R6 and R15 both work. It needs a `Head` (or whatever
`FocusPartName` names) and a `Torso` or `UpperTorso`.

## Respawning

**This package turns `Players.CharacterAutoLoads` off** and spawns every
character itself: once on join, and after each death when the client reports
the screen is done (or `MaxRespawnWait` runs out). If another script in your
place also takes over respawning, the two will fight - pick one.

An admin `LoadCharacter` (Objective System's included) still works. It just
cuts the screen short.

**Compatible with `RagdollDeath/ragdoll.luau`** and Random Arty's dismemberment.
Both act on the body in Workspace, which carries on behind the black screen.
Random Arty clears corpses on `CharacterAdded`, which does not depend on
auto-loading.

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o SkullDeathScreen.rbxm
```

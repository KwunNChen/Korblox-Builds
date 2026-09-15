# Blast Door

A two-leaf blast door for Roblox. The halves slide apart from the middle to
open and slide back together to close, and anyone still caught in the gap
when it closes dies -- turned to red mist, not a ragdoll.

Entirely server-side. No client scripts, no remotes, nothing to place in
StarterPlayer.

## Install

**1. Drag `BlastDoor.rbxm` into ServerStorage.** Always ServerStorage — scripts
do not execute there. Drop it into ServerScriptService or Workspace and the
server scripts start running before the modules they need exist.

**2. The folders inside are signposts, not things to move.** Open each one and
move the folder *inside* it into the real service:

```
KorbloxBlastDoor            <- staging folder, delete when done
|-- README                     read me, not installed
|-- ReplicatedStorage          <- SIGNPOST, do not move this
|   `-- BlastDoor              <- move THIS into game.ReplicatedStorage
|-- ServerScriptService        <- SIGNPOST
|   `-- BlastDoor              <- move THIS into game.ServerScriptService
`-- Tools
    `-- BuildExampleDoor       optional, see below
```

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `BlastDoor` | ReplicatedStorage |
| `ServerScriptService/` | `BlastDoor` | ServerScriptService |

Moving a signpost itself gives you `ReplicatedStorage.ReplicatedStorage.BlastDoor`
and nothing finds anything.

**3. Delete the staging folder** — or keep it, since `Tools` is a command-bar
helper that never runs on its own and does no harm sitting in ServerStorage.

**4. Make a door.** Two parts or models named `Left` and `Right`, built touching
in the middle (that is the closed position), grouped in a Model. Tag that Model
`BlastDoor` in the Properties panel's Tags box. The server picks up anything
tagged this way, including doors added after the game has started.

No art yet? Once installed, run this in the **command bar** for a test door:

```lua
require(game.ServerStorage.KorbloxBlastDoor.Tools.BuildExampleDoor).build(workspace)
```

After install, the only file you edit is `ReplicatedStorage.BlastDoor.DoorConfig`.

## Building a door

1. Model two halves named `Left` and `Right` (parts or whole models, doesn't
   matter), built in their **closed** position -- touching in the middle.
2. Group them in a Model and tag that Model `BlastDoor` (Properties panel,
   Tags box at the bottom).
3. That's it for Proximity activation. For a button, drop a `ProximityPrompt`
   on whatever part should trigger it -- if you don't, the server puts a
   default one on a part named `Button`, or on `Left` if there's no `Button`
   either.

No example on hand? Run this from the Command Bar once the package is
installed and it drops a working one into Workspace:

```
require(game.ServerStorage.KorbloxBlastDoor.Tools.BuildExampleDoor).build(workspace)
```

## What's here

| | |
|---|---|
| `src/shared` | `DoorConfig` holds every tunable. `DoorShared` has the axis/box maths |
| `src/server` | `DoorService` owns motion and activation, `DoorCrush` handles the kill, `DoorRuntime` wires up tagged doors as they appear |
| `src/tools` | `BuildExampleDoor`, a Studio helper for testing. Never runs in game |

## Tuning: `ReplicatedStorage.BlastDoor.DoorConfig`

| | |
|---|---|
| `SlideAxis`, `SlideDistance` | which way the halves travel, and how far |
| `OpenTime`, `CloseTime`, `Easing*` | the tween |
| `ActivationMethod` | `"Proximity"`, `"Button"`, or `"Both"` |
| `SenseRadius`, `CloseDelay` | proximity: how close counts, how long empty before it shuts |
| `ButtonPartName`, `Button*` | button: where the prompt goes and how it reads |
| `AutoCloseDelay` | button-mode only -- 0 leaves closing entirely to the button |
| `OpenSoundId`, `CloseSoundId` | ship silent, see the note below |
| `CrushGapThreshold` | how narrow the gap has to be before standing in it is fatal |
| `CrushZoneHeight`, `CrushZoneDepth` | size the detection box to your actual doorway |
| `Mist*` | color, particle count, speed, size, sound |

Sound ships silent. Roblox audio is private per place, so an id copied from
another game plays as nothing and reports no error -- paste your own in.

## How it decides who's caught

While closing, every frame checks a box centered on the shrinking gap between
the two halves. Once that gap narrows past `CrushGapThreshold`, anyone with a
`HumanoidRootPart` still inside it dies -- so walking through early is safe,
and only the actual pinch is lethal. The door does not reverse or pause for
this; a blast door that stops for what's in the way stops being a hazard.

## The kill itself

`DoorCrush.kill` sets Health to 0 like any other death, but the corpse never
appears: parts go invisible and non-colliding first, a burst of red particles
fires at the last known position, and the model is destroyed a moment later.
Nothing stands there limp and nothing ragdolls.

**Compatible with `RagdollDeath/ragdoll.luau`.** Before killing, the victim
gets a `SuppressRagdoll` attribute (the name lives in `DoorConfig`). The
shared ragdoll script checks for that attribute and backs off if it's set --
so if both are installed in the same place, a crush death still turns to mist
instead of also ragdolling for a frame first. Uninstalled, the door works
identically; it never depended on that script existing.

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o BlastDoor.rbxm
```

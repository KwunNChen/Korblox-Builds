# TREK Parkour

Vaulting and ledge mantling for TREK 4.

Sprint into low cover and go over it. Jump at a wall, press jump again, and haul
yourself up — with your weapon slung and your sprint gone until you are standing.

**Requires TREK 4.** It adds listeners to values and remotes TREK already owns and
modifies nothing. Removing the folders leaves your install byte-for-byte as it was.

## Status

| Phase | What it adds | State |
|---|---|---|
| 0 | Package scaffold, TREK install gate, session and teardown plumbing | **done** |
| 1 | Obstacle detection and the Studio probe tool | not started |
| 2 | Sprint vault | not started |
| 3 | Ledge mantle, the lockout, and the fail-safes | not started |
| 4 | Animator handoff, config test, docs | not started |

Wall climbing, grappling, sliding and stamina are deliberately out of scope for
v1. See the roadmap for why.

## Install

`SPS` is `game.StarterPlayer.StarterPlayerScripts`.

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `TREKParkour` | ReplicatedStorage |
| `ServerScriptService/` | `TREKParkour` | ServerScriptService |
| `StarterPlayerScripts/` | `TREKParkour` | SPS |

Then delete the empty wrapper folder.

Unlike Ski, Random Arty and Variable Snowstorm, **there is no `Common` folder**.
Those three ship one because they all write `Humanoid.WalkSpeed` and would fight
each other over it. This package never touches WalkSpeed, so it has nothing to
share and nothing to collide with.

## Config

`ReplicatedStorage.TREKParkour.ParkourConfig` — the only file you should need to
open. Turn on `DebugLog` while tuning; every refusal prints its reason, and
"too high" and "no room up there" are fixed by different numbers.

## Why it works the way it does

Three facts about TREK shape every decision in here, and they are worth knowing
before changing anything:

**TREK rewrites `Humanoid.WalkSpeed` every 100ms.** `MovementHandler` runs a
`while true … task.wait(.1)` loop that flips `Sprinting`, and each flip writes the
speed. So this package never sets WalkSpeed to hold a player still — it uses
`PlatformStand`, which makes those writes irrelevant.

**TREK rewrites `HumanoidRootPart.CFrame` every frame while a weapon is out.**
`HeadAndArmsController` forces the yaw to the mouse and flattens pitch and roll.
Position survives; rotation does not. That asymmetry is why the two moves differ:
the vault only translates and keeps the weapon out, while the mantle unequips —
which makes TREK's own gun handler call `HeadArmsModule:Stop()` and hand the
rotation back.

**`PlatformStand` is TREK's paralysis marker.** `TREKGibsModule` sets it on a
player who has lost both legs and never clears it. So this package refuses to
start a move on a character that already has it set, and only ever restores it to
`false` when it set it itself. Otherwise a mantle would cure paralysis.

## Building

```bash
rokit install
```

```bash
rojo build package.project.json -o TREKParkour.rbxm
```

`default.project.json` is the dev project — `rojo serve` it into a Studio place
with TREK already installed. It marks the shared services `$ignoreUnknownInstances`
so syncing does not strip TREK out.

`package.project.json` is the distribution project; its service names are plain
Folders acting as signposts, which is what the install table above walks you
through.

## Made by

PlagueByte (pb6008 on Discord). TREK is not mine and is not included here.

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
| 1 | Obstacle detection and the Studio probe tool | **done** |
| 2 | Sprint vault | **done** |
| 3 | Ledge mantle, the lockout, and the fail-safes | **done** |
| 4 | Animator handoff, config test, docs | **done** |

Wall climbing, grappling, sliding and stamina are deliberately out of scope for
v1. See the roadmap for why.

## Install

`SPS` is `game.StarterPlayer.StarterPlayerScripts`.

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `TREKParkour` | ReplicatedStorage |
| `ServerScriptService/` | `TREKParkour` | ServerScriptService |
| `StarterPlayerScripts/` | `TREKParkour` | SPS |
| `Tools/` | `ParkourRig` | *optional* — leave it in ServerStorage |

Then delete the empty wrapper folder.

If you have rojo, skip all of that: `rojo serve` from this folder puts everything
at the right paths itself. The table above is for people installing the `.rbxm`.

Unlike Ski, Random Arty and Variable Snowstorm, **there is no `Common` folder**.
Those three ship one because they all hold a *sustained* `Humanoid.WalkSpeed`
modifier and would fight each other over it. This package writes WalkSpeed in
exactly one place — the 1.2s vault boost — and it multiplies whatever value is
already there, then restores it. So another package's slow still gets its say:
you get 1.3× of the slowed speed, and the slowed speed back afterwards.

Turn `EnableVaultBoost` off and the package touches WalkSpeed nowhere at all.

## Config

`ReplicatedStorage.TREKParkour.ParkourConfig` — the only file you should need to
open. Turn on `DebugLog` while tuning; every refusal prints its reason, and
"too high" and "no room up there" are fixed by different numbers.

## Checking the detector against your own geometry

`tools/ParkourProbe.luau` is a command-bar script — not installed with the
package, paste it in. Press Play, **switch the command bar to Client**, paste,
and walk at things. It draws both probes, where they hit, the top surface they
found and the box it checks for headroom, labelled with the classification and
the reason.

Stop it with `_G.__ParkourProbeStop()`.

This is how you find out whether `VaultMaxHeight` and `MantleMaxHeight` match
what your level is actually built out of, before any of the motion code depends
on those numbers. It runs on Client because the detector casts against what the
player's own machine can see; on Server it will refuse with a message saying so.

## Why it works the way it does

Three facts about TREK shape every decision in here, and they are worth knowing
before changing anything:

**TREK rewrites `Humanoid.WalkSpeed` every 100ms.** `MovementHandler` runs a
`while true … task.wait(.1)` loop that flips `Sprinting`, and each flip writes the
speed. So this package never sets WalkSpeed to hold a player still — it uses
`PlatformStand`, which makes those writes irrelevant.

The vault boost is the one thing that does write WalkSpeed, and it only works
because it re-asserts every frame, which beats a 100ms poll. It also stands down
the instant you crouch or change sprint state, because those writes are TREK's
and holding a boost through them would be wrong.

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

## Animations

Three slots in the config — `Vault`, `MantleCatch`, `MantlePull` — all shipping
empty. An empty slot plays nothing; the move still happens, it just isn't posed.

For whoever animates, build an R6 Block Rig and run:

```bash
require(game.ServerStorage.TREKParkour.Tools.ParkourRig).attach(workspace.Dummy)
```

That places the real obstacles beside the dummy, built from the live config, plus
markers on the two points the game drives the root through. Retune a threshold
and re-running `attach` moves them with it, so nobody animates against a number
that has since changed.

The one trap: an animation this place can't *read* behaves exactly like an empty
slot. `LoadAnimation` still returns a track and playing it does nothing visible,
with no error. Publish under the account that owns the game.

## Tests

```bash
lune run tools/configtest.luau
```

Checks the config's bands are ordered and contiguous, that the easing curves
actually reach their endpoints, and that the classifiers agree with the config at
every band boundary. Ends with a static scrape asserting every `Config.X` the
source reads is defined — delete a key and it names both the key and every file
that wanted it, before anything can crash on the nil.

`tools/ParkourProbe.luau` is a command-bar visualiser for the detector. Paste it
in with the command bar **on Client**, then walk at things.

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

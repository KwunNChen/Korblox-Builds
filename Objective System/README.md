# Objective System

A capture-point raid system. Terminals sit on the map, teams stand on them to
take them, and owning them ticks score up until one side hits the objective and
wins.

Extracted from the Bricktops place, where it ran as `Workspace.TObjectiveSystem`.

## Install

Download `ObjectiveSystem.rbxm`, drag it into ServerStorage, and move the
`TObjectiveSystem` folder inside it into Workspace. It has to live in Workspace
— both scripts resolve their config with `script.Parent.Parent`, so the folder
layout is load-bearing and the terminals are real parts that need to be in the
world anyway.

## Admin commands

Chat commands, for anyone who passes the admin check.

| | |
|---|---|
| `!begin` | start the raid — reloads every character |
| `!end` | stop the raid |
| `!score N` | set the score needed to win |
| `!defenderId N` | set the defending group by group id |
| `!raiderId N` | set the raiding group by group id |

Admin is granted two ways, both under `Settings/AdminControls`. `GroupId` plus
the `RankId` inside it gives it to everyone at or above that rank in that group.
`UserId` gives it to one person. **`GroupId` ships set to 35065811 — change it
or you are handing control to my group.**

`UserId` is also overwritten at runtime with `game.PrivateServerOwnerId`, so the
owner of a private server always has control whatever you set.

## Setting up terminals

`Points` holds them, one folder each, named `A`/`B`/`C`. Clone one to add
another, delete one to remove it — nothing is hardcoded to three.

| | |
|---|---|
| `Progress` | `MaxValue`/`MinValue` are how long a capture takes. MinValue must be negative. Ships ±20, which is 4 seconds of uncontested standing at the 0.2s tick |
| `Value` | score per second this terminal pays its owner |
| `Capital` | a capital is skipped entirely — never captured, never reset |
| `Point` | the part players stand on |
| `CaptureRadius` | optional. Add a NumberValue to override the radius |

Without a `CaptureRadius`, the radius comes from the part: `Size.X + 6` if X is
at least 1, else `Size.Z + 6`, else a flat 16. The shipped 10×0.1×10 pads gives
16 studs.

**The terminal parts build at the origin.** The source place's positions did not
survive extraction, so all three land on top of each other and you need to place
them yourself.

## Teams

`Settings` has `DefendingTeams`, `RaidingTeams` and `NeutralTeams`. Point the
`Team` ObjectValue inside a category at a Team in `game.Teams`, and clone it for
more. Neutrals can't capture.

Each category folder carries a `CategoryColour` attribute, which is what the HUD
tints terminal markers with.

## What's here

| | |
|---|---|
| `src/server/MainHandler` | the raid loop — counts who's standing where, moves progress, awards score, calls victory |
| `src/server/AdminsControl` | the admin check and the five chat commands |
| `src/package/README` | the original in-Studio INSTRUCTIONS, shipped inside the model |
| `src/point.project.json` | one terminal, reused for A/B/C |

Two loops run: terminals every 0.2s, score every 1s.

## The HUD is not in this package

`TObjectiveHud` lives in StarterGui in the source place and was left there. This
package fires `System/Remotes/Victory` and `System/Remotes/notif` to clients
with nothing listening, which is harmless but means you get no on-screen
feedback until you supply a client.

`notif` sends `('notif', {Title, Text, Icon, Duration})`, and `Victory` sends the
winning category as a string, either `Defenders` or `Raiders`. Anything matching
those two shapes will work.

## Known issues, carried over as-is

These are in the original and I have not touched them — this is an extraction,
not a rewrite.

- **Score survives a victory.** In `cap`, the win branch sets score to the
  objective and calls `victory`, which yields 5 seconds and zeroes both scores —
  then control returns and the `+=` underneath it still runs. The winning side
  starts the next round on its terminal value instead of zero.
- **Only one `RankId` is ever read.** The source had seven `RankId` values under
  `GroupId`, but `plrAdded` reads `v.RankId.Value`, which resolves to whichever
  one Roblox returns first. The other six did nothing. One ships, set to 254.
- **`getPlrCategory` assumes a team.** It reads `plr.Team.Name` with no nil
  check, so a player on no team throws inside the capture loop.
- **`Begin`, `Pause` and `End` are dead.** Three BindableEvents in
  `System/Remotes` that nothing connects to or fires. Kept so external scripts
  expecting them still find them.
- **`System/Ended` is written, never read.**

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o ObjectiveSystem.rbxm
```

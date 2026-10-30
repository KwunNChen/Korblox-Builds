# Warthog

A four-wheel buggy with a driver's seat and a spinning turret on the back. Players can drive it, and Bloxian soldiers will crew it and come at you
in it.

## Install

**Drag `Warthog.rbxm` into Workspace** wherever it should sit. When it is
wrecked, flipped or left abandoned away from home it respawns where you put
it, in the same parent.

Bloxians need the Bloxian package with its `VehicleModule` (it is in the
current `Bloxian.rbxm`). Nothing else to wire up: the Warthog tags itself, and
soldiers find it on their own.

## How the Bloxians use it

- A soldier with an enemy at least 35 studs away and a free seat within 80
  studs claims it (driver first, then gunner), walks over and gets in.
- **Driver:** drives straight at the enemy, then circles him at about 45 studs
  so the gunner always has an angle and the car keeps moving. Paths round
  walls, and backs out with the wheel turned when stuck.
- **Running people over:** within 60 studs of an enemy on foot the driver may
  go for him instead (re-decided every 6 seconds, always when nobody is on the
  turret): he aims where the target is heading, drives through, keeps going
  for a moment and swings round for another pass.
- **Driver dies:** his body is pulled out of the seat and the car brakes. After
  3 seconds with the wheel empty the gunner climbs over and drives; any other
  soldier nearby can also claim the empty seat.
- **Gunner:** swings the turret onto the enemy, leading a moving target, and
  fires 12-round bursts (8-14 damage each) whenever the barrel is on him with a
  clear line.
- Every burst alerts nearby Bloxians the same way rifle fire does.
- The crew gets out after 20 seconds with no enemy, but never bails, however
  damaged: they go up with the Warthog.

Turn it off per soldier with `Settings.UseVehicles` on the Bloxian. Every
number (ranges, circling distance, turret damage and fire rate) is at the top
of the Bloxian's `Scripts/Modules/VehicleModule`.

## Sounds

Set at the top of `Listener` (IDs and volumes):

| | Asset | Plays |
|---|---|---|
| Machine gun | `80013099941453` | each round of a burst (red tracers), replacing the original `Turret.Barrel.Shoot` |
| Engine | `126994453153159` | looped while someone is driving, pitched up with the throttle |

## Destroyed

Until then the crew cannot be hurt: while seated they carry a hidden ForceField,
damage that sets Health directly is undone, the Random Arty barrages skip them
(`InVehicle` attribute), and Bloxian rounds that hit them damage the car
instead. The protection comes off the moment they get out.

When its health runs out, anyone still inside dies (player or Bloxian) and is
dropped out of the seat. The car is thrown up and rolled over (`LAUNCH_SPEED`,
`LAUNCH_DRIFT`, `LAUNCH_SPIN` in `Listener`), its wheels come off, and the
wreck burns and smokes until `Settings.RespawnDelay` runs out.

The blast is drawn by `Effects` on each client, the same Random Arty-style
effect as the Abrams' (light, ground-tinted dust, debris chunks, smoke, camera
shake), instead of the original Roblox `Explosion`, which cratered terrain and
flung everything nearby.

## SPEARHEAD guns

The `Spearhead` script (the same one the Abrams has) moves the Warthog into
`workspace.Vehicles`, where SPEARHEAD's bullets stop instead of passing
through. It then damages it from SPEARHEAD's `BulletHit`:
- **Bullets:** the gun's `damage.Other`.
- **Explosive rounds:** three times that. An RPG-7 kills it outright.

It does nothing in a game without SPEARHEAD. The constants are at its top.

## Tuning: `Warthog.Settings`

| | |
|---|---|
| `Team` | blank: any Bloxian may crew it. Set it to a team name to keep it to that team |
| `RespawnDelay` | seconds a wreck sits before respawning |
| `MaxInactive` | seconds left empty and still away from home before it respawns |

## Roadkill

Whoever is driving, player or Bloxian, hurts anyone the Warthog hits faster
while going faster than 12 studs/s toward them (running away does not help):
20 damage plus 4 per stud/s above that, checked every frame, so a
full-speed hit kills. It never hurts the crew, anyone on the driver's team
(player `Team`, or the NPC `Team` value), or players when the Bloxian driver
has `AttackPlayers` off. A player driver gets the standard `creator` tag on the
victim, so leaderboard kill scripts credit him; each kill also bumps the
`Roadkills` attribute on the car, which a Bloxian driver uses for his kill
callout. Numbers are at the `RAM_` constants in `Listener`.

## Changes from the original

- Tagged `BloxianVehicle` so soldiers can find it (the old `MarineVehicle` tag is kept and also works).
- Reads `AIThrottle` / `AISteer` attributes, so an NPC driver can actually drive it: a seated NPC sends the seat no input of its own.
- The model had no `PrimaryPart`, so the "keep the server simulating it" fix at the top of the script errored silently every time. It now sets one, and keeps the server in charge of the physics (every wheel, not just the body) unless a player is driving, who gets it for responsive controls.
- Respawns go back to the parent the Warthog was placed in, not straight into Workspace.
- Deprecated `wait` / `Velocity` replaced, and a duplicate variable removed.

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o Warthog.rbxm
```

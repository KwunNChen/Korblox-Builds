# Skis

A physics-based ski system for Roblox. Skis and poles weld to an R6 character
and sling across your back on a carry strap when you're not using them.

Press **G**, point downhill, and go. Carving, snowplow braking, jumps that throw
you along the slope rather than straight up, landings you can blow, and a proper
ragdoll when you do.

## Install

Download `Ski.rbxm`, drag it into ServerStorage, and follow the README inside
it. Three folders, each named after the service it goes into.

Updating an existing install is just the script folders — the server rebuilds
any missing remotes on startup.

## Controls

| | |
|---|---|
| `G` | strap in / take them off |
| `WASD` / stick | steer |
| `S` / pull back | snowplow brake |
| `Shift` | tuck — cuts air drag, raises top speed |
| `Space` | jump |

Steering reads `Humanoid.MoveDirection`, so rebound keys, gamepads and mobile
thumbsticks work with no extra setup. You can also strap in by walking over a
brick tagged `SkiZone`.

## What's here

| | |
|---|---|
| `src/shared` | `SkiConfig` — every tunable. `SkiShared` — helpers, remote plumbing |
| `src/server` | `SkiGear` builds and moves the gear, `SkiService` owns equip state, `SkiRagdoll` handles wipeouts |
| `src/server-common` | `SpeedService` — shared with Variable Snowstorm |
| `src/client` | `SkiController` runs the sim, `SkiPhysics` is the maths under it, `SkiPose` does the R6 posing |

**Gear is built on the server** so it replicates to everyone for free. **The sim
runs on the client**, because Roblox gives a player network ownership of their
own character — a server-driven force is simulated on the owning client anyway,
so running the loop there only costs input latency. **Ragdolls are server-side**
so everyone sees the crash.

## How it rides

The downhill pull is gravity with its ground-normal component removed — flat
ground gives zero, steep ground gives a lot, and there's no slope-angle special
case anywhere in the code.

Sideways speed is treated completely differently from forward speed. The edges
scrub sideways drift off hard and a fraction of it comes back as forward speed.
That's carving, and **the ratio of `LateralDrag` to `ForwardDrag` is the entire
feel of the system** — tune it before anything else.

Snow, ice and glacier are almost frictionless, so you keep what you earn. Two
things follow: you won't coast to a stop (braking is how you stop now), and top
speed is set almost entirely by `AirDrag`.

## Gotchas worth knowing

`HoverHeight` is not a free number — 3.0 works because R6's root sits exactly 3
studs above the soles and `SkiFootOffset` puts the ski bases level with them.
Move one and the other has to follow.

Poses hold the hips near zero on purpose. The skis are welded to the legs, so
they inherit whatever angle the legs are at — that's what keeps them flat.

Procedural poses are **local to you**; joint changes on the client don't
replicate. Filling in `SkiConfig.Animations` swaps a slot for a real animation,
which does.

## Not in yet

Tricks and scoring. Air pitch is wired in `SkiPhysics` but switched off in the
controller — flips with nothing scoring them just means landing backwards for
free.

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o Ski.rbxm
```

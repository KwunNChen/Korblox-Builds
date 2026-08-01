# Skis

A physics-based ski system for Roblox. Skis and poles weld to an R6 character
and sling across your back on a carry strap when you're not using them.

Press G, point downhill, and go. You get carving, a snowplow brake, jumps that
throw you along the slope instead of straight up, landings you can blow, and a
proper ragdoll when you do.

## Install

Download `Ski.rbxm`, drag it into ServerStorage, and follow the README inside
it. Three folders, each named after the service it goes into.

Updating an existing install only needs the script folders. The server rebuilds
any missing remotes when it starts.

## Controls

| | |
|---|---|
| `G` | strap in, or take them off |
| `WASD` or stick | steer |
| `S`, or pull back | snowplow brake |
| `Shift` | tuck, which cuts air drag and raises your top speed |
| `Space` | jump |

Steering reads `Humanoid.MoveDirection`, so rebound keys, gamepads and mobile
thumbsticks all work without extra setup. You can also strap in by walking over
a brick tagged `SkiZone`.

## What's here

| | |
|---|---|
| `src/shared` | `SkiConfig` holds every tunable. `SkiShared` has the helpers and remote plumbing |
| `src/server` | `SkiGear` builds and moves the gear, `SkiService` owns equip state, `SkiRagdoll` handles wipeouts |
| `src/server-common` | Shared with Variable Snowstorm. Ski only uses `SpeedService`, but `CharacterCache` ships for Snowstorm's sake. Merge this folder, never replace it |
| `src/client` | `SkiController` runs the sim, `SkiPhysics` is the maths under it, `SkiPose` does the R6 posing, `SkiEffects` the spray and camera, `SkiSound` the audio, `SkiRemoteView` renders everyone else |

Sound ships silent. Roblox audio is private to whichever place owns it, so an ID
copied from another game plays as nothing at all and reports no error. The IDs
sit at the top of `SkiConfig` as placeholders, and you need to paste your own
over them.

## How the halves split

The gear is built on the server, so it replicates to everyone for free.

The simulation runs on the client. Roblox hands a player network ownership of
their own character, which means a force applied from the server gets simulated
on that client anyway. Running the loop there costs a round trip of input
latency and buys nothing.

Ragdolls go back to the server, so everyone sees the crash rather than just the
person who ate it.

## How it rides

The downhill pull is gravity with its ground-normal component removed. Flat
ground gives zero, steep ground gives a lot, and there is no slope-angle special
case anywhere in the code.

Sideways speed is treated completely differently from forward speed. The edges
scrub sideways drift off hard, and a fraction of what they scrub comes back as
forward speed. That is carving. The ratio of `LateralDrag` to `ForwardDrag` is
the whole feel of the system, so tune it before you touch anything else.

Snow, ice and glacier are almost frictionless, so you keep whatever speed you
earn. Two things follow from that. You will not coast to a stop any more, which
makes braking the only way to stop. And your top speed ends up set almost
entirely by `AirDrag`, since nothing else is taking much off you.

## Before you tune it

`HoverHeight` is not a free number. 3.0 works because R6's root sits exactly
three studs above the soles, and `SkiFootOffset` puts the ski bases level with
those soles. Move either and the other has to follow.

Keeping the skis flat takes more than it looks. They are welded to the legs, and
on R6 the legs hang off the Torso, which `RootJoint` pitches. So leaning the
body forward tips the skis nose-up on its own, with the hips sitting at zero.
The pose feeds that lean back into the hips to cancel it out, which is the part
actually holding them level.

Nothing cosmetic replicates by itself. Joint poses, particles and sounds made on
a client are only ever seen by that client. Other players get rendered from
replicated state instead: each client publishes its state, speed, sideways
speed, lean and whether it is on snow, the server writes those as character
attributes, and everyone else drives the same pose, spray and sound code from
them.

## Not in yet

Tricks and scoring. Air pitch is already wired up in `SkiPhysics` and switched
off in the controller, because flips with nothing scoring them just mean landing
backwards for free.

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o Ski.rbxm
```

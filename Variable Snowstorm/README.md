# Variable Snowstorm

Weather system for Korblox Confederacy. Storms run on a cycle, snow stops when
you walk under a roof, and getting caught out in one slows you down.

## What it does

Storms cycle through Clear, Building, Peak, and Fading, with randomized phase
lengths so it never feels metronomic. Every player gets their own roof check, so
snow, wind volume, and the speed penalty all fade under cover and come back when
they step outside. Wind audio scales with intensity and goes muffled indoors.
Fog and Atmosphere shift with the storm, per client.

## Architecture

Server-based code, clients will pull from it

```
SERVER   ServerScriptService.Weather
  WeatherService  ->  attributes on ReplicatedStorage.WeatherState
                      Intensity, Phase, WindX, WindZ,
                      InstantCue, PhaseSecondsLeft, ThunderActive
                      also sets workspace.GlobalWind
  ThunderService  ->  ThunderStrike RemoteEvent, one packet per strike
                              |
                              |  replicates automatically
                              v
CLIENT   StarterPlayerScripts.Weather
  reads those      ->  particle rig parented to Camera
                   ->  its own roof raycasts
                   ->  local Lighting, Atmosphere, wind audio
                   ->  lightning bolts, markers, thunder
```

Roof detection cannot work server side. A ParticleEmitter made on the server
replicates to everyone, and there's no way to hide a server-owned instance from
one player but not another, so turning off one person's snow turns off
everyone's. Server raycasts also scale with player count.

The cycle itself, so everyone shares
weather, plus global wind and the movement penalty. A client could simply
decline to slow itself down, so that check uses the server's own raycast and
never a value a client reports.

## Layout

```
ReplicatedStorage
├── Weather
│   ├── WeatherConfig        all tuning lives here
│   └── WeatherShared
├── WeatherState             replicated attributes
└── ThunderStrike            RemoteEvent, lightning only

ServerScriptService
├── Weather
│   ├── WeatherService       state machine + hooks
│   ├── ThunderService       lightning window, placement, kills
│   └── WeatherRuntime       entry point + gameplay effects
└── Common
    └── SpeedService         owns WalkSpeed and jump height

StarterPlayer/StarterPlayerScripts
└── Weather
    ├── WeatherClient        rendering + roof detection
    ├── WeatherAudio         wind ambience
    └── WeatherThunder       lightning visuals + thunder
```

## Installing in a game

Three services, one model file, so you place the folders yourself. The folders
inside the .rbxm are named after where they go.

1. Drag `VariableSnowstorm.rbxm` into **ServerStorage**. Scripts don't execute
   there. Drop it into ServerScriptService or Workspace instead and the server
   scripts start running before the shared modules exist.

2. From its `ReplicatedStorage` folder, move `Weather`, `WeatherState`, and
   `ThunderStrike` into the real ReplicatedStorage. Miss `ThunderStrike` and
   lightning disables itself with a warning in Output; everything else runs.

3. From its `ServerScriptService` folder, move `Weather` and `Common` into the
   real ServerScriptService. If your game already has a `Common` folder, drag
   `SpeedService` into that one rather than replacing it.

4. From its `StarterPlayerScripts` folder, move `Weather` into StarterPlayer >
   StarterPlayerScripts. Skip this step and the storm still runs and still slows
   players, but nothing draws. That failure looks exactly like a broken install,
   so it's worth double checking.

5. Delete the empty `VariableSnowstorm` folder.

Press Play. After that the only file you edit is
`ReplicatedStorage.Weather.WeatherConfig`.

### Wind audio needs your own asset

`WindSoundId` ships pointing at an asset your game may not have access to.
Roblox audio has been private by default since 2022, and an id that works in one
place is silent in another with no error at all.

### Rebuilding the package

```bash
rojo build package.project.json -o VariableSnowstorm.rbxm
```

This reads the same `src/` as the dev project, so there's no second copy of the
code to keep in sync.

## Setup for development

Requires [Rokit](https://github.com/rojo-rbx/rokit/releases). From this folder:

```bash
rokit install
```

```bash
rojo plugin install
```

```bash
rojo serve
```

Then hit Connect in the Rojo plugin in Studio.

## Testing

The cycle opens with 60 to 120 seconds of clear weather, so force a storm rather
than waiting it out.

`DebugStartIntensity` is the only knob. Values from 0 to 1 pin the storm at that
intensity, anything negative runs the normal cycle. The config seeds it at boot
and the attribute changes it live.

Mid playtest, with the Client/Server toggle in the toolbar set to Server:

```lua
game.ReplicatedStorage.Weather:SetAttribute("DebugStartIntensity", 1)
```

Negative resumes the cycle. The server prints
`[Weather] debug override -> intensity 1.00` when it lands. No print means the
command never reached the server, which is almost always the toggle sitting on
Client. You can also edit the attribute directly on `ReplicatedStorage.Weather`
in Explorer during a playtest.

To bake it in instead, set `WeatherConfig.DebugStartIntensity = 1` and every
playtest opens at a full storm. That runs as ordinary server code at boot, so
nothing Command Bar related can break it.

### BUG: Storm running but no snow

The first two are correct behavior, not bugs.

1. Are you under a roof? Shelter detection mutes snow on purpose. Anything solid
   within `ShelterRayLength` (250 studs) overhead counts, so a large ceiling in
   a test place suppresses everything. Walk into the open.

2. Did it reach your client? Run this on Client context:
   ```lua
   print(game.ReplicatedStorage.WeatherState:GetAttribute("Intensity"))
   ```
   `1` means the server and replication are fine and the problem is local
   rendering or shelter. `0` means the override never applied.

3. Too sparse to notice? `ParticleBudget` (1200) spreads across the
   `RigSize` volume (100x50x100). Raising the budget or shrinking the volume
   both make it denser, but reach for `FlakeSizePeak` first -- it reads as
   heavier snow without adding a single particle.

A faster check than any of these: look for fog. Lighting is applied before
anything else in the client render loop, so fog at high intensity proves the
client is alive and the problem is elsewhere. Clear sky at full intensity means
the client scripts aren't running at all, which usually means install step 4 got
missed.

## Tuning

Everything is in `src/shared/WeatherConfig.luau`.

| Setting | Effect |
| --- | --- |
| `ParticleBudget` | Cap on live flakes. The main performance knob. |
| `FlakeSizePeak` | Flake size at full storm. The other performance knob -- overdraw scales with area, so this can cost more framerate than `ParticleBudget` does. |
| `SquashAtPeak` | How far flakes stretch into streaks at full storm. Free drama. |
| `RigSize` | Volume flakes spawn in. Smaller reads as denser at no extra cost, but don't go below ~100 studs wide -- `positionRig` pushes the box up to 40 studs upwind, and a smaller box leaves the camera near its edge with a bare patch on one side. |
| `FlakeGravity` | Fall speed, as `FlakeGravity / FlakeDrag`. Faster flakes read as heavier snow but spread the same budget down a taller column, so it trades away some density. |
| `PhaseDurations` | Length of each phase of the cycle. |
| `WindStormSpeed` | How hard a full blizzard blows. |
| `ShelterSmoothing` | How fast snow fades when you step under cover. |
| `ShelterRespectCanCollide` | On by default, so decorative non-collidable parts aren't roofs. Turn off if your builders make real roofs non-collidable. |
| `FlakeTexture` | Swap for a custom snowflake asset. |
| `WindSoundId` | Required for audio. See above. |
| `WindMaxVolume` | Wind loudness at full storm. |
| `WindPitchSmoothing` | Raise if pitch sounds jumpy, lower if gusts feel sluggish. |
| `StormSpeedMultiplier` | Speed multiplier at full intensity, before heading is applied. |
| `WindDirectionalSwing` | How far heading moves that multiplier. 0 makes the storm slow you the same in every direction. |
| `WindAirborneAccel` | How hard wind shoves you while airborne. |
| `StormJumpMultiplier` | Jump height at full intensity. |
| `EnableThunderstorm` | Lightning window inside each Peak. |
| `ThunderSafeRadius` | The fairness knob. Strikes never land this close to any player, so standing still is always survivable. Drop it below `ThunderKillRadius` and lightning starts killing stationary players. |
| `ThunderTelegraph` | Seconds the charge marker shows before a strike lands. |
| `ThunderStrikeInterval` | Seconds between strikes near one targeted player. |
| `ThunderAnchorCount` | How many players the storm hunts at once. Total strike rate stays constant regardless of server size. |
| `ThunderAnchorRotate` | Seconds before the target set is re-rolled. |
| `ThunderCrackSoundId` | The only thunder asset you need. Your own id, same as `WindSoundId`. |
| `ThunderWarningPitch` | How far the opening rumble is slowed from the crack. Lower is deeper and longer. |
| `ThunderDarkenExposure` | How far the sky darkens during a thunderstorm. Lower is darker. |
| `ThunderDarkenBrightness` | Sun brightness multiplier during a thunderstorm. |
| `EnableLightingEffects` | Set false if your map already drives fog and Atmosphere. |
| `DebugStartIntensity` | 0 to 1 starts every playtest at that intensity. |

## Speed modifiers

`SpeedService` is the only thing allowed to assign `Humanoid.WalkSpeed` or the
character's jump height. Systems register named modifiers and it folds them
together:

```
final = base × (all multipliers) + (all additions)
```

A sprint system plugs in like this and needs to know nothing about weather:

```lua
local SpeedService = require(game.ServerScriptService.Common.SpeedService)

SpeedService.setModifier(humanoid, "Sprint", { mul = 1.5 })
SpeedService.clearModifier(humanoid, "Sprint")
```

Multipliers compose, so the storm stacks on top by itself:

| Situation | Math | Speed |
| --- | --- | --- |
| Walking, clear | `16` | 16 |
| Walking, peak storm, crosswind | `16 × 0.875` | 14 |
| Walking, peak storm, into the wind | `16 × 0.70` | 11.2 |
| Walking, peak storm, wind behind | `16 × 1.05` | 16.8 |
| Sprinting, clear | `16 × 1.5` | 24 |
| Sprinting, peak storm, into the wind | `16 × 1.5 × 0.70` | 16.8 |

`{ add = -2 }` also works for flat modifiers. A `MinWalkSpeed` floor keeps
stacked penalties from leaving a player unable to move.

A single modifier can carry jump alongside speed, so one name registers and
clears both:

```lua
SpeedService.setModifier(humanoid, "Storm", { mul = 0.875, jumpMul = 0.85 })
```

`jumpMul` and `jumpAdd` fold exactly like `mul` and `add`. Roblox reads either
`JumpPower` or `JumpHeight` depending on `Humanoid.UseJumpPower`, so the service
records both baselines and writes whichever one the character actually obeys --
you do not have to care which mode your rig uses.

The storm's own multiplier is not a single number: it swings with your heading
relative to the wind, between `StormSpeedMultiplier - WindDirectionalSwing`
walking into it and `+ WindDirectionalSwing` with it at your back. Both terms
scale with intensity, and the swing also scales with live wind speed, so the
penalty pulses as gusts roll through rather than sitting flat.

Jumping in the open during a storm blows you downwind, since a Humanoid resists
force while grounded but not mid-air. Turn that off with
`EnableWindAirborneDrift`.

## Thunderstorms

Somewhere inside every Peak, a 30-second thunderstorm opens with a warning
rumble and then starts dropping lightning. A strike kills instantly. Being under
a roof makes you immune.

The sky darkens as the window opens, ramping in across `ThunderWarningLead` so
it lands before the first strike — the darkening *is* the warning. It also makes
each flash punch harder by contrast. Only `Brightness`, `Ambient`,
`ExposureCompensation`, and `Atmosphere.Color` move; fog and Atmosphere density
stay with the snowstorm, so the two lighting owners never fight. Exposure is
what darkens the skybox itself, which fog alone never touches.

The storm hunts `ThunderAnchorCount` players at a time rather than everyone, and
re-rolls that set every `ThunderAnchorRotate` seconds so it roams. Total strike
rate is therefore roughly `ThunderAnchorCount / ThunderStrikeInterval` — about
1.6 a second — whether there are two people on the map or thirty. A full server
is not proportionally more dangerous, and the storm reads as weather picking
victims rather than as something following every player individually.

The design rule is that **standing still is always survivable.** Strikes land in
a ring 20 to 45 studs out and are rejected if they would land within
`ThunderSafeRadius` of anyone — not just the player they were aimed at, so being
near someone the storm is hunting cannot get you killed while stationary. You
die only by walking into a strike that has already been marked. That turns a thunderstorm
into a reason to stop moving or get indoors, rather than a coin flip. It also
means the marker can stay subtle: a few motes gathering at the impact point that
build over `ThunderTelegraph` seconds, not a warning decal.

Bolts cannot pass through roofs, and this is structural rather than a special
case. The impact point is found by raycasting *down* from `ThunderCloudHeight`,
so the ray stops at the first surface it meets — a strike over a building lands
on the roof, and the bolt is drawn to that point. Immunity is a separate check
using the same shelter raycast the snow uses, taken **fresh at the moment the
strike lands**, so running through a doorway during the telegraph saves you.

To test one without waiting for a Peak, set the `DebugThunder` attribute on
`ReplicatedStorage.Weather` to `true` from the server:

```lua
game.ReplicatedStorage.Weather:SetAttribute("DebugThunder", true)
```

It resets itself to `false` and prints confirmation. Same toggle rule as
`DebugStartIntensity` — the Client/Server switch has to be on **Server**.

One rule: never assign `WalkSpeed` directly once a humanoid is managed here.
Outside writes get overwritten on the next recompute.

## Gameplay hooks

`WeatherRuntime.server.luau` has a commented out cold damage example. Use
`WeatherService.isPlayerSheltered(player)`, which is the server's own raycast,
and never a value reported by a client. `WeatherService.PhaseChanged` and
`IntensityChanged` are there for anything else.

### Countdown to the next phase

`WeatherService.getPhaseTimeRemaining()` returns seconds left in the current
phase, for server scripts. From the client, or anywhere else, read the same
value off `ReplicatedStorage.WeatherState.PhaseSecondsLeft`:

```lua
local Shared = require(game.ReplicatedStorage.Weather.WeatherShared)
local stateHolder = Shared.getStateHolder()

local secondsLeft = Shared.getPhaseTimeRemaining(stateHolder)
```

`PhaseSecondsLeft` is a plain integer, visible in Explorer too, and updates
about once a second rather than every tick, since nothing here needs finer
resolution than that.

## Performance notes

- The particle rig is parented to `workspace.CurrentCamera`, so it never
  replicates.
- Network cost is a handful of numbers a few times a second, and only when they
  move past a threshold. It doesn't scale with player count.
- Raycasts run 5 per client every 0.2s, and none at all when no storm is active.
- Engine property writes (Lighting, particle rate, sound volume, pitch, EQ) are
  epsilon gated. Smoothing is asymptotic and never exactly settles, so writing
  every frame would churn the renderer and audio DSP for changes too small to
  perceive.
- The render loop and the server's slowdown sweep both idle fully in clear
  weather.
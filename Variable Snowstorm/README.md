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
  WeatherService  ->  5 attributes on ReplicatedStorage.WeatherState
                      Intensity, Phase, WindX, WindZ, InstantCue
                      also sets workspace.GlobalWind
                              |
                              |  replicates automatically
                              v
CLIENT   StarterPlayerScripts.Weather
  reads those      ->  particle rig parented to Camera
                   ->  its own roof raycasts
                   ->  local Lighting, Atmosphere, wind audio
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
└── WeatherState             replicated attributes

ServerScriptService
├── Weather
│   ├── WeatherService       state machine + hooks
│   └── WeatherRuntime       entry point + gameplay effects
└── Common
    └── SpeedService         owns Humanoid.WalkSpeed

StarterPlayer/StarterPlayerScripts
└── Weather
    ├── WeatherClient        rendering + roof detection
    └── WeatherAudio         wind ambience
```

## Installing in a game

Three services, one model file, so you place the folders yourself. The folders
inside the .rbxm are named after where they go.

1. Drag `VariableSnowstorm.rbxm` into **ServerStorage**. Scripts don't execute
   there. Drop it into ServerScriptService or Workspace instead and the server
   scripts start running before the shared modules exist.

2. From its `ReplicatedStorage` folder, move `Weather` and `WeatherState` into
   the real ReplicatedStorage.

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

3. Too sparse to notice? `ParticleBudget` (700) spreads across a 140x50x140 stud
   volume. Raise it toward 1500 to 2000 for a dense blizzard, in small steps,
   since live particle count scales linearly with it.

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
| `PhaseDurations` | Length of each phase of the cycle. |
| `WindStormSpeed` | How hard a full blizzard blows. |
| `ShelterSmoothing` | How fast snow fades when you step under cover. |
| `ShelterRespectCanCollide` | On by default, so decorative non-collidable parts aren't roofs. Turn off if your builders make real roofs non-collidable. |
| `FlakeTexture` | Swap for a custom snowflake asset. |
| `WindSoundId` | Required for audio. See above. |
| `WindMaxVolume` | Wind loudness at full storm. |
| `WindPitchSmoothing` | Raise if pitch sounds jumpy, lower if gusts feel sluggish. |
| `StormSpeedMultiplier` | Speed multiplier at full intensity. |
| `EnableLightingEffects` | Set false if your map already drives fog and Atmosphere. |
| `DebugStartIntensity` | 0 to 1 starts every playtest at that intensity. |

## Speed modifiers

`SpeedService` is the only thing allowed to assign `Humanoid.WalkSpeed`. Systems
register named modifiers and it folds them together:

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
| Walking, peak storm | `16 × 0.875` | 14 |
| Sprinting, clear | `16 × 1.5` | 24 |
| Sprinting, peak storm | `16 × 1.5 × 0.875` | 21 |

`{ add = -2 }` also works for flat modifiers. A `MinWalkSpeed` floor keeps
stacked penalties from leaving a player unable to move.

One rule: never assign `WalkSpeed` directly once a humanoid is managed here.
Outside writes get overwritten on the next recompute.

## Gameplay hooks

`WeatherRuntime.server.luau` has a commented out cold damage example. Use
`WeatherService.isPlayerSheltered(player)`, which is the server's own raycast,
and never a value reported by a client. `WeatherService.PhaseChanged` and
`IntensityChanged` are there for anything else.

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
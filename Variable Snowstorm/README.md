# Variable Snowstorm

A weather system for Korblox Confederacy. Storms cycle on their own, snow stops
when you step under a roof, and being caught outside slows you down.

## What it does

- **Automatic storm cycle** — Clear → Building → Peak → Fading, with randomized
  durations so it never feels metronomic.
- **Per-player roof detection** — snow, wind volume, and the speed penalty all
  fade out under cover and return when you step back into the open.
- **Wind audio** — volume scales with the storm; indoors it drops and gets
  muffled, like a storm heard through a wall.
- **Movement penalty** — exposed players move slower, scaling with intensity.
- **Local lighting** — fog and Atmosphere shift with the storm, per client.

## Architecture

The storm's **state** is server-owned; its **appearance** is client-rendered.

```
SERVER  ServerScriptService.Weather
  WeatherService ──► 5 attributes on ReplicatedStorage.WeatherState
                     Intensity · Phase · WindX · WindZ · InstantCue
                     also sets workspace.GlobalWind

                              │ replicates automatically
                              ▼
CLIENT  StarterPlayerScripts.Weather
  reads those values ──► particle rig parented to Camera
                    ──► its own roof raycasts
                    ──► local Lighting / Atmosphere / wind audio
```

### Why rendering is not on the server

The roof feature *cannot* work server-side. A ParticleEmitter created on the
server replicates to every client, and there is no way to hide a server-owned
instance from one player but not another — disabling Player A's snow would
disable it for everyone. Server raycasts also scale with player count and eat
the single-threaded server budget.

What *is* server-side, and has to be: the storm cycle (so everyone shares the
same weather), global wind, and the movement penalty. A client could simply
decline to slow itself down, so that check uses the server's own raycast and
never a value reported by a client.

## Layout

```
ReplicatedStorage
├── Weather
│   ├── WeatherConfig        ← all tuning lives here
│   └── WeatherShared
└── WeatherState             ← replicated attributes

ServerScriptService
├── Weather
│   ├── WeatherService       ← state machine + hooks
│   └── WeatherRuntime       ← entry point + gameplay effects
└── Common
    └── SpeedService         ← owns Humanoid.WalkSpeed

StarterPlayer/StarterPlayerScripts
└── Weather
    ├── WeatherClient        ← rendering + roof detection
    └── WeatherAudio         ← wind ambience
```

## Setup

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

Then hit **Connect** in the Rojo plugin in Studio.

### Wind audio

`WindSoundId` ships empty — Roblox audio is private-by-default since 2022, so no
id can be safely hardcoded. In Studio open **View → Toolbox → Audio**, search
`wind loop`, right-click → **Copy Asset ID**, and paste it into
`WeatherConfig.WindSoundId`. Pick one that loops **seamlessly** — it plays
continuously, so a seam is very audible.

Until an id is set the system warns once at startup and runs silently.

## Testing

The cycle opens with 60–120s of clear weather, so don't wait it out. Press Play,
switch the Client/Server toggle in the toolbar to **Server**, and run:

```lua
require(game.ServerScriptService.Weather.WeatherService).setOverride(1, true)
```

The `true` skips the visual ramp-up so the storm appears immediately.

> The Command Bar runs in whichever context that toggle is set to.
> `ServerScriptService` is never replicated to clients, so on **Client** this
> errors with "Weather is not a valid member of ServerScriptService".

Other helpers:

```lua
local W = require(game.ServerScriptService.Weather.WeatherService)
W.setOverride(nil)      -- resume the automatic cycle
W.forceStorm()          -- jump to Building
W.forceClear()          -- jump to Fading
W.getPhase()
```

## Tuning

Everything is in `src/shared/WeatherConfig.luau`.

| Setting | Effect |
| --- | --- |
| `ParticleBudget` | Cap on live flakes. **The main performance knob.** |
| `PhaseDurations` | Length of each phase of the cycle. |
| `WindStormSpeed` | How hard a full blizzard blows. |
| `ShelterSmoothing` | How fast snow fades when you step under cover. |
| `ShelterRespectCanCollide` | On by default, so decorative non-collidable parts aren't roofs. **Turn off if your builders make real roofs non-collidable.** |
| `FlakeTexture` | Swap for a custom snowflake asset. |
| `WindSoundId` | Required for audio — see above. |
| `WindMaxVolume` | Wind loudness at full storm. |
| `WindPitchSmoothing` | Raise if pitch sounds jumpy, lower if gusts feel sluggish. |
| `StormSpeedMultiplier` | Speed multiplier at full intensity. |
| `EnableLightingEffects` | Set false if your map already drives fog and Atmosphere. |

## Speed modifiers

`SpeedService` is the only thing that may assign `Humanoid.WalkSpeed`. Systems
register named modifiers and it folds them together:

```
final = base × (all multipliers) + (all additions)
```

A sprint system integrates like this, and needs to know nothing about weather:

```lua
local SpeedService = require(game.ServerScriptService.Common.SpeedService)

SpeedService.setModifier(humanoid, "Sprint", { mul = 1.5 })
SpeedService.clearModifier(humanoid, "Sprint")
```

Multipliers compose, so the storm applies on top automatically:

| Situation | Math | Speed |
| --- | --- | --- |
| Walking, clear | `16` | 16 |
| Walking, peak storm | `16 × 0.875` | 14 |
| Sprinting, clear | `16 × 1.5` | 24 |
| Sprinting, peak storm | `16 × 1.5 × 0.875` | 21 |

`{ add = -2 }` is also supported for flat modifiers. There's a `MinWalkSpeed`
floor so stacked penalties can't leave a player unable to move.

**The one rule:** never assign `WalkSpeed` directly once a humanoid is managed
here — outside writes get overwritten on the next recompute.

## Gameplay hooks

`WeatherRuntime.server.luau` has a commented-out cold damage example. Use
`WeatherService.isPlayerSheltered(player)` — the server's own raycast — and
never a value reported by a client. `WeatherService.PhaseChanged` and
`IntensityChanged` are available for anything else.

## Performance notes

- The particle rig is parented to `workspace.CurrentCamera`, so it never
  replicates.
- Network cost is a handful of numbers a few times a second, and only when they
  change past a threshold — independent of player count.
- Raycasts: 5 per client every 0.2s, and **zero** when no storm is active.
- Engine property writes (Lighting, particle rate, sound volume, pitch, EQ) are
  all epsilon-gated. Smoothing is asymptotic and never exactly settles, so
  writing every frame would churn the renderer and audio DSP for changes too
  small to perceive.
- Both the render loop and the server's slowdown sweep fully idle in clear
  weather.

## Known trade-offs

- **Shelter is measured from the character, not the camera.** In third person
  the camera often floats outside the building you're in; measuring from the
  body matches player intuition.
- **Lighting is driven by intensity only**, not shelter, so fog still reads
  indoors. Tying it to shelter pops every time you cross a doorway.
- **`WindAffectsDrag` is flagged deprecated** while still being the documented
  way to make particles follow `GlobalWind`. It's set inside a `pcall`; the
  snow's horizontal motion comes from `Acceleration`, so nothing breaks if it
  goes away.

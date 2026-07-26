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

## Installing in a game

Drag `VariableSnowstorm.rbxm` into **ServerScriptService**.

That's the whole install. The system spans four services, but a model file can
only be inserted into one place, so the package ships with an `Installer` script
that distributes the folders on first server start and then deletes itself.
Press Play once to run it, then **Stop and Play again** to start from the
installed copy.

After installing, the only file you touch is
`ReplicatedStorage.Weather.WeatherConfig`.

The installer never overwrites. If a name already exists at its destination it
keeps the existing instance and warns instead — so it merges safely into a
`ServerScriptService.Common` folder your game already uses for other systems.

### Rebuilding the package

```bash
rojo build package.project.json -o VariableSnowstorm.rbxm
```

`package.project.json` reads the same `src/` as the dev project, so there is no
second copy of the code to keep in sync.

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

Then hit **Connect** in the Rojo plugin in Studio.

## Testing

The cycle opens with 60–120s of clear weather, so force a storm instead of
waiting it out.

`DebugStartIntensity` is the single knob: `0`–`1` pins the storm at that
intensity, anything negative runs the normal cycle. It exists in two places for
the same value — the config seeds it at boot, the attribute changes it live.

### By command, mid-playtest

Switch the Client/Server toggle in the toolbar to **Server**:

```lua
game.ReplicatedStorage.Weather:SetAttribute("DebugStartIntensity", 1)
```

Back to the automatic cycle:

```lua
game.ReplicatedStorage.Weather:SetAttribute("DebugStartIntensity", -1)
```

The server prints `[Weather] debug override -> intensity 1.00` when it lands.
**No print means the command never reached the server** — almost always the
toggle was on Client. You can also select `ReplicatedStorage.Weather` in
Explorer during a playtest and edit `DebugStartIntensity` under Attributes.

### Or bake it in

In `WeatherConfig.luau`:

```lua
WeatherConfig.DebugStartIntensity = 1
```

Every playtest now opens at a full storm. This runs as ordinary server code at
boot, so it works regardless of anything Command Bar related.

### If a storm is running but you see no snow

Check these in order — the first two are correct behavior, not bugs.

1. **Are you under a roof?** Shelter detection kills the snow on purpose. Walk
   into the open. Anything solid within `ShelterRayLength` (250 studs) above you
   counts, so a large ceiling in a Studio test place will suppress everything.
2. **Confirm the storm reached your client.** On **Client** context:
   ```lua
   print(game.ReplicatedStorage.WeatherState:GetAttribute("Intensity"))
   ```
   `1` means the server and replication are fine and the problem is local
   rendering or shelter. `0` means the override never applied.
3. **Snow too sparse to notice?** `ParticleBudget` (450) spreads over a
   140×50×140 stud volume. Raise it to 1500–2000 for a dense blizzard.

### Why not `require()` from the Command Bar

The Command Bar shares the **instance tree** with your running scripts, but it
executes in a separate Luau VM. Module caches and `_G` are per-VM, so
`require(WeatherService)` there builds a brand-new, disconnected copy of the
module — one that never had `start()` called on it — and `_G` values set by
server scripts read back as `nil`. Attributes live on the Instance itself, so
they cross the boundary cleanly.

The same applies to `forceStorm()` / `forceClear()` — reach them from a real
script (a gameplay hook, an admin command), not the Command Bar.

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

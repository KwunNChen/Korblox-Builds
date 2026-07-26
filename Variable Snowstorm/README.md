# Korblox Snowstorm

A server-authoritative snowstorm with per-player roof detection. Snow stops when
you walk under cover and resumes when you step back into the open.

## Architecture

The storm's **state** is server-owned; its **appearance** is client-rendered.

```
SERVER  (ServerScriptService.Weather)
  WeatherService ──► publishes 4 attributes on ReplicatedStorage.WeatherState
                     Intensity · Phase · WindX · WindZ
                     also sets workspace.GlobalWind (foliage + clouds)

                              │ replicates automatically
                              ▼
CLIENT  (StarterPlayerScripts.WeatherClient)
  reads those 4 numbers ──► particle rig parented to Camera
                       ──► its own roof raycasts
                       ──► local Lighting / Atmosphere
```

### Why rendering is not on the server

The roof feature *cannot* work server-side. A ParticleEmitter created on the
server replicates to every client, and there is no way to hide a server-owned
instance from one player but not another. Disabling Player A's snow would
disable it for everyone; giving each player their own emitter means all clients
render all emitters.

Server raycasts also scale with player count and consume the single-threaded
server budget — the scarcest resource in a Roblox game — and add 50–150 ms of
replication lag before snow cuts off when you step under an awning.

What *is* server-side, correctly: the storm cycle (so everyone shares the same
weather), global wind, and a coarse shelter check reserved for gameplay effects,
since a client's claim about being indoors is trivially spoofable.

## Setup

You have Studio but no Rojo yet. Pick either path.

**Option A — Rokit (recommended, pins the version for the whole team)**

Install Rokit from https://github.com/rojo-rbx/rokit/releases, then:

```bash
rokit install
```

**Option B — direct install**

Download the `rojo` binary from https://github.com/rojo-rbx/rojo/releases and
put it on your PATH.

**Then, for either path:**

1. Install the Rojo *Studio plugin*: `rojo plugin install`
2. Start the server from this folder: `rojo serve`
3. In Studio, open the Rojo plugin and click **Connect**.

The tree appears in Studio automatically. Edit the `.luau` files in your editor
and Studio updates live.

## Explorer layout after sync

```
ReplicatedStorage
├── Weather                  (Folder)
│   ├── WeatherConfig        (ModuleScript)  ← all tuning lives here
│   └── WeatherShared        (ModuleScript)
└── WeatherState             (Configuration) ← replicated attributes

ServerScriptService
└── Weather                  (Folder)
    ├── WeatherService       (ModuleScript)  ← state machine + hooks API
    └── WeatherRuntime       (Script)        ← entry point

StarterPlayer/StarterPlayerScripts
└── WeatherClient            (LocalScript)   ← rendering + roof detection
```

## Testing it

The default cycle opens with 60–120 s of clear weather, so don't wait it out.
Run a **Local Server** test (Test → Clients and Servers, 2 players), switch to
the **Server** view, and use the command bar:

```lua
require(game.ServerScriptService.Weather.WeatherService).setOverride(1)
```

That pins full intensity. Then switch to a client window and walk under a roof —
snow should fade out over about a third of a second and return when you step out.

Note that the storm still takes a few seconds to visually ramp up (particle
density needs time to fill in, lighting eases in) — that's intentional so a
real storm doesn't snap on like a light switch. For faster iteration while
testing, pass `true` as a second argument to skip the ramp-up entirely:

```lua
require(game.ServerScriptService.Weather.WeatherService).setOverride(1, true)
```

Other command-bar helpers:

```lua
local W = require(game.ServerScriptService.Weather.WeatherService)
W.setOverride(nil)   -- resume the automatic cycle
W.setOverride(1, true) -- instant full storm, testing only
W.forceStorm()       -- jump straight to Building
W.forceClear()       -- jump straight to Fading
W.getPhase()
```

## Tuning

Everything is in `src/shared/WeatherConfig.luau`. The ones you'll actually touch:

| Setting | Effect |
| --- | --- |
| `ParticleBudget` | Hard cap on live flakes. **The one knob for performance.** Max emission rate is derived from it. |
| `PhaseDurations` | How long each phase of the cycle lasts. |
| `WindStormSpeed` | How hard a full blizzard blows. |
| `ShelterSmoothing` | How fast snow fades when you step under cover. |
| `ShelterRespectCanCollide` | On by default, so decorative non-collidable parts don't count as roofs. **Turn off if your builders make real roofs non-collidable.** |
| `FlakeTexture` | Swap for a custom snowflake asset when art provides one. |
| `EnableLightingEffects` | Set false if your map already drives fog and Atmosphere. |

### Known trade-offs

- **Shelter is measured from the character, not the camera.** In third person the
  camera often floats outside the building you're in; measuring from the body
  matches player intuition. The cost is that snow stops while the camera is
  outdoors looking in.
- **Lighting is driven by intensity only**, not by shelter, so fog still reads
  indoors. Tying it to shelter looks worse — it pops every time you cross a
  doorway.
- **`WindAffectsDrag` is flagged deprecated** in the API dump while still being
  the documented way to make particles follow `GlobalWind`. It's set inside a
  `pcall`; the snow's actual horizontal motion comes from `Acceleration`, so
  nothing breaks if it goes away.

## Performance notes

- The rig is parented to `workspace.CurrentCamera`, so it never replicates.
- Total network cost is 4 numbers a few times a second, and only when they
  change by more than a threshold — independent of player count.
- Raycasts: 5 per client every 0.2 s, and **zero** when no storm is active.
  `RaycastParams` is built once and reused.
- `NumberSequence` properties allocate on assignment, so they're rebuilt only
  when intensity crosses a bucket boundary, not every frame.
- The whole loop early-outs when there's no storm and nothing left to fade.

## Adding gameplay effects

`WeatherRuntime.server.luau` has a commented-out, working example of cold damage.
Use `WeatherService.isPlayerSheltered(player)` — the server's own raycast — and
never a value reported by the client.

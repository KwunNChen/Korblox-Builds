# Random Artillery

Artillery system for Korblox Confederacy. Barrages fall on wherever the players are, the
guns are audible before the shells land, and anything caught in the open comes apart.

Built after CENTAURA's artillery: no models, no shell parts on the server — just bright
trails arcing over the sky, a wide scatter of impacts, and dismemberment on every kill.

## What it does

Every couple of minutes the guns fire. You hear them, and you get `BarrageWarningLead`
seconds before the first of a dozen-odd shells arrives. They come in on a shared heading so
the trails arc roughly parallel, scatter across an area centred on wherever players are
clustered, and detonate with a kill radius, a falloff band, and a cover check. Anyone killed
by one loses limbs. Anyone who survives nearby is dazed for a few seconds.

## Architecture

Server-based code, clients pull from it.

```
SERVER   ServerScriptService.Artillery
  BarrageService  ->  picks epicentre + every impact point
                  ->  ArtilleryShell RemoteEvent, one packet per shell
                      launch, impact, flightTime, impactTime
                  ->  attributes on ReplicatedStorage.ArtilleryState
                      BarrageActive, WarningActive, ShellsLeft,
                      SecondsToFirstImpact
  ImpactService   ->  radius sweep, falloff, cover raycast, damage
  Dismember       ->  R6 limb severing + corpse ragdoll
                              |
                              |  replicates automatically
                              v
CLIENT   StarterPlayerScripts.Artillery
  reads those      ->  its own shell parts, parented to the Camera
                   ->  Trail, whistle, surface-matched debris
                   ->  distance-delayed boom, camera shake, dust
```

**The server never creates a shell.** It publishes four values and lets each client draw its
own. Twenty replicated physics assemblies per barrage would be visible network stutter for
an effect that is purely cosmetic — the only thing that has to be authoritative is the
damage, and that never leaves the server.

**Timing is shared, not measured.** Each shell carries an absolute `impactTime` from
`workspace:GetServerTimeNow()`, which is the same clock on every machine. The client derives
its own progress from it every frame, so the explosion lands on the frame the damage is
applied whatever the player's ping is. Sending a duration instead would drift by exactly one
trip's latency per shell.

**Damage is never client-reported.** The client is told where shells land so it can draw
them; it is never asked what it hit. A client that simply declined to mention it was
standing in the crater would otherwise be immortal.

## The arc

Real projectile motion. Given a launch point `S`, an impact point `P` and a flight time `T`:

```
v    = (P - S - 0.5*a*T^2) / T        -- a = (0, -ShellGravity, 0)
p(t) = S + v*t + 0.5*a*t^2
```

Both sides run it, which is why a shell is four numbers on the wire and not a stream of
positions. The shell accelerates downward for the whole flight, so it comes in visibly
faster than it went out — that acceleration is the entire reason this isn't a Bézier. A
curve of the same shape travelled at constant speed reads as floaty no matter how good the
shape is.

`ShellGravity` is a look knob. It has nothing to do with `workspace.Gravity` and doesn't
need to match it; the shell is drawn, never simulated.

### Change `ShellGravity` whenever you change `ShellFlightTime`

The launch velocity is *solved* so the shell lands exactly on target, and its upward component
works out to roughly `0.5 × gravity × flightTime`. Double the flight time at fixed gravity and
the shell is fired twice as hard upward — it climbs out of sight and drops back in rather than
arcing. At the current 7.25s flight, leaving gravity at the old 180 would launch shells at
539 studs/s upward, peaking 800 studs above their own launch point.

To keep the same arc *shape* at a new flight time, scale gravity by the inverse square of the
change. 3.8s → 7.25s is 1.9× longer, so gravity drops by 1.9² — 180 to about 50.

Current defaults peak only 10–160 studs above the launch point and travel 112–200 studs/s
horizontally, about half the old speed.

## The trail

A `Trail` between two attachments on a small Neon part, with `LightEmission = 1` so it
ignores scene lighting and always reads bright against a dark or foggy sky. That's the whole
trick — twenty actual `PointLight`s would not survive contact with a framerate.

The part, its trail and the impact particles all live in a folder under
`workspace.CurrentCamera`. Nothing under the Camera replicates, which is the same approach
Variable Snowstorm uses for its particle rig.

## The impact

**Nothing is left behind.** No crater, no decal, no scorch — a shell throws the ground up and
that's the whole of it. Every part the impact creates is an emitter host that cleans itself
up within `ImpactEffectLifetime`.

The debris is made of whatever the shell actually hit. One downward raycast at the crater
reads the surface: a part's `Color`, or `Terrain:GetMaterialColor` for terrain. Snow throws
white, mud throws brown, and none of it has to be authored per map. `DebrisFallbackColor`
covers the case where the ray finds nothing.

### Three stages, in order

An impact is a sequence, not one burst:

| Time | Stage |
| --- | --- |
| 0.00s | **Dust** — one cloud appearing over the crater and opening out |
| 0.04s | **Debris** — the ground thrown out |
| 0.22s | **Smoke** — what's left hanging over it |

There's no glowing ball. A brief `PointLight` stays (no visible geometry) because it lifts the
scene for a moment on a dark map; `EnableImpactLight = false` removes even that.

### The dust cloud

**One flat image per crater**, not particles and not a field of geometry — both were tried,
and both read as many separate pieces rather than one cloud. A hundred small sprites look
thin against open ground; forty overlapping balls just look like forty balls. One image that
visibly **grows and sinks** is the whole effect, and it costs one `Part` with one `Decal`.

The animation is the point. A static decal is a stain — what sells this as dust settling is
that it does two things at once over its life:

- **Grows**, fast at first (`DustDecalGrowthCurve` below 1) then slower, from
  `DustDecalStartSize` out to `DustDecalEndSize` — the punch of the burst followed by the
  drift of dust still opening out.
- **Sinks**, from `DustDecalStartHeight` down to `DustDecalEndHeight` — the image visibly
  settling onto the ground rather than appearing already flat.

...plus a slow `DustDecalSpin`, so the mass reads as churning rather than scaling in place.
It's stepped by hand each frame rather than tweened, because size, height and transparency
all move on different curves.

It's oriented against the **surface normal** from the same raycast that picks the debris
colour, so it lies flat on a slope instead of floating at a fixed world-up angle.

It's still temporary: held fully visible for `DustDecalHoldTime`, then fades over
`DustDecalFadeTime` and is destroyed. "Nothing is left behind" means nothing left behind
*forever*, not nothing drawn at all. `MaxLiveDust` caps how many can exist across a whole
barrage at once — excess impacts simply draw no dust.

**This is the one impact effect that still needs a texture.** Debris is real parts and cannot
fail; this can, silently — a decal id where an image id was needed renders nothing at all. If
dust never shows up, `DustDecalTexture` (or its fallback, `SmokeTexture`) is why — see
[The one remaining texture slot](#the-one-remaining-texture-slot).

`DustDecalTexture` falls back to `SmokeTexture` when empty, so filling in one image covers
both. Set it separately only if you want the dust to be a different image — a soft round
cloud sprite reads better here than the wispier shape that suits rising smoke.

Everything firing on the same frame is what makes an explosion read as a flat pop. The dust
appearing, the ground coming up and the smoke settling become one event visually otherwise. A
few hundredths of a second between them is enough to fix it — `ImpactDebrisDelay` and
`ImpactSmokeDelay` set the gaps.

### Debris is real parts, not particles

This is deliberate, and it was a rewrite. Sprites depend on a texture asset, and **every way
that can go wrong fails silently and identically**:

- A moderated or deleted asset ID
- A *decal* ID used where an *image* ID was needed
- `rbxasset://<number>` — the engine-path prefix with an upload ID after it, which asks for a
  file named after a number and finds nothing
- No texture at all, which falls back to Roblox's default **white sparkle**

None of those print anything to Output. You get glitter, or you get nothing, with no way to
tell which knob is at fault. Two rounds of tuning went into chasing exactly that.

A `Part` can't fail that way. It has a size, a colour and a position; it renders; and if it
ends up somewhere wrong you can *see* where it went. It also matches the reference better —
real tumbling boxes rather than flat sprites always facing you.

Chunks are `Anchored` and moved by hand each frame, because nothing parented under
`workspace.CurrentCamera` is physically simulated. That's a feature: reach is exactly
predictable from the numbers instead of depending on collisions, and a few hundred `CFrame`
writes are far cheaper than a few hundred physics assemblies.

### Setting the debris radius

- **`ChunkSpeed`** — how hard it's thrown
- **`ChunkLifetime`** — how long before it vanishes if it hasn't landed
- **`ChunkGravity`** — how fast it's pulled down

Reach is roughly `speed × lifetime`, but only if gravity lets it stay airborne that long. **To
go wider, raise lifetime and lower gravity.** To go more violent without going wider, raise
speed and gravity together.

**The speed range must start low.** Every chunk rolls its own speed inside the range. Set the
*minimum* high — say 200 — and nothing travels slower than that, so within half a second the
whole burst is hundreds of studs away and there's a visible hole where the explosion just was.
A wide range starting low gives the real thing: a dense pile at the crater thinning out to
chunks arcing away at the edges.

`ChunkElevation` (degrees above horizontal) replaces what used to be a separate plume and
splash. Low angles skim across the ground, high angles go up and come back down, and rolling
across the whole span every time gives you both from one throw.

`MaxLiveChunks` caps every burst on screen at once. A barrage is a dozen-plus shells inside a
few seconds, so without it a heavy one would put well over a thousand parts up.

## Layout

```
ReplicatedStorage
├── Artillery
│   ├── ArtilleryConfig     all tuning lives here
│   └── ArtilleryShared     attributes, trajectory math
├── ArtilleryState          replicated attributes
└── ArtilleryShell          RemoteEvent, one packet per shell

ServerScriptService
├── Artillery
│   ├── BarrageService      cadence, targeting, shell scheduling
│   ├── ImpactService       damage, falloff, cover, concussion
│   ├── Dismember           R6 limb severing
│   └── ArtilleryRuntime    entry point + debug knobs
└── Common
    ├── CharacterCache      cached root/humanoid lookups
    └── SpeedService        owns WalkSpeed and jump height

StarterPlayer/StarterPlayerScripts
└── Artillery
    ├── ArtilleryClient     entry, owns the one render loop
    ├── ShellRender         the arcing part + Trail + impacts
    ├── DebrisChunks        thrown ground, as real parts
    ├── DustCloud           the ground dust cloud, one decal per crater
    ├── ArtilleryAudio      report, whistle, distance-delayed boom
    └── ArtilleryShake      camera shake + screen dust
```

## Installing in a game

Three services, one model file, so you place the folders yourself. The folders inside the
.rbxm are named after where they go.

1. Drag `RandomArtillery.rbxm` into **ServerStorage**. Scripts don't execute there. Drop it
   into ServerScriptService or Workspace instead and the server scripts start running before
   the shared modules exist.

2. From its `ReplicatedStorage` folder, move `Artillery`, `ArtilleryState`, and
   `ArtilleryShell` into the real ReplicatedStorage. Miss `ArtilleryShell` and artillery
   disables itself with a warning in Output.

3. From its `ServerScriptService` folder, move `Artillery` and `Common` into the real
   ServerScriptService. If your game already has a `Common` folder — and it will if you
   installed Variable Snowstorm or Ski — drag `CharacterCache` and `SpeedService` into that
   one rather than replacing it. They are the same files.

4. From its `StarterPlayerScripts` folder, move `Artillery` into StarterPlayer >
   StarterPlayerScripts. Skip this and barrages still land and still kill people, but nothing
   draws and there's no warning sound. That failure looks exactly like a broken install and
   plays like a very unfair one.

5. Delete the empty `RandomArtillery` folder.

Press Play. After that the only file you edit is
`ReplicatedStorage.Artillery.ArtilleryConfig`.

### This is R6 only

Dismemberment destroys the `Motor6D`s on an R6 character's `Torso`. Those joints don't exist
on R15, so an R15 character is detected, killed normally, and warned about once. Set
`EnableGore = false` for plain kills and no warning.

### Tag your spawns

Nothing stops shells landing on a spawn until you say so. Tag a part covering the area with
`ArtillerySafeZone` (Properties > Tags). Height is ignored, so one flat plate laid over the
spawn protects the whole column above it.

### Audio needs your own assets

Four ids in the config, all shipping empty: `BatteryReportSoundId`, `ShellWhistleSoundId`,
`ImpactNearSoundId`, `ImpactFarSoundId`. Roblox audio has been private by default since 2022,
and an id that works in one place is silent in another with no error at all.

`BatteryReportSoundId` is the one that matters — it's the only warning a player gets, and
without it a barrage is an unannounced death.

### Rebuilding the package

```bash
rojo build package.project.json -o RandomArtillery.rbxm
```

This reads the same `src/` as the dev project, so there's no second copy of the code to keep
in sync.

## Setup for development

Requires [Rokit](https://github.com/rojo-rbx/rokit/releases). From this folder:

```bash
rokit install
```

```bash
rojo serve
```

Then hit Connect in the Rojo plugin in Studio.

## Testing

Barrages are 120–260 seconds apart, so force one rather than waiting it out. Mid playtest,
with the Client/Server toggle in the toolbar set to **Server**:

```lua
game.ReplicatedStorage.Artillery:SetAttribute("DebugBarrageNow", true)
```

It resets itself and the server prints `[Artillery] barrage -> 12s warning, then shells`. No
print means the command never reached the server, which is almost always the toggle sitting
on Client.

To bake it in instead, set `ArtilleryConfig.DebugFirstBarrageDelay = 10` and every playtest
opens with a barrage. That runs as ordinary server code at boot, so nothing Command Bar
related can break it.

`DebugDrawImpacts = true` marks every impact point as the barrage is scheduled, so you can
watch targeting without standing in it.

### BUG: the timer never fires a barrage on its own, only `DebugBarrageNow` does

This is **`MinPlayersForBarrage`**, almost always. The natural loop skips a cycle entirely if
fewer players are online than that — default **4** — while `DebugBarrageNow` has no such
check and always fires. Testing solo or with a couple of friends means the natural timer is
never satisfied, no matter how long you wait, and it used to fail *silently*: nothing printed,
so it looked indistinguishable from broken.

The loop now logs `natural barrage skipped -- N online, MinPlayersForBarrage is M` every time
this happens (needs `DebugLog = true`). If you see that line, the timer is working correctly —
it's the player count that's stopping it. Set `MinPlayersForBarrage = 1` while testing alone.

### BUG: barrage runs but nothing appears

1. Did the server fire? Look for `BARRAGE INCOMING` in Output. If it isn't there the barrage
   never ran — check someone is alive and `Enabled` is true.

2. Did it reach your client? `[Artillery/client] ready` prints at join. No line means install
   step 4 got missed.

3. Looking the wrong way? Shells come in on `BatteryHeading`, 45 degrees by default. Turn to
   face it, or use `DebugDrawImpacts`.

4. Landing out of sight? `GroundSnapHeight` has to clear the tallest thing on your map or
   impacts snap onto rooftops. `GroundSnapDepth` caps how far down a shell will chase ground
   it can't find.

5. Everyone indoors? `barrage skipped -- all N players are under cover` in Output means the
   shelter check ate every candidate. See below — on a heavily enclosed map you may want
   `ShelterBlockedThreshold` higher, or `SkipShelteredPlayers = false`.

### Players under a roof aren't aimed at

A battery a kilometre away can't see through a bunker, so anyone indoors is dropped from the
list the epicentre is picked from — and stops counting toward anyone else's cluster weight
along with it. A squad that made it inside shouldn't still be pulling fire onto the door they
came through.

It's five upward raycasts per candidate — one straight up plus four at `ShelterSampleRadius`
— and whatever stops a ray *is* the roof, so bunkers, bridges, rock overhangs and tree canopy
all work with nothing tagged. Five rather than one for the same reason the damage cover check
samples three: a single ray is a coin flip on the edge of any cover, so standing in a doorway
would flicker between safe and targetable from one barrage to the next.

**This is not a shield.** It only decides where the guns *aim*. A shell aimed at the squad
outside your door still lands outside your door, and the blast that follows doesn't care what
you're standing under — a roof only helps you there through the damage cover check, which is
separate and doesn't apply in the kill sphere at all.

If every player is indoors the barrage is skipped and logged rather than falling back to
shelling someone anyway.

## Tuning

Everything is in `src/shared/ArtilleryConfig.luau`.

| Setting | Effect |
| --- | --- |
| `BarrageInterval` | Seconds between barrages. |
| `MinPlayersForBarrage` | Below this online, the natural timer skips its cycle. `DebugBarrageNow` ignores it. Set to 1 solo. |
| `ShellsPerBarrage` | How many shells one barrage drops. Twelve-plus is what makes it read as a barrage. |
| `ShellSpacing` | Seconds between launches. Small lands them at once, large walks the barrage across the ground. |
| `BarrageWarningLead` | Seconds of warning before the first impact. **This is the mechanic** — under about 4 nobody reaches cover and the whole thing reads as unfair. |
| `ClusterRadius` | How far apart players still count as a crowd for targeting. |
| `SkipShelteredPlayers` | Players under a roof aren't aimed at. Decides targeting only — it is not a shield. |
| `ShelterCheckHeight` | How far up the roof rays look. Only has to clear your tallest interior. |
| `ShelterSampleRadius` | How far out the four side rays sit. Roughly a doorway's width. |
| `ShelterBlockedThreshold` | Fraction of five rays that must be blocked. 0.5 is three of five. |
| `EpicenterJitter` | How far the barrage lands from whoever drew it. Keep it well above `KillRadius` or it stops reading as area denial. |
| `ShellScatterRadius` | How wide shells spread from the epicentre. |
| `ScatterCenterBias` | Lower packs shells toward the middle; 0.5 spreads them evenly. |
| `BatteryHeading` | Compass direction the guns fire from. Shared by every shell in a barrage. |
| `BatteryHeadingSpread` | Per-shell wobble on that heading. Zero looks artificial. |
| `ShellFlightTime` | Seconds in the air — also how long the arc is on screen. |
| `ShellGravity` | Steepness of the arc and how hard it plunges. Not `workspace.Gravity`. |
| `TrailLifetime` | Length of the streak. The single biggest look knob. |
| `TrailLightEmission` | What makes the trail glow without a light source. |
| `MaxRenderedShells` | Shells drawn at once. The main client performance knob — live trail segments scale with it. |
| `ShellRenderDistance` | Deliberately huge. Watching a barrage land on someone else across the map is most of the point. |
| `ImpactEffectDistance` | Particles are culled well before trails are; dust is invisible at range anyway. |
| `DebrisMatchSurface` | Colour the debris from what the shell hit. Off uses `DebrisFallbackColor` everywhere. |
| `EnableDustDecal` | The dust cloud. One image per crater — the main "more effect" knob. |
| `DustDecalTexture` | Its image. Falls back to `SmokeTexture` when empty. The one dust effect that can fail silently. |
| `MaxLiveDust` | Ceiling on how many can exist across a whole barrage at once. |
| `DustDecalStartSize` / `DustDecalEndSize` | What it grows from and to. The gap between them *is* the effect. |
| `DustDecalGrowthCurve` | Below 1: fast growth then a creep. 1: linear. Above 1 reads backwards. |
| `DustDecalStartHeight` / `DustDecalEndHeight` | The sink — where it appears and where it settles. |
| `DustDecalSpin` | Slow rotation so the mass churns instead of just scaling in place. |
| `DustDecalHoldTime` | Seconds fully visible before it starts fading. |
| `DustDecalFadeTime` | How long the fade takes. Hold + fade is its whole lifetime. |
| `DustDecalDarken` | How far the image colour is pulled toward black, after the surface tint. |
| `EnableImpactLight` | Brief light at the crater. No visible geometry. |
| `ChunkCount` | Chunks thrown per shell. The main density knob, and the main cost. |
| `MaxLiveChunks` | Ceiling across every burst on screen at once. |
| `ChunkSize` | Per-chunk size range. A wide span matters more than the numbers. |
| `ChunkSpeed` | **Must start low** — a high minimum leaves a hole at the crater. |
| `ChunkGravity` | Lower throws chunks wider. The real limit on radius. |
| `ChunkElevation` | Degrees above horizontal. Low skims the ground, high arcs up. |
| `ChunkSpin` | How hard chunks tumble. |
| `ChunkMaterial` | Material of the chunks. Slate reads as rock. |
| `DebrisDarken` | How dark the thrown earth is. Stops it reading as glitter. |
| `ImpactDebrisDelay` | Gap between the flash and the debris. |
| `ImpactSmokeDelay` | Gap between the flash and the smoke. |
| `ImpactSmokeCount` | Particles in the lingering cloud. |
| `ImpactSmokeColor` | Tints the smoke, including whatever `SmokeTexture` you upload. |
| `ImpactSmokeRise` | How fast the cloud climbs. Small values — fast smoke reads as rocket exhaust. |
| `SmokeTexture` | Your own image for the smoke. The slot most worth filling. |
| `KillRadius` | Instant death, always dismembers. |
| `DamageRadius` | Outer edge of the falloff band. |
| `FalloffExponent` | 2 is inverse-square; 1 is linear and far more punishing at the edges. |
| `EnableCoverCheck` | Raycast from crater to victim. Walls work. |
| `DismemberRadius` | Layer 2. Damage plus limbs off. Must sit between `KillRadius` and `DamageRadius`. |
| `DismemberOnAnyKill` | Make layer 3 kills dismember too. Off keeps the layers visually distinct. |
| `BlastVerticalScale` | How much height counts when measuring distance. Below 1 the blast reaches up and down slopes. 1 is a true sphere. |
| `MaxFalloffDamage` | Damage at the kill radius edge. **Keep it well above a full health bar** — at exactly 100 nobody healthy can die outside the kill sphere. |
| `CoverDamageReduction` | What full cover is worth in layers 2 and 3. Sampled at three body points and scaled, not switched. Never applies to layer 1. |
| `CoverRayLift` | How far the cover ray starts above the crater. **Must stay above 0** — see below. |
| `EnableMaiming` | Shrapnel takes limbs off survivors the blast didn't kill. |
| `MaimChance` | Odds a layer-2 survivor loses limbs, falling to zero at the layer's outer edge. |
| `MaimIncludesLegs` | Off by default — a living R6 character with no legs hovers. |
| `AffectNPCs` | On by default. NPCs take damage, concussion and dismemberment on the same terms players do. |
| `EnableConcussion` | Survivors near a blast get dazed. Goes through `SpeedService`. |
| `EnableGore` | False turns every artillery kill into an ordinary death. |
| `MaxLimbsSevered` | Limbs off on a direct hit. |
| `ShowStumps` | Exposed bone in the socket. No asset needed. |
| `GoreLifetime` | Seconds before severed limbs clean up. |
| `ShakeTranslation` | How hard the camera rattles at the crater. |
| `ShakeDustStrength` | Screen dust wash on close hits. 0 turns it off. |
| `SoundSpeed` | Studs/sec the boom travels. Lower stretches the gap after the flash. |
| `MaxConcurrentSounds` | Ceiling on overlapping booms. A barrage will try to layer twenty. |
| `SafeZoneTag` | CollectionService tag for areas never shelled. |
| `DebugDrawImpacts` | Marks impacts before they land. |
| `DebugFirstBarrageDelay` | Seconds to the first barrage after boot. Negative uses the normal interval. |

## Damage bands

Three of them, measured from the crater to the victim's `HumanoidRootPart`:

Four spheres around the crater, each wholly inside the next. A victim is measured once, lands
in exactly one layer, and that layer decides everything.

| Layer | Distance | What happens |
| --- | --- | --- |
| 1 | ≤ `KillRadius` (18) | **Dead. Always.** Full dismemberment. |
| 2 | ≤ `DismemberRadius` (34) | Falloff damage, and limbs come off — a corpse's if it killed you, yours if it didn't. |
| 3 | ≤ `DamageRadius` (46) | Falloff damage only. A kill here dies intact. |
| 4 | ≤ `ConcussionRadius` (70) | Dazed for a few seconds, no damage. |

**Layer 1 is pure distance.** No raycast is even fired. Cover, walls, bunker roofs — none of
it applies. A shell landing on top of you is not survivable by standing behind something, and
making it survivable turns the kill sphere into a suggestion. Cover only scales damage in
layers 2 and 3.

A kill out in layer 3 dying intact is what makes the onion readable — what's left of a body
tells you which layer caught them. Set `DismemberOnAnyKill = true` to make every artillery
kill come apart at any distance, which is what Centaura itself does, at the cost of that
distinction.

The layers **must** be in ascending order. Out of order, an inner sphere swallows an outer one
and that band silently never happens — which looks like a broken feature rather than a bad
number, so the server checks at startup and warns.

### Height counts less than ground distance

Distance to a victim is measured with the **vertical** component scaled by
`BlastVerticalScale` (0.6) before the length is taken, so the blast is a flattened,
ground-hugging ellipsoid rather than a sphere.

A true sphere is why a shell can land a few studs in front of you on a slope and leave you
standing — height spends exactly the same radius budget as ground distance. A shell 6 studs
in front of you but 25 studs down a slope measures **28.6** studs on a true sphere, which is
past the damage radius entirely. At 0.6 it measures 17.8 and kills.

On flat ground the two are nearly identical, which is why this only ever showed up on terrain
with level changes.

Raise it toward 1 for strict spherical falloff on a flat map. Don't go to 0 — the blast would
reach infinitely far vertically and shell people through floors.

### Why damage used to feel random

Three separate causes, all fixed, all worth knowing because they're easy to reintroduce.

**`ForceField` split the onion in half.** `Humanoid:TakeDamage` is blocked by a ForceField —
Roblox's default spawn protection. Assigning `Humanoid.Health` is *not*, and `Dismember.apply`
assigns it. So against a freshly spawned player, layers 2 and 3 did absolutely nothing while
layer 1 killed them outright through the shield: same barrage, same player, opposite outcomes
decided only by which ring they stood in.

Every point of damage now goes through one `applyDamage` helper in `ImpactService` that
assigns `Health` directly, so **artillery penetrates spawn protection in every layer**. That's
the intended behaviour — a shell doesn't care that you just respawned — but the reason it's a
single helper is that the *inconsistency* is what was actually broken, and two call sites
using two different APIs is how it comes back. To protect a spawn, tag it `ArtillerySafeZone`;
unlike a ForceField that stops the shell being aimed there at all.

**Cover was a coin flip.** One raycast to the torso meant a stud of shuffling swung the whole
hit between full damage and a quarter of it, with nothing in between. Three rays now sample
head, torso and legs, and damage scales by the fraction blocked.

**A full-health player could never die outside the kill sphere.** `MaxFalloffDamage` was 100,
exactly a default health bar, so at a tenth of a stud past the boundary the curve dealt 99.3
and they walked away on 1 HP. Whether a layer-2 hit killed depended entirely on invisible
prior damage from earlier shells in the same barrage. At 165 the curve stays lethal to about
24 studs and then grades off, so the kill sphere has a margin instead of an edge.

### Reading what actually happened

With `DebugLog = true` the server prints one line per victim per shell:

```
Player1 at 24.3 (21 flat, -12 up) -- LAYER 2, cover 33%, 98 damage, survived (2 HP left)
```

The `flat` and `up` figures are the whole point: they tell you immediately whether a shell
that *looked* close was actually far away vertically.

Most remaining "that felt wrong" moments are two shells overlapping within a second, or a
health pool already chewed down — neither of which is visible from inside the game.

**NPCs are treated identically.** Every band above applies to any non-player Humanoid in
range, including dismemberment. The sweep walks *up* from each part it finds to the model
that actually owns a Humanoid, rather than taking the nearest `Model` ancestor — a hat, a
tool or a weapon rig is a `Model` too, and stopping at one of those silently skips the NPC
wearing it. Players are excluded from the sweep because `detonate` already handled them by
name; hitting them twice would double every shell.

### The texture slots that are left

Debris is real parts and depends on no asset at all. Smoke and the dust cloud are both
images, and by default they **share one slot** — `DustDecalTexture` falls back to
`SmokeTexture` when empty, so filling in one covers both. Set `DustDecalTexture` separately
only if you want the dust to look different from the smoke.

**`SmokeTexture` ships as an engine path, not an ID, on purpose.** An engine path can't be
moderated, can't be a decal id by mistake, and renders on every client with no upload. IDs
kept going into this slot and kept coming out invisible — which is exactly what "no dust is
showing up" was, since the dust cloud falls back here too. Put your own back if you have one
that works, but if the smoke or the dust ever vanishes again, restore the engine path first
and you have your answer in one playtest.

**Never leave `SmokeTexture` empty.** A `ParticleEmitter` with no `Texture` falls back to
Roblox's default sprite, which is a **white sparkle** — the glittery confetti look, and no
amount of size, count or colour tuning removes it, because the sparkle *is* the sprite. The
dust `Decal` fails differently and more quietly: an empty or bad texture there just renders
nothing at all, which is why `EnableDustDecal` skips the cloud entirely rather than drawing a
blank rectangle when neither texture resolves to anything.

Two forms are valid, and mixing them is the classic mistake:

| Form | Meaning |
| --- | --- |
| `rbxassetid://13623094740` | An uploaded image |
| `rbxasset://textures/particles/smoke_main.dds` | An engine file that ships with Studio |

`rbxasset://13623094740` is **neither** — it asks the engine for a file named after a number,
finds nothing, and renders blank with no error. `ArtilleryShared.assetId` repairs that case,
but it's worth knowing because nothing else you paste an ID into will.

**The other trap:** uploading an image to Roblox creates a **Decal**, and a decal's id is
*not* the image's id. A decal id renders nothing, silently. Drop the decal onto any part in
Studio and read the `Texture` property off the `Decal` instance it creates — that value is the
image id. Uploading through the Creator Dashboard under Images gives you the image id directly.

Use a **greyscale** image; `ImpactSmokeColor` tints whatever you give it.

### `CoverRayLift` must stay above zero

`snapToGround` returns a point sitting exactly *on* the surface. A cover ray cast from there
hits the ground it starts on within the first stud, so every shell in the open reads as fully
covered and damage silently caps at `MaxFalloffDamage × CoverDamageReduction` — 25 against a
default 100 HP humanoid. Artillery stops killing anyone and looks like it simply doesn't
work. Lifting the origin a few studs is the whole fix.

## Gameplay hooks

`ArtilleryState` carries `BarrageActive`, `WarningActive`, `ShellsLeft` and
`SecondsToFirstImpact` as replicated attributes, so a UI can read them from anywhere:

```lua
local Shared = require(game.ReplicatedStorage.Artillery.ArtilleryShared)
local stateHolder = Shared.getStateHolder()

stateHolder:GetAttributeChangedSignal("WarningActive"):Connect(function()
	if stateHolder:GetAttribute("WarningActive") then
		-- flash an INCOMING banner
	end
end)
```

`WarningActive` is true only during the lead; `BarrageActive` stays true until the last shell
has actually landed, so an all-clear read off it won't fire while rounds are still in the air.

`BarrageService.triggerNow()` drops a barrage from server code.

## Speed modifiers

The concussion effect registers a `Concussed` modifier through `SpeedService` and clears it
when it wears off. Modifiers compose, so being concussed while sprinting in a blizzard stacks
all three without any of them knowing about the others:

```
final = base × (all multipliers) + (all additions)
```

One rule: never assign `WalkSpeed` directly once a humanoid is managed there. Outside writes
get overwritten on the next recompute.

## Performance notes

- No shell part is ever created on the server, and nothing the client draws replicates.
- Network cost is four values per shell, roughly fifteen shells every couple of minutes. It
  doesn't scale with player count.
- One `RenderStepped` connection for every shell, not one per shell.
- Impact sounds are pooled and capped; a failed asset can't leak the pool.
- Blood emitters disable themselves after the spurt rather than running for the corpse's
  whole lifetime.
- Severed limbs are explicitly server-owned. Client-owned gore sinking through the floor is
  the classic failure here.
- The render loop and the shake loop both idle fully between barrages.

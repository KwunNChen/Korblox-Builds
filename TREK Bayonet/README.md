# TREK Bayonet

A melee **fire mode** for TREK rifles. Press **V** to switch from the rifle to the blade,
click to thrust — **at any ammo count, mid-reload, while sprinting**. TREK ships no melee
of any kind, so all of this is new.

| | |
|---|---|
| **Needs** | [TREK Custom Bullets](https://devforum.roblox.com/t/shapecasthitbox-for-all-your-melee-needs-v025/3624241) installed as your gun handler, and an existing TREK 4 install |
| **Adds** | one folder each in ReplicatedStorage and ServerScriptService, plus one module in `BulletTypes` |
| **Touches** | nothing in TREK — it plugs into Custom Bullets' documented extension point |
| **Works at** | 0 ammo, mid-reload, while sprinting |

> **If you are coming from the G-key version, two things it insisted on are now wrong.**
> The config block was at `[9]` *so that V could never reach it*; it is now at `[2]`
> *because V must*. And it had no `MagCapacity` on purpose; it now needs
> `MagCapacity = math.huge`. Both reversals are explained under
> [How it works](#how-it-works).

---

## Install

### 1. Custom Bullets first, and rename every `BulletType`

Install TREK Custom Bullets as your gun handler. Then go through **every weapon config in
the place** and change `BulletType` from a number to a name:

```lua
BulletType = 1;           -- vanilla TREK
BulletType = 'Hitscan';   -- Custom Bullets

BulletType = 2;           -- vanilla TREK
BulletType = 'Projectile';
```

**This is not optional and the failure mode is brutal.** The handler resolves the name to
a module and then does:

```lua
local bulletType = bulletTypes[config[i].BulletType]
if not(bulletType) then return end
```

That `return` is at **script scope**, not loop scope, and it sits above
`UIS.InputBegan:Connect(input)`. One weapon with a leftover numeric `BulletType` exits the
handler before the mouse is ever connected, and **every gun in the place silently stops
responding**. Because the loop walks `pairs`, which weapon triggers it varies between
runs.

### 2. Put the pack and the bayonet where the installer will find them

**If TREK is built at runtime by `Workspace.Installer`** — the usual case, and the one to
assume unless you know otherwise — nothing you place in `ReplicatedStorage.TREK_SERVICES`
survives. The installer builds that folder itself, and `TREKServerGeneral` does:

```lua
for i, service in pairs(game.ReplicatedStorage:WaitForChild('TREK_SERVICES'):GetChildren()) do
```

A `TREK_SERVICES` that already exists makes that `WaitForChild` return **instantly**, so
TREK enumerates a folder the installer has not filled yet, misses `TREK_Globals`, and the
entire install dies at the next line. Creating that folder early — by hand or with Rojo —
breaks TREK completely, and the symptom is a wall of unrelated errors.

Everything local goes in as a **plugin** instead, shaped like the ones already there:

```
Workspace > Installer  > Plugins > TREKCustomBullets
    ReplicatedStorage/TREK_SERVICES/TREK_Modules/
        BulletModule, ShapecastHitbox
        BulletTypes/{Hitscan, Projectile, Melee, Bayonet}
    ServerStorage/TREKToolHandlers/Gun
```

(Note the trailing space in `Installer ` — it is part of the instance name.)

`ServerStorage.TREKToolHandlers.Gun` is **place content**, not something the installer
recreates. Deleting it means nothing handles the Tool and your guns stop equipping
entirely.

`Bayonet` must sit beside `Hitscan`, `Projectile` and `Melee`. If it does not, the handler
cannot resolve `BulletType = 'Bayonet'` and takes every gun down with it, as above.

**This repo's `default.project.json` already does all of that**, so from source it is just:

```bash
rojo serve default.project.json
```

**If you are installing from `TREKBayonet.rbxm`** instead, it gives you a staging folder:

```
TREKBayonet                   <- staging folder, delete when done
|-- README                       read-me, not installed
|-- BayonetWeaponMode            paste-in snippet, not installed
|-- ReplicatedStorage
|   `-- TREKBayonet           <- move THIS into game.ReplicatedStorage
|-- ServerScriptService
|   `-- TREKBayonet           <- move THIS into game.ServerScriptService
`-- BulletTypes
    `-- Bayonet               <- move THIS next to Hitscan / Projectile / Melee
```

`ReplicatedStorage.TREKBayonet` and `ServerScriptService.TREKBayonet` are ordinary
locations the installer does not touch, so those two are safe to place directly.

### 3. Paste the `[2]` block into the weapon's config module

From `BayonetWeaponMode`, into the same `local configs = { ... }` table that holds `[1]`.

### 4. Three things in Studio

| | |
|---|---|
| **`Bayonet`** | something with that name inside the weapon's Tool. On the stock KR-61 this already exists: `Tool > Weapon > Bayonet`. Its position and size **are** the hitbox. |
| **`2Barrel`** | a small part in the Tool, at the blade, **with no ParticleEmitters**. Without it `currentBarrel` falls back to the rifle muzzle and every swing fires a **muzzle flash and a gunshot** on everyone else's screen. |
| **`2Recoil`** | the thrust animation, in the weapon module's `Animations` folder. `determineAnim` prefixes the mode number, so `2Recoil` plays on a swing while `Recoil` still plays when you fire. `2Idle` and `2SprintHold` do the same for the held and charging poses. |

Optionally add a **`2Fire`** sound to the weapon module — a stab or a whoosh. Without it,
`GFXRender` falls through to `module.Fire` and other players hear a gunshot when you
swing.

### 5. Animations for the fire mode

`determineAnim` picks by mode prefix — `animations["2" .. name] or animations[name]` — so
an Animation named `2Recoil` in the weapon module's `Animations` folder plays on a bayonet
swing while `Recoil` still plays when the rifle fires. `2Idle` and `2SprintHold` do the
same for the held and charging poses.

[tools/WeaponAnimations.luau](tools/WeaponAnimations.luau) creates them from a table of
ids. It locates the weapon **by path**, because two cleverer methods both silently wrote
into the wrong module: matching on the name took the last match in Workspace, and matching
on a known `Idle` asset id hit the KT-60, since TREK weapons share animation ids.

**The trap that costs the most time: an animation with no `AnimPart` track parks the whole
gun at the torso origin.**

TREK joins the weapon with a `Motor6D` named `toolAnim`, built by `createMotor` with
default `C0` and `C1` — both identity. At rest, `AnimPart.CFrame == Torso.CFrame`, so the
gun collapses into the chest and *every* bit of its visible placement comes from the
animation's own `AnimPart` track. In game this reads as "the gun is upside down", and no
rotation fixes it, because there is no pose to rotate.

So before authoring anything for this weapon, **attach the gun to the editing rig**:

| | |
|---|---|
| Rig | must be **R6** — an R6 animation on an R15 rig loads with zero tracks and an empty timeline |
| Joint | `Tool > AnimPart` joined to `Torso` by a `Motor6D` named `toolAnim`, `C0` and `C1` both identity |
| Looks wrong | the gun sits *inside* the torso at rest. That is correct — it is the real rest pose |

An animation that keyframes only the torso and arms lets TREK's walk keep playing
underneath — that is how `2SprintHold` works. But it also means **no `AnimPart` track**,
which for this weapon parks the gun at the torso origin. TREK's own stab, asset
`130508149089530`, is the reference to build from: its poses include `AnimPart`, `Bolt`
and the rest.

To get a published animation back for editing, the Clip Editor's Import is FBX-only, so:

```lua
game:GetObjects("rbxassetid://130508149089530")
```

and parent the result where your Studio's **Load** menu reads from. That location varies by
Studio version — in this project's it is `ServerStorage.RBX_ANIMSAVES.<rig name>`, **not**
`Rig > AnimSaves`. Check which one your Studio uses before assuming; an empty Load menu
usually means the sequence is sitting in the other one.

### 6. Respawn

`TAmmo` is built **once**, lazily, guarded by `if not child:FindFirstChild('TAmmo')`. A
tool carrying a `TAmmo` folder from before the `[2]` block existed never gains a `"2"`
entry. Restart the playtest after editing the config — `SetUpGuns` caches weapon modules
at server start anyway.

### Check it worked

Paste [tools/CheckInstall.luau](tools/CheckInstall.luau) into the command bar. It verifies
every requirement and names what is missing and why it matters — the installer, the pack,
the handler version, both halves of the package, the `[2]` block's load-bearing fields,
every weapon's `BulletType`, the `Bayonet` part, `2Barrel`, and the animations. Set
`FIX = true` in it to create the pieces it can create safely.

Run it **in edit mode** to check what is saved, and **during a playtest** to check what
TREK actually built. Several things exist in only one of the two.

On a playtest you should also see:

```
[TREKBayonet] service ready -- fire mode [2], blade hitbox padded 1.25 side / 2.50 up / 1.50 forward, swept over 0.35s, cadence from the weapon's RoundsPerMinute
```

There is no second line: the client half is a bullet type now, not a script of its own.

---

## Tuning

Hit detection lives in `ReplicatedStorage > TREKBayonet > BayonetConfig`:

```lua
Config.ConfigIndex           = 2      -- which mode block the bayonet is
Config.HitPadSide            = 1.25   -- how far off-centre your aim can be
Config.HitPadVertical        = 2.5    -- how much height difference is forgiven
Config.HitPadForward         = 1.5    -- reach past the tip
Config.HitWindow             = 0.35   -- how long the blade keeps being tested
Config.HitSampleInterval     = 0.03   -- gap between tests inside that window
Config.ServerCooldownTolerance = 0.9  -- slack on the derived rate limit
Config.RestoreSprint         = true   -- keep sprinting through the swing
Config.Debug                 = false  -- true = every swing reports itself
```

**Damage, fire rate and animations are not here.** They are in the weapon's `[2]` block
and its `Animations` folder, because the bayonet is a fire mode rather than a system
bolted on beside one. There is no `Cooldown` setting either — the server derives its rate
limit from the same `RoundsPerMinute` the handler paces swings with, so there is one
number to change.

**The padding is measured in your frame** — level, facing where you face — so the three
numbers mean the same thing at every point in the swing. The KR-61's blade is
**0.19 × 0.53 × 1.94 studs**, a sliver against a 5-stud character, so padding is not a
fudge factor here; it is most of the hitbox. Reach comes out around **5.1 studs**, just
past the tip.

---

## When a swing does not land

Set `Config.Debug = true` and swing. Every swing prints one line naming the cause.

| Line | What happened | Fix |
|---|---|---|
| **no gun in the place responds at all** | a weapon mode has a `BulletType` the handler cannot resolve, so it `return`ed before connecting the mouse | check every config for a numeric `BulletType`, and that `Bayonet` sits beside `Hitscan` |
| *(nothing at all on a swing)* | the bullet type never ran | is `BulletType = 'Bayonet'` on the `[2]` block? |
| `BayonetStab remote not found` | the ServerScriptService half is missing, or the service errored first | check for the `service ready` line |
| `REFUSED -- nothing named "Bayonet" anywhere inside X` | that weapon has no blade | step 4 |
| `REFUSED -- X has no [2] block` | the snippet was not pasted, or the playtest was not restarted | steps 3 and 5 |
| `REFUSED -- X [2] has no usable RoundsPerMinute` | the mode has no cadence, so the server has no interval to enforce | add `RoundsPerMinute` |
| `REFUSED -- TREK returnTool gave no equipped tool` | TREK does not think you are holding anything | usually TREK's own respawn setup failing; re-equip or respawn |
| `ABORTED -- X (a Motor6D) contains no BasePart` | the thing named `Bayonet` is not geometry | rename it, or name the actual Part/Model `Bayonet` |
| `MISS ... Nearest was Y, 0.8 studs outside the box` | genuinely short | add that number to the padding it was short on |
| `MISS ... belongs to no Humanoid` | the target is a prop, not a character | only models with a Humanoid can be stabbed |
| `MISS ... IS in the box but was filtered out` | the target sits in `workspace.IgnoreList` | move it out |
| `hit Y in the Torso on sample 3` | it landed | if no damage followed, check `Damage` in the `[2]` block |

A miss also reports **how far the blade travelled** during the sweep. A stud or more means
the server watched a real thrust and the box was short. Near zero means the server never
saw the animation, and no amount of padding fixes that.

---

## How it works

### Why the index is 2, having been 9

`switchModes` walks fire modes by **increment**:

```lua
if (currentMode == 1 and not config[currentMode + 1]) then return end
```

The G-key version put the bayonet at `[9]` **so that walk would stop dead** — it was
triggered by its own key and only borrowed the block for its numbers. Now the bayonet is a
fire mode, so it has to sit exactly where V lands. If you already use `[2]` for a real fire
mode, move the bayonet to the first free index after your last one and set
`Config.ConfigIndex` to match; it only has to be reachable by incrementing.

### Why it works at 0 ammo, and why that flipped too

The old build omitted `MagCapacity`, which kept the bayonet out of the ammo system
entirely — both ammo-store builders skip a block without one.

**That no longer works.** A fire mode goes through `shoot()`, which does:

```lua
tool.LocalTAmmo[mode].Ammo.Value -= 1
```

unconditionally. With no `MagCapacity` there is no `LocalTAmmo` entry and every swing
errors. So the mode now has `MagCapacity = math.huge`: `inf - 1` is still `inf`, the
magazine never empties, `mousePress` never diverts you into a reload, and the bayonet
swings at 0 rifle ammo — not by being outside the ammo system, but by having a magazine
that cannot be emptied. `useSharedClip = false` keeps it off the rifle's clip.

> **It must be the number `math.huge`, not the string `'INF'`.** TREK's own infinite
> sentinel is the string, but the client's ammo store assigns `ReservedAmmo` straight onto
> a `DoubleConstrainedValue`, which rejects it.
>
> The consequence is `CanReload = false`. Because `ReservedAmmo` is `math.huge` rather
> than `'INF'`, TREK's reload handler misses its early return and computes
> `inf - inf = NaN`, writing that into your ammo values. `reloadSecurityChecks` honours
> `CanReload` before any of that can be reached.

### The hitbox is the blade, and the server owns it

Custom Bullets ships a `Melee` bullet type built on ShapecastHitbox. This package does not
use it. That one runs on the client and reports hits through `TREK_Remotes.Damage`, which
takes its origin **from the client** and does not check it, because `ServerRays` is false
in GlobalConfigs. Fine for a rifle you can see down the sights of; for a melee attack whose
entire balance is its reach, it means the reach is enforced on the attacker's machine.

Instead our bullet type sends **one empty message**. The server sweeps the real bayonet
part, which is welded to the character and therefore already somewhere the server owns.
There is no claimed position, so there is nothing to validate and nothing to spoof.

The blade is sampled repeatedly across `HitWindow` rather than tested once, for two
reasons: the animation needs time to extend it, so a single test at click would check a
bayonet that has not moved; and a single test can be stepped over, since a blade at speed
passes through a torso between physics frames. That tunnelling is why this does not use
`Touched`.

Discovery and decision are separate. `GetPartBoundsInBox` finds candidate parts and the
code walks **up** to the owning character; the hit itself is an explicit box test on that
character's parts. A crowded query can cost discovery but never accuracy. How deeply a rig
nests — in a Folder, inside a Model grouping a squad — never decides whether it can be
stabbed, and nor does how it nests its own limbs.

**NPCs are targets**, deliberately. Resolution does not use
`shared.S.trekFuncs.findPlrAndChar`, which bails the moment the owning model has no
`Player` — that would make the bayonet useless against dummies and clones.

### Sprinting through the swing

`shoot()` cancels sprint before it reaches any bullet type:

```lua
if controls.sprinting.Value then plrconfig.SprintEnabled.Value = false end
```

Right for a rifle, wrong for a bayonet charge. Our `fire()` runs *after* that line, so it
sets the flag back — only while you are genuinely still sprinting, so releasing the key
still stops you. No edit to the handler. Set `Config.RestoreSprint = false` to behave like
every other fire mode.

### What reaches TREK

| Piece | Where it lives | How it reaches TREK |
|---|---|---|
| Bayonet stats | `[2]` block in the weapon config | read by index |
| Swing trigger | `BulletTypes.Bayonet` | Custom Bullets' extension point |
| Hit detection | `BayonetService` | its own box test, around the bayonet part |
| Damage | `BayonetService` | `ServerStorage.TREKDamageModule.setDamage` / `.DamagePlayer` |
| Gore | `BayonetService` | `shared.S.trekGibs.handleGibs` |
| Hitmarker | `BayonetService` | `EffectsModule.Hitmark.DrawEffect` |
| Kill credit | `TREKDamageModule` | `lbmodule.tagPlr` |
| Animations | weapon module | `2Recoil` / `2Idle` / `2SprintHold`, by mode prefix |
| Pose layering | `WeaponPosePriority` | raises weapon poses above the global `Run` |

---

## Why sprinting needs `WeaponPosePriority`

Sprinting layers two animations: TREK’s global body/legs `Run`, and the weapon’s own
upper-body `SprintHold`. Measured on a live character:

```
WalkAnim    Core       1.00
SprintHold  Movement   1.00
Run         Movement   1.00
```

Same priority, same weight. Roblox blends equal-priority tracks by weight, so the arms
and torso average halfway between the two poses and the weapon reads as dropped, or as
having no animation at all. `Idle` is authored at `Action`, which is why standing still
never showed it and only sprinting did.

The two fire modes behaved differently for an accidental reason: `2SprintHold` points at
the same asset as `2Idle`, so it inherited `Action` and won, while `SprintHold` points at
the Patrol asset, authored at `Movement`, and tied. Bayonet mode was never correct by
design — it was correct by luck.

`AnimationTrack.Priority` is writable at runtime, so `WeaponPosePriority` raises any
weapon pose below `Action` up to `Action` as it starts. No republished asset, no TREK
edit. `Run` keeps the legs, because `SprintHold` does not keyframe them.

The symptom to recognise: **the pose is correct if you equip while already sprinting, or
if you press V mid-sprint, but not if you start sprinting while equipped.** Those two
paths play the weapon pose *after* `Run`, and for equal priorities the most recent track
wins. Re-playing the track would also “fix” it, but only until something plays `Run`
again — which is why the priority is raised instead.

---

## Not plug-and-play yet

Three things are specific to the place this was built in, and a fresh install has to
adjust them:

| | |
|---|---|
| **The installer's name** | `default.project.json` maps into `Workspace["Installer "]` — with a **trailing space**, because that is this place's instance name. Invisible in the Explorer, and wrong for most installs. `CheckInstall` prints the real name. |
| **The weapon name** | `tools/WeaponAnimations.luau` and `tools/CheckInstall.luau` hold `KR-61 "Bonecrusher"`. One constant at the top of each. |
| **The animation ids** | `2Recoil` and `2Idle` are ids published from this place's account. Yours will differ, and animations cannot be shared by id across owners. |

Beyond that, `2Barrel`, `2Fire` and the animations are Studio-side work no script can do
for you end to end — `CheckInstall` with `FIX = true` creates the first two, but the
animations have to be authored and published by hand, against a rig with the gun attached.

## Limits

`THealth` props and `TVehicle` are not valid targets — stabbing a tank does nothing. There
is no bayonet-specific voice bark, though a bayonet kill fires the existing `Kill` bark
from TREK Voicelines, because kill credit goes through `tagPlr` like any other.

**The server cannot verify which fire mode you are in.** TREK exposes no server-side mode
state, and anything the client says about its own mode is unverifiable. A modified client
could therefore swing without switching to mode 2. The server still enforces the rate
limit, the team checks, the blade's existence and the geometry, so the worst case is a
melee attack available one keypress sooner than intended — the same property the G-key
version had.

---

## Development

```bash
lune run tools/geometrytest.luau   # 24 tests on the hit maths
lune run tools/configtest.luau     # the [2] block has every field TREK dereferences
lune run tools/geometrybench.luau  # guards against a performance regression
```

`configtest` is worth running after any config edit. Every assertion in it maps to a line
in TREK or Custom Bullets that reads a field without a nil check and throws, or writes
something worse — a numeric `BulletType`, a missing `limbRemovalChance`, `CanReload` left
true. None of those degrade gracefully.

`geometrytest` includes a test asserting that `local c, d = x and f()` truncates to one
value, because that exact mistake once made every swing silently miss while looking like a
tuning problem.

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o TREKBayonet.rbxm
```

### Working with Rojo without breaking the place

**Rojo deletes what it manages when the source goes away.** Move or rename a file that
the project maps while a session is connected, and the instance disappears from the place
— which is how `BayonetService` and the bullet type went missing after a tidy-up, taking
the fire mode with them.

The order that avoids it:

1. **Disconnect** the Rojo plugin in Studio
2. move or rename the files
3. update `default.project.json`
4. restart `rojo serve` — it reads the project once, at startup
5. **Connect** again

A server left running from before a project edit still holds the old mappings, so a
reconnect alone is not enough.

Shared parents — `ServerStorage`, `ServerStorage.TREKToolHandlers`, `Workspace`, the
installer and its `Plugins` folder — carry `$ignoreUnknownInstances: true`, so Rojo leaves
TREK's own content there alone instead of treating it as drift. The folders that are
entirely ours are strict, so a rename really does clean up after itself.

### What Rojo does NOT place

These live in the place and no sync will restore them. `tools/CheckInstall.luau` verifies
all of them:

| | |
|---|---|
| the weapon's `[2]` block | pasted into the config module in `Installer > GunConfigs` |
| `2Recoil` / `2Idle` / `2SprintHold` | Animation instances in that module's `Animations` folder — `tools/WeaponAnimations.luau` writes them |
| `2Barrel` | a part in the Tool, no ParticleEmitters — `CheckInstall` with `FIX = true` creates it |
| `WeaponPosePriority` | Rojo places it, but a hand install needs it in `StarterPlayerScripts` — without it every weapon looks dropped while sprinting |
| `2Fire` | optional sound in the config module, silences the gunshot on a swing |

### Keeping a tool off the back

`HolsterService` decides what to sling by looking for an `AnimPart`, because
until recently that only ever meant "TREK weapon". It is also how TREK joins
*any* tool to the hand, so a non-weapon tool — a throwable, a carried object —
looks exactly like a rifle from here.

A tool opts out by declaring it:

```lua
tool:SetAttribute("NoHolster", true)
```

Worth doing for anything that isn't a weapon, and it buys more than just staying
off your back. The attribute is what separates "a tool was equipped" from "the
slung weapon was equipped", which are the same event right up until a place has
a tool that isn't a weapon. Tools that declare it:

- are never slung themselves
- **don't clear the holster when drawn**, so your rifle stays visibly on your
  back while you're holding a grenade — you didn't put it away, you just stopped
  holding it
- don't block the spawn scan, so spawning with one in hand still slings your
  rifle
- don't consume the spawn scan's single slot, which stops at the first
  holsterable tool it finds — one that counted would take the rifle's place and
  the rifle would never appear at all

[TREK Gas Grenade](../TREK%20Gas%20Grenade) sets this on itself.

### Repo layout

| | |
|---|---|
| `src/shared/` | `BayonetConfig`, `BayonetGeometry` → `ReplicatedStorage.TREKBayonet` |
| `src/BayonetService.server.luau` | the server half → `ServerScriptService.TREKBayonet` |
| `src/Bayonet.luau` | the bullet type → the `BulletTypes` folder |
| `src/HolsterService.server.luau` | slung weapons, unrelated to the bayonet → `ServerScriptService.TREKHolster` |
| `src/WeaponPosePriority.client.luau` | raises weapon poses above TREK’s `Run` → `StarterPlayerScripts.TREKBayonet` |
| `src/package/` | read-me and paste-in snippet, staging only |
| `vendor/` | TREK Custom Bullets, verbatim, so Rojo can place it |
| `weapon/` | working copies of merged weapon modules (gitignored) |
| `tools/` | everything below |

### tools/

Run with `lune run tools/<name>.luau`:

| | |
|---|---|
| `geometrytest` | 24 tests on the hit maths |
| `configtest` | the `[2]` block has every field TREK dereferences, and every `Config.X` the code reads exists |
| `geometrybench` | guards against a performance regression |

Paste into the Studio **command bar**:

| | |
|---|---|
| `CheckInstall` | verifies the whole install and says what is missing; `FIX = true` creates `2Barrel` and `2Fire` |
| `WeaponAnimations` | writes `2Recoil` / `2Idle` / `2SprintHold` onto the weapon, by path |
| `StripLegTracks` | removes leg poses so the legs keep running under an upper-body animation |
| `AngleWeaponPose` | pitches the weapon in a pose, for making a sprint variant of an idle |
| `HolsterTuner` | measures the holster and moves it live |

Drop into the place as their own Scripts — standalone TREK fixes, nothing to do with the bayonet:

| | |
|---|---|
| `TREKSpawnFix` / `SpawnDiagnostic` | the gun sometimes not setting up after respawn |
| `TREKDuplicateHandlerFix` / `SprintDiagnostic` | duplicate handlers cancelling sprint |

---

## Credit

Made by PlagueByte (pb6008 on Discord). TREK and TREK Custom Bullets are not mine and are
not included here — this hooks into whatever install you already have.

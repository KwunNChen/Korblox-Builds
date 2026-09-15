# TREK Bayonet

A melee thrust for TREK rifles. Press **G** with a bayonet-equipped weapon and
you stab whatever is in front of you — **at any ammo count, in any fire mode,
mid-reload**. While sprinting, the character holds the rifle in a charge pose.

TREK ships no melee of any kind, so all of this is new. **None of it edits TREK.**
Delete the folder and your install is byte-for-byte what it was.

| | |
|---|---|
| **Needs** | an existing TREK 4 install, and Rojo only if you want to build from source |
| **Adds** | one folder in each of ReplicatedStorage, ServerScriptService, StarterPlayerScripts |
| **Touches** | nothing in TREK — it calls TREK's modules from outside |
| **Works at** | 0 ammo, mid-reload, any fire mode, while sprinting |

---

## Install

**1. Drag `TREKBayonet.rbxm` into Studio.** What you get is a *staging* folder,
not the installed shape. Nothing runs until four folders are moved out of it:

```
TREKBayonet                   <- staging folder, delete when done
|-- README                       read-me, not installed
|-- BayonetWeaponMode            paste-in snippet, not installed
|-- ReplicatedStorage
|   `-- TREKBayonet           <- move THIS into game.ReplicatedStorage
|-- ServerScriptService
|   `-- TREKBayonet           <- move THIS into game.ServerScriptService
|-- StarterPlayerScripts
|   `-- TREKBayonet           <- move THIS into game.StarterPlayer.StarterPlayerScripts
`-- ServerStorage
    `-- TREKBayonetPoses      <- move THIS into game.ServerStorage
```

The four service-named folders are **signposts**, not things to move. You move
the **inner** folder out of each one, then delete the staging folder.

`TREKBayonetPoses` is the only optional one — it holds the two R6 animation
sequences and is needed only if you want to edit and publish them. Nothing
breaks without it, but **do not just delete the staging folder and leave it
behind**; you cannot get the poses back without re-importing the model.

Or select the staging folder and run this in the **command bar**, which does the
same thing and replaces any previous install:

```lua
local staging = game:GetService("Selection"):Get()[1]
assert(staging and staging.Name == "TREKBayonet", "Select the TREKBayonet staging folder first")
for _, move in ipairs({
    { "ReplicatedStorage",    "TREKBayonet",      game:GetService("ReplicatedStorage") },
    { "ServerScriptService",  "TREKBayonet",      game:GetService("ServerScriptService") },
    { "StarterPlayerScripts", "TREKBayonet",      game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts") },
    { "ServerStorage",        "TREKBayonetPoses", game:GetService("ServerStorage") },
}) do
    local signpost, innerName, dest = staging:FindFirstChild(move[1]), move[2], move[3]
    local inner = signpost and signpost:FindFirstChild(innerName)
    assert(inner, "staging folder has no " .. move[1] .. "/" .. innerName)
    local old = dest:FindFirstChild(innerName)
    if old then old:Destroy() end
    inner.Parent = dest
end
staging:Destroy()
print("TREKBayonet installed")
```

> Leaving the package in ServerStorage installs nothing **and logs nothing** —
> Scripts do not run there, so there is no error to go looking for.

**2. Put something named `Bayonet` inside the weapon's Tool.**

A weapon without one cannot stab. That instance *is* how the system knows which
rifles have a bayonet, so fitting one to another rifle later is a modelling job,
not a config edit.

Only the **name** is checked, and the search is recursive — a loose Part, or a
Model of several parts, nested or not, all work. Its position and size **are**
the hitbox.

On the stock KR-61 this is already done: `Tool > Weapon > Bayonet` is a Model
whose `BayonetPrimary` is Motor6D'd to `AnimPart`, with the rest welded to it.
Nothing to change.

If you build a **new** one as a loose Part, give it the three properties that
model was carrying for you, or it will misbehave visibly:

| | |
|---|---|
| **Weld it** | TREK only Motor6Ds `AnimPart`; it does not weld the rest of a weapon. An unwelded part drops to the floor on equip. A `WeldConstraint` to the gun's main part is enough. |
| `CanCollide = false` | otherwise the blade snags on walls and shoves you around |
| `Massless = true` | otherwise it drags on the character's physics |

**3. Paste the `BayonetWeaponMode` block into that weapon's config module,**
inside the same `local configs = { ... }` table that already holds `[1]`.

That block holds the damage numbers. Two things in it are load-bearing and
commented as such: the index is **9**, and there is **no `MagCapacity`**.

**4. Restart the playtest.** `SetUpGuns` caches every weapon module at server
start, so config edits need a fresh run.

### Check it worked

Two lines on a playtest:

```
[TREKBayonet] service ready -- blade hitbox padded 1.25 side / 2.50 up / 1.50 forward, swept over 0.35s, 1.2s cooldown, weapon config [9]
[TREKBayonet] controller ready -- press G to stab
```

Only the first means the StarterPlayerScripts half is missing. Neither means
nothing was installed. Load order does not matter — it waits on `TREK_INSTALLED`
itself.

---

## Tuning

Everything here is in `ReplicatedStorage > TREKBayonet > BayonetConfig`.
**Damage is not** — that lives in the `[9]` block of the weapon module.

```lua
Config.Key               = "G"    -- F is NOT free: TREK binds it to sprint
Config.HitPadSide        = 1.25   -- how far off-centre your aim can be
Config.HitPadVertical    = 2.5    -- how much height difference is forgiven
Config.HitPadForward     = 1.5    -- reach past the tip
Config.HitWindow         = 0.35   -- how long the blade keeps being tested
Config.HitSampleInterval = 0.03   -- gap between tests inside that window
Config.Cooldown          = 1.2    -- seconds between thrusts
Config.RequireSprint     = false  -- true = only stab while sprinting
Config.Debug             = false  -- true = every stab reports itself
```

**Keys taken by TREK** in GlobalConfigs: `F` (sprint), `C`, `R`, `Q`, `T`, `N`,
`V`, `LeftShift`, `LeftControl`. `G`, `X` and `B` are free.

**The padding is measured in your frame** — level, facing where you face — so the
three numbers mean the same thing at every point in the swing. The KR-61's blade
is **0.19 × 0.53 × 1.94 studs**, a sliver against a 5-stud character, so padding
is not a fudge factor here; it is most of the hitbox. With the values above the
box reaches about **5.1 studs** ahead of you, just past the tip.

**`HitWindow`** should comfortably cover the extend portion of your thrust
animation. Too short and the hit is tested before the blade arrives.

---

## When a stab does not land

Set `Config.Debug = true` and press G. Every stab then prints one line, and the
line names the cause.

| Line | What happened | Fix |
|---|---|---|
| *(nothing at all)* | the key never reached the controller | check the StarterPlayerScripts half installed; check nothing else binds `G` |
| `sent a stab` on the client, no server line | the remote did not arrive | the ServerScriptService half is missing |
| `REFUSED -- nothing named "Bayonet" anywhere inside X` | that weapon has no blade | step 2 above |
| `REFUSED -- X has no [9] block` | the snippet was not pasted, or the playtest was not restarted | steps 3 and 4 |
| `REFUSED -- TREK returnTool gave no equipped tool` | TREK does not think you are holding anything | usually TREK's own respawn setup failing; re-equip or respawn |
| `REFUSED -- 0.42s since the last thrust` | cooldown | expected; lower `Config.Cooldown` if you want |
| `ABORTED -- X (a Motor6D) contains no BasePart` | the thing named `Bayonet` is not geometry | rename it, or name the actual Part/Model `Bayonet` |
| `MISS ... Nearest was Y, 0.8 studs outside the box` | genuinely short | add that number to the padding it was short on |
| `MISS ... belongs to no Humanoid` | the target is a prop, not a character | only models with a Humanoid can be stabbed |
| `MISS ... IS in the box but was filtered out` | the target sits in `workspace.IgnoreList` | move it out — that folder is where TREK parks bullets and gibs |
| `MISS ... the box was empty` | the server has the target elsewhere | check the target actually exists server-side |
| `hit Y in the Torso on sample 3` | it landed | if no damage followed, check `Damage` in the `[9]` block |

A miss also reports **how far the blade travelled** during the sweep. A stud or
more means the server watched a real thrust and the box was short. Near zero
means the server never saw the animation play, and no amount of padding fixes
that.

---

## Animations

Both ids ship as `"PLACEHOLDER"`, and that is a working state — the bayonet still
does damage, it just does it without a pose. A missing animation must never stop
the weapon working.

- **`Config.ChargeAnimation`** — held while sprinting with a bayonet fitted
- **`Config.ThrustAnimation`** — the stab itself

They play at `Enum.AnimationPriority.Action`, which outranks the gun's own `Idle`
and `SprintHold`, so TREK keeps animating underneath and ours wins while it runs.
Nothing goes near `determineAnim`.

**Two R6 poses ship with the package**, synced to `ServerStorage >
TREKBayonetPoses`:

| | |
|---|---|
| `BayonetCharge` | guard pose, looped, 2.2s |
| `BayonetThrust` | the lunge, 0.62s — guard, coil, drive, hold, recover |

**Rojo cannot upload them.** `Animator:LoadAnimation` needs a real
`rbxassetid://` and only publishing produces one. Select an R6 rig, open the Clip
Editor (Avatar tab), import the sequence from ServerStorage, **Publish to
Roblox**, then paste the id into the config.

The poses are generated, not hand-dragged — `tools/makeposes.luau` holds every
angle as a named constant (`GUARD`, `WINDUP`, `THRUST`, `RECOVER`). Change a
number, `lune run tools/makeposes.luau`, and Rojo pushes the new sequence live.

They pose the **arms and torso only**. The legs and head are deliberately absent,
so TREK's own walk and run keep playing underneath — a pose that keyframed them
would freeze your feet mid-stride at `Action` priority.

The thrust is driven from the **torso**, which is not an aesthetic choice: TREK
Motor6Ds the rifle to the torso (`chr.Torso.toolAnim.Part1 = tool.AnimPart`), so
posing the arms alone leaves the rifle hanging while the hands wave around it.

---

## How it works

### Why it works at 0 ammo

Not because the magazine is enormous. **Because there is no magazine.**

Both of TREK's ammo-store builders — client `Gun.client.luau:282`, server
`TREKServerGeneral.server.luau:69` — skip any mode block that has no
`MagCapacity`:

```lua
if not config['MagCapacity'] then continue end
```

The `[9]` block omits it, so no `LocalTAmmo["9"]` and no `TAmmo["9"]` are ever
created. There is no counter to deplete and no ammo check to fail — the bayonet
is *outside* the ammo system rather than having a lot of ammo in it.

The stab also never enters the gun handler's `shoot()`, which is what gates on
ammo — and, usefully, is also the line that cancels your sprint when you attack:

```lua
if controls.sprinting.Value then plrconfig.SprintEnabled.Value = false end
```

So the charge survives the thrust with no workaround and nothing patched.

> **Do not "fix" the missing `MagCapacity` with `math.huge`.** The HUD does
> `string.format("%03d", Ammo.Value)` and `Ammo.Value / maxAmmo`. Tested: those
> render infinity as `-9223372036854775808` and `NaN`.

### Why the index is 9

`switchModes` walks fire modes by **increment**:

```lua
if (currentMode == 1 and not config[currentMode + 1]) then return end
```

A block at `[2]` would put the bayonet straight into the **V** cycle, letting the
player switch into a "fire mode" that cannot shoot. With nothing at `[2]` that
walk stops dead, while the service still looks the block up directly by index.
Verified by replaying `switchModes` against the real merged config: twenty
presses, never leaves mode 1.

Already using `[2]` and `[3]`? Keep the bayonet at 9 and leave the gap.

Everything else in that block is inert for a melee attack but has to **exist**:
the gun handler builds a `modeStuff` entry for every table in the config at load
and dereferences `ProjectileTypes[tabl.ProjectileName]`, which throws on `nil`
and would break the entire weapon.

### The hitbox is the blade

Not a box projected from your character — **the bayonet part itself**. It is
welded to you, so the server already knows where it is; it sweeps the real blade
as the thrust drives it forward and asks what it overlapped. A longer blade
genuinely reaches further, with nothing to reconfigure.

It is sampled repeatedly across `HitWindow` rather than tested once, for two
reasons: the animation needs time to extend the blade, so a single test at
keypress would check a bayonet that has not moved yet; and a single test can be
stepped over entirely, since a blade at speed passes through a torso between
physics frames. That tunnelling is why this does not use `Touched`, along with
`Touched` being unreliable for a `CanCollide = false` part.

Reading the blade is also **what removed the need for lag compensation**.
Attacker and target are both read from the server's own view at the same instant,
so their relative geometry is correct regardless of ping.

Discovery and decision are separate: `GetPartBoundsInBox` finds candidate parts
and the code walks **up** to the owning character, then the hit itself is an
explicit box test on that character's parts. A crowded query can cost discovery
but never accuracy. How deeply a rig nests — in a Folder, inside a Model grouping
a squad — never decides whether it can be stabbed, and nor does how it nests its
own limbs.

### Server authority

**The client sends nothing.** There is no claimed position, so there is nothing
to validate and nothing to spoof. The server rate-limits, checks teams, skips
forcefields and corpses, and refuses to stab out of a vehicle seat.

This is why it does not reuse `TREK_Remotes.Damage`: `ServerRays` is false in
GlobalConfigs, so TREK's own distance check never runs and `handleDamage` takes
its origin from the client.

Kill credit still goes through TREK — `DamagePlayer` tags the victim with the
same `WeaponTag` the kill feed reads, so a bayonet kill also fires the `Kill`
bark from TREK Voicelines with no changes there.

**NPCs are targets**, deliberately. Resolution does not use
`shared.S.trekFuncs.findPlrAndChar`, which bails the moment the owning model has
no `Player` — that would make the bayonet useless against dummies and clones,
which is most of what anyone tests against.

### What reaches TREK

| Piece | Where it lives | How it reaches TREK |
|---|---|---|
| Bayonet stats | `[9]` block in your weapon's config module | read by index, never entered as a fire mode |
| Hit detection | `BayonetService` | its own box test, around the bayonet part |
| Damage | `BayonetService` | `ServerStorage.TREKDamageModule.setDamage` / `.DamagePlayer` |
| Gore | `BayonetService` | `shared.S.trekGibs.handleGibs` |
| Hitmarker | `BayonetService` | `EffectsModule.Hitmark.DrawEffect` |
| Kill credit | `TREKDamageModule` | `lbmodule.tagPlr` |
| Charge pose | `BayonetController` | its own `AnimationTrack` at `Action` priority |

---

## Limits

`THealth` props and `TVehicle` are not valid targets — stabbing a tank does
nothing. There is no bayonet-specific voice bark.

---

## Development

```bash
lune run tools/geometrytest.luau
```

Run that after touching `BayonetGeometry`. It builds real Instances in memory and
checks the hit maths headlessly — blade bounds, what should and should not be
reachable, limbs nested deeper than expected, a held Tool never being reported as
the part hit, and that `bladeBox` returns **both** of its values.

That last test earns its place. The bug it guards was
`local centre, half = frame and bladeBox(...)`, where `x and f()` yields exactly
one value — so the box had no size, nothing was ever hit, and the failure looked
like a tuning problem for three rounds of playtesting.

```bash
lune run tools/geometrybench.luau
```

Times one stab's geometry against a transcription of the previous
implementation. Be careful reading it: lune reaches instance properties through
a reflection layer far slower than the engine's, so it inflates per-part work and
hides the cost of what was removed. It is a ratio between two implementations on
identical work, not a per-stab cost.

**What a sweep costs now**, per stab, against what it used to:

| | before | after |
|---|---|---|
| blade measured | 22 | 11 |
| blade descendants walked | 22 | 1 |
| limb descendants walked (6 targets) | 66 | 6 |
| `Size.Magnitude` square roots | 924 | 84 |
| tables allocated | ~130 | ~11 |
| **query volume searched** | 16.5 × 17.5 × 17.6 | 4.5 × 5.5 × 5.6 |

That last row is the one that matters most and the one the benchmark cannot see.
The six-stud margin exists only so a **miss** can report who was nearby and how
far outside they were — about thirty-six times the volume for the engine to
search, eleven times per stab. With `Config.Debug` off nobody reads that report,
so the query is now the hitbox itself and not a stud more.

Measured Luau-side, the rest comes to **1.2× in a crowd and about 1.0× for a
normal stab** — the descendant walks and allocations were never the bottleneck in
this harness, and in the engine they are cheaper still. The honest summary is
that the sweep was not slow; it was doing a lot of redundant work that now
doesn't happen, and the query was far larger than it needed to be.

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o TREKBayonet.rbxm
```

| | |
|---|---|
| `src/shared/` | `BayonetConfig`, `BayonetGeometry` → `ReplicatedStorage.TREKBayonet` |
| `src/server/` | `BayonetService` → `ServerScriptService.TREKBayonet` |
| `src/client/` | `BayonetController` → `StarterPlayerScripts.TREKBayonet` |
| `src/package/` | the read-me and paste-in snippet, staging only |
| `assets/` | the two R6 poses → `ServerStorage.TREKBayonetPoses` |
| `tools/` | pose generator, geometry tests, standalone TREK diagnostics |
| `weapon/` | working copies of merged weapon modules (gitignored) |

---

## Credit

Made by PlagueByte (pb6008 on Discord). TREK itself is not mine and is not
included here — this hooks into whatever TREK install you already have.

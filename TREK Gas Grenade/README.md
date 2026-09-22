# TREK Gas Grenade

A throwable for TREK 4. Hold to cook, release to throw. It bounces to a stop and
vents a cloud of nerve agent — thin white smoke that kills anyone who breathes
it, whether or not they get out.

**Requires TREK 4.** Damage goes through `ServerStorage.TREKDamageModule`, part of
the core install. Nothing in `trek-core` is modified — TREK dispatches tool
behaviour on a `ToolType` string, so this registers a new handler and leaves your
install byte-for-byte as it was.

**The first TREK tool that is not a gun.** Vanilla TREK ships exactly one tool
handler, `Gun`. This adds `Throwable`.

## Install

Drag `TREKGasGrenade.rbxm` into ServerStorage, then paste
[tools/Install.luau](tools/Install.luau) into the Studio command bar in **edit
mode**. It moves everything and deletes the staging folder.

**Use it rather than installing by hand.** The package lands in five places and
has gained a destination in most builds. Moving new folders in alongside old ones
leaves two with the same name, Roblox runs both, and the stale copy fails on a
module it has never heard of — which reads as a broken package rather than a
half-finished install. The installer replaces wholesale instead of merging.

If you'd rather do it by hand anyway:

| From | Move | Into |
|---|---|---|
| `ReplicatedStorage/` | `TREKGasGrenade` | ReplicatedStorage |
| `ServerScriptService/` | `TREKGasGrenade` | ServerScriptService |
| `ServerStorage/TREKToolHandlers/` | `Throwable` | your existing `ServerStorage.TREKToolHandlers` |
| `GunConfigs/` | `Gas Grenade` | your existing `GunConfigs` |
| `StarterPlayerScripts/` | `TREKGasGrenade` | `StarterPlayer.StarterPlayerScripts` |

**Delete the old folder at each destination first — don't merge into it.** Then
delete the empty wrapper.

With rojo, skip all of it: `rojo serve` from this folder puts everything at the
right paths itself.

**The config module's name must match the Tool's name exactly.** Several TREK
paths resolve a tool's config by `tool.Name` and ignore the `TConfigToUse`
attribute — naming them identically is the only arrangement every lookup agrees
on. Do not set `TConfigToUse` on this tool.

## The art

The meshes ship separately in `GasGrenades.rbxm` — two models, `ActiveGasGrenade`
and `InactiveGasGrenade`. Drop both into `ServerStorage.TREKGasGrenade`, then:

```bash
# paste tools/PrepareGrenadeRig.luau into the Studio command bar
```

That rigs both models and leaves a finished `Gas Grenade` tool in StarterPack.

Doing it by hand instead: make a Tool named `Gas Grenade`, set `RequiresHandle`
to false, and put a copy of `InactiveGasGrenade` inside it.

You do **not** need to weld, unanchor, or set a `PrimaryPart`. The export arrives
as four loose anchored MeshParts with no welds and no `PrimaryPart` every single
time, so the rig is rebuilt at runtime from whatever the model contains. Re-export
the art with different part names and it still works.

## How it plays

**One grenade, and it does not come back.** `MagCapacity = 1`, `ReservedAmmo = 0`,
and `DestroyWhenEmpty` removes the tool from your hotbar once it is spent — so
throwing it leaves you with an empty hand and one fewer slot, not a grenade that
silently refuses to throw.

Raise `ReservedAmmo` if you want a resupply; the reload path is wired and works,
it just has nothing to draw from at zero.

Hold left mouse to cook. An arc shows where it lands and reddens as the fuse
burns. Release to throw.

The fuse starts on **press**, not release. That is what cooking is: you spend
fuse time to deny the enemy the time to walk out of where it lands. Hold too long
and it goes off in your hand — `CookKillsYou`, on by default.

Putting the grenade away does not stop the fuse. If it did, cooking would be free.

Where it detonates is where it stopped rolling. Bounce is deliberately dead; a
gas grenade that pinballs back to your feet is funny exactly once.

## The cloud

Gas builds over `BuildUpTime` instead of appearing at full strength, and the
visual density, the hiss and the disorientation all ride the same curve — a cloud
that looks thin is thin.

| Behaviour | Why |
|---|---|
| Walls block it | Gas that seeps round corners meant players dying behind cover with no idea why |
| Bodies do not block it | A raycast that hits a character is re-fired past them |
| Affects everyone, thrower included | Otherwise there is no decision about where to put it |
| A `VehicleSeat` protects you | Matches what TREK's own explosions already do |
| You cannot run through it | Contact is tested against the path you travelled, not where you stood on a tick |

Contact is a **swept** test. Sampling where someone stands at each tick is how a
sprinter crosses a cloud untouched — at 18 studs of radius and a 0.4s tick a
sprint covers 11 studs between samples, so a path clipping the edge can begin and
end outside the sphere having gone straight through it. The check is against the
segment travelled instead, and the overlap query reaches `SweepMargin` studs past
the edge so fast movers are handed to it at all. Raise that margin if people
start driving through clouds.

Who it reaches is one rule; **what it does to them** is the nerve agent below.
`FullDamageRadius` and `DamagePerTick` shape the fallback irritant only — with
`Nerve.Enabled` they do nothing, because the whole radius doses equally.

While a character is in gas its Humanoid carries a `TGasCondition` BoolValue,
following TREK's own `TBleedCondition` / `TParalCondition` convention. Read it for
a coughing animation, a screen effect, or a mask mechanic. It is ref-counted, so
overlapping clouds do not clear each other's condition.

## The nerve agent

**One lungful is fatal.** The cloud does not damage you — it reports that you
breathed it, and everything after that is already decided. Leaving the cloud does
not help. Neither does the cloud expiring.

```
dose    one tick inside the radius. Irreversible from here.
seize   0.35s later the body goes limp and starts convulsing
bleed   1.2s after that, blood from the mouth
death   health drains to zero across 12 seconds
```

| | |
|---|---|
| Lethal zone | The whole radius. No falloff — either you're breathing it or you aren't |
| Thrower | Gets **1.4s of grace**, and only the thrower. A bad bounce is survivable if you run immediately |
| Your team | No grace at all. It kills them exactly as fast as it kills the enemy |
| Recovery | None. `TNerveCondition` on the Humanoid is the hook a gas mask would read later |

Health is *drained*, not set — a player watching their own bar sees it fall. A
kill that set Health to 0 outright reads as a disconnect. The drain is a fraction
of **max** health per tick, so a wounded player and a healthy one die on the same
schedule; that's what "the dose is lethal" means.

From the moment of the dose the victim loops `Nerve.Sound.Id` from their Head —
positional, so it travels with the body through the collapse and outlives the
cloud, which expires long before a slow death does. It fades over `FadeOut` when
they stop, because a loop cut dead on the last frame sounds like a bug rather
than a body going quiet.

Their ordinary pain noises are suppressed for the duration. The drain takes
health every `TickInterval` for twelve seconds, and every one of those steps is a
health change big enough to trigger a hurt bark — roughly **48 of them per
death**, over the top of the sound above. `GasNerve` sets `SuppressHurtVoice` on
the character before the first tick lands; TREK Voicelines reads it and skips
`Hurt` only. Death lines still play: they do die, and that lands once at the end.

> `SuppressHurtVoice` lives in **TREK Voicelines**, a separate package. Syncing
> this one does not carry it.

Going limp takes the body off the player entirely, which turned out to need more
than limp joints:

| | |
|---|---|
| `Physics` state | `PlatformStand` is a property the state machine walks back out of — jump on the dose frame and the Humanoid stands you up again mid-ragdoll |
| Blocked states | `GettingUp` is the door back to standing; `Jumping` and `Climbing` are how a held key re-enters from the far end |
| Network ownership | All of the above is the server asking politely. For your own character the **client** owns the physics and can overrule it next frame |
| Disarmed | Hands emptied, hotbar stashed out of reach. Unequipping alone just means they press the key again |

Everything taken is recorded first, so `stop()` hands it all back. Nothing calls
`stop()` — there's no recovery from the gas — but `start()` shouldn't be a one-way
trapdoor, and a gas mask would need it.

The ragdoll is **R6 only**. TREK is an R6 framework and the joint names are R6;
on an R15 rig it finds nothing and leaves the character upright, still dying. That
failure is deliberate — better than half-rigging a skeleton it doesn't understand.

`Nerve.Enabled = false` reverts to the old irritant: damage by distance, walking
out saves you. The two are mutually exclusive — with it on, the cloud deals no
damage of its own at all.

## Being gassed

Perceptual only — blur, tint, muffled hearing. Nothing here touches WalkSpeed,
aim or controls.

That is not the same as being able to fight your way out. Contact doses you, and
the seizure follows `SeizeDelay` later; from that point the ragdoll has the body
and your weapons are gone. This section describes the fraction of a second before
that, and what everyone *else* in the cloud sees while they are still standing.

| | |
|---|---|
| Vision | Blur, a wash toward the gas colour, drained saturation, darkened and contrastier |
| Hearing | The world muffled through an equaliser, with a ring fading in over it |
| Build | Reaches full over `BuildTime` in the cloud, clears over `FadeTime` once you're out |
| Who | Everyone in it, thrower included — same rule as the dose |

All of it rides one number: **`GasExposure`**, a 0–1 attribute the server writes
to the victim's Humanoid. The server owns it because the server is the only thing
that knows who's standing in gas, and publishing a value rather than firing effect
remotes means the worst a tampered client can do is blind *itself*.

It's also a plain attribute, so anything else can watch it — a HUD, a medic
system, a spectator overlay, a future gas mask — without this package knowing
they exist.

Muffle needs a `SoundGroup` called `Muffle` in SoundService, which is where
TREK's own concussion effect lives. No group, no muffle; everything else still
works. The ring borrows TREK's staged `Tinnitus` sound so gas and blasts ring
with the same tone.

## The hiss

A looping positional sound on the cloud itself, so you can hear roughly where the
gas is. That matters more than it sounds — gas is the one thing here that hurts
you from outside your field of view, so `RollOffMax` deliberately reaches well
past `CloudRadius`. The warning is for people *near* the cloud, not confirmation
for people already choking in it.

Volume rides the same build-up curve as the particles and the damage, and fades
rather than cutting on expiry: the gas keeps drifting for a few seconds after it
stops hurting, and a hiss stopping dead would call it safe while it still looked
dangerous.

## What it borrows from TREK, and what it doesn't

It is a TREK tool, not a TREK weapon. It goes through the tool pipeline and the
damage module; it does not touch the gun pipeline, because none of the gun
pipeline applies to something you throw.

| Uses | Doesn't use |
|---|---|
| `checkForGun` dispatch — GunConfigs entry + `ToolType` | Any `BulletType` (Hitscan / Projectile / Melee) |
| `createAmmoStore` → a real `TAmmo` store | FastCast, rays, spread, recoil |
| `handleReload` via TREK's own Reload remote | The Explosion remote and `TREKExplosionModule` |
| `TREKDamageModule.DamagePlayer` — kill credit and stats | `updateMotor` / `AnimPart` — see below |
| The `TREK_INSTALLED` gate, `workspace.IgnoreList` | `EffectTypes` / `ImpactTypes` |
| TREK's `T*Condition` BoolValue convention | `MainHud` — no ammo HUD, see below |
| | The GFX remote — no muzzle flash, no reload GFX |
| | Scopes, zoom, fire modes |

**It is joined to the hand, not the torso.** TREK hangs tools off `toolAnim`, a
Motor6D from the *torso* to a part called `AnimPart`, and relies on each weapon's
animations keyframing the `AnimPart` track to carry it into the hands. That works
for a rifle with a full animation set. The grenade has no idle pose, so the same
arrangement parks it at a fixed point beside the chest — attached and moving with
the body, but never following the arm, which reads as hovering in mid air.

So the grenade ships **no `AnimPart` at all**. `checkForGun` then skips
`updateMotor` entirely, and the package joins the grenade to `Right Arm` (R6) or
`RightHand` (R15) with its own `GasGrenadeGrip` Motor6D. It swings with every
walk cycle and gets carried by the throw animation for free. `GasConfig.GripOffset`
is that joint's `C0`.

**It also sets `NoHolster` on itself.** TREK Bayonet's `HolsterService` slings any
Tool carrying an `AnimPart`. This one has none, so it's already excluded — but
the attribute states the intent outright and survives anyone adding an `AnimPart`
later. Harmless without that package; it's just an unread attribute.

**No ammo HUD.** TREK sources a weapon's ammo display from a `MainHud` Frame
parented to the config ModuleScript, which the Gun handler clones into `GunHud`.
The grenade's config has no `MainHud` and the Throwable handler never looks for
one, so nothing appears and nothing errors. The count is live at
`tool.TAmmo["1"].Ammo.Value` if you want to drive a label off it.

## Design notes

**The server owns the fuse clock.** Cook start and throw arrive as two separate
messages and the elapsed time is measured server-side. If the client reported its
own cook time, the cheapest possible cheat would be to claim a full cook on an
instantly-thrown grenade, landing a cloud with no warning at all.

**The cloud snapshots its config at spawn.** It never looks at the thrower's tool
again, because it cannot: TREK resolves a tool's config through `returnTool`,
which is `FindFirstChildOfClass('Tool')` — the *currently equipped* tool. A
grenade's whole life happens after it left the hand.

**Damage does not go through the explosion module.** `handleExplosion` is
one-shot, fires blast VFX to every client on each call, and applies blast falloff
semantics that do not fit a cloud. It also routes through an armour-resist branch
whose `math.clamp` arguments are swapped (value and min), so any part with an
`ArmourDamageResist` takes exactly zero. Falloff is computed locally instead,
which sidesteps that entirely.

**`TREKDamageModule.DamagePlayer` rather than `Humanoid:TakeDamage`.** It also
tags the victim for kill credit and records damage against the thrower's stats. A
raw `TakeDamage` kills people and credits nobody.

**Particles are built in code.** Every vanilla TREK effect clones a pre-authored
`Particle` instance staged inside its module. This does not, so the whole look
answers to `GasConfig.Visual` with no Studio round-trip. It is a deliberate break
from convention and the one place this package does not follow TREK's lead.

## The throw animation

`GasConfig.Animation` holds the id, the priority, and the wind-up timing.

```lua
GasConfig.Animation = {
	Throw = "rbxassetid://98119005875692",
	Priority = Enum.AnimationPriority.Action,
	ReleaseDelay = 0.25,
	FadeTime = 0.1,
}
```

Two things decide whether it looks right:

**Priority must be Action or above.** TREK's global `Run` and `WalkAnim` sit at
`Movement`, and Roblox blends equal-priority tracks by weight — a throw authored
at `Movement` gets averaged halfway into your run cycle and reads as a twitch.
`Action` is what [WeaponPosePriority](../TREK%20Bayonet/src/WeaponPosePriority.client.luau)
raises weapon poses to, so the throw sits level with them rather than fighting.

**`ReleaseDelay` should match the frame your hand opens.** The grenade spawns
that many seconds after the animation starts. At 0 it leaves before the arm has
moved, which reads as it teleporting out of you. It's client-side pacing only —
the fuse has been burning since you pressed, so the delay costs you fuse time
like any other hesitation.

The track is built from the id in code rather than shipped as an `Animation`
instance in an `Animations` folder, which is TREK's convention. Same trade as the
particles: one id in one file, at the cost of `WeaponPosePriority` not seeing it,
so the priority is set explicitly instead.

The animation must be owned by the place owner or its group or it won't load. If
it can't, you get one warning and the grenade still throws — just without the
animation.

## Where it sits in the hand

Don't iterate on this through the config. Paste
[tools/GripTuner.luau](tools/GripTuner.luau) into the Studio command bar during a
playtest with the grenade equipped:

- Run as-is, it **measures** and prints where the grenade currently sits, in the
  same six numbers you'd edit. Nothing moves.
- Set `APPLY = true`, change the numbers, run again — it moves in the live
  playtest, no rebuild, no re-import.
- When it looks right it prints the exact `GasConfig.GripOffset` line to paste.

`YAW` spins the grenade in the palm; `PITCH` and `ROLL` tip it out of the hand.
Re-equipping resets to whatever the config says, so save the line before you stop
the playtest.

## Tuning

Everything is in `ReplicatedStorage.TREKGasGrenade.GasConfig`, documented in place.
The `GunConfigs` module is a thin shim that reads from it — edit `GasConfig`.

```bash
lune run tools/configtest.luau
```

Checks the config for mistakes that stay invisible until someone throws one: a
full-damage radius larger than the cloud, a build-up longer than the duration, a
tick interval of zero, a key deleted while the source still reads it.

## Out of scope

No gas mask or immunity gear — TREK has no damage typing or resistance system at
all, so there is nothing to hook into. `TGasCondition` is the place to build one.

No cook or idle pose — only the throw is animated. The grenade is gripped by the
right hand and otherwise just follows your global movement animations.

No impact detonation. The fuse is a timer, because a grenade that went off on
contact would not be cookable.

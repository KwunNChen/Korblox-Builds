# TREK Voicelines

Voice barks for TREK. A clip plays out of a character's head when they start
reloading, run low, take a hit, get a kill, or die.

Lines are spatial and server-played, so the people around you hear your callouts
— which is the entire reason to have them. TREK's own `LocalSound` remote plays
2D to a single client, so it is deliberately not used.

## It does not modify TREK

No TREK script is edited, patched or replaced. Every event is reached from
outside:

| Event | Hooked from | How |
|---|---|---|
| `Reload` | `TREK_Remotes.GFX` (`'Reload'`) | fired at reload **start**, before the ReloadSpeed wait |
| `ReloadDone` | `TREK_Remotes.Reload` | the end-of-reload signal — "back up" |
| `LowAmmo` | `tool.TAmmo.*.Ammo` | value watcher, fires on the shot that crosses the threshold |
| `OutOfAmmo` | `tool.TAmmo.*.Ammo` | the same watcher, at exactly zero — the dry click |
| `Incoming` | `TREK_Remotes.Explosion` | fires on everyone near the blast, not on whoever fired |
| `Hurt` | `Humanoid.HealthChanged` | plain Roblox, so explosions and vehicles count too |
| `Death` | `Humanoid.Died` | plain Roblox |
| `Kill` | `Humanoid.WeaponTag` | the killer tag TREK writes in `LeaderBoardModule.tagPlr` |
| `PointTaken` | `TObjectiveSystem.Points.*.Owner` | optional; inert in places without the objective system |

Delete the folder and your TREK install is byte-for-byte what it was.

Two of those choices are deliberate and worth keeping:

**Reload hooks `GFX`, not the `Reload` remote.** TREK sends `GFX('Reload')` at
the top of `reloadTypeOne`, before the `ReloadSpeed` wait; it only sends the
`Reload` remote *after* it. On a six-second reload the latter arrives when you
are already loaded, which is the wrong moment for a "reloading" callout. The
`Reload` remote is still used as a fallback for ReloadType 2 recharge weapons,
which never send a start signal.

**Damage comes from `HealthChanged`, not `TREK_Remotes.Damage`.** That remote
fires on the *attacker's* claim, before TREK's team check, ammo check and
anti-HBE have run — listening there barks on damage TREK then rejects.

## Install

Download `TREKVoicelines.rbxm`, drag it into ServerStorage, and move the three
inner folders into the services they are named after:

```
ReplicatedStorage    -> game.ReplicatedStorage
ServerScriptService  -> game.ServerScriptService
StarterPlayerScripts -> game.StarterPlayer.StarterPlayerScripts
```

It waits on `TREK_INSTALLED` itself, so load order does not matter. The
StarterPlayerScripts half is only the preloader — skip it and everything still
works, the first use of each clip is just late or silent.

## Your clips, not these ones

**The ids in `VoicelineConfig` are mine and will not play in your game.** Roblox
audio is private to the place that owns it: an id copied from another experience
plays as silence and reports no error at all. Replace every id with your own
uploads.

Any of these forms work, mixed freely in one list:

```lua
Sounds = {
    3526632933,
    "rbxassetid://3526632933",
    "http://www.roblox.com/asset/?id=3526632933",
}
```

Resolved clip lists are memoised on first use, because they sit on the per-bark
hot path and nothing behind them changes while the server runs. If you edit
`Config.Events` live — from the command bar while tuning — call
`Config.refresh()` afterwards to drop the caches. Editing the file and
restarting needs nothing.

A slot you have not filled yet is written `"PLACEHOLDER"`. Placeholders and
malformed entries are stripped before the picker sees the list, so a half-filled
event never spends a turn on a clip that cannot play, and one holding nothing but
placeholders is simply silent. Anything unusable is named once at startup:

```
[TREKVoicelines] Death sound #5 is not a usable asset: "rbxassetid://" -- it is being skipped
[TREKVoicelines] no clips yet, so these stay silent: LowAmmo, Reload
```

## The events

| | Priority | Cooldown | Chance | Notes |
|---|---|---|---|---|
| `Death` | 10 | 0s | 1.0 | always lands; **ignores the crowd limiter** |
| `Incoming` | 7 | 6s | 0.8 | everyone within `IncomingRadius` of a blast |
| `Hurt` | 6 | 5s | 1.0 | above Kill on purpose — taking fire beats a kill quip |
| `Kill` | 5 | 0.25s | 1.0 | **concurrent**: layers over whatever is playing; **ignores the crowd limiter** |
| `OutOfAmmo` | 4 | 3s | 1.0 | the dry click, at exactly zero |
| `PointTaken` | 4 | 10s | 0.7 | capturing side only, near the point |
| `LowAmmo` | 3 | 0.25s | 0.85 | shares Reload's voice |
| `Reload` | 2 | 0.25s | 1.0 | |
| `ReloadDone` | 2 | 0.25s | 0.5 | |

**Priority** decides who wins. A line already playing is cut off only by
something *strictly* higher, so two equal-priority events cannot trade the
channel back and forth mid-line.

**Cooldown** is per event, per character. Note a failed `Chance` roll still
starts it, so the real gap between lines is roughly `Cooldown / Chance`.

**Chance** is the probability the line plays at all. `1.0` is every time.

**Concurrent** lifts an event out of the one-voice-at-a-time rule entirely — it
layers over whatever is already speaking rather than waiting or interrupting.
`Priority` stops meaning anything for such an event, since it neither blocks nor
is blocked. `Cooldown` and `Chance` still apply.

**GlobalCooldown** is the pause after a line *ends* before the next may begin. It
is `0`, which is safe: it does not permit overlap, because a playing clip
occupies the channel and Priority governs. It only removes the breath between
consecutive callouts.

## How far a bark carries

```lua
Config.RollOffMode        = "InverseTapered"
Config.RollOffMinDistance = 10   -- full volume inside this
Config.RollOffMaxDistance = 70   -- silent beyond this
```

**`RollOffMode` must be set, and for a long time it was not.** `Sound.RollOffMode`
defaults to `Inverse`, and in that mode `RollOffMaxDistance` is **ignored** — the
curve is driven by MinDistance alone and the clip stays faintly audible far past
whatever the config claims. Barks carried across the map while the config said
140 studs.

`InverseTapered` behaves like real sound near the source, roughly inverse square,
then tapers so it actually reaches silence at MaxDistance. Natural close up,
genuinely bounded far away. Approximate volume by distance:

| studs | 5 | 10 | 20 | 35 | 50 | 60 | 70+ |
|---|---|---|---|---|---|---|---|
| volume | 100% | 100% | 42% | 17% | 7% | 3% | silent |

Range is a tactical setting, not just an audio one: barks have no team filter, so
anything you say is heard by enemies inside that radius too. 70 studs reaches the
people you are fighting alongside and not someone across the compound.

`CrowdRadius` is deliberately the same number, so the limiter only counts barks a
listener could actually hear.

## Crowd mixing

Arbitration is per character, so without a limiter a twenty-player push produces
twenty simultaneous voices — each obeying its own cooldown perfectly, and none
of them legible.

A bark is refused when `CrowdLimit` **other characters** have already started a
bark within `CrowdWindow` seconds and `CrowdRadius` studs of the speaker:

```lua
Config.CrowdWindow = 1.5
Config.CrowdRadius = 70   -- matches RollOffMaxDistance
Config.CrowdLimit  = 2
```

Counted per locality rather than globally, so a firefight on the far side of the
map cannot silence the one next to you.

**Your own recent lines do not count against you.** This gate exists because
several voices at once are unintelligible; one voice saying two things in
sequence is not that, and how often a single character may speak is already
governed entirely by `Cooldown` and by the channel. Counting a speaker's own last
line against their next one is double jeopardy.

The gate sits after the cooldown check and before the chance roll, so a bark
dropped for crowding does not also burn its cooldown; the speaker can talk again
as soon as the noise dies down.

`IgnoresCrowd = true` bypasses it entirely. Two events do:

- **`Death`**, because a death carries information nobody else can supply.
- **`Kill`**, because a kill arrives at the end of a chain that has already made
  noise — the victim's `Hurt` bark when you first hit them, then the victim's
  `Death` bark an instant before. Both are inside `CrowdRadius` of the killer at
  any normal range, so without this flag a kill bark was routinely refused by the
  very death that earned it, landing only when the victim took longer than
  `CrowdWindow` to die after their last `Hurt` line. `Concurrent` does not help
  here: it exempts `Kill` from priority and the one-voice rule, but the crowd gate
  is a separate gate and applied regardless.

## Sharing a voice

`LowAmmo` has no clips of its own — it borrows Reload's:

```lua
LowAmmo = { Priority = 3, Cooldown = 0.25, Chance = 0.85, SharesWith = "Reload" },
```

Sharing is deeper than copying ids into two lists. Events that share a voice also
share the **no-repeat memory** and the **cooldown clock**, so going low and then
reloading a second later cannot say the same line twice. Two separate lists
holding the same ids would do exactly that.

## Picking clips

Selection is uniform across every clip except the one just played, which is
excluded outright.

The exclusion rolls across the remaining `n - 1` slots and steps over the
excluded index. Rolling across all `n` and nudging collisions onto the next slot
is the obvious shortcut and it skews the *sequence*: long-run play counts stay
even, but the clip following the last one played comes up twice as often, so you
hear the list walk forwards. With exactly two clips any no-repeat rule gives
strict alternation — that one is unavoidable.

## NPCs

`Config.IncludeNPCs` (default on) binds anything with a Humanoid that appears in
Workspace, not just player characters. NPCs and dummies get their own Hurt and
Death lines, and killing one credits a Kill — attribution reads the victim's
`WeaponTag` rather than requiring the victim to be a player.

Cooldowns are per character, so ten NPCs have ten independent timers. That is
correct for a firefight but can read as "the cooldown is broken" when you are
testing against a crowd.

`Config.Debug` prints a line on every humanoid death saying whether a `WeaponTag`
was present and who it named. Use it when a Kill is not firing and you want to
know whether the kill was simply never attributed.

## Two details worth knowing before you tune it

**Death lines emit from a detached part, not the head.** TREK gibs characters,
and a `Sound` whose parent is destroyed stops instantly — a death bark parented
to the head gets cut off mid-word. `Death` parks an anchored invisible part where
the head was and plays from there.

**`MaxLineLength` is a backstop, not a guess at clip length.** The server cannot
read `Sound.TimeLength` until the asset loads, so `Ended` never fires for an id
that fails to load. Without the timeout the channel would wedge for the rest of
the round. Keep it above your longest clip.

## Ammo is watched, not read at reload time

`LowAmmo` fires on the shot that crosses the threshold, not during the reload.
TREK's `handleReload` refills the magazine synchronously on the same RemoteEvent
this system listens to, so reading ammo inside that handler is a race you would
usually lose. Watching the counter sidesteps it.

**The counter is a `DoubleConstrainedValue`, not a `NumberValue`.** TREK builds
it in `createAmmoStore` with `Instance.new('DoubleConstrainedValue')` and sets
`MaxValue = MagCapacity`. The two classes are siblings under `ValueBase`, so an
`IsA("NumberValue")` test is false for every weapon in the game — which is
exactly how this event spent its first release doing nothing at all.

That `MaxValue` is the magazine size, so capacity needs no config lookup.

`TAmmo` is also created lazily on the same `ChildAdded` signal that triggers the
watcher, after a yield — so the watcher waits for it rather than checking once
and giving up, which used to lose the race on a weapon's first equip.

Counters are deduplicated by identity: equipping the same weapon twenty times
connects once, not twenty times.

## What's here

| | |
|---|---|
| `src/shared/VoicelineConfig` | every tunable, the sound lists, and the id/placeholder handling |
| `src/server/VoicelineService` | the channel — cooldowns, priority, concurrency, playback, cleanup |
| `src/server/VoicelineHooks` | the TREK adapters, one per event |
| `src/server/VoicelineRuntime` | waits for `TREK_INSTALLED`, validates config, starts the hooks |
| `src/client/VoicelinePreload` | warms the audio cache on each client at join |

The preloader has to be a client script: the Sound is created on the server and
parented to the speaker's head, so the instance replicates but the audio data
does not — every listener fetches the asset themselves.

## Not in yet

Team-only playback, and a client-side path for lines only the speaker should
hear. Both are config-shaped rather than rewrites.

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o TREKVoicelines.rbxm
```

## Credit

Made by PlagueByte (pb6008 on Discord). TREK itself is not mine and is not
included here — this hooks into whatever TREK install you already have.

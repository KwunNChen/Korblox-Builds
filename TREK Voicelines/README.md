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
| `LowAmmo` | `tool.TAmmo.*.Ammo` | value watcher, fires on the shot that crosses the threshold |
| `Hurt` | `Humanoid.HealthChanged` | plain Roblox, so explosions and vehicles count too |
| `Death` | `Humanoid.Died` | plain Roblox |
| `Kill` | `Humanoid.WeaponTag` | the killer tag TREK writes in `LeaderBoardModule.tagPlr` |

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
| `Death` | 10 | 0s | 1.0 | always lands; cooldown is moot, you die once per life |
| `Hurt` | 6 | 5s | 1.0 | above Kill on purpose — taking fire beats a kill quip |
| `Kill` | 5 | 0.25s | 1.0 | **concurrent**: layers over whatever is playing |
| `LowAmmo` | 3 | 0.25s | 0.85 | shares Reload's voice |
| `Reload` | 2 | 0.25s | 1.0 | |

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

Magazine size comes from `trekServerFuncs.checkForModule` when reachable, and
falls back to the largest value ever seen on that counter. Note `LowAmmoFraction`
is a fraction: on a 6-round magazine 0.25 triggers at one round left, which is
late. Consider a floor if you run small magazines.

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

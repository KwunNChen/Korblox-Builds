# Apache

An AH-64 attack helicopter that flies and fights by itself (Y3llow Mustang's
helicopter AI). It is hooked into the Bloxian team system: it hunts players,
Bloxians and crewed vehicles, and they all shoot back.

## Install

Drag `Apache.rbxm` into Workspace **where it should fly**. Placed more than 10
studs above the ground, it starts in the air with the engine running and
hovers there (`AIRBORNE_HEIGHT` in `Helicopter AI`). Placed on the ground, it
waits there and takes off when it sees a target, as the original did. It needs
nothing else; the Vehicle Spawner can drop it too, 50 studs up.

## Fighting

- **Targets:** the nearest enemy within `Settings.Distance` (1000) that is out
  in the open: players, Bloxians anywhere in Workspace, other Apaches, and
  vehicles with an enemy aboard (fought as the vehicle, not the man inside).
  An empty vehicle nobody owns is left alone.
- **Sides:** `Settings.Team` works like a Bloxian's. Bloxians with the same Team
  value are friends, a player on a Roblox team of that name is a friend, and
  `AttackPlayers` off spares every player. `Settings.Team.FFA` fights
  everyone.
- **M230 chain gun:** 25-50 a round with red tracers, cut by a vehicle's
  `SmallArmsScale` (the Abrams takes 5%).
- **Hydra rockets:** 200 damage across 6 studs.
- **Hellfire missiles:** 1000 across 12 studs, used first on vehicles: three
  kill an Abrams, one a Warthog.
- **Ammo** (`Settings.Ammo`): 1200 M230, 38 Hydras, 8 Hellfires. When it runs
  dry it flies home and rearms there, or `Ammo.Infinite` never runs out.
- Blasts are drawn by `Effects` (the same Random Arty-style effect as the
  vehicles') with no Roblox `Explosion`, so terrain is never cratered.

Damage, blast sizes and tracer colour are the constants at the top of
`Modules/Combat`.

## Crew

Two Bloxians in aviator helmets and USAF flight suits sit in the cockpit: the
pilot in the back and the gunner in the front. They are still figures, can't be
shot through the canopy, and need `ServerStorage.BLOXIAN` (without it the
cockpit is empty).

**Bailing out:** at 30% health (`BAIL_HEALTH`), or if a single hit would kill
it, both jump out of opposite sides as live Bloxians. Their parachutes open
after 0.6 s, they sink at 14 studs/s and drift outward, and the canopy fades
once they land. On the ground they fight like riflemen with the FN FAL, on the
Apache's team and `AttackPlayers` setting. They do not respawn. The Apache
goes down without them.

Seat positions are the `PilotSeat` and `GunnerSeat` attachments on `Body`.
They're my estimate of the cockpit, so move them in Studio if the figures sit
wrong. The outfit, weapon, ejection and parachute numbers are at the top of
`Modules/Crew`.

## Shooting it down

It has 1500 health (`Humanoid.MaxHealth`). Bloxian rifles, vehicle machine guns
and shells, and SPEARHEAD guns and RPGs all hurt it as they would a soldier.

When it dies it spins out and falls smoking and burning, then blows up on the
ground: 120 damage within 25 studs, drawn as the vehicles' wreck explosion. The
wreck lies there for `Settings.Respawn.Time` (80 s), fades out, and a fresh one
appears where it was placed, unless `Settings.Respawn` is off or it came from the
Vehicle Spawner. The blast and fade are at the top of `Helicopter AI`.

## Changes from the original

- Targets go through the Bloxian rules above. The original only looked at the
  top of Workspace and ignored vehicles.
- Missiles and the wreck no longer make Roblox explosions, which cratered terrain
  (`Settings.DestroyTerrain` is gone).
- Starts airborne, and hovers at an airborne home instead of landing.
- 1500 health instead of 500. `BreakJointsOnDeath` is off, so it falls in one
  piece.
- The crash fires are shown, and the death no longer prints debug lines.

## Building

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o Apache.rbxm
```

`src/Base.rbxm` is the original model without its scripts; the scripts are the
`.luau` files beside it.

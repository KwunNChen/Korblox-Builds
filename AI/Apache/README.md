# Apache

An AH-64 attack helicopter crewed by Bloxians, like the Abrams: a pilot in the
`VehicleSeat` and a gunner on the M230 chin gun and the Hellfires in the `Seat`.
It has no AI of its own; the crew's `VehicleModule` flies and fights it. Players
can fly it too.

## Install

Drag `Apache.rbxm` into Workspace. It needs the current `KorbloxAI.rbxm`, for the
crew logic and `ServerStorage.BLOXIAN`.

- **Placed by hand** with `Settings.AutoCrew` on, it brings its own pilot and
  gunner. It clones two Bloxians on its `Settings.Team` (`Hostile` when blank)
  and they get straight into their seats.
- **From the Vehicle Spawner** it appears 50 studs up (`Settings.Height`) with
  a full crew (the panel has no crew choice for aircraft). Bloxians on foot never
  try to board one: nobody can walk up to it in the air.
- **The crew see out of it:** a seated Bloxian's sight ignores the vehicle he is
  in and reaches its `SpotRange`.

The crew wear the `Pilot` uniform (aviator helmet, USAF flight suit) and carry
the FN FAL.

## Flying

The body is moved by script through rigid constraints, like the Abrams' hull.

- **Height:** it holds `Settings.Height` above the highest ground under it and
  just ahead, climbing at up to 25 studs/s. It climbs straight up off anything
  it would fly into.
- **Speed:** up to 60 studs/s forward and 20 back, turning at 60°/s. It leans
  nose-down with speed and banks into turns.
- **No pilot:** it hovers where it is.
- **Rotors:** `Rotors` spins them on each client, on motors rather than physics
  hinges, and they run down once it is wrecked.
- **Bloxian pilot:** closes in, then circles the enemy at about 110 studs
  (`EngageDistance`). He spots out to 600 studs (`SpotRange`).
- **Player pilot:** W/S and A/D from the pilot seat; height is automatic. On the
  ground there is a prompt at each cockpit door.

## Weapons

- **M230 chin gun:** swings up to 100° each side, 60° down and 10° up, and fires
  the crew's bursts with red tracers, like the other vehicles' guns.
- **Hellfires:** one every 3 seconds off the eight rails, at 220 studs/s,
  steering onto where the gunner is aiming.
  - **Blast:** 14 studs, 200 damage at the centre falling to 40 at the edge.
  - **Against vehicles:** 1000 on a direct hit (three kill an Abrams), a quarter
    of that in the blast.
  - **Rearming:** a fired rail reloads after 20 seconds.
- **Blasts:** drawn by `Effects` with no Roblox `Explosion`, so terrain is never
  cratered.

## Damage, bailing out, destroyed

It has 1500 health (`Settings.Health`). Bullets do 30% of their damage to it
(`SmallArmsScale`), and SPEARHEAD guns and RPGs hurt it through the `Spearhead`
script. The crew are protected while seated, as in the other vehicles.

- **Bailing out:** at 30% health (`BAIL_HEALTH`), or if a single hit would kill
  it, the crew jump out of the doors.
  - **The parachute:** it opens after 0.6 s, they sink at 14 studs/s, and the
    canopy fades once they land.
  - **On the ground:** they fight on as Bloxians with their FALs.
  - **Players:** anyone getting out more than 12 studs up gets a parachute too.
- **Going down:** with nobody aboard it spins out and falls, and anyone still
  inside dies.
  - **Destroyed:** the whole airframe goes up in flames, with a fire on each of
    its 30 biggest parts and black smoke off the largest.
  - **On the ground:** it blows up with its wreck blast and one of Random Arty's
    shell impacts at 4x size (`CRASH_SCALE`).
- **The wreck:** it lies charred for 12 s (`WRECK_TIME`, or
  `Settings.RespawnDelay` if that's shorter), then fades out over 3 s.
  - **Placed by hand:** a fresh one appears where it was placed once the full
    `RespawnDelay` (30 s) is up.
  - **From the Vehicle Spawner:** it's gone.

Every number is at the top of `Heli`.

## Building

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o Apache.rbxm
```

`src/Base.rbxm` is the original model with its old AI and its character parts
(`HumanoidRootPart`, `Head`, `Torso`) removed, and two seats added. The seats
are placed from the model's dimensions: if the crew sit wrong, move
`VehicleSeat` and `Seat` in Studio.

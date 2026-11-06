# AC130

A spawnable AC-130 gunship. It flies itself, holds station over where it was
spawned, and flies the fire missions its side's Bloxian radiomen call, in
place of the artillery battery. An enemy F-4 Phantom can shoot it down.

## Install

It goes in `ServerStorage.BloxianVehicles` as `AC130`, next to the other
vehicles. The root project, the Vehicle Spawner project and this package's own
`default.project.json` all sync it there. It needs:

- **Random Arty**, current build, for `ServerStorage.ArtilleryFireMission`.
- **Bloxian**, current build, whose radiomen call it.
- The **Bloxian Spawner** tool (Vehicles mode) to spawn it.

## What it does

Spawn it from the Bloxian Spawner's Vehicles mode and pick its team (Hostile or
Friendly: the spawner refuses `Any`, since it needs a side to know who to shell). It's
`Aircraft` and `Uncrewed`, so it gets no crew and the Crew row is hidden.
When it spawns, every player hears `rbxassetid://8261242927` (the old
artillery warning sound; `ARRIVAL_SOUND` in `Gunship`), so its arrival is
announced. That's the only heads-up: its barrages come with no warning.

- **On station:** it circles 700 studs above where it was spawned, at a
  radius of 350 and 110 studs/s, banked 20° with its guns (the left side)
  turned in.
- **Its own barrages:** its side is `Settings.Team` (blank counts as Hostile),
  copied to its `Team` attribute. Nobody calls it. 15 s after arriving, then
  every 30-50 s, it picks the biggest group of enemies within 800 studs of its
  station (Bloxians of another team, players not on its team), counting
  everyone within 25 studs of each, and never one with a friend within 30
  studs. It slides its orbit over them (90 studs/s, `RELOCATE_SPEED`, for up to
  12 s) and Random Arty fires every shell from the `Muzzle` attachment on the
  105 mm, with no warning sound. Each shell flashes the muzzle and plays the 40 mm sound (`rbxassetid://18754665604`, `FIRE_SOUND`).
  (`FIRST_BARRAGE`, `BARRAGE_INTERVAL`, `BARRAGE_RANGE`, `CLUSTER_RADIUS`,
  `DANGER_CLOSE`, `OVERHEAD_WAIT`.)
  - **The shells:** each one comes nearly straight down from the gunship in 0.8–1 s, one every 0.08–0.18 s (Random Arty's `GunshipShellFlightTime` and `GunshipShellSpacing`).
  - **Where they land:** within 12 studs of the spot it picked
    (Random Arty's `GunshipScatterRadius`), not across the battery's 90-stud
    spread.
  - **The impacts:** each lands with the same artillery explosion.
- **After:** once the last shell lands it slides back to its station
  (`OnMission` is set while it's out). Radiomen always call the artillery
  battery, never the gunship, and the two can fire at the same time.
- **Flares, chaff and health:** it carries 120 flares and 120 chaff bundles, 8 to a salvo, against missiles and 600
  `AirHealth` against a Phantom's cannon (see the F4 README).
- **Shot down:** it's tagged `BloxianGunship`. A missile from an F-4 Phantom on another
  side sets `ShotDown`. Any barrage it's firing stops at once.
  - **Going down:** the whole airframe goes up in flames, with a fire on each of
    its 30 biggest parts and black smoke off the largest.
  - **The crash:** one blast of Random Arty's shell impact at 4x size where it
    hits the ground (`CRASH_SCALE`, `ENGULF_PARTS`, `ENGULF_MAX_FIRE` at the
    top of `Gunship`).
  - **The wreck:** the wreck stays where it hit, charred black and
    tilted on the ground, still burning and smoking. The fires go out after 6 s
    and the smoke after 12 s. Then it fades away over 3 s and is removed
    (`WRECK_BURN`, `WRECK_TIME`, `WRECK_FADE`). It's no longer an aircraft:
    its tag comes off and it's marked `Wrecked`, so Phantoms don't go after it
    and the tracker drops it.

Every number is at the top of `Gunship`.

## Building

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o AC130.rbxm
```

`src/Base.rbxm` is the original model, minus its thumbnail copy. `Body1` is the
root. Every part is saved anchored, with nothing collidable or queryable, and
`Gunship` welds them to `Body1` and lets them go when it starts.
`ModelStreamingMode` is Persistent, so it's always loaded and trackable. The `Muzzle` attachment and its `Fire` sound are added on `Body1`.
`package.project.json` adds the `Aircraft` and `Uncrewed` attributes and the
`Settings.Team` value the spawner fills in.

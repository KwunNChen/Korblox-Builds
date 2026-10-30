# Vehicle Spawner

A tool for dropping Warthogs, Abrams and Apaches into the game, the same way the Bloxian
Spawner drops soldiers, optionally with a Bloxian crew already aboard.

## Install

Drag `VehicleSpawner.rbxm` into ServerStorage, then move the contents of each
signpost folder into the real service:

| Folder | Goes in |
|---|---|
| `ServerStorage/BloxianVehicles` (Warthog, Abrams, Apache) | ServerStorage |
| `ServerScriptService/VehicleSpawner` | ServerScriptService |
| `StarterPack/Vehicle Spawner` | StarterPack |

A crew needs the Bloxian package's `ServerStorage.BLOXIAN`, and the current
`Bloxian.rbxm`, whose `VehicleModule` knows how to take an assigned seat.

## Using it

Hold the **Vehicle Spawner** and **click the ground**. The vehicle lands there
facing the way you look; a flat marker the size of the vehicle shows where. The
panel along the bottom picks what spawns (each button cycles):

- **Vehicle:** every Model in `ServerStorage.BloxianVehicles`. Drop another
  vehicle built the same way in there and it shows up.
- **Team:** `Any` lets every Bloxian crew it. `Hostile`, `Friendly` or a Roblox
  team keeps it to Bloxians of that team (its `Settings.Team`).
- **Crew:** `Empty`, `Driver only` or `Full crew`. The crew are Bloxians of the
  chosen team (`Any` gives a Hostile crew) who get straight into their seats and
  stay in them whether or not there is an enemy, until they are thrown out or
  the vehicle is wrecked.
- **Clear mine** removes every vehicle you spawned and its crew.

**Aircraft** (the Apache, or any template with the `Aircraft` attribute) fly
themselves. They appear `Settings.Height` studs (50) above the click, engine
running, and the Crew button does nothing for them (the Apache always has its
two pilots, who bail out as Bloxians the Clear button also removes). Team works like a crew's
team: `Any` gives a Hostile one that fights everyone, and `Friendly` never
attacks players. A Roblox team leaves that team's players alone.

Spawned vehicles do not respawn: wrecked, flipped or left abandoned away from
where they were spawned, they are removed. At most 8 are alive on the server at
once, one spawn per player every 2 seconds, within 400 studs of you.

**Who can spawn with it:** everyone in Studio, plus the place owner (or rank 255
of the owning group) in live servers. Add user ids to `ALLOWED_USER_IDS`, or set
`GROUP_ID` and `MIN_GROUP_RANK`. These and the limits are at the top of
`VehicleSpawner`.

## Building

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o VehicleSpawner.rbxm
```

The vehicles are pulled in from `../Warthog`, `../Abrams` and `../Apache`, so rebuild this
after changing any of them.

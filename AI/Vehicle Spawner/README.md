# Vehicle Spawner

Adds a **Vehicles** mode to the Bloxian Spawner tool for dropping Warthogs,
Abrams, AA trucks and Apaches into the game, optionally with a Bloxian crew already aboard.
There is no separate tool: the Bloxian Spawner's panel gets a Spawn row
(`Soldiers` / `Vehicles`) once this package's server script is running.

## Install

Installs with [KorbloxAI](../KorbloxAI).

## Using it

Hold the **Bloxian Spawner**, pick `Vehicles` in the panel's Spawn row, and
**click the ground**. The vehicle lands there facing the way you look; a flat
marker the size of the vehicle shows where. The panel's rows pick what spawns:

- **Vehicle:** every Model in `ServerStorage.BloxianVehicles`. Drop another
  vehicle built the same way in there and it shows up.
- **Team:** `Any` lets every Bloxian crew it. `Hostile`, `Friendly` or a Roblox
  team keeps it to Bloxians of that team (its `Settings.Team`).
- **Crew:** `Empty`, `Gunner only` or `Full crew`. The crew are Bloxians of the
  chosen team (`Any` gives a Hostile crew) who get straight into their seats and
  stay in them whether or not there is an enemy, until they are thrown out or
  the vehicle is wrecked.
- **Gunner only:** the vehicle stands where it was dropped with its gun (or the
  AA truck's launcher) manned, like an emplacement. The vehicle gets the
  `GunnerOnly` attribute, so the gunner never climbs over to drive. Another
  soldier, or a player, can still take the empty driver's seat.
- **Clear all** (in Vehicles mode) removes every spawned vehicle and its crew.

**Aircraft** (the Apache, or any template with the `Aircraft` attribute) appear
`Settings.Height` studs (50) above the click. Their crew get straight into the
seats in the air, wearing the Pilot uniform with the FN FAL, and bail out on
parachutes when it is shot up. An aircraft always comes with a full crew (the
Crew row is hidden for one): Bloxians on foot never board an aircraft. The
**F-4 Phantom** (`Uncrewed` attribute) is the exception: it flies itself and gets no
crew. Its team decides whose side it is on (`Any` counts as Friendly). The
**AC-130** is uncrewed too: it circles high over where it was spawned and
flies its team's radiomen's fire missions instead of the artillery. It has the
`NeedsTeam` attribute, so the spawner refuses it on team `Any`: pick Hostile or
Friendly, the side whose radiomen should get it. Only that side's radiomen
can call it. See the AC130 README.

Spawned vehicles do not respawn: wrecked, flipped or left abandoned away from
where they were spawned, they are removed. At most 10 are alive on the server at
once, one spawn per player every 2 seconds, within 5000 studs of you (`MAX_SPAWN_DISTANCE`).

**Who can spawn with it:** everyone in Studio, plus the place owner in live servers.
Add user ids to `ALLOWED_USER_IDS`. These and the limits are at the top of
`VehicleSpawner`.

## Building

```bash
cd ../KorbloxAI && /c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o KorbloxAI.rbxm
```

The vehicles are pulled in from `../Warthog`, `../Abrams`, `../AA Truck` and `../Apache`, so rebuild this
after changing any of them.

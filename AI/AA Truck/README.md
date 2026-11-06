# AA Truck

A BM-21 Grad truck whose 40 tubes hold homing surface-to-air rockets instead
of artillery rockets. Bloxians crew it against enemy aircraft: F-4 Phantoms,
AC-130s and Apaches. Players can drive it and sit at the launcher too.

## Install

Spawn it from the Vehicle Spawner (it is in `ServerStorage.BloxianVehicles`,
synced by the root project), or drag `AA Truck.rbxm` into Workspace. Bloxians
need the current `KorbloxAI.rbxm` to crew it. Rocket blasts use Random Arty's
artillery effect when it is installed, and a plain explosion when it is not.

## How it works

The downloaded model was an A-Chassis car with a turret kit. Only its meshes
are kept, in `src/Base.rbxm`. The scripts, GUIs and the kit's parts are gone.
`Truck` rigs it when the server starts, much like the Abrams:

- **Rigging:** the body welds to the invisible `Hull`. The launcher (`TurretRing`
  and `Trunnion`) is welded on fixed, and only comes loose when the truck is
  destroyed.
- **Driving:** the hull is held by rigid constraints that the script moves every
  frame. It follows the ground and tilts with slopes, drives over bumps up to
  1.5 studs, and drops off edges. It steers like a truck, turning only while it
  rolls. Top speed is 20 studs/s forward and 8 in reverse (slower than the
  Abrams' 28), picking up 8 studs/s each second.
- **Wheels:** each wheel hangs on a motor. The `Wheels` client script rolls
  them at the truck's speed, within 300 studs of the camera.
- **Seats:** both are in the cab. The driver (`VehicleSeat`) is on the left,
  the launcher operator (`Seat`) on the right. Players hold E at the doors:
  **Drive** on the left, **Run the launcher** on the right. The crew are
  protected while inside, as in the Abrams.

## The launcher

It needs someone in the launcher seat, a Bloxian or a player. Firing is then
automatic:

- **Targets:** the nearest enemy aircraft within 2500 studs (and at least 80
  out) with nothing solid in the way. That means a Phantom, an AC-130 or a
  crewed Apache on the other side from whoever sits at the launcher. It never
  fires at anything on the ground.
- **No aiming:** the launcher is fixed to the truck, with its tubes 16° up over
  the cab, and never turns. Only the truck moves. It fires as soon as it has a
  target, wherever the target is.
- **Firing:** salvos of 2 rockets, one salvo every 4 s, with at most 2 rockets
  in the air at one target. All 40 tubes, then a 30 s reload.
- **Rockets:** they leave the tubes the way the tubes point, fly straight for
  0.3 s, then steer onto the aircraft at 160°/s (fast enough to come round onto
  one behind the truck) at 450 studs/s. A rocket that misses bursts after 9 s.
- **Damage:** 187.5 to a plane's AirHealth and 1200 to a helicopter. A Phantom
  (200) takes 2 rockets, an Apache (1500) 2, and an AC-130 (600) 4.
- **The aircraft fight back:** the rockets are radar-guided, so aircraft
  answer them with chaff, not flares. Each rocket sets the target's
  `MissileInbound` and `ThreatAt`, so a Phantom breaks square across the
  rocket's path (beaming it). Every chaff bundle near a rocket has a 20% chance
  to pull it off, or 50% while the aircraft is beaming it, including chaff
  thrown against the other rocket of the salvo. A Phantom's salvo of 4 decoys
  each rocket about 59% of the time flying straight, and 94% beaming it (see
  the F4 README).
- **Sound:** each launch uses the Javelin's sound, with a muzzle flash.
- **Tracker:** its `Status` attribute reads No gunner, Scanning, Engaging
  F-4/AC-130/Apache, or Reloading. `Rockets` is how many are left, `AATarget`
  what it is shooting at.

## How the Bloxians use it

It has the `Support` attribute, so:
- **Who crews it:** only a crew spawned with it (Vehicle Spawner). Soldiers on
  foot never take it.
- **Full crew:** the driver never goes after the enemy or rams. He keeps with
  the nearest friendly infantry, about 25 studs off, or patrols when nobody is
  near, and the operator shoots down whatever flies over.
- **Gunner only:** it stays parked where it was dropped as a fixed AA site, and
  the operator fires from there. He never climbs over to drive.

## Taking it out

**800 health.** Bullets do 25% (`SmallArmsScale`). One Javelin, one Abrams
shell or one Maverick destroys it. Phantoms go after it like any other enemy
vehicle. When it goes up:
- **The crew** inside die.
- **The blast** hurts people within 25 studs (120 damage at the centre, 20 at
  the edge) and does 200 to other vehicles in it.
- **The launcher** is thrown off and the wreck burns.
- **Cook-off:** rockets left in the tubes go off over the next few seconds.
- **Respawn:** one from the Vehicle Spawner is removed. One placed by hand comes
  back where it was after `Settings.RespawnDelay` seconds.

## Tuning

Everything is a constant at the top of `src/Truck.server.luau`: speeds and
turning, launcher rates and limits, range, salvos and reload, rocket speed,
turn and damage, flares, crushing, and the wreck. On the model:

| | |
|---|---|
| `Settings.Health` | hit points (800) |
| `Settings.RespawnDelay` | seconds the wreck burns before a fresh truck appears where it was placed |
| `Settings.Team` | blank: any Bloxian crew; set to a team name to keep it to that team |
| `HalfWidth`, `AgentRadius`, `SmallArmsScale` attributes | its size for the driver's path-finding, and how much bullets hurt it |

## Building

`src/Base.rbxm` is made from the original download (`AA.rbxm`) by
`tools/BuildBase.luau`, not by hand. To change which meshes are kept, or where
the seats and pivots go, edit that script and run it again, then build.

Run the base-model script:

```bash
/c/Users/pbche/.rokit/bin/lune.exe run tools/BuildBase.luau "C:/Users/pbche/Downloads/AA.rbxm" src/Base.rbxm
```

Then build the model:

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o "AA Truck.rbxm"
```

The Effects and Spearhead scripts are copies of the Abrams' own.

## Not done

- **Placed by measurement:** the pivots, seats and the tubes' angle (16°) were
  placed from the mesh's measurements, not by eye. Rockets leave from the long,
  open end of the tubes (the `Launch` attachment), which rests pointing over
  the cab. If the tubes sit off the
  pod or the crew sit in the dashboard, move `TurretRing`, `Trunnion`, `Seat`
  or `VehicleSeat` in `Base.rbxm`.
- **The front wheels do not turn when it steers.** They only roll.

# Abrams

M1A2 Abrams that Bloxian soldiers crew against you: a driver who hunts and
crushes, and a gunner on the coax machine gun and the 120 mm main gun. Players
can drive it too.

## Install

Drag `Abrams.rbxm` into Workspace where you want it. Bloxians need the current
`KorbloxAI.rbxm` (with the vehicle-generic `VehicleModule`) to crew it.

## How it works

The mesh is a static War Thunder model, so `Tank` rigs it when the server
starts:

- Hull meshes weld to the invisible `Hull`, the turret to `TurretRing`
  (traverses) and the gun to `Trunnion` (elevates).
- The hull is not on physics wheels. The script works out where it should be
  every frame and holds it there with rigid constraints: it follows the ground
  and tilts with slopes, drives over bumps up to 2 studs, stops at anything
  taller, and drops off edges.
- `VehicleSeat` is the driver (low in the driver's hatch, head out), `Seat` the
  gunner (up in the commander's hatch, turning with the turret).
- **Getting in:** both seats are inside the hull where nobody can walk onto
  them, so each door has a prompt: **Drive** at the front left, **Gunner's
  hatch** at the right side (hold E within 12 studs). Leaving a seat, or being
  thrown out, puts you down outside that seat's door rather than inside the
  hull. Bloxians board from anywhere within 3 studs of the hull, and a Bloxian
  driver waits up to 8 seconds for a crewmate still on his way to the gun.
- **Tracks:** `Tracks` (a client-side script) spins the road wheels and runs a
  belt of tread links round each track at that track's own speed, so they roll
  forward, back, and in opposite directions when it turns on the spot. The
  track meshes themselves cannot scroll (they use a SurfaceAppearance), so the
  links are what shows the movement. The links are welded to the hull inside
  the tank, so they move with it exactly and disappear with it; they stop when
  it is wrecked and fade out with the wreck. It only animates within 300 studs
  of the camera.

## How the Bloxians use it

Same crew logic as the Warthog:

- **Driver:** closes in, then circles at about 70 studs (`EngageDistance`
  attribute) so the gun keeps an angle. Within 60 studs of someone on foot he
  may go for him and drive through instead.
- **Gunner:** swings the turret onto you (50°/s traverse, 25°/s elevation) and
  fires coax bursts, leading a moving target. When the main gun is loaded,
  within 3° and you are 20-400 studs away, he fires a high-explosive shell.
- **Through the barrel, not past it:** he only fires when the barrel is clear
  from its breech to the muzzle and the muzzle has a line to you. With the
  barrel pushed into a wall, he cannot shoot whoever is on the other side.
  When his target is out of the barrel's line, he switches to the nearest enemy
  it can hit, if there is one.
- If the driver dies the gunner takes over the driving after 3 seconds. The crew
  never bails, however damaged; they get out only after 20 seconds with no enemy.

## Riders

Four `RiderSeat` seats on the turret roof, behind the hatches, two facing each
side. They turn with the turret.
- **Who rides:** Bloxian infantry climb on by themselves (see the Bloxian
  README). Players hold E at the back of the hull (**Ride**) for a free seat,
  and jump to get off.
- **Exposed:** riders get no protection, unlike the crew, and the tank's own
  shells and tracks never hurt them.
- **When it is destroyed:** they are thrown off into its blast.
- **Placement:** `RIDER_SPOTS` (studs from the turret ring, and which way each
  rider faces). Each seat drops onto the roof found under its spot; `RIDER_ROOF`
  is the height used if none is found.

## Smoke

M250-style launchers on the turret: **2 salvos** of 6 grenades.
- **When:** the crew fires them on their own (player crews too) when a missile
  is coming. A Javelin locking on and a Phantom's Maverick both say so through
  the `MissileInbound` and `ThreatAt` attributes. A single hit of 500 damage or
  more also sets them off. It needs someone aboard, and waits at least 6 s
  between salvos.
- **The screen:** the grenades burst in a 120° fan 20 studs out toward the
  threat, or the way the turret faces when nobody knows where the threat is.
  Each leaves a cloud 14 studs across that hangs for 25 s.
- **What it blocks:** nobody can see or aim through a cloud. That covers
  soldiers, vehicle gunners, a Javelin locking on, and a Javelin or Maverick
  homing on the tank. A missile that loses sight of it flies to where it last
  saw it, and misses if the tank has moved.
- **The crew's move:** a Bloxian driver backs straight out for 4 s, so the
  smoke stays between the tank and the threat.
- **Left:** the `Smoke` attribute is the number of salvos remaining, and
  `SmokeAt` is when the last one went up.
- **Tuning:** the `SMOKE_*` constants at the top of `Tank`. `SMOKE_SOUND` uses
  Roblox's built-in rocket launch sound, pitched up.

## Barrel hitbox

The barrel is solid, from the breech (`Trunnion`) out to the muzzle,
`BARREL_THICKNESS` (1.2 studs) across:
- **Turning:** the turret stops against a wall rather than swinging the barrel
  through it.
- **Driving:** the tank stops when driving or turning would push the barrel
  into something. Only solid things count, not people or parts that do not
  collide.
- **Already in a wall** (spawned that way, say): it is free to move out.
- **Shells:** a shell fired with the barrel in a wall bursts on the wall, on
  the tank's side.

## Main gun

One HE shell every 6 seconds at 500 studs/s, straight down the barrel. It
bursts on whatever it hits with a 30-stud blast: 150 damage at the centre
falling to 25 at the edge (a Bloxian grenade is 16 studs and 20 damage). It
never hurts the crew or the gunner's own team.

Against vehicles a direct hit does 750 damage and one only caught in the blast
takes a quarter of that: four hits kill an Abrams (3000 health), one kills a
Warthog (400). Bullets do 5% of their damage to it (`SmallArmsScale` 0.05).

## Crushing

Anything it drives into faster than 5 studs/s takes 40 damage plus 8 per stud/s
above that, so at speed it kills outright. Same rules as the Warthog: not the
crew, not the driver's team, and a player driver gets the `creator` tag for kill
credit.

## Tuning

| | |
|---|---|
| `Settings.Health` | hit points (3000) |
| `Settings.RespawnDelay` | seconds the wreck burns before a fresh tank appears where it was placed |
| `Settings.Team` | blank: any Bloxian may crew it; set to a team name to keep it to that team |
| `EngageDistance`, `HalfWidth`, `AgentRadius` attributes | how far out the driver circles, and the tank's size for his path-finding |

Speeds, turret rates, the main gun's reload, blast and damage, and crushing are
the constants at the top of `Tank`.

## Not done

- A player in the gunner's seat cannot aim or fire yet: that needs a client
  script for mouse aim. Players can drive.
- Other gun systems only damage it if they look for the Humanoid further up than
  the part they hit; SPEARHEAD is handled (below).

## SPEARHEAD guns

The `Spearhead` script lets SPEARHEAD guns hurt it, and does nothing in a game
without SPEARHEAD. On start it moves the tank into a `workspace.Vehicles`
folder, made if missing, because SPEARHEAD's bullets stop on anything in there.
Otherwise they pass straight through. It then listens for SPEARHEAD's
`BulletHit` and damages the tank:

- **Bullets:** the gun's `damage.Other` times `SmallArmsScale` (5%), also when
  they hit a crewman in his hatch.
- **Explosive rounds (RPG-7):** times 3 (`EXPLOSIVE_SCALE`), with no
  `SmallArmsScale`. That is 600 for an RPG, so five kill an Abrams. A vehicle
  only caught in the blast takes up to half, less further out.
- **Who can hurt it:** never its own crew, the shooter's team when SPEARHEAD's
  `teamKill` is off, or a player that Friendly Bloxians aboard leave alone.
  The shooter gets the `creator` tag.

## Sounds

Set at the top of `Tank` (IDs and volumes), created when the server starts:

| | Asset | Plays |
|---|---|---|
| Main gun | `138839154527248` | each shell, from the gun |
| Machine gun | `80013099941453` | each round of a burst (red tracers) |
| Engine | `17485939810` | looped while someone is driving, pitched up with speed |
| Impact | `73652976704676` | each shell burst and the wreck (the Random Arty near-impact sound), set in `Effects` |

## Explosions

`Effects` draws them on each client in the Random Arty style, scaled down to a
tank round: a brief light, one dust image tinted to whatever the shell hit that
opens out and settles, real debris chunks thrown out of it, a smoke puff, and
camera shake. No fireball, and nothing left behind: damage is a plain radius
check on the server, not a Roblox `Explosion`, so terrain is never cratered.
The muzzle gets a flash, a smoke puff and a little shake. Every size, count and
timing is at the top of `Effects`.

## Destroyed

**Until then the crew cannot be hurt.** While seated they carry a hidden
ForceField (stops anything that uses `TakeDamage`), damage that sets Health
directly is undone, and the `InVehicle` attribute on their character tells the
Random Arty barrages to skip them. A Bloxian round that hits a crewman damages
the tank instead. The protection comes off the moment they get out.

When its health runs out:

- **Anyone still inside dies**, player or Bloxian, and their bodies come out of
  the seats. Bloxian crews never bail, so they go up with it.
- **The blast:** the same effect as a shell impact, 1.7 times the size
  (`WRECK_SCALE` in `Effects`), with the main gun's 30-stud blast damage around
  the hull.
- **The turret is blown off:** thrown 70 studs/s upward, drifting and spinning,
  and crashes down beside the hull.
- **The wreck** is charred dark and burns and smokes from the hull and the
  turret, the ammunition cooks off twice more at 1.3 and 2.8 seconds, and after
  `Settings.RespawnDelay` it fades out (and a fresh one appears where it was
  placed, unless it came from the Vehicle Spawner).

The toss, char colour, cook-off timing and fade are the constants above the
death handler in `Tank`.

## Building

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o Abrams.rbxm
```

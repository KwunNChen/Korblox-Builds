# Bloxian

A soldier NPC. He hunts players and other teams, shoots, reloads, throws
grenades at clusters, knifes anything that gets close, ragdolls when he dies
and respawns. Soldiers on the same team now talk to each other too.

## Install

**1. Insert `Bloxian.rbxm`.** It is a folder named after the services its
contents go in:

- `ServerStorage/BLOXIAN` goes in **ServerStorage**. It is the master copy that
  every spawn is cloned from, and scripts do not run there. To place a soldier by
  hand, clone it into Workspace.
- `ServerScriptService/BloxianSpawner` goes in **ServerScriptService**. It does
  the spawning for the tool.
- `StarterPack/Bloxian Spawner` goes in **StarterPack**. It is the tool.

Needs a baseplate or navmesh the PathfindingService can walk.

## Spawner tool

Everyone gets the **Bloxian Spawner** tool from StarterPack. While it is held:

- **Click the ground** to spawn a group there. The soldiers stand in a wedge
  facing the way you look. A blue or red ring shows where they will land.
- **The panel** on the left picks what spawns. Click a choice in each row:
  - Unit: `Infantry`, `Sniper team` (a sniper and his spotter) or `AT team`
    (a Javelin rocketeer and his loader); see below.
    Group, Weapon and Radioman only show for infantry.
  - Group: a soldier, a fire team (4) or a squad (9).
  - Team: `Hostile`, `Friendly`, then every team in the game's Teams service,
    read each time you take the tool out. The ring shows the team's colour.
  - Weapon: `Random`, or one class for everyone in the group.
  - Radioman: `Random` (10% each), `Leader` (the first soldier carries it), or `None`.
- **Track all** pins a tag over every Bloxian in the world, through walls: team
  colour, team and role, weapon, distance and a health bar. It stays on with the
  tool put away and through your respawns, until you click it again.
- **Clear mine** removes every soldier you spawned.

Spawned soldiers do not respawn. At most 40 are alive at once on the server,
and a click spawns at most once a second within 400 studs of you.

Anyone holding the tool can spawn. The limits are at the top of `BloxianSpawner`.

## Teams

`Settings.Team` decides who a soldier fights:

| Team | Players | Other Bloxians |
|---|---|---|
| `Hostile` (the default) | fights every player | fights every one not on `Hostile` |
| the name of a team in the game's **Teams** service | sides with that team's players, fights players on any other team | fights every one not on his team |
| `Friendly`, or any other name | leaves players alone if `AttackPlayers` is off, fights them if on | fights every one not on his team |

Players with no team (`Neutral`) are left to `AttackPlayers`, so a soldier on a
Roblox team ignores them when it is off. The team is read live, so a player who
switches teams changes sides at once. Bullets, grenades and knives never hurt
his own side, and Warthog and Abrams crews follow the same rules for roadkill
and shells.

## Squad chatter

Soldiers on the same `Team` hear each other within 70 studs. Lines show as a
speech bubble over the head. Everything is written ahead of time, nothing is
generated live, and answers are written to fit the line they answer.

**What they say depends on what is happening**
- Spotting an enemy: the call changes with how far he is, how close, how many
  there are, whether he is a player, and gives a clock position and range
  ("Contact, two o'clock, 80 out!"). Idle squadmates turn to face him.
- Reload, grenade, hit (a different set at low health), kill (a different set
  for a knife kill), losing a target, and a squadmate dying.

**Answers make sense**
- A line can carry its own answers ("Well, hello there." gets "Rude of him to
  drop in."), otherwise the answer comes from a set that fits that kind of call.
- A soldier already fighting answers a contact call differently from one who
  has not seen him yet ("Same here!" versus "Where?!").
- A question gets answered by the original caller ("Where?!" then "Two o'clock!").
- When a squadmate dies, the nearest two react one after the other.

**They do not talk over what they are doing**
- Answers and small talk wait while a soldier is reloading, firing a burst,
  throwing a grenade, stabbing, or drawing or lowering a weapon, and drop
  after a few seconds if he never gets free.
- Small talk only starts between two idle soldiers with no target. The moment
  either one spots an enemy or gets busy, the conversation stops where it is.
- A line about what he is doing at that very moment ("Reloading!") is allowed.

**Idle talk**
- Two idle soldiers nearby play out a written conversation of 2 to 4 turns.
- A soldier alone now and then mutters to himself.

Turn it all off with the `Chatter` BoolValue under `Settings`. The lines live
in `Scripts/Modules/ChatterLines` (calls, answers, mutters) and
`ChatterBanter` (conversations). Distances, chances and timings are at the top
of `ChatterModule`.

## Taking cover

Soldiers no longer stand in the open and trade shots.

- **When:** they run for cover when hurt (under half health), reloading or low on
  ammo, and, depending on how cautious each one is, when under fire or
  outnumbered. Enemies in knife range get fought instead.
- **Finding it:** a ring of spots around the soldier is tested. A spot counts
  if a wall within 7 studs blocks the enemy's line to it, it is not walking
  toward the enemy, and a step to the side gives a clear shot. Nearest,
  least exposed spot wins, and two soldiers will not share one.
- **In cover:** he waits, reloads once the magazine is under 30%, then steps
  out, shoots for a second or two, and ducks back. Hurt soldiers hide longer
  and peek shorter. If the enemy moves and can see his spot, he finds a new one.
- **Pushing on:** after 25 seconds of cover, healthy and loaded, he moves up.
  He calls it out ("Taking cover!", "Moving up!") and squadmates answer.

Turn it off with `Settings.UseCover`. All distances and timings are at the top
of `Scripts/Modules/TacticsModule`.

## Squad tactics

Soldiers of the same `Team` within 60 studs of each other fight as a squad,
loosely after US Army / Ranger battle drills. The highest ranked soldier leads,
and the squad splits into two fire teams, Alpha and Bravo.

- **Staying together:** soldiers join up within 60 studs and then stay one squad
  out to 150 studs, so a straggler rejoins instead of going it alone. Anyone
  more than 30 studs from the middle of the squad heads back (only rushes and
  the flanking team may go further), and cover is only picked within 30 studs
  of the squad.
- **Rifle at the ready:** in a squad the rifle is never slung. On patrol it is
  held at low ready; once an enemy is known it comes up to aim the moment he
  is in sight. Only a soldier on his own with nothing going on slings it.
- **On patrol:** the formation follows the way the leader is walking.
  - *Fire team wedge* (2-3 soldiers): the leader at the point, the rest staggered
    back to either side, 8 studs apart.
  - *Squad column* (4+): Alpha's wedge leads with the squad leader at its point,
    Bravo's wedge follows 10 studs behind.
  - *File*: walls within 7 studs on both sides of the leader (corridors,
    doorways) put the squad in single file, 6 studs apart.
  - *Security halt*: when the leader stops for 3 seconds, the squad forms a
    circle 7 studs round him covering every direction. A rally after breaking
    contact forms the same circle straight away.
- **Hearing:** a soldier hears a moving enemy through walls within
  `HearingRange` (120 studs), or within half that if the enemy is standing
  still. Hearing him counts as spotting him: he goes after him by pathing round
  the walls, and remembers him for 10 seconds after he goes quiet.
- **General awareness:** within `AwarenessRange` (250 studs) a soldier always
  has a rough idea where an enemy is, through any walls. The fix is only good to
  about 20 studs and updates every 4 seconds, so idle soldiers (and squads, in
  formation behind their leader) head for that area to investigate. Awareness
  alone never lets them aim or shoot: that still needs sight or hearing. Lone
  guerrillas use it to pick who to stalk.
- **Gunfire alerts everyone:** the moment any soldier fires, every ally within
  150 studs learns where the enemy is and engages, chatter on or off. Each
  burst refreshes it, so nobody forgets the enemy while a squadmate is still
  shooting at him.
- **Everyone gets a shot:** a soldier with no cover to fire from steps to the
  nearest spot with a clear shot, or pushes toward the enemy if there is none.
  Cover is only used for laying down fire if it has a spot to shoot out of. In
  a fight the squad leash loosens to 60 studs so they can close in together.
- **React to contact (Battle Drill 1):** everyone gets into the nearest cover
  and returns fire. The spotter calls the contact with a clock position and
  range. After 3 seconds the leader picks a plan.
- **Bounding overwatch:** one team rushes 3-5 seconds to the next cover while
  the other suppresses from cover, then they swap. Stops at 30 studs and fights.
- **Flank (3+ soldiers):** Alpha is the base of fire. Bravo bounds round to a
  point 30 studs off the enemy's side, preferring the side he cannot see, then
  assaults. Alpha shifts fire once Bravo is close.
- **Break contact:** when outnumbered by 2+ or the squad is badly hurt, the
  teams bound backwards covering each other, then rally on the leader.
- Every step is called out ("Bravo, flank left!", "I'm up!", "Set!",
  "Shift fire!", "Rally on me!") and answered.

Turn it off with `Settings.SquadTactics`. Numbers are at the top of
`Scripts/Modules/SquadModule`.

## Radiomen and platoons

About one soldier in ten spawns as a **radioman**, with an SCR-300 radio pack
on his back and an M81 patrol cap instead of a helmet (catalog items, set by
`RADIO_PACK_ID` and `PATROL_CAP_ID` in `RadioModule`). If the pack cannot be
downloaded a plain one stands in; if the cap cannot, he keeps his helmet. Every soldier of his team within 300 studs of him is on his radio
net, whatever squad they are in.

- **Contacts carry across the net.** Anything one soldier spots or fires at,
  every squad on the net learns about and engages, not just the ones in earshot.
- **Squads link into a platoon.** The radioman's squad leads. Every other squad
  leader on the net takes a slot in a wedge of squads behind it, 30 studs apart,
  facing the way the lead squad walks, and his men follow him in their own
  formation. A soldier with no squad of his own joins as a squad of one, and
  nobody on a net fights as a lone guerrilla.

`Settings.Role` is `Random`, or `Radioman` / `Rifleman` to force one. The chance,
net range and squad spacing are at the top of `Scripts/Modules/RadioModule`.

## Artillery

A radioman can call in the **Random Arty** package's guns. Every 3 seconds he
looks at his target: if it is 70-450 studs away and no one on his net is within
30 studs of it, there is a 35% chance he calls a fire mission on it, then not
again for 90 seconds. The 12 second warning is his squads' time to get clear. The barrage lands centred on the target with the package's usual
warning, scatter and damage.

Every Bloxian near the zone, on either team, then gets as far from it as he can
until the last shell is down: inside the impact radius plus 40 studs he runs
straight out past the edge, and within another 40 studs of that he holds his
ground rather than walk back in. They keep shooting while they move. Shells hurt
Bloxians, so a soldier caught in the zone is in real danger.

Needs Random Arty installed with its new `ServerStorage.ArtilleryFireMission`
(rebuild or re-sync that package). Without it, the first radioman to try warns
in Output and none are ever called.
`Settings.CallArtillery` turns calling off. Numbers are at the top of
`Scripts/Modules/FireSupportModule`.

## Lone guerrilla

A soldier with no squadmates within 60 studs fights alone, hit-and-run.

- He picks the closest player he knows about (seen in the last 60 seconds, or
  within 25 studs) and heads for the nearest ambush spot: one with a clear shot
  at the player that is out of the player's view. That can be his flank, round
  the near end of a wall, or his back; the back is only slightly preferred.
  If the route there stays hidden he walks it, otherwise he moves from hidden
  spot to hidden spot, and if there is no hidden way at all he goes anyway.
  He says nothing while stalking.
- He shoots the moment he can see the player, whatever he is doing.
- Hit and run: he fights from one spot for 4-7 seconds, then slips round to a
  hidden spot on a different side of the player, never more than 12 studs
  further away, waits 2-3.5 seconds and strikes again from the new angle. He
  keeps track of the player the whole time. Lose the angle mid-fight and he
  works round to a new one straight away.
- Spotted, he fights back at any range his gun reaches; with no shot he keeps
  working round to an angle.
- Below 40% health and taking fire he falls back the same way, hiding a little
  longer.
- Within 15 studs he drops the sneaking and goes straight in, pathing round a
  door or corner to get his shot (or his knife), and fights on there instead
  of hitting and running. Looking for an angle never takes him further away.
- Alone, he shouts no callouts at all: contact, reload, grenade, hit or kill.
- Lose track of the player (unseen for 60 seconds) and he goes to where he last
  saw him and looks round for up to 20 seconds before giving up.
- Against NPC enemies, or with no known player around, he fights the normal way.

Turn it off with `Settings.Guerrilla`. Numbers are at the top of
`Scripts/Modules/GuerrillaModule`.

## Vehicles

Bloxians crew any vehicle tagged `BloxianVehicle` (the Warthog and Abrams
packages). A
soldier with an enemy at least 35 studs off and a free seat within 80 studs
claims it, driver first then gunner, walks over and gets in. The driver closes
in and then circles the enemy at about 45 studs; the gunner leads the target
and fires bursts whenever the barrel is on him. Turret fire alerts nearby
soldiers like rifle fire. Within 60 studs of an enemy on foot the driver may go
for him instead of circling, aiming where he is headed and driving through
(always, when there is no gunner); running someone over kills. If the driver
dies, the gunner climbs over and takes the wheel after 3 seconds. They get out
after 20 seconds without an enemy, but never bail: however damaged, they fight
it out and go up with it. Nobody gets into a vehicle below a quarter health. A vehicle with a main gun (the Abrams) also gets HE shells from
its gunner whenever the gun is loaded and on target. Turn it off with
`Settings.UseVehicles`; the numbers are at the top of `Scripts/Modules/VehicleModule`.

**Infantry fight vehicles too.** An enemy sitting in a vehicle is targeted as
the vehicle: soldiers on foot aim at and shoot its hull, and a shot or a look
that reaches any part of it counts. Against an Abrams their rifles do almost
nothing (see `SmallArmsScale` below), but they engage it rather than ignore it.

**Vehicles fight vehicles.** A crew looks for the nearest vehicle crewed by an
enemy (and by no friend) within 350 studs that its gun can see, and engages it
ahead of anyone on foot: the driver closes and circles it, the gunner lays the
machine gun on it and, in an Abrams, the main gun. Hitting the vehicle counts as
hitting its crew. Bullets that hit a vehicle damage the vehicle, scaled by its
`SmallArmsScale` attribute (the Abrams has 0.05, so rifles and machine guns
barely mark it; the Warthog takes them in full). Only a vehicle on the other
side is hurt: one crewed by an enemy (and no friend), or kept to another team.
One crewed by friends, kept to your team, or empty and open to anyone is never
hurt by your fire, so stray rounds cannot wreck a vehicle a soldier wants to take.

## Grenades

Each soldier throws one every 10 seconds at most, at an enemy 15-70 studs away:

- **A group:** two or more enemies within 15 studs of each other, with no ally nearby.
- **Standing still in the open:** an enemy he can see who has stopped moving, 25+ studs out.
- **Behind cover:** an enemy he knows is there (heard or seen in the last 10 s)
  but has not been able to see for 2 seconds. He lobs it over the wall to flush
  him out.

**How a throw is aimed.** He aims at the target's feet and works out real
ballistic arcs under Roblox gravity, flattest first: flight times of 0.6, 0.8,
1.0, 1.2 and 1.45 seconds, the last a high lob that peaks around 45 studs up.
Each arc is traced in 14 straight pieces. An arc only counts if the first thing
it touches is within 7 studs of the aim point; one that clips a wall top, a
ceiling or a ledge on the way is thrown out, because it would bounce off
somewhere useless. He throws the flattest arc that clears. If none does (the
wall is too tall, there is a roof over the target, or it needs a throw faster
than 150 studs a second) he does not throw at all and keeps checking once a
second. The arc is solved again from the grenade's real position the moment it
leaves his hand. The grenade has a dead bounce and high friction, so it stops
where it lands instead of skipping away.

The blast kills anyone within 5 studs. Out to 16 studs it takes up to 80% of
his max health, less the further away he is, so it hurts a 200 HP soldier as
much as a 100 HP player. It never hurts the thrower's own side.

Not while his squad is holding fire. Ranges and timings are `GRENADE_MIN_RANGE`,
`GRENADE_MAX_RANGE` and `FLUSH_DELAY` in `Soldier AI`, and `GRENADE_COOLDOWN`,
`GRENADE_RADIUS`, `GRENADE_KILL_RADIUS`, `GRENADE_WOUND`, `MAX_THROW_SPEED`,
`THROW_FLIGHT_TIMES` and `LANDING_TOLERANCE` in `CombatModule`.

## Sniper teams

`Sniper team` on the spawner drops two soldiers linked by a `PairId`
attribute: a **sniper** with the bolt-action Sniper rifle and a **spotter**
with a Rifle.

- They hold the spot they were dropped on and fight from it. They do not join
  squads, chase, investigate, wander or hit and run.
- The spotter stays within 8 studs of his sniper's shoulder and never goes
  after anyone: he guards the sniper from there, shooting whatever he can reach.
- An enemy inside 40 studs of the sniper is too close to snipe: the sniper
  fights him like a rifleman, then goes back to holding. The spotter stays with him.
- If the sniper dies, the spotter carries on as an ordinary rifleman.
- Both spot enemies out to 600 studs (they raise their `DetectionRange` to
  `SPOT_RANGE`). The sniper fires out to 575; the spotter calls out what he sees.
- Both wear the Dark Grass Camouflage Ghillie set (hood, body, shoulders and
  legs), no helmet and no face accessory (a uniform rule, below).

`Settings.Unit` is `Sniper`, `Spotter` or `Infantry`; the logic is in
`Scripts/Modules/SpecialTeamModule` (`TOO_CLOSE`, `GUARD_LEASH`, `SPOT_RANGE`).

## AT teams

`AT team` on the spawner drops a **rocketeer** with a Javelin and a carbine,
and a **loader** with a rifle and the spare rounds in an Olive Rucksack (a
uniform rule). They hold
their ground like a sniper team: the loader stays at the rocketeer's shoulder
and guards him, and becomes a rifleman if the rocketeer dies.

- Both spot out to 500 studs. The rocketeer fights infantry with his carbine.
- When an enemy-crewed vehicle is in sight between 25 and 500 studs, he slings
  the carbine, swings the Javelin off his back onto his left shoulder (the
  sight comes to his face) with both hands on it, locks on for 1.5 s and fires:
  backblast and kick. The spent launcher drops to the ground and despawns after
  20 s; a fresh one is on his back once he has reloaded. The pose is done in code (`RIGHT_HOLD`, `LEFT_HOLD`,
  `SHOULDER`, `RECOIL` and the timings), so there is no animation to upload.
- The missile climbs and dives onto the vehicle from above, following it as it
  drives. **1600 damage**, armour ignored: one hit wrecks a Warthog (400), two
  wreck an Abrams (3000). Vehicles caught in the blast take a quarter. People
  within 4 studs die; out to 14 they are badly hurt. Friendlies are never hurt.
- Launch sound: `rbxassetid://139048208305901` (`LAUNCH_SOUND`).
- Reload (until the next launcher): 15 s with the loader within 12 studs, 30 s alone.
- Only vehicles with an enemy aboard are fired at, never empty ones.

**The launcher model** is the FGM-148 in `assets/Javelin.rbxm`, served as
`ServerStorage.BloxianJavelin` (the package and both project files include it).
Without it, a launcher built from parts stands in. `MODEL_HOLD` says where on
the model it is held.

Everything is tunable at the top of `Scripts/Modules/JavelinModule`.

## Uniforms

`Scripts/Modules/UniformModule` dresses each soldier by team, unit and role.
Every rule in `uniform.rules` that matches him is applied, top to bottom:

```lua
uniform.rules = {
	{unit = "Sniper", accessories = GHILLIE, helmet = false, face = false},
	{unit = "Spotter", accessories = GHILLIE, helmet = false, face = false},
	{team = "Hostile", unit = "Infantry", shirt = 123, pants = 456},
	{team = "Red", role = "Radioman", accessories = {789}},
}
```

- **Matches on** `team` (`Settings.Team`), `unit` (`Infantry` / `Sniper` /
  `Spotter` / `Rocketeer` / `Loader` / `Pilot`) and `role` (`Rifleman` / `Radioman`). Leave one out to match everyone.
- **Sets** `accessories` (catalog ids), `helmet = false`, `face = false` (no
  random beard, mask or glasses), `remove` (names of other kit to take off),
  `shirt` and `pants`
  (catalog ids of classic clothing), and `offset` (a CFrame to nudge the rule's
  accessories if they sit wrong).
- Each item downloads once per server.
- **Pilots** (`Unit` `Pilot`) are the Apache's crew after they bail out. Their
  rule gives them the aviator helmet and the USAF flight suit, and takes off the
  helmet, comtacs and face accessory. They fight like riflemen with the FAL.
- **Use rigid accessories** (hats, shoulder, front, back and waist items).
  Layered clothing (jackets, sweaters, "suits") cannot stretch over these R6
  bodies; it is worn rigidly on the torso and sits wrong.

## Weapons

Each soldier spawns with one of four guns, rolled again on every respawn. They
differ in how they fire, how they sound and their tracer colour. A fifth, the
**Sniper**, is never rolled; only `Settings.Weapon` or the spawner gives it.

| | Odds | Fires | Damage | Range | Magazine | Feel |
|---|---|---|---|---|---|---|
| **Rifle** | 50% | 3-round bursts close, single shots far | 5-15 | 150 | 30 | the original M4 |
| **DMR** | 20% | single shots, 1.1 s apart | 25-35 | 250 | 15 | slow, accurate, hits hard, deep crack, orange tracer |
| **Carbine** | 20% | 5-round bursts close, 3 far | 4-9 | 90 | 35 | fast and loose, short range, sharp crack |
| **LMG** | 10% | 6-round bursts close, 4 far | 6-12 | 180 | 100 | long bursts, slow reload, red tracer |
| **Sniper** | never | single shots, 2.8 s apart | 80-110 | 575 | 5 | near-perfect aim, very fast round, its own shot sound (asset 130570662564570), white tracer |

**Gun models.** The Rifle, Carbine and LMG show an **FN FAL** and fire its
sound ("FN-FAL [Free]", 154619598); the Sniper shows an **AWP**; the DMR keeps
the original M4 mesh. An **M4A1** (EOTech, suppressor) ships too and can be given
to any weapon in `GunModels`. The
models ship in `assets/guns` (stripped to their visible parts) and are served as
`ServerStorage.BloxianGuns`. Each is welded to the hidden M4, so every hold,
reload and ragdoll still works; the Barrel attachment moves to the new muzzle,
and reloads drop the model's own magazine. Which weapon shows which model, and
each model's scale and placement, are at the top of `Scripts/Modules/GunModels`.

`Settings.Weapon` picks one by name (`Rifle`, `DMR`, `Carbine`, `LMG`, `Sniper`), or
`Random`. The Rifle still reads `MagSize`, `M4.Delay` and `M4.Range`. Every
number, and the odds, are in `Scripts/Modules/WeaponProfiles`. A soldier's gun
shows as a `Weapon` attribute on his model and in the `start:` debug line.

**Aim.** Soldiers lead a moving target by the bullet's actual flight time. Once
the rifle (or the Warthog's turret) is pointing roughly at him, each round goes
at where he will be, thrown off only by the weapon's spread, so a soldier still
swinging round no longer sprays wide. How rough "roughly" is: `AIM_ASSIST` (20°)
in `CombatModule`, `AIM_TOLERANCE` (12°) in `VehicleModule`. Spread is the knob
for how good they are.

## Tuning: `BLOXIAN.Settings`

| | |
|---|---|
| `Team` | his side; see Teams below. Soldiers on the same team never shoot each other, and talk to each other |
| `AttackPlayers` | for a team that is not `Hostile` or a Roblox team: off and he leaves players alone |
| `DetectionRange` | how far he looks for targets |
| `HearingRange` | how far he hears a moving enemy through walls (120). Standing still, half that |
| `AwarenessRange` | how far he senses roughly where an enemy is, through anything (250) |
| `M4.Range`, `M4.Delay` | gun range and seconds between bursts (Rifle) |
| `MagSize` | rounds per magazine (Rifle) |
| `Weapon` | `Random`, or `Rifle` / `DMR` / `Carbine` / `LMG` / `Sniper` |
| `Unit` | `Infantry`, `Sniper` / `Spotter` for a sniper team, or `Rocketeer` / `Loader` for an AT team |
| `Role` | `Random` (10% radioman), or `Radioman` / `Rifleman` |
| `CallArtillery` | radiomen call in Random Arty fire missions |
| `UseVehicles` | soldiers crew nearby vehicles like the Warthog |
| `Wander` | walk around when idle |
| `Respawn`, `RespawnDelay` | respawn a fresh copy this many seconds after death. The ragdolled body lies for 15 s either way (`CORPSE_TIME` in `HumanoidHandler`) |
| `RandomAppearance` | random face, hair and skin on spawn |
| `Chatter` | squad chatter on or off |
| `UseCover` | soldiers take cover, peek and reload behind it |
| `SquadTactics` | squads bound, flank and break contact as fire teams |
| `Guerrilla` | lone soldiers stalk the nearest player and hit and run |
| `Debug` | draws paths, rays and shot markers |
| `PrintDebug` | prints each soldier's decisions to Output: what is steering him, his target, and why he is or isn't firing |

## What's here

| | |
|---|---|
| `Scripts/Server/Soldier AI` | the four loops: search, attack, move, aim |
| `Scripts/Server/HumanoidHandler` | sounds, hurt face, ragdoll, respawn |
| `Scripts/Server/RandomizeAppearance` | random look, assets cached per server |
| `Scripts/Server/Animate` | stock R6 animation script |
| `Scripts/Modules` | `Core` sight and ally checks, `Target` search, `Combat` bullets and grenades, `Actions` weapons and aiming, `Movement` pathing, `Tactics` cover, `Squad` fire team drills, `Guerrilla` lone stalking, `Chatter` squad radio, `SpecialTeam` sniper and AT teams, `Javelin` the AT team's launcher, `GunModels` gun models other than the M4 |
| `BloxianSpawner` | the spawner's server script |
| `Bloxian Spawner` | the tool, with its panel in `SpawnerClient` |

## Changes from the original

Performance
- Line-of-sight raycasts are cached for 0.1 s. Four loops asking about the same target used to cast four rays.
- One workspace scan every 0.5 s is shared between all soldiers, instead of each soldier walking every Workspace child.
- Bullets are pooled and moved by one Heartbeat connection, not a new part, sound, trail and thread per shot. They no longer block each other's rays.
- `slowAdvance`, `strafe` and `retreat` scan with a handful of rays instead of 20 to 60.
- The side-sweep for attackers runs once a second and ignores the soldier's own body.
- Faces only reparent when the mood actually changes.
- A dead soldier's Animate script is switched off, and soldiers that do not respawn skip the spare clone.

Bugs
- Terrain attachments for aiming were never removed, one pair leaked per spawn.
- `pathToLocation` kept walking the old path after re-pathing.
- Several jump-assist threads could run at once.
- Bullets were spawned at the origin and trailed to the barrel, and shot through terrain.
- Grenade damage hit once per limb, and the default blast joint-break killed allies. It now damages once per soldier.
- A shared global (`touched`) could unhook the wrong grenade.
- Reload could hang forever if its animation finished early.
- The hurt face was overwritten a tick after it showed.
- Aiming could produce NaN angles when standing on the target or past 500 studs.
- Sight checks threw on a target destroyed mid-check.
- Debug markers now clean up, and `Name` is set from a string.
- Two reloads could run at once when the gun and the cover routine both asked.
- A burst could drive the magazine below zero.
- A grenade that never touched anything vanished without exploding. It now has a 3 s fuse.
- Bullets froze in mid-air if the soldier was removed while they flew.
- The respawn copy could be cloned with a random face already on it, so respawns stacked accessories.
- Soldiers inside a Folder were invisible to each other's target search.
- Seeing a different enemy wrongly counted as cover being blown.
- Soldiers tracked enemies through walls: anyone within `DetectionRange` was hunted whether
  seen or not. Now an enemy must be seen, heard (within 25 studs) or called out by a
  squadmate, and is forgotten 10 seconds after he was last seen.
- The shot check failed when one ray hit a player's hat and the other his body, so
  soldiers often refused to fire at players wearing accessories.
- A lone soldier never shot back at a player facing him: being seen always sent him
  into hiding.

## Building

```bash
rojo serve default.project.json
```

```bash
rojo build package.project.json -o Bloxian.rbxm
```

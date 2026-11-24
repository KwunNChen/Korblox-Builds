# Bloxian

A soldier NPC. He hunts players and other teams, shoots, reloads, throws
grenades at clusters, knifes anything that gets close, ragdolls when he dies
and respawns. Soldiers on the same team now talk to each other too.

## Install

Soldiers install with [KorbloxAI](../KorbloxAI). To place one by hand, clone
`ServerStorage.BLOXIAN` into Workspace.

## Spawner tool

Everyone gets the **Bloxian Spawner** tool from StarterPack. While it is held:

- **Click the ground** to spawn a group there. The soldiers stand in a wedge
  facing the way you look. A blue or red ring shows where they will land.
- **The panel** on the left picks what spawns. Click a choice in each row:
  - The top tabs pick `Infantry` or `Special Operations` (see below).
  - Spawn: `Soldiers`, `Vehicles` or `Kinetic Events`. `Vehicles` only shows
    when the Vehicle Spawner's server script is installed (see `Vehicle
    Spawner`). It swaps the rows for Vehicle, Team and Crew, and the ring for
    the vehicle's footprint. `Kinetic Events` swaps them for Event (and Side for
    an airstrike), and the ring for the area it covers; see below.
  - Unit: `Infantry`, `Sniper team` (a sniper and his spotter) or `AT team`
    (a Javelin rocketeer and his loader); see below.
    Group, Weapon and Radioman only show for infantry.
  - Group: a soldier, a fire team (4) or a squad (9). A fire team or squad
    also brings an AT team at the back of the wedge, if the server limit
    has room for both of them.
  - Team: `Hostile`, `Friendly`, then every team in the game's Teams service,
    read each time you take the tool out. The ring shows the team's colour.
  - Weapon: `Random`, or one class for everyone in the group.
  - Radioman: `Random` (10% each), `Leader` (the first soldier carries it), or `None`.
  - Uniform: a preset, `Bloxia` for now (see Uniforms below). It shows in
    Vehicles mode too and dresses the crew.
- **Track all** pins a tag over every aircraft and land vehicle in the world,
  through walls (F-4 Phantoms, AC-130s, Apaches, Abrams, Warthogs): team (from
  the crew, else the vehicle's own), what it is, what it's doing, distance and
  health. Soldiers have no tag of their own, crews included: only squads and
  vehicles are tagged.
  - Each sniper team and AT team gets a tag the same way, numbered in spawn order
    (`SNIPER TEAM 1 100%`, `AT TEAM 2 50%`). **Clear all** starts the numbers again.
  - Each spawned squad gets one tag of its own, floating 35 studs over the
    middle of its live soldiers on foot and following them every frame (anyone
    seated in a vehicle still counts but doesn't move it, `SQUAD_TAG_HEIGHT`).
    It shows the NATO unit-size mark for the unit's echelon (Ø fire team,
    ● squad, ●● section, ●●● platoon) in the team's colour, and under it
    the unit's name, echelon and strength (`ALPHA SECTION 80%`), red once
    demoralized. Soldiers that respawn far away, or stream out and back in,
    keep their tag.
  - **A Phantom's status:** Patrol, Intercept, Dogfight, Defending, Break,
    Attack, Strafe, Egress or Leaving.
  - **An AC-130's status:** On station or Fire mission.
  - **A land vehicle's status:** `Crew 1`, `Crew 2` or Empty.
  - **Destroyed:** Down for an aircraft, Wrecked for a land vehicle.
 It stays on with the
  tool put away and through your respawns, until you click it again.
- **Clear all** removes every spawned soldier, or in Vehicles mode every
  vehicle and its crew.

Spawned soldiers do not respawn. At most 60 are alive at once on the server,
and a click spawns at most once a second within 5000 studs of you (`MAX_SPAWN_DISTANCE` in the server script, `CLICK_RANGE` in the tool).

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
and shells. A soldier with a blank team counts as `Hostile` to other Bloxians,
the same as the vehicles' side rules (`Shared/Sides`).

Sight, shots and cover pass through anything a body can walk through (leaves,
trigger zones, a capture point's volume), so a bush neither hides anyone nor
stops a round, and an enemy standing in an objective zone is seen and shot.
They never pass through a body (`core.cast` in `CoreModule`).

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

Soldiers no longer stand in the open and trade shots. Only something solid counts
as cover: a squadmate or anyone else standing in the way never does
(`blockedFrom` in `TacticsModule`).

- **When:** they run for cover whenever the enemy they're fighting can see
  them (shot at or not), and when hurt (under half health), reloading or low on ammo. Depending
  on how cautious each one is, also when outnumbered. Enemies in knife range get
  fought instead.
- **Scrambling:** shot, or seen by the enemy he's fighting, with no cover within 22 studs, he looks further out (30,
  40 and 50 studs, `SCRAMBLE_RINGS`, ignoring his squad's leash) for any wall
  between him and the enemy, and runs for it flat out (`SCRAMBLE_SPEED`), up
  to 10 s (`SCRAMBLE_TIMEOUT`).
- **Off the open:** with no cover at all he still won't fight from the middle of a
  road or field. He runs for the nearest spot with something solid within 5 studs
  (`EDGE_REACH`): a wall, a tree, a car. It searches out to 50 studs (`EDGE_RINGS`),
  at most every 3 s (`EDGE_COOLDOWN`), and skips spots indoors. Holding an angle, a
  spot out in the open counts 15 studs further off (`OPEN_COST`).
- **No cover:** a line soldier in a squad keeps moving with its drills. Anyone else,
  with no wall and no edge in reach, drops prone where he is and
  shoots back. He stays down 6 s (`PRONE_HOLD`), longer while still being hit,
  and stands if he can't see his target from the ground.
- **Shooting:** he keeps his rifle on the enemy and fires while running or
  scrambling for cover. Being shot sends him to cover even if he only just left it.
- **Finding it:** a ring of spots around the soldier is tested. A spot counts
  if a wall within 7 studs blocks the enemy's line to it, it is not walking
  toward the enemy, and a step to the side gives a clear shot. Nearest,
  least exposed spot wins, and two soldiers will not share one. A spot needs 4 studs
  clear round it (`BODY_SIZE`), so nobody is sent into a gap too narrow to walk. A spot with no
  side step to shoot from is only taken when he's hurt.
- **In cover:** he ducks for about a second (0.8 to 1.6 s), reloads once the
  magazine is under 30%, then steps out and shoots for 2.5 to 4 s, and ducks back. Hurt soldiers hide longer
  and peek shorter. If the enemy moves and can see his spot, he finds a new one.
- **Moving between peeks:** after 3 peeks from one spot he moves to a different
  one, so he can't be pre-aimed (`PEEKS_PER_SPOT`).
- **Pinned down:** a Bloxian round passing within 4 studs of the soldier it
  was aimed at pins him for 3 s (kept server-side in `CombatModule`). He
  hides 1.5 times longer, peeks half as long, and shoots 1.5 times wider.
  Out in the open, a near miss sends him for cover the same as a hit does.
  TREK guns tell the server every shot, so a player's round pins him the same
  way, and one passing within 12 studs (out to 500 from the gun) turns him on
  the shooter (`FIRED_AT_*` in `CombatModule`). Other gun systems don't pin anyone.
- **Gas:** he runs out of a TREK gas cloud to 8 studs past its edge
  (`GAS_MARGIN` in `FireSupportModule`), the same way he clears artillery.
- **Aim:** his shots go twice as wide while he is moving faster than 4 studs/s,
  and for 0.6 s after he turns on a new target, so moving and surprise both
  matter (`MOVING_SPREAD`, `NEW_TARGET_SPREAD` in `CombatModule`).
- **Pushing on:** after 12 seconds of cover, healthy and loaded, he moves up
  if his side here is at least as many as the enemies he knows of, but only
  once he has lost sight of the enemy. While he can see him he stays put and
  keeps peeking.
  He calls it out ("Taking cover!", "Moving up!") and squadmates answer.
- **Never idle:** in a fight, a soldier who has neither moved 4 studs nor fired
  for 8 s (`IDLE_*` in `IdleModule`) leaves his spot for the nearest edge of the
  open with a shot at the enemy within 50 studs, else heads for where the enemy
  was, for up to 6 s (`UNSTICK_*` in `Soldier AI`). Snipers, spotters, spec ops, AT
  teams, demoralized squads, a squad rallying or breaking contact, one holding
  fire and one reloading are left alone.

- **Aircraft:** while an enemy F-4, Apache or AC-130 is in the air (20+ studs
  off the ground) within 3000 studs, he reacts to it ("Air! Air! Hide!"), ahead
  of any squad drill, whatever his own side has in the air.
  - **Cover:** he heads indoors first (any ceiling within 40 studs over his
    head), else behind a wall from it. He stays hidden, no peeking, until it
    lands or leaves, but for 8 s at most; then he fights for 12 s before hiding
    again.
  - **No cover, or fighting back:** he never stands still under it. He runs
    25-stud legs across its path and away from it, a new one every 1.5 s, still
    shooting, so a squad scatters.
  - **Tuning:** `AIR_DANGER`, `ROOF_REACH`, `OPEN_SKY_COST`, `AIR_HIDE_MAX`,
    `AIR_FIGHT`, `AIR_EVADE_DISTANCE`, `AIR_EVADE_LEG` in `TacticsModule`.
- **Armor:** everyone but the AT team keeps out of an enemy tank's way, ahead
  of any squad drill: one within 250 studs that can see him sends him into cover
  from it, not peeking. With no cover to reach he runs 60 studs straight away
  from it. He hides for up to 15 s, then fights for 10 s before hiding again.
  The AT team and the F-4s are what kill it (`ARMOR_*` in `TacticsModule`).
- **Knocked over:** soldiers can't be knocked flat by a blast (their Humanoid
  never enters FallingDown), so they always stay on their feet to fight.
- **Fall damage:** landing faster than 85 studs/s (about an 18 stud drop) hurts,
  140 (about 50 studs) or faster kills (`FALL_*` in
  `Scripts/Server/HumanoidHandler`). Parachutes land well under both.

Turn it off with `Settings.UseCover`. All distances and timings are at the top
of `Scripts/Modules/TacticsModule`.

## Long-range firefights

An enemy a soldier is already fighting stays his target, and he keeps shooting,
however far away he gets, as long as there is a clear line between them (out to
2000 studs, `ENGAGED_RANGE` in `Scripts/Modules/CoreModule`). A tree, wall or
rock in the way breaks it. Each round flies 50 studs past the enemy it was
fired at; past his gun's usual range his spread just makes hits rarer. New enemies are still only spotted
within `DetectionRange` (or his gun's range), so this keeps a fight going
rather than starting one across the map.

## Holding angles

Soldiers don't rush. When they lose sight of the enemy, or he's out of range,
they hold an angle on where he was last seen: each picks a spot within 12
studs that can see it, preferring one with something waist-high in front (a
log, rock or wall), turns to face it, rifle up, and waits for him to show. A
sound they can't place gets the same treatment.

- **Pushing in a mass:** they only push (chase, investigate, leave cover after
  12 s, or close in when a squad has no firing spot) with at least 2 of their
  side within 60 studs, none broken, and at least as many as the enemies
  they know of (`MASS_MIN`, `MASS_RANGE`, `MASS_RATIO`). Everyone checks the
  same thing, so a group that has the numbers moves up together ("Moving up!").
- They say so now and then ("Holding this angle!", "Eyes on the treeline!").
- Tunables are at the top of the holding-angles block in
  `Scripts/Modules/TacticsModule`.

## Firing back

A soldier who is shot turns on whoever shot him, at any range he can see him
from. A Bloxian's rounds say who fired them; for a player it's worked out: the
enemy player holding a tool, with a clear line to him, whose body faces him most
squarely. A grenade counts as its thrower's shot; a shell or a fall is nobody's,
so it never sets him on a player. Every friend within 150 studs who isn't already in a firefight with
someone he can see goes after that shooter too ("Find that shooter!"), pushing
toward him for 20 s even without the numbers (snipers and demoralized squads
hold instead). Word spreads: each friend told passes it on to his own friends
within 150 studs, so a whole group strung out across the map learns where the
shooter is, even ones busy with a fight of their own. Numbers are
`ALLY_ALERT_RANGE`, `ALERT_REPEAT`, `HUNT_TIME` and `SHOOTER_FACING` in
`Scripts/Server/Soldier AI`.

## Covered routes

In a fight, a soldier walking more than 40 studs looks at how much of his path
his enemy can see. If it's over 40%, he also works out two routes bent 30 studs
out to either side and takes whichever leaves him in view for the fewest studs,
counting every extra stud walked as a third of a stud in view. Short moves and
straight walks inside 25 studs are left alone. Numbers are `DETOUR_*`,
`EXPOSED_SHARE` and `EXPOSURE_SAMPLES` in `Scripts/Modules/MovementModule`.

**Blocked:** a soldier stuck in place hops and works his path out again. Stuck
3 times running, he goes another way round, through a point 15 studs to one
side of where he's stuck, then on to where he was going. If that side's
blocked too, he tries the other side, and only then gives up and stands
(`MAX_REPATHS`, `SNAG_DETOUR`, `MAX_DETOURS`).

**Indoors:** a soldier drops a crumb every 4 studs and keeps the last 30. With no
path out of a building, or blocked every way round, he walks his crumbs back out
the way he came (`MAX_CRUMBS`, a ceiling within `ROOF_REACH` means indoors). Holding
an angle indoors with no view of it, he heads for the last place he stood outside.
Cover he has had no sight from for 12 s (`COVER_BLIND`) is given up, whatever his orders.

**Roads:** a stud of Asphalt or Pavement counts as 3 on a route (`ROAD_COST`), so
soldiers keep off roads unless it saves real distance.

## Reading the enemy's weapon

A soldier fights a player differently by what's in his hands (`Scripts/Modules/ThreatModule`),
read from the TREK gun config the held tool uses, or guessed from its name. A
Bloxian enemy is read from his `Weapon`.

- **Shotgun or blade** (more than one pellet a shot, or a melee weapon): he
  backs off whenever the enemy is inside 40 studs (`STANDOFF` in
  `Scripts/Server/Soldier AI`) and shoots him from there.
- **Sniper** (a scoped gun that isn't automatic): peeks last half as long
  (`SNIPER_PEEK`), and two soldiers at even odds are enough to rush him instead
  of three at two to one (`SNIPER_MASS_*` in `Scripts/Modules/TacticsModule`).
- **Automatic** (500+ rounds a minute): he hides 1.6x longer between peeks,
  waiting out the bursts (`AUTO_HIDE`).
- He calls it out the first time he sees it ("Shotgun! Don't let him close!",
  "Sniper! Close the distance!", "MG! Stay down!") and squadmates answer.

## Hearing a reload

When an enemy player reloads or heals, soldiers who can see or hear him (within
`HearingRange`) use it. Within 90 studs they call it ("He's reloading, push!")
and push him, whatever the numbers, until the moment passes; snipers still
hold back. Further off, anyone whose magazine is under 70% tops it off.

What gives a player away, as the server sees it: an animation whose name has
"reload" (or "heal", "bandage", "medkit", "inject", "syringe") in it, a sound
by one of those names starting to play in his character or tools, a
`Reloading` or `Healing` attribute set true on his character or tool (for gun
systems that publish one), or his health jumping 15 or more at once. A reload
counts for 2.5 s from the last sign, healing for 3 s. Tunables are at the top of
`Scripts/Modules/OpeningsModule`.

## Last man standing

The last man left of a squad (radio net or not) fights like a lone guerrilla
against players: he goes quiet, works round to an angle the player isn't
watching (his back, if he has to) and ambushes him. If the player keeps turning
to face him and he hasn't had his ambush after 40 s (`STALK_PATIENCE` in
`Scripts/Modules/GuerrillaModule`), he gives up sneaking and comes straight at him.

## Morale

Every soldier has morale, 0 to 100, starting full (`Scripts/Modules/MoraleModule`).

- **Losing it:** a friend dying within 25 studs costs 25, within 70 costs 12.
  Every hit he takes costs 4, and facing 3 or more enemies costs 1 a second.
- **Getting it back:** every kill he makes gives 8. With no enemy in sight he
  recovers 1.5 a second, plus 1 for each steady friend within 30 studs (up to 3).
- **Shaken** (under 60): his shots spread 1.6x wider and he hides 1.6x longer in
  cover. He says so ("They're tearing us apart!") and friends steady him.
- **Broken** (under 25): he shouts "I'm out of here!" and runs about 90 studs
  away from the enemy, only shooting at anyone inside 25 studs. Friends yell
  "Get back here!". Once his morale is back to 50 he rallies ("Okay. I'm
  good.") and fights again.
- The tracker shows SHAKEN or BROKEN after a soldier's job. The `Morale` and
  `MoraleState` attributes hold the numbers.

Every threshold and amount is at the top of the module.

## Patrolling

With `Wander` on and nothing to fight or investigate, a soldier patrols: he
walks legs of up to 150 studs out from where he first went idle, pausing 3 to
8 s between them, and his squad follows him in formation. Tunables at the top
of `Scripts/Server/Soldier AI` (`PATROL_RADIUS`, `PATROL_PAUSE_MIN`,
`PATROL_PAUSE_MAX`, `PATROL_LEG_TIME`). With `Wander` off he holds where he is.

## Prone

Soldiers outside a line squad go prone when caught in the open with no cover (see
Taking cover), and
snipers and spotters lie down on their perch. They stand up to move, ride or use
the knife, and whenever they can't see their target from the ground. They can't
change stance again until 3 s after the last change (`STANCE_COOLDOWN`), except
to get in a vehicle, and move at 60% of whatever speed he has while prone (`PRONE_SPEED`). Their shots
spread a quarter as wide while prone (`PRONE_SPREAD` in `CombatModule`). Prone, a
soldier always has his rifle in his hands: he never slings it. The poses
are done on the joints in code (`STANCES` and `EYE` at the top of
`Scripts/Modules/ActionsModule`); prone soldiers' torso and head go in the
`BloxianProne` collision group so they lie on the ground without pushing off it.

## Squad tactics

Soldiers of the same `Team` within 60 studs of each other fight as a squad,
loosely after US Army / Ranger battle drills. The radioman leads (the spawner's
Leader option makes the first man one), else a rifleman picked at random; an AT
man only once no rifleman is left. The squad splits into two fire teams, Alpha and Bravo.

- **Re-planning:** a squad that has been in a plain fight for 12 s gets a fresh
  plan (`REPLAN_TIME`), so a stalled fight turns into a flank, pincer or bound.
  Other plans run to their end first. Under any plan, the squad breaks contact at
  once when it's losing (below 40% average health, or outnumbered by 2).
- **What comes first:** a vehicle he's crewing, clearing an artillery zone, running
  when broken, hiding from enemy aircraft or armor, and taking cover from a sniper's
  shot all pull a soldier out of the drill until they're over.
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
    Bravo's wedge follows 10 studs behind. A bigger unit adds more wedges behind
    them, 5 soldiers each. Past 9 soldiers, how far it may spread grows with it
    (`LEASH_SQUAD`).
  - *File*: walls within 7 studs on both sides of the leader (corridors,
    doorways) put the squad in single file, 6 studs apart.
  - *Security halt*: when the leader stops for 3 seconds, the squad forms a
    circle at least 7 studs round him covering every direction, wider for a big
    unit (`HALT_GAP`). A rally after breaking contact forms the same circle straight
    away.
- **Hearing:** a soldier hears a moving enemy through walls within
  `HearingRange` (120 studs), or within half that if the enemy is standing
  still. Hearing him counts as spotting him: he goes after him by pathing round
  the walls, and remembers him for 10 seconds after he goes quiet.
- **General awareness:** within `AwarenessRange` (250 studs) a soldier always
  has a rough idea where an enemy is, through any walls. The fix is only good to
  about 20 studs and updates every 4 seconds, so idle soldiers (and squads, in
  formation behind their leader) head for that area to investigate. Awareness
  alone never lets them aim or shoot: that still needs sight or hearing. Lone
  guerrillas and special operations use it to pick who to stalk.
- **Gunfire alerts everyone:** the moment any soldier fires, every ally within
  150 studs learns where the enemy is and engages, chatter on or off. Each
  burst refreshes it, so nobody forgets the enemy while a squadmate is still
  shooting at him.
- **Everyone gets a shot:** a soldier with no cover to fire from steps to the
  nearest edge of the open with a clear shot within 18 studs (`EDGE_NEAR`), then the
  nearest spot with one, or pushes toward the enemy if there is none.
  Cover is only used for laying down fire if it has a spot to shoot out of. In
  a fight the squad leash loosens to 60 studs so they can close in together.
- **React to contact (Battle Drill 1):** everyone gets into the nearest cover
  and returns fire. The spotter calls the contact with a clock position and
  range. After 1.5 s (`REACT_TIME`) the leader picks a plan.
- **Bounding overwatch:** one team rushes up to 22 studs, for at most 5 s, to the
  next cover while the other suppresses from cover, then they swap. With no cover
  ahead he rushes to the edge of the open instead, and flank points move to one
  too. With neither he stays where he is and keeps firing. A team that can't see the enemy from its cover for 6 s moves to a spot with a shot, or pushes on toward him (`OVERWATCH_BLIND`); "Set!" is only called once he gets there. Stops at 30 studs, or after 6 bounds (`MAX_BOUNDS`), and fights.
- **Flank (3+ soldiers, enemy over 18 studs off):** Alpha is the base of fire. Bravo bounds round to a
  point 30 studs off the enemy's side, preferring the side he cannot see, then
  assaults. Alpha shifts fire once Bravo is close.
- **Pincer (4+ soldiers, enemy over 18 studs off, half the time):** Alpha heads round one side and
  Bravo the other, to points 35 studs off the enemy, shooting as they go. A
  team that gets there holds fire (it still shoots back if hit). Once both are
  in place, 6 s after the first one is, or 25 s after the order, the leader
  calls "Both sides, go now!" and both assault at once (`PINCER_*` in
  `Scripts/Modules/SquadModule`).
- **Fight:** with no flank or pincer to run and the enemy inside 30 studs,
  everyone fights on their own.
- **Break contact:** when outnumbered by 2+ or the squad is badly hurt, the
  teams bound backwards 4 times covering each other, then rally on the leader
  for 15 s (`BREAK_BOUNDS`, `RALLY_TIME`). Special Recon, stalking nobody, breaks
  contact from any fight it ends up in as a squad.
- Every step is called out ("Bravo, flank left!", "I'm up!", "Set!",
  "Shift fire!", "Rally on me!") and answered.

### Squad strength

Every infantry group of 2 or more from the spawner is a named unit, in NATO
alphabet order (Alpha, Bravo, ... Zulu, then Alpha again, skipping any name a
living unit still has), set on its soldiers as the `SquadId`, `SquadName` and
`SquadSize` attributes, and it stays one squad (it doesn't mix with other squads
that walk near it). Its strength is how many are alive against how many it
spawned with, shown as `SquadStrength` (percent) and `SquadAlive`. A respawned
soldier comes back to his squad.

- **75% and up, cohesive:** every drill, pincer and flank included.
- **Under 75%:** the fire teams stop manoeuvring together: bounding, fighting
  and breaking contact only, no flanks or pincers.
- **Under 30%, demoralized:** the squad stops pushing. It fights where it is,
  holds angles and leaves the attacking to fire support, though it still breaks
  contact when losing. `Demoralized` is set on its soldiers. Special operations
  ignore all of this.
- **Morale:** a soldier out of the fight only recovers morale up to his squad's
  strength (never below 50), so a shot-up squad stays shaken.
- **Spawning on top:** infantry spawned within 30 studs of a living infantry unit
  of their team join it instead of forming their own (`UNIT_JOIN_RANGE`). The AT
  team a group brings stays its own unit, but moves with the group.
- **Merging:** under 20%, or down to his last man, a soldier with no target
  joins the nearest friendly squad of his own kind (infantry or special
  operations) within 150 studs that is bigger than his. That can take a squad
  over 100%. Neither splits nor merges in a unit's first 5 s (`SPAWN_SETTLE`).
- **Echelons:** a unit is a Fire team (1-5 alive, Ø), Squad (6-12, ●), Section
  (13-24, ●●) or Platoon (25+, ●●●), shown as `SquadEchelon`. It moves up as
  merges grow it and never moves back down: once a Section or Platoon falls
  below its minimum it splits in two ("We're spread too thin, split up!"). The
  half nearer the soldier who noticed keeps the name as number 1; the other half
  gets the same name and the next number: Foxtrot Section becomes Foxtrot Squad 1
  and Foxtrot Squad 2, and a later Foxtrot split makes Foxtrot 3. Each half's size
  is its share of the old one, so their strength carries over. Squads and fire
  teams don't split.

Turn it off with `Settings.SquadTactics`. Numbers are at the top of
`Scripts/Modules/SquadModule`.

## Radiomen and platoons

About one soldier in ten spawns as a **radioman**, wearing the `Radioman` morph.
Every soldier of his team within 300 studs of him is on his radio
net, whatever squad they are in.

- **Contacts carry across the net.** Anything one soldier spots or fires at,
  every squad on the net learns about and engages, not just the ones in earshot.
- **Squads link into a platoon.** The radioman's squad leads. Every other squad
  leader on the net takes a slot in a wedge of squads behind it, 30 studs apart,
  facing the way the lead squad walks, and his men follow him in their own
  formation. A soldier with no squad of his own joins as a squad of one, and
  nobody on a net fights as a lone guerrilla.

**Calling for help** needs no radioman. When a regular infantryman is attacked,
every other unit on his side hears where the attacker is, at most every 5 s per
attacker (`UNIT_CALL_INTERVAL`). Those within 2000 studs of him go after him
unless busy with someone in sight ("Unit's under attack, moving to support!");
further off they drop him at once (`ENGAGED_RANGE` in `CoreModule`). Special Recon
only notes where he is.

`Settings.Role` is `Random`, or `Radioman` / `Rifleman` to force one. The chance,
net range and squad spacing are at the top of `Scripts/Modules/RadioModule`.

## Kinetic Events

Radiomen no longer call artillery or air. Both come from the spawner's **Kinetic
Events** tab: pick an event and click the ground, at most every 10 s per player
(`KINETIC_COOLDOWN` in `BloxianSpawner`).

- **Artillery:** one **Random Arty** barrage centred on the click, with the
  package's usual 12 s warning, scatter and damage. It hits everyone, so it has
  no side. If the guns are already firing, the panel says so.
- **Airstrike:** an F-4 Phantom of the chosen **Side**, from
  `ServerStorage.BloxianVehicles`. It appears 650 studs up, 800 studs off and
  attacks only infantry (soldiers and players on foot, never vehicles or
  aircraft), those within 150 studs of the click first. After 3 strafes, or
  once nobody is left to attack, it flies out of the map, unless shot down
  first (`STRIKE_*` in `BloxianSpawner`).

### Clearing a barrage

Nobody hears the call: soldiers stay put until the shells are seen coming in,
4 s before the first one lands (`SHELLS_SEEN_AT` in `BloxianSpawner`).

Soldiers inside the impact zone (plus 40 studs) run straight out, ignoring
everything else. Each picks his spot past the edge once, on the ground, and
keeps it for the whole run. If there is no path to it (a building, water, a
cliff), he turns to the next of the angles in `ESCAPE_TURNS` (up to 110° off
straight out). While running he takes the shortest path out, not the one most
hidden from the enemy. Just outside it they hold where they are rather than walk back
in, but still shoot, and still dive for cover from aircraft or out of a
vehicle's path. Near a barrage, on either side of it, a soldier keeps every
enemy he knew of in mind where he last saw them, so he picks the fight back up
once it lifts (`EVAC_MARGIN`, `HOLD_BAND` in `Scripts/Modules/FireSupportModule`).

A spawned **AC-130** is separate: it picks its own targets and fires its own
barrages with no warning (see the AC130 README), and soldiers get no chance to
clear out of those.

Every Bloxian near the zone, on either team, then gets as far from it as he can
until the last shell is down: inside the impact radius plus 40 studs he runs
straight out past the edge, and within another 40 studs of that he holds his
ground rather than walk back in. They keep shooting while they move. Shells hurt
Bloxians, so a soldier caught in the zone is in real danger.

Numbers are at the top of `Scripts/Modules/FireSupportModule`.

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
dies, the gunner climbs over and takes the wheel after 3 seconds (not in a
vehicle spawned gunner-only, with the `GunnerOnly` attribute, where he stays on the gun). They get out
after 20 seconds without an enemy, but never bail: however damaged, they fight
it out and go up with it. A crew spawned with its vehicle stays in, and with
no enemy the driver keeps up with the nearest friendly soldier on foot within
250 studs (stopping about 25 studs off him), or patrols legs up to 150 studs
out when nobody is near. Any soldier on foot in the path of a ground vehicle
doing over 8 studs/s that would reach him within 2.5 seconds, friend or foe,
drops what he is doing and runs about 15 studs clear of its side. Nobody gets into a vehicle below a quarter health. A vehicle with a main gun (the Abrams) also gets HE shells from
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

**Support vehicles.** One with the `Support` attribute (the AA truck) is crewed
only by the crew spawned with it. Its driver never goes after the enemy or rams:
he keeps with the nearest friendly infantry, or patrols. Its launcher does the
fighting.

**Riding on tanks.** A vehicle with `RiderSeat` seats (the Abrams has four on
its turret roof) carries infantry.
- **Climbing on:** an `Infantry` soldier with no enemy for 8 s walks to one
  within 60 studs that has a friendly driver, and climbs up from the side of the
  hull. Snipers, spotters and AT teams stay on foot.
- **Riding:** the driver carries on as usual, keeping up with whoever is still on
  foot or patrolling, so a squad that is all aboard goes out on patrol.
- **Into a fight:** riders stay on while the enemy is still far off, shooting
  from the roof as the tank closes in.
- **Jumping off:** once an enemy is within 80 studs, a missile is coming in, the
  smoke goes up, the tank loses 10% of its health in one go (an AT round; rifle
  fire doesn't count), the driver is lost, or after 120 s with no enemy. He stays
  off for 20 s afterwards. The driver and gunner never get out for any of this.
- **Exposed:** riders are not protected like the crew. They can be shot, and a
  tank that goes up throws them into its blast.
- **Tuning:** `RIDE_RANGE`, `RIDE_CALM`, `RIDE_DISMOUNT_DISTANCE`, `RIDE_HIT_SHARE`,
  `RIDE_MAX`, `RIDE_COOLDOWN` in `VehicleModule`.

**Smoke.** Nobody sees through a tank's smoke screen (anything tagged
`SmokeScreen`): soldiers lose sight of what is behind it, and a gunner neither
spots nor fires through it. When his tank's smoke goes up, the driver backs
straight out for 4 s (`SMOKE_REVERSE_TIME`).

## Grenades

Each soldier throws one every 20 seconds at most, at an enemy 15-70 studs away:

- **A group:** two or more enemies within 15 studs of each other, with no ally nearby.
- **Standing still in the open:** an enemy he can see who has stopped moving, 25+ studs out.
- **Behind cover:** an enemy he knows is there (heard or seen in the last 10 s)
  but has not been able to see for 2 seconds. He lobs it over the wall to flush
  him out.

**How a throw is aimed.** He aims at the target's feet and works out real
ballistic arcs under Roblox gravity, flattest first: flight times of 0.6, 0.8,
1.0, 1.2 and 1.45 seconds, the last a high lob that peaks around 45 studs up.
Each arc is traced in 14 straight pieces, 0.6 studs wide either side of its middle
(`GRENADE_CLEARANCE`), starting from his chest up to his hand, so a roof or beam
right over him counts. An arc only counts if the first thing
it touches is within 7 studs of the aim point; one that clips a wall top, a
ceiling or a ledge on the way is thrown out, because it would bounce off
somewhere useless. He throws the flattest arc that clears. If none does (the
wall is too tall, there is a roof over the target, or it needs a throw faster
than 150 studs a second) he does not throw at all and keeps checking once a
second. The arc is solved again from his release point the moment it leaves his hand,
and if it no longer clears he keeps the grenade. The grenade has a dead bounce and high friction, so it stops
where it lands instead of skipping away.

The blast kills anyone within 5 studs. Out to 16 studs it takes up to 80% of
his max health, less the further away he is, so it hurts a 200 HP soldier as
much as a 100 HP player. It never hurts the thrower's own side, and never
anyone it has no clear line to (torso or head) from where it lies: a wall,
floor or crate between them stops it. A soldier killed mid-throw takes the
grenade down with him, unexploded. A vehicle takes 80 damage at the burst
(less further out), cut by its armour against small arms (`GRENADE_VEHICLE_DAMAGE`):
it scratches an Abrams and hurts a Warthog. M203 rounds are the same.

Not while his squad is holding fire. Ranges and timings are `GRENADE_MIN_RANGE`,
`GRENADE_MAX_RANGE` and `FLUSH_DELAY` in `Soldier AI`, and `GRENADE_COOLDOWN`,
`GRENADE_RADIUS`, `GRENADE_KILL_RADIUS`, `GRENADE_WOUND`, `MAX_THROW_SPEED`,
`THROW_FLIGHT_TIMES`, `GRENADE_CLEARANCE` and `LANDING_TOLERANCE` in `CombatModule`.

**Dodging:** the moment an enemy Bloxian lets go of a grenade, everyone it would
land within 16 studs of shouts ("Grenade!"), leaves his cover and sprints 20 studs
straight away from where it will land (`GRENADE_RUN` in `Soldier AI`). Players'
grenades aren't seen; they aren't Bloxian code.

## Special operations

Special operations only talk in clipped, tactical radio speak ("Tango, 2 o'clock,
80.", "Dry. Cover.", "Displacing.") from their own set, `ChatterSof`, and never
make small talk or mutter to themselves. Answering a line soldier, they use their
own replies, not his.

The `Special Operations` tab spawns a special operations unit, named with four
random digits. Size: a **Recce** (a radioman and a rifleman) or a **Fireteam** (a
radioman, two riflemen and a shotgunner). The tracker shows one tag over the middle of the unit
("4821 SOF FIRETEAM", "4821 RECCE"); its soldiers get no tag each. They wear the `SpecOps` morph, and:

- lose no morale: never shaken, broken or demoralized, and a soldier near them
  recovers his nerve as fast as with three steady friends;
- fire with 30% of a line soldier's spread, from suppressed rifles heard out to
  35% of the usual distance;
- patrol on their own until they sense a player within 300 studs, through
  anything, or see or hear one within 800, then stalk him one by one
  (`SOF_DETECT_RADIUS` and `SOF_STALK_RANGE` in `GuerrillaModule`);
- a fireteam down to half its men or fewer is relabelled a Recce ("4821 RECCE",
  `RECCE_SHARE` in `SquadModule`). They only merge with other special operations
  remnants.

An enemy sniper, Bloxian or player, is the exception: they ignore the ring and
work toward him at a run from cover to cover without pausing, and open fire within 150 studs
with a clear line (`SNIPER_RANGE` in `SofModule`).

**Special Recon** (rifles and a Benelli M4 shotgun) works like Air Force Special
Reconnaissance: get eyes on, stay unseen, report, and break contact rather than
fight. It sees out to 400 studs and follows you from cover to cover, rifle up. With
a line to you from 120 to 250 studs (`OBSERVE_MIN`, `OBSERVE_MAX` in `SofModule`) it
stops, goes prone and watches, reporting you over the radio. It picks spots behind something at least 10 studs wide, such as
a building, and only uses thinner cover like a tree with none in reach
(`COVER_WIDTH` and `COVER_REACH` in `TacticsModule`). Caught in the open it runs
at 20 studs/s for the nearest cover up to 140 studs off, no closer to you than
30 studs (`COVER_HOPS` and `COVER_MIN_DISTANCE` in `GuerrillaModule`). It stays
120 studs out, and backs off when you come closer (`STALK_RING`). It is compromised for
5 s, the whole unit together, when anyone in it is hit or fired at (a round
passing within 12 studs, hit or miss), or when it has a clear line to you within
30 studs, or within 60 with you not turned away from it (`ENGAGE_*` and
`FIRED_AT_*` in `SofModule`). For 20 s after that, any enemy it can see keeps it
compromised at any range (`COMPROMISED_TIME`), so it doesn't go quiet on someone who
just shot it. With your back turned it keeps stalking, aimed at
you whenever it can see you, so it's already on target when it fires. Compromised,
it breaks contact ("We're compromised, break contact!"): it runs from cover to
cover, each hop at least 15 studs further from you (`BREAK_GAIN`), shooting as it
goes, stops firing when you stop, then finds a new post. With no
sight of you for 8 s, in a building say, or told about you over the radio, it
works toward you the same way, ring or not, until it has one. It pauses in cover
between hops and runs for the next one if it's seen. With no cover in reach it
moves 50 studs at a time (`HUNT_AFTER`, `COVER_HOP_COST` and `HUNT_STEP` in
`GuerrillaModule`). Enemy
special operations and snipers it can see are fired on at once, at any range. Fired at, he also turns on the shooter. Every player one of them is stalking, seen or not, is
reported at most every 8 s per unit: a soldier of the unit says so over the radio, heard and read out to 150 studs even while stalking: a
burst of radio chatter, and a line with where you are ("Hostile at grid 503-498,
80 studs northeast of me, over."; `RADIO_*` and `GRID_SIZE` in `ChatterModule`):
every friendly soldier within 1500 studs who isn't already fighting goes after
him ("Recon's got a target for us, move!"). It never brings in aircraft.

**Special operations radiomen** relay enemy players to each other. A radioman
who is stalking an enemy player passes his position to every special operations
radioman on his side, at most every 5 s per player (`RELAY_INTERVAL`), and each
of their squads hears it ("Net's got a position, move!"). Those within 2000 studs
of him then know where he is and stalk him (`ENGAGED_RANGE` in `CoreModule`).
Without a radioman alive, a squad hears nothing.

Like everyone but the AT team, they keep out of a tank's sight: an enemy vehicle within 250 studs that
can see them sends them into cover from it, not peeking, for up to 15 s, then
they fight for 10 s before hiding from armor again (`ARMOR_*` in
`TacticsModule`). The AT team and the F-4s are what kill it.

Caught in a fight with no cover in reach and the enemy in sight, they
drop prone and fight from the ground instead of standing in the open.

The shotgun fires 8 pellets out to 50 studs (`Shotgun` in `WeaponProfiles`). His aim error moves the whole shot, then the pellets fan out `pelletSpread` (4°) around it. Shotgunners keep the Benelli under every uniform preset.

Numbers are at the top of `Scripts/Modules/SofModule` (`SOF_SPREAD`,
`SUPPRESSED_HEARING`, `RECON_DETECTION`, `REPORT_RANGE`, `RADIO_INTERVAL`),
`SOF_ECHELONS` in `SquadModule` and `SOF_STEADY` in `MoraleModule`.

## Sniper teams

`Sniper team` on the spawner drops two soldiers linked by a `PairId`
attribute: a **sniper** with the bolt-action Sniper rifle and a **spotter**
with a Rifle.

- **Perch:** as soon as he is dropped, the sniper scans up to 115 studs around
  for higher ground with cover close around him (walls, rocks, foliage, a roof
  overhead) and at least two open lines of sight. He walks to the best spot he
  has a path to (giving up after 40 s) and holds it. With nothing better
  around, he holds where he was dropped. They do not join squads, chase,
  investigate, wander or hit and run.
- **Prone:** on his perch the sniper lies down facing the way his view out is
  widest (away from the wall he hides by), and the spotter lies beside him
  looking the same way.
  If his target can't be seen from the ground he stands instead, and if lying
  down puts the ground or a ledge between his barrel and the target, he gets up
  and stays up 10 s (`PRONE_BLOCKED_WAIT` in `Scripts/Modules/ActionsModule`).
- **Accuracy:** the sniper's round always goes at his target (plus the rifle's
  0.08 degree spread), from the rifle's real muzzle, however his pose has the
  rifle pointing (`aimAssist` in `Scripts/Modules/WeaponProfiles`).
- **Relocating:** after 3 shots from one perch (`SHOTS_BEFORE_MOVE`), or as
  soon as he's hit there, he calls "Relocating!" and moves to another perch at
  least 25 studs away (`RELOCATE_MIN`). The spotter goes with him.
- **Keeping a shot:** a perch needs at least 3 of 8 directions open for 80
  studs from low eye height (`MIN_VIEWS`, `VIEW_REACH`), so the cover he hides
  in doesn't blind him.
- **Facing the enemy:** a perch scores for every enemy he knows of that it
  overlooks (up to 6 checked), and none within 100 studs of a known enemy is
  taken, so he sets up at a distance looking at the fight, not beside it
  (`ENEMY_SIGHT_WEIGHT`, `PERCH_STANDOFF`, `SIGHT_CHECKS`). If his target is in range but he hasn't had a line to it for 3 s
  (`BLIND_TIME`), he calls it and moves to a perch that sees it, preferring
  one that sees it from low down. When he relocates under fire, the new perch must
  see his target too. If no perch around has a shot, he tries again after 15 s.
- The spotter stays within 8 studs of his sniper's shoulder and never goes
  after anyone: he guards the sniper from there, shooting only what is within
  his own rifle's range. Anything further is left to the sniper.
- An enemy inside 40 studs of the sniper is too close to snipe: the sniper
  fights him like a rifleman, then goes back to his perch. The spotter stays with him.
- **Never pushing:** whatever the numbers around them, the sniper and spotter
  never chase, close in or stalk. An enemy who drops out of sight gets an angle
  held on where he was (`NEVER_PUSH` in `Scripts/Modules/TacticsModule`).
- If the sniper dies, the spotter carries on as an ordinary rifleman.
- If the spotter dies, half the sniper's shots go wide and his range drops by 200
  studs, to 375, until a spotter of his pair is back (`NO_SPOTTER_*` in
  `SpecialTeamModule`). He still spots out to 600.
- **The shot gives him away:** it carries 1000 studs. Past 150 studs from him
  (`ECHO_CLOSE` in `CombatModule`) players hear a distant rifle shot (asset
  18156809081) from where he fired, fading out with distance (`echo` in
  `WeaponProfiles`, `ECHO_RANGE` in `CombatModule`). Enemy soldiers in that range react:
  - **Most soldiers** not busy with someone in sight take cover from it, not
    peeking, for up to 8 s, then ignore it for 12 s (`ECHO_*` in `TacticsModule`).
  - **Special operations** hunt him the way they stalk a player, out to 800
    studs, unless already on a player, and fire on him at sight.
  - **Snipers** within their own range drop other targets for 20 s (`COUNTER_TIME`)
    and move to a perch with a line to him, unless an enemy is inside 40 studs.
- Both spot enemies out to 600 studs (they raise their `DetectionRange` to
  `SPOT_RANGE`). The sniper fires out to 575; the spotter calls out what he sees.
- Both wear the `Sniper` morph (see Uniforms below).

`Settings.Unit` is `Sniper`, `Spotter` or `Infantry`; the logic is in
`Scripts/Modules/SpecialTeamModule` (`TOO_CLOSE`, `GUARD_LEASH`, `SPOT_RANGE`,
and the perch search: `PERCH_RINGS`, `PERCH_MAX_CLIMB`, the `*_WEIGHT` scores,
`MIN_VIEWS`, `PERCH_TIMEOUT`).

## AT teams

`AT team` on the spawner drops a **rocketeer** with a Javelin and a carbine,
and a **loader** with a rifle and the spare rounds. On its own the loader stays at the
rocketeer's shoulder and guards him; if the rocketeer dies he fights on as a rifleman.

The AT team a group brings is part of that squad: same squad id, counted in its
size and strength. Both men move in its wedge, take cover, bound, flank and
break contact with it by the same drills, and merge or split with it. The
rocketeer only stops to fire the Javelin, wherever the squad has him; the
squad can't move him mid-launch. It never goes off hunting. Its men only lead
the squad once no rifleman is left. Since the loader moves in the wedge rather
than at his shoulder, he speeds up the reload from anywhere within 30 studs
(`SQUAD_LOADER_RANGE` in `JavelinModule`). An AT team spawned by itself hunts and patrols on
its own as below.

- **Armor first:** the rocketeer fires on enemy vehicles on the ground before
  aircraft; he only takes an Apache when there is no armor in sight and range.
- **Under enemy aircraft:** AT teams don't hide or scatter like other soldiers.
  They keep hunting armor (`AIR_IGNORE_UNITS` in `TacticsModule`).

- **Calling in AT:** any other soldier who sees an enemy vehicle shouts it
  ("Armor, two o'clock! Get AT on it!", or "Take cover!" when his side has no
  AT team within range) and reports it to his side. A vehicle is called out at
  most every 40 s (`CALL_AGAIN`); a report goes stale after 45 s without anyone
  seeing it (`REPORT_MEMORY`).
- **Hunting:** with a launcher ready and nobody to fight, the rocketeer takes
  the nearest fresh report within 1000 studs (`HUNT_RANGE`), says "AT moving!"
  (his loader answers) and walks toward it. He stops as soon as he has it in
  sight within 500 studs to fire, and never walks closer than 50. Firing, he
  shouts "Javelin out!".
- **Patrol:** with no enemy vehicle about, he patrols legs up to 150 studs from
  where he was dropped (`PATROL_RADIUS`), pausing 3 to 6 s between legs.
- While reloading he stands still with his loader. An infantry target in sight
  also stops him to fight it with the carbine.

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
- Launch sound: `rbxassetid://112204190873336` (`LAUNCH_SOUND`).
- Reload (until the next launcher): 15 s with the loader within 12 studs (30 in a squad), 30 s alone.
- Only vehicles with an enemy aboard are fired at, never empty ones.
- **Smoke beats it:**
  - **The warning:** the moment he starts locking on, the vehicle is told a
    missile is coming (`MissileInbound` and `ThreatAt`), so an Abrams pops smoke
    toward him.
  - **During the lock:** smoke between him and the target breaks the lock.
  - **In flight:** a missile that loses sight of the vehicle in smoke flies on to
    where it last saw it, and only hurts the vehicle if it is still there.
- **Aircraft too:** an enemy Apache (anything tagged `BloxianAircraft`) in
  sight and range gets the same lock and missile, which follows it through the
  air. 1600 damage (`AIRCRAFT_DAMAGE`) against its 1500 health: one hit.

**The launcher model** is the FGM-148 in `assets/Javelin.rbxm`, served as
`ServerStorage.BloxianJavelin` (the package and both project files include it).
Without it, a launcher built from parts stands in. `MODEL_HOLD` says where on
the model it is held.

Everything is tunable at the top of `Scripts/Modules/JavelinModule`.

## Uniforms

**Presets:** the panel's Uniform row picks a preset for everything you spawn
next; soldiers already out keep what they wear. Soldiers placed by hand or
bailing out wear `Bloxia`. Every preset dresses everyone from the morphs in
`ServerStorage.BloxiaMorphs` (`assets/morphs`).

**Bloxia:**

| Morph | Worn by |
| --- | --- |
| `Infantry` | riflemen, AT teams, pilots, vehicle crews |
| `Radioman` | line radiomen (the radio is part of the morph) |
| `Sniper` | snipers and spotters |
| `SpecOps` | Special Recon |

**Korblox:**

| Morph | Worn by |
| --- | --- |
| `KorbloxInfantry` | everyone but line radiomen: the regulars' uniform, helmet, NVGs, rig and pack |
| `KorbloxRadioman` | line radiomen: the irregulars' kit, with Bloxia's radio on his back in place of the pack |

Korblox riflemen (Rifle, Carbine) carry the FN FAL with its bayonet
(`assets/guns/FNFAL.rbxm`). The sniper team (snipers and spotters) and DMR
shooters carry the KZW-A-4 bolt-action (`assets/guns/KZW-A-4.rbxm`). A gun
preset is looked up by unit first, then by weapon, so the spotter's rifle shows
as the KZW-A-4 too. Only the look changes; the weapon's numbers stay the same.

**KorbloxNaval** (Korblox Naval Infantry, the panel's "Naval"):

| Morph | Worn by |
| --- | --- |
| `NavalRaider` | riflemen, AT teams, pilots, vehicle crews: helmet, ski mask, scarf, flare bag |
| `NavalRaiderVest` | line radiomen, the sniper team and Special Recon: helmet, goggles, ski mask, vest, belt |

Every Naval soldier carries the naval rifle with wooden furniture
(`assets/guns/NavalRifle.rbxm`), whatever his weapon. Only the look changes; the
weapon's numbers stay the same. Naval radiomen have no radio on their back.

Bloxia soldiers with a Rifle, Carbine or DMR carry the AR-18 with its 3x20
optic (`assets/guns/AR18.rbxm`, `gunModels.presets` in `GunModels`). It only
changes the look; the weapon's numbers stay the same.

A morph is a rig: its `Shirt`, `Pants` and every part that isn't its body go on
him, each piece where it sits on the morph's body. To add a preset, give it
rules in `uniform.presets` in `Scripts/Modules/UniformModule` and add its name
to the Uniform row in `SpawnerClient`:

```lua
uniform.presets = {
	Bloxia = {{unit = "Infantry", role = "Rifleman", morph = "Infantry"}, ...},
	Desert = {{morph = "Desert"}},
}
```

- **Matches on** `unit` (`Infantry` / `Sniper` / `Spotter` / `Rocketeer` /
  `Loader` / `Pilot` / `Special Recon`) and `role` (`Rifleman` /
  `Radioman`). Leave one out to match everyone.
- **Pilots** (`Unit` `Pilot`) are the Apache's crew after they bail out. They
  fight like riflemen with the FAL. On the ground, a pilot joins the nearest
  friendly unit from the spawner within 1500 studs and walks over to it ("Pilot
  on foot, moving to you!"), then fights as one of its riflemen (`JOIN_RANGE` in
  `Scripts/Modules/SquadModule`).

## Weapons

Rifles and vehicle machine guns are hitscan: a round hits the instant it is fired,
so nobody leads a target. Every 7th round per soldier is also drawn as a tracer,
with a casing (`TRACER_EVERY` in `CombatModule`). `SPREAD_SCALE` there scales every
weapon's spread. A soldier with no enemy in sight runs at full speed, rifle up.

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

**Gun models.** The Rifle, Carbine and DMR show an **AR-18** in the Bloxia preset
and fire its sound (680741924, the DMR pitched down and the Carbine up). The LMG
shows an **M249** (asset 17747401068, its ammo box as the magazine) and fires a
machine gun sound (111337931044928); the Shotgun fires 132711300701696; the Sniper
shows an **AWP**. An **M4A1** (EOTech, suppressor) ships too and can be given
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

## Walk speed

Every module sets a soldier's speed through `SpeedModule`, never on the Humanoid.
With `ServerScriptService.Common.SpeedService` in the place (Random Arty, Ski and
Variable Snowstorm ship it) his own speed is its base, so a storm or an artillery
concussion slows him on top of whatever he is doing instead of being written over.

## Footsteps

Conventional infantry are loudest (volume 0.4), special operations quietest
(0.05), everyone else 0.2 (`STEP_VOLUME`, `STEP_VOLUME_BY_UNIT` in
`Scripts/Server/HumanoidHandler`). It only changes what players hear; soldiers
hear each other by distance, not volume.

## Leaning

Soldiers lean into the way they walk, and turn their legs toward a sideways
step, like players with the DirectionTilting script (`Scripts/Client/BloxianLean`,
a copy of which the first soldier puts in ReplicatedStorage). Each client draws
it for soldiers within 300 studs of its camera, so it costs the server nothing.
It sits on top of aiming and is off while a soldier lies prone, sits or is dead.
Numbers are at the top of the script (`LEAN_DISTANCE`, `RANGE_OF_MOTION`,
`MOMENTUM_FACTOR`).

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
| `UseVehicles` | soldiers crew nearby vehicles like the Warthog |
| `Wander` | patrol around when idle (see Patrolling) |
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
| `Scripts/Client/BloxianEffects` | tracers, casings and impact chunks, drawn on each client |
| `Scripts/Modules` | `Core` sight and ally checks, `Target` search, `Combat` bullets and grenades, `Actions` weapons and aiming, `Movement` pathing, `Tactics` cover, `Squad` fire team drills, `Guerrilla` lone stalking, `Chatter` squad radio, `SpecialTeam` sniper and AT teams, `Javelin` the AT team's launcher, `GunModels` gun models other than the M4 |
| `BloxianSpawner` | the spawner's server script |
| `Bloxian Spawner` | the tool, with its panel in `SpawnerClient` |

## Changes from the original

Performance
- Line-of-sight raycasts are cached for 0.1 s. Four loops asking about the same target used to cast four rays.
- One workspace scan every 0.5 s is shared between all soldiers, instead of each soldier walking every Workspace child.
- The server keeps rounds as a position and heading, moved by one Heartbeat connection, and only sends each round once to the clients. Tracers, spent casings and kicked-up chunks are drawn on each client by `Scripts/Client/BloxianEffects`, which the first soldier copies into ReplicatedStorage. Clients skip tracers over 1200 studs from the camera and casings or chunks over 200, and keep at most 60 casings (tunables at the top of the script).
- `strafe` and `retreat` scan with a handful of rays instead of 20 to 60.
- The check for attackers walking up on a soldier runs once a second, raycasting only to enemies within 20 studs (it used to cast 21 rays).
- Whether a group has the numbers to push is worked out at most every 0.5 s.
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
cd ../KorbloxAI && rojo build package.project.json -o KorbloxAI.rbxm
```

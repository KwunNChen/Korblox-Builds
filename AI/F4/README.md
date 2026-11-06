# F4

An F-4 Phantom that flies itself. Its job is air superiority first, then close
air support. It has no crew but its pilot, who ejects when it's shot down.
Spawn one from the Bloxian Spawner's Vehicles mode, or place it by hand.

## Install

Put the model in `ServerStorage.BloxianVehicles` as `F4 Phantom`. The root
project syncs it there. From the Vehicle Spawner it appears 300 studs up
(`Settings.Height`) and has no Crew choice. Its ejecting pilot needs
`ServerStorage.BLOXIAN` (the Bloxian package).

## Whose side

`Settings.Team`: blank (the spawner's `Any`) counts as Friendly.

- **Friendly:** fights Bloxians of other teams, never players.
- **Hostile:** fights everyone.
- **A Roblox team's name:** sides with that team's players.

## Air superiority first

It hunts every enemy aircraft on the map, however far: AC-130s, Phantoms on
another side, and enemy-crewed Apaches. In combat it flies at 400 studs/s,
turns at 110°/s and climbs or dives at up to 220 studs/s. Cruising, those are
260, 55° and 120.

**Near the players:** with `FOLLOW_PLAYERS` on (the default), its station is
its own spot 800 to 2500 studs off the middle of the live players, in a random
direction picked when it spawns (`STATION_SPREAD_MIN`, `STATION_SPREAD_MAX`),
not where it was spawned. Each Phantom patrols its own spot, so dogfights break
out across the map instead of all over the players.

- **Altitude:** against another jet it fights between 700 and 1300 studs above
  the ground (`DOGFIGHT_FLOOR`, `DOGFIGHT_CEILING`), breaks included. Chasing a
  helicopter it climbs no higher than 1300 and dives down to it. It still goes
  up for an AC-130.
- **Leash:** once it is more than 2500 studs from its station with the enemy
  further out still, it heads back there and drags the fight with it
  (`DOGFIGHT_LEASH`).

The dogfight follows basic fighter maneuvers:

- **Lag pursuit on the way in:** further than 1200 studs out, it aims 250
  studs behind the target, so it closes in without flying past.
- **Lead pursuit for the shot:** inside 1200 studs it aims where the target
  will be in 0.6 s, cutting it off.
- **High yo-yo instead of an overshoot:** within 300 studs, with the target
  more than 60° off its nose, it pulls up 150 studs and comes back down behind.
- **Sidewinders** (the four small pylon missiles):
  - **When it fires:** the target must be 150–1800 studs off and within 35° of
    its nose, and it fires at most one every 2.5 s.
  - **The missile:** 900 studs/s, turning at 160°/s.
  - **A hit** brings a plane down. An Apache takes 2000 damage, more than its
    1500 health.
- **The cannon:** inside 800 studs, with the lead point within 8° of its nose,
  it fires at 40 rounds/s.
  - **A hit:** a round counts if it passes within 14 studs of where the target
    will be.
  - **Damage per round:** 8 to a plane's `AirHealth` (a Phantom has 200, an
    AC-130 600) and 25 to an Apache.

**Defending:** it breaks for 2.5 s in its hardest turn, diving 120 studs.

- **A missile homing on it:** it turns square across the missile's path
  (beaming it), whichever way needs the least turn. It knows where the missile
  came from by the `ThreatAt` attribute the launcher sets.
- **An enemy Phantom on its tail:** it turns into the attacker so he
  overshoots. He has to be within 900 studs, behind it (more than 120° off its
  nose, `TAIL_BEHIND`), with his nose within 20° of it. One coming head-on
  doesn't count, so two Phantoms meeting nose to nose fight instead of both
  breaking.
- **Between breaks:** it attacks for at least 3 s before it can break again
  (`BREAK_COOLDOWN`).

**Flares and chaff:** limited, after the real dispensers. Flares fool
heat-seekers (the Phantom's Sidewinders). Chaff fools radar missiles (the AA
truck's rockets). Every aircraft carries a `Flares` count and a `Chaff` count
and fires each in salvos:

| | Flares | Chaff | Per salvo | Pulls a heat-seeker off | Pulls a radar missile off (beaming) |
|---|---|---|---|---|---|
| F-4 Phantom (two AN/ALE-40s) | 30 | 30 | 4 | about 76% | about 59% (94%) |
| Apache (one M130) | 30 | 30 | 2 | about 51% | about 36% (75%) |
| AC-130 (estimate, no published figure) | 120 | 120 | 8 | about 94% | about 83% (99%) |

- **Beaming:** chaff works far better when the aircraft flies within 30° of
  square across the missile's path, at 20+ studs/s (`BEAM_ANGLE`,
  `BEAM_BONUS`). A Phantom breaks that way on purpose; an AC-130 or Apache
  only beams a missile when its own course happens to.
- **Chaff hangs:** it drifts as a glittering cloud for 5 s, where flares are
  thrown clear and drop for 4.

- **When a salvo goes:** a missile gets within 500 studs and the last salvo
  was at least 3 s ago (`FLARE_INTERVAL`, the F-4's shortest burst interval).
  That's at most 20 salvos a minute, and a Phantom's 30 flares run out after 8.
- **A missile during the gap** gets no fresh salvo, but the flares still
  burning from the last one (within 500 studs of it) can take it. So both
  missiles of a pair, or both of an AA truck's rockets, can be decoyed.
- **The decoy:** each flare near a heat-seeker has a 30% chance
  (`FLARE_PULL`) of taking it, and each chaff bundle near a radar missile 20%
  (`CHAFF_PULL`). The missile then blows up on the decoy. Decoys are tagged
  `BloxianFlare` (with a `Decoy` attribute, flare or chaff), so the Phantom's
  missiles and the AA truck's rockets see each other's.
- **No reloading:** flares and chaff are only refilled by spawning a new aircraft.
- **Tuning:** all of it is in `Shared/AirDefense.luau`.

## Close air support, once the sky is clear

This only starts when there has been no enemy aircraft for 10 s
(`AIR_CLEAR_TIME`). On patrol it scans every 0.5 s for enemy soldiers, players
and vehicles to engage. It looks within 900 studs of its station first
(`STATION_RADIUS`), and when there are none there, anywhere on the map
(`SEARCH_RADIUS`, unlimited by default). It flies off to engage whatever it
finds and comes back to circle its station when the ground is clear.

- **Who it goes for:** an enemy its own side's Bloxian Special Recon reported in
  the last 30 s (`REPORT_TIME`), anywhere on the map; otherwise the enemy
  closest to its own side's troops. It never fires with a friend within 35
  studs of the target.
- **Not targeted:** wrecks, and anyone still hanging under a parachute, such as
  a pilot just out of a downed aircraft. Once he lands he's fair game.
- **Mavericks into vehicles** (the two big pylon missiles): vehicles come first
  while one is loaded.
  - **When it fires:** it comes in 250 studs up and fires within 2000 studs
    and 60° of its nose. The missile steers the rest of the way.
  - **Damage:** one destroys the vehicle it hits, Abrams included. Other enemy
    vehicles within 15 studs take 400.
  - **Sound:** it launches with the Javelin's missile sound, and so do its
    Sidewinders.
  - **Never at people:** a Maverick only ever hits vehicles.
  - **Smoke:** at launch the vehicle is told a missile is coming
    (`MissileInbound`, `ThreatAt`), so an Abrams pops smoke. A Maverick that loses
    sight of it in the smoke flies to where it last saw it. It only hurts the
    vehicle if the vehicle is still there.
- **Gun runs on soldiers and players:**
  - **The run:** it comes in 150 studs up and fires a 1.5 s burst within
    700 studs and 25° of its nose.
  - **The rounds:** 40 rounds/s, scattered 5 studs round the target, each with
    an orange tracer and a dust puff.
  - **Damage per round:** 20 to people and 30 to vehicles. It never hurts its
    own side.
  - **The gun is also the fallback** for vehicles once the Mavericks are spent.
- **After each attack** it pulls away for 4 s, then turns back in.
- **Straight runs:** a target too close to line up on (inside 600 studs and off
  its nose) makes it fly straight out to 1100 studs, for at most 6 s, then
  turn in for one clean run (`MIN_RUN_DISTANCE`, `RUN_START_DISTANCE`,
  `EXTEND_TIME`). It doesn't circle over the target. The tracker shows Extend
  while it does.

Otherwise it patrols, circling its station 650 studs up at a radius of 600.
It never flies lower than 100 studs above the ground.

**Pylons:** each missile is a part under the wings (`Armory`). It disappears
when fired and is back after 25 s (`REARM_TIME`). The rocket pods are only for
show.

## Called in by recon

Bloxian Special Recon radioman clones this F-4 from `ServerStorage.BloxianVehicles`
when they see enemy aircraft and their side has none up. A copy sent like that
carries a `Lifetime` attribute (40 s) and disappears once it runs out, unless it
was shot down first.

## Flyby

Passing within 400 studs of a player, it plays a flyby sound, at most once
every 8 s (`FLYBY_*` near the top of `Jet.server.luau`).

## Shot down

The pilot ejects at once.

- **The pilot:** a Bloxian of its side in the Pilot uniform with the FN FAL.
  He goes up out of the jet, opens his canopy after 0.8 s and sinks at
  25 studs/s, then fights on the ground. A jet you spawned hands him to you:
  either spawner's Clear all removes him.
- **The jet:** the whole airframe goes up in flames. There's a fire on each of
  its 30 biggest parts, sized to the part (`ENGULF_PARTS`, `ENGULF_MAX_FIRE`),
  and black smoke pours off the largest. It falls like that.
- **The crash:** where it hits the ground, one blast of Random Arty's shell
  impact at 4x size (`CRASH_SCALE`): debris, dust, smoke and light, a louder,
  deeper boom, and camera shake further out. Without Random Arty it's a plain
  explosion.
- **The wreck:** the wreck stays where it hit, charred black and
  tilted on the ground, still burning and smoking. The fires go out after 6 s
  and the smoke after 12 s. Then it fades away over 3 s and is removed
  (`WRECK_BURN`, `WRECK_TIME`, `WRECK_FADE`). It's no longer an aircraft:
  its tag comes off and it's marked `Wrecked`, so Phantoms don't go after it
  and the tracker drops it.
- **Missile hits:** a missile that makes contact sets off a normal-size shell
  impact.

Its `Status` attribute is what the Bloxian Spawner's Track all shows: Patrol,
Intercept, Dogfight, Defending, Break, Attack, Strafe, Egress or Down.

Every number is at the top of `Jet`.

## Building

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o F4.rbxm
```

`src/Base.rbxm` is the RS2: Vietnam F-4 Phantom model with its landing gear
removed. An invisible `Root` faces the nose along -Z. Every part is saved
anchored and none of them is collidable or queryable. `Jet` welds them to
`Root` and lets them go when it starts, since welds saved in the file didn't
hold them together. `ModelStreamingMode` is Persistent, so every player always
has it loaded and can track it however far off it is. An `Exhaust`
attachment and `Settings` (`Team`, `Height`) are added.

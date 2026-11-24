# Handoff: Operation ragdolls + dying corpses in Spearhead

**Date:** 2026-11-23
**Studio place:** "Korblox Spearhead test" (placeId 91546882172702)
**Source place:** "Operation Obsolete Finale" (placeId 112356781991175)
**State:** these changes live only in Studio. The place is NOT saved, so save and publish before a live server gets them. Nothing is in git: these scripts live only in the place.

## What the user asked

1. Bring Operation's ragdolls into the Spearhead test place.
2. Make corpses either crawl away or grasp at their wounds.

Both are done.

## Changes

### `ReplicatedStorage.SPH_Assets.Modules.RagdollMod` (replaced)

It is now Operation's version, plus a new dying-moments section.

From Operation:
- **`crumple()`:** the body drops where it stands. The legs buckle and the torso leans along `GoreDir`.
- **`Corpses` collision group:** bodies pile onto each other. The module also registers the `Bloxian`/`BloxianProne` groups, which are harmless here.
- **Self-collision:** `noSelfCollide()` stops a body's own parts from colliding with each other.
- **Gear:** non-body gear doesn't collide.
- **Leg sockets:** they get loose friction right away (`legs = true`), so bodies don't balance on stiff legs.
- **`module.LimitR6(character)`:** ragdolls an NPC in place.

New (Spearhead only, not in Operation): `dying(body, torso, character)` runs at the end of both `MakeCorpse` and `LimitR6`.
- It is skipped when `GoreHit == "Head"` or when the head is gone (decapitated by Gore).
- **Roll:**
  - Below `CRAWL_CHANCE` (0.25), the body crawls if it's face-down (`torso.LookVector.Y < -0.5`) and has both arms.
  - Otherwise, below `GRASP_CHANCE + CRAWL_CHANCE` (0.70), it grasps.
  - Anything else goes limp.
- **Timing:** it starts after `SETTLE` (1.1 s) and is always over before SPH anchors the body (`GameConfig.bodyAnchorTime` = 10).
- **Grasp:**
  - One or both arms get an `AlignOrientation` (OneAttachment, `ARM_TORQUE` 900) that points the hand at the wound.
  - The wound is `GorePos`, held in the hit part's local space and clamped to its size. With no `GorePos` (a bleed-out), it defaults to the gut.
  - It writhes with a sine wobble for 3.5-6.5 s, and the torque fades out over the last `FADE` (1.5 s).
- **Crawl:**
  - It runs 3-5 cycles of `CRAWL_CYCLE` (1.5 s): one arm reaches for 0.6 s (`REACH_DIR`), then both plant (`PLANT_DIR`, flat along the body).
  - During the plant, a torso `LinearVelocity` (Line mode, toward the head) pulls at `CRAWL_SPEED` 2.2, getting weaker each cycle.
  - The pull force is body mass × gravity × `CRAWL_GRIP` (1.4). Corpses have friction 1, so a weaker pull can't move them; a fixed 4000 did nothing.
  - A torso `AlignOrientation` ("keep") holds the start orientation so the body stays face-down. Without it, the arms levered the body onto its back.
  - Crawl arms use `CRAWL_ARM_TORQUE` 450.
- Every added instance is named `DyingDrive` and is destroyed when the behavior ends. The work runs on a Heartbeat connection per body.

### `ServerScriptService.SPH_Server` (patched to match Operation)

- **Removed the death shove**, the `deathForce` VectorForce on `torso.NeckAttachment`. In its place is a comment: `-- no death shove: RagdollMod crumples the body in place and leans it along GoreDir`.
- **Anchor delay block:** dropped `desc.CanCollide = false`, so anchored corpses stay solid and later bodies land on them.

### `ServerScriptService.NPCRagdoll` (new Script)

- It hooks every R6 `Humanoid` in Workspace that isn't a player and isn't a `*_Dead` corpse, including ones added later (deferred).
- It sets `BreakJointsOnDeath = false`.
- On `Died`, it:
  - disables `Animate` and stops the animation tracks;
  - unanchors the parts **only if there's ground within 20 studs below the Torso**. The dummy lineup at y≈-35 floats over the void and would otherwise fall out of the world;
  - gives the server network ownership;
  - calls `RagdollMod.LimitR6`;
  - sets the six body parts to `CanCollide = true`.
- Spearhead's dummies are fully anchored statues with no scripts, so before this they never fell over.

## Verified (in Studio playtests)

- Dummies ragdoll in place; grasp drives fire.
- After the fix, the crawler stays face-down (faceY about -0.96) and moves about 3.5 studs, stepping on each pull. Before the fix it moved 0.03 studs, and then later flipped onto its back.
- `MakeCorpse` on 10 cloned soldiers ran with no errors: 3 crawled, the rest grasped.
- No console errors from RagdollMod or NPCRagdoll. The rest of the console noise was already there: asset permissions, the M41/4x4 supply scripts, Adonis.

## Not verified / known limits

- **Not watched in motion.** Checks were numeric plus still frames, so the look still needs the user's eye in a playtest.
- **Real player deaths not tested.** That path is Medical downed, then death, then SPH `Died`, then `MakeCorpse`. It's the same code path as the clone test, but Medical's leftover `MedRagdoll` sockets on the character could fight the arm drives.
- **Rigid crawl.** R6 has no elbows, and the arm cone (80° around torso (0,-1,-1)) lets a prone body claw only just ahead. The crawl reads as a drag.
- **Hidden hands.** A face-down body that grasps has its hands underneath it, so the grasp is only readable on back or side landings.
- **Mostly face-down falls.** In testing, Operation's `crumple` put nearly every body face-down, whichever way it was shot. That's Operation's behavior, left as-is.
- **R6 only.** R15 corpses get no limits and no dying moments.

## Tuning knobs (top of the dying section in RagdollMod)

`GRASP_CHANCE`, `CRAWL_CHANCE`, `SETTLE`, `ARM_TORQUE`, `FADE`, `CRAWL_CYCLE`, `CRAWL_REACH`, `CRAWL_SPEED`, `CRAWL_GRIP`, `REACH_DIR`, `PLANT_DIR`, `CRAWL_ARM_TORQUE`.
Keep every behavior shorter than `bodyAnchorTime`: the crawl is at most 1.1 + 5×1.5 = 8.6 s.

## Standing user rules that apply here

- Don't save the place unless asked.
- The user playtests in Studio.
- No gore at downing; downed players are Medical's, never this code.
- Test bodies must look like real soldiers. The `Forktx` soldier on the map (y > 200) was used as the clone source.

## Possible next steps (none requested)

- A blood smear trail under a crawling corpse, using the Gore module's decals.
- Port the dying section back to Operation's RagdollMod if the user wants it there too.
- A 2-player test of a real player death, to check Medical's sockets against the arm drives.

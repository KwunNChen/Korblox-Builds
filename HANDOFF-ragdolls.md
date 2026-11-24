# Handoff: ragdolls (SPH / Medical / Bloxian NPCs)

Read 2026-11-23 from the Studio file **copyleviathan.rbxl** (the tower game's local copy). The live place
**Operation Obsolete Finale** (placeId 131865741119806) wasn't connected then, so check it matches before you edit.
Neither place is in the git repo. You work on them through the Roblox Studio MCP (`execute_luau`, `script_grep`).

## Three ragdoll systems

| What | Where | When | Undoable |
|---|---|---|---|
| Player corpse | `ReplicatedStorage.SPH_Assets.Modules.RagdollMod.MakeCorpse`, called from `ServerScriptService.SPH_Server` (~line 588) | player death | no (new model) |
| NPC ragdoll in place | `RagdollMod.LimitR6`, called from `ServerStorage.BLOXIAN.Scripts.Server.HumanoidHandler` (~line 200) | Bloxian/enemy NPC death | no |
| Downed ragdoll | `ServerScriptService.Medical` `ragdoll()` / `unragdoll()` (~lines 92-180) + `StarterCharacterScripts.MedicalClient` | lethal hit -> Downed | yes (revive) |

### RagdollMod (shared by player corpses and NPCs)
- `R6_JOINTS` holds each joint's pivot in Torso space, the swing-cone axis (tilted forward, -Z is front), and cone/twist degrees.
  Head 40/45, arms 80/60, legs 55/25.
- `limitedSocket`: BallSocket with cone and twist limits and `Restitution 0`. Friction tweens from `STIFF_FRICTION 150` to `LOOSE_FRICTION 25`
  over `RELAX_TIME 1` s, so knees buckle instead of the body flinging or flopping. A limb's weight pulls with about 275.
- Attachment1's position is taken from the limb's current pose, so nothing snaps at death. Its rotation is the motor's rest pose,
  so the cone is centred on a standing body.
- `BODY_PHYSICS = PhysicalProperties.new(0.7, 1, 0, 1, 100)`: no bounce, high grip.
- `MakeCorpse` moves the parts, Shirt, Pants and accessories into a new `<Name>_Dead` model. It adds a welded, massless
  `RagdollHitbox` (0.95x size) per limb so the body doesn't sink, puts NoCollisionConstraints between the torso and each limb
  (both parts and both hitboxes), anchors and non-collides the HRP, disables every Humanoid state, and leaves a fake
  `MaxHealth 0` Humanoid on the old character.
- R15 still gets the original unlimited sockets. Marked as a `shortcut:` in the code; give R15 its own table if it's ever used.
- `LimitR6` ragdolls the NPC in place: same sockets, switches the motors off itself, then calls `crumple`.
- `crumple` (2026-11-23, replaced the plank tip and the SPH death shove): every part gets 6 studs/s downward, the legs
  get a forward spin (4 rad/s, knees buckle), and the torso/arms/head get a 1.2 rad/s lean along `GoreDir` (random
  forward/back if unset). Legs skip the stiff-friction phase (start at LOOSE) and fold ~100° forward / ~20° back
  (cone 60 around a 40° forward axis). Result: the body drops where it stands and lies still in ~0.5 s. `MakeCorpse` calls it too (R6 only).

### SPH_Server death path
- `config.ragdolls` (GameConfig line ~128) toggles all of it. `humanoid.BreakJointsOnDeath = not config.ragdolls`.
- The corpse goes into `workspace.SPH_Workspace.Bodies` and despawns after `config.bodyDespawn`. Above `config.bodyLimit`, the oldest is removed.
- No death push any more (the 600 VectorForce was removed 2026-11-23); `RagdollMod.crumple` leans the body along `GoreDir` instead.
- Char attribute `SuppressRagdoll` (Dark Magic MELT) skips the corpse entirely. Medical's `down()` also kills outright when it's set.
- `TowerRun` clears `Bodies` and `BloodDecal`s between raids (~line 496).

### Bloxian HumanoidHandler (NPCs)
- Uses RagdollMod if the place has SPH. Otherwise it falls back to the model's own loose `*Rag` sockets.
- On death: Animate is disabled, all Motor6Ds are switched off, and only Head, Torso and the limbs collide (`ragdollCollide`). The HRP must stay
  non-colliding or the body jitters or sinks. CanTouch and CanQuery are off on the corpse. It lies for `CORPSE_TIME 15` s, then fades over 1 s.
- Physics/Ragdoll/GettingUp states are disabled on the living NPC (lines ~81-86).

### Medical downed ragdoll (details in memory `spearhead-medical.md`)
- Limb Motor6Ds are switched off and BallSockets added, all named `MedRagdoll`. Each original joint stores its old Enabled in attribute
  `MedRagdoll`; `unragdoll` strips the MedRagdoll instances and restores the joints.
- Gotcha: SPH's WeaponRig welds the arms to a head rig (welds `law`/`raw`), and SPH flips shoulder motors on
  equip/unequip. So the ragdoll watches `Enabled` on those joints and keeps them off until revive.
- Gotcha: when the carrier's client owns the patient, it kills the humanoid for the disabled neck. The ragdoll therefore sets
  `RequiresNeck = false`.
- Drag tightens the sockets: limits (cone/twist: legs 20/5, arms 35/10, head 20/10), friction (legs 2, arms and head 1.5), density 0.02.
  Release resets them to loose (`LimitsEnabled false`, friction 0).
- MedicalClient knocks the body over backwards, or it balances on its legs.

### Corpse collision (2026-11-23)
- `LimitR6` and `MakeCorpse` put every corpse part (not the HRP) in the `Corpses` collision group. It collides with itself and Default,
  but not with `Bloxian` / `BloxianProne`, so bodies pile up while living NPCs still walk through them. Before this, NPC corpses kept the
  `Bloxian` group, which doesn't collide with itself.
- SPH's `bodyAnchorTime` anchor no longer sets CanCollide false, so later bodies land on older ones instead of sinking in.
- `noSelfCollide`: NoCollisionConstraints between every pair of a body's own parts and hitboxes. Without it, the body's own limbs jitter against each other.
- `corpseGroup` turns CanCollide off for anything that isn't a body part or a RagdollHitbox (gear, Morph meshes, accessories). Solid gear welded to a limb shoves
  the other limbs every frame, and the body spazzes. Anything that later sets CanCollide on a corpse must only touch the six body parts
  (HumanoidHandler's `ragdollCollide` already does).

### Ragdoll test dummy
- `Workspace["Ragdoll Test Dummy"]`: a copy of the Staging Sergeant with its HeldProp removed. Its own `RagdollTestDummy` script calls `LimitR6` on death,
  and a fresh copy stands up after 6 s (`RESPAWN`). It stands just outside VanSpawn. Copy the model to place more dummies.
- `LimitR6` turns CanCollide off on the HRP itself. With a solid HRP still jointed to the Torso, the body balances on it and tips over stiff like a board.
- Saved to Roblox as place version 18 on 2026-11-23. Not published.

## Gotchas
- Gore cuts every Motor6D, Weld and ragdoll BallSocket holding a severed part (`Gore` ~line 182). Any new joint type must be cuttable there too.
- Bodies need NoCollisionConstraints at every limb-torso overlap; the body jitters without them.
- Don't add world AngularVelocity dampers to calm limbs. They fight the body turning and halved the dragger's speed;
  joint friction is what works.
- In a test, `hum:Move` from execute_luau gets overridden; use `MoveTo`.

## User rules that touch ragdolls
- No gore at downing; gore happens on death.
- A dragged body must not flop or fling the dragger.
- Test bodies must look like real soldiers (team morph), not the white block Dummy.
- Don't save the place unless asked. The user playtests in Studio.

## R6
- Operation Obsolete Finale (112356781991175) was MorphToR15 until 2026-11-23; set to R6 Only in File → Avatar Settings → ⋯
  (not in Game Settings, and not readable or settable from scripts). The other place (131865741119806) was already MorphToR6.
- To test a standing player death, copy Medical's `die()` steps: set `CanDie` true, enable the Dead state, set Health to 0, then `ChangeState(Dead)`.
  Plain `Health = 0` only downs the player.

## Open / not verified
- Whether Operation Obsolete Finale's RagdollMod, SPH_Server, HumanoidHandler and Medical match the copy described here.
- R15 corpses are unlimited (see shortcut above).

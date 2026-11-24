# Tower Assault - handoff for the next Claude session

Snapshot: 2026-11-21. Covers three parallel sessions: this one ("raid UI / tower / insertion / gas mask pickup"),
"Mini-boss battle design" (CBRN boss), and "Spearhead issue" (NPC ragdolls).
Long-term project notes also live in the memory file `tower-assault.md`; read that too.

## The place
- Roblox Studio place **"Operation Obsolete Finale"**, placeId **131865741119806**, universe 10776515545 (group 35065811).
  It used to be "Operation Leviathan"; the naval mode now lives in `../Operation Leviathon` in the repo.
- The Studio MCP `studio_id` changes every launch: call `list_roblox_studios` and match on the placeId.
- **NOTHING FROM THESE SESSIONS IS SAVED.** "Save to Roblox" (TeamCreate) failed all session. First job: get the user
  to save (File → Save to Roblox, or a local copy if that fails).

## Game in one paragraph
Co-op PvE. Players are the Korblox Confederacy, enemies are the Bloxian AI (`ServerStorage.BLOXIAN`, `workspace.BLOXIAN`).
Squad readies up in the staging tavern (`workspace.Staging`), van insertion cutscene to `workspace.GarrisonTower`,
then fights up a stack of prefab floors (`ServerStorage.TowerFloors`: Barracks, Armory, Communications/CommsCenter),
cloned at X=30000 by `ServerScriptService.TowerRun`. Roof wave, heli extraction, raid report.
Difficulties in `ReplicatedStorage.TowerDifficulties`; boss floors call `ServerStorage.TowerBosses`.

## User rules (hard)
- Props are **realistic marketplace meshes**, never block-built.
- **No non-90° yaws** on props; the user reads any off angle as "tilted". `insert_asset` adds a ~22° yaw: reset it.
- Don't regroup or group the user's loose items.
- UI font is **HighwayGothic** (`Font.new("rbxasset://fonts/families/HighwayGothic.json")`).
- No extra ServerStorage folders for medical items.
- Don't save the place unless asked.
- The user playtests while you work. A `DeveloperShutdown` in the log means they stopped it. You need Edit mode to edit,
  so stop Play first and tell them you did.

## Working method that works
- Edit scripts with `execute_luau` on the **Edit** datamodel: plain `find` on `.Source`, assert a unique match, splice,
  wrap in `ChangeHistoryService:TryBeginRecording/FinishRecording`, and check with `loadstring(src)`.
  `multi_edit` times out or fails on tabs. `script_read` sometimes says "not found" for real scripts.
- `script_grep` only sees client scripts during Play.
- Check visuals with `screen_capture` using camera_position/look_at in Edit mode.

## Done this round (all unsaved)
### Raid end / HUD (verified in play)
- No fade to black. `StarterGui.TowerHUD.DisplayOrder` = 21, above RaidReport's 20, so the RAID FAILED / EXTRACTED
  header draws on top of the results card.
- `StarterPlayerScripts.RaidReport` `show()`: after the score pops in, it tweens TowerHUD.Header out.
- `TowerRun.endRun`: reports are sent after 4.5 s on extraction and 3 s on failure.
- Side effect: TowerHUD's boss strip now draws above every GUI with DisplayOrder 1-20.

### GarrisonTower (verified by screenshot)
- `workspace.GarrisonTower.Neck`: Tier parts set to 88×8×88 and Reveal strips moved out, so the tower is a straight box,
  with no PLA-Hong-Kong setbacks.

### Insertion cutscene (shake fix NOT playtested)
- `StarterPlayerScripts.Insertion`, city branch: the camera starts low across the road, aimed at the tattered Bloxian
  flags (`workspace.City.SpawnLife`, stop-local (4,46,0)). Over 3.5 s it tilts to a fixed point at the HQ doors.
  It aims at fixed points, never the van: the van's replicated position jitters, and that was the shake.
- `TowerRun`: `CITY_RUN, CITY_TIME = 220, 8` (was 120, 6). `INSERT_STOP = CFrame.lookAt((0,0,-83),(1,0,-83))`.
  The road along z=-83 is clear back to x=-300.
- Tuning knobs: the 3.5 s tilt, and 220 studs / 8 s.

### CBRN gas mask pickup (Edit-mode mock only, NOT playtested)
- `ServerStorage.TowerBosses` `issueMasks`: the yellow box is replaced by `GasMaskPickup`, a Model made from the real
  MCU-2 parts in `ServerStorage.BloxiaMorphs.GasMask.Gear` (Body + Lens, no Balaclava).
  - It stands upright on the desk nearest the EntryPoint (within 30 studs; every floor has a DutyDesk 12-19 away)
    and faces the stairs, snapped to 90°.
  - Raycasts at desk positions 0.2 / -0.2 / 0 along the long axis; the lowest hit wins, which avoids the phone.
  - Yellow outline-only `Highlight`, AlwaysOnTop. The ProximityPrompt is on the body.
  - No desk → falls back to the old floor spot.
- `TowerRun.playFloor` now passes `floor = m` in the boss ctx.
- `StarterPlayerScripts.GasMaskClient`: once the player has `HasMask`, it hides the pickup locally (parts, outline,
  prompt). Squadmates without a mask still see it.
- Limit: one mask per player per floor, so there's no refill once the filter runs out.

## From "Mini-boss battle design" (CBRN boss: done, play-tested earlier)
- Behind Enemy Lines has `bossFloors {3,6,9}` and `bossPool {"CBRN"}`. Other approved bosses (Quartermaster Juggernaut,
  Sapper, Blackout NVG team, Garrison Commander) are **waiting on the user**. They'll supply model builds, so ask.
- Everyone, player and Bloxian, uses the MCU-2 mask mesh (from the user's gasmask.rbxm). The Hazmat morph was removed.
- The squad lead is marked by a red glass lens (Glass, 150,25,20, transparency 0.5) and a yellow armband. Morphs:
  `BloxiaMorphs.GasMask` / `GasMaskOfficer`. UniformModule presets: `CBRN` / `CBRNOfficer`.
- Kill feed names: `TowerBosses` sets the `FeedName` attribute ("CBRN Trooper", "CBRN Squad Lead"), and
  `ServerScriptService.Medical` `nameOf` checks FeedName first. Other bosses can use the same hook.
  Verified with test kills, not on a real CBRN floor.
- Gas: `GasCloud` treats `GasMask` characters as protected. The nerve dose is fatal and skips Medical downing.

## From "Spearhead issue" (NPC ragdolls, partly done)
- New `RagdollMod.LimitR6(character)` in `ReplicatedStorage.SPH_Assets.Modules.RagdollMod`, called on death from
  `ServerStorage.BLOXIAN.Scripts.Server.HumanoidHandler`. It gives NPCs the same grounded ragdoll as player corpses
  (joint limits, stiff→loose over 1 s, no bounce). Verified with 3 test kills.
- **Open:** an NPC killed while standing still stays upright ~1.1 s before it falls. The cause isn't known (stiff legs?).
- NPCs already in Workspace keep the old handler until they respawn from the template.

## Suggested next checks
1. Get the place saved.
2. Run "Behind Enemy Lines" to a CBRN floor. Check:
   - the mask on the desk, and its outline through walls;
   - that it disappears for the grabber only;
   - the kill feed names;
   - the death drop timing.
3. Watch the arrival cutscene for shake and van timing.

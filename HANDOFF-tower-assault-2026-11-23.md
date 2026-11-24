# Handoff: Tower Assault (Studio place 131865741119806)

All of this work is in Roblox Studio, not in git. Check whether the place is saved before you trust any of it: the user saves it themselves, and Studio has been reopened a few times this session.

## Standing rules from the user
- Use realistic Creator Store meshes. Never block-build props.
- Yaws must be multiples of 90°.
- Don't regroup the user's items.
- UI font is HighwayGothic. Keep the HUD and hint text minimal.
- Never save the place unless asked.
- If Studio is in Play, stop it to edit and tell the user. The user often starts Play mid-task.
- Marketplace inserts: quarantine them first and strip every script.
- No lettering on meshes or textures.

## Done this session
- **Equip sounds** (`StarterCharacterScripts.SPH_Character.CharacterClient`):
  - Every equip animation keyframes `Equip` at t=0, and `KeyframeReached` doesn't fire for that. The SUR-61 and UH-60 animations have no keyframes at all.
  - `EquipAnim()` now calls `PlayRepSound("Equip")` directly, and `OnKeyframe` skips `Equip` so it can't double up.
  - Verified in Play on the SUR-61.
- **StaffOffices furniture** (`Workspace.StaffOffices` and `ServerStorage.TowerFloors.StaffOffices`, synced):
  - Desks and tables are now 2.55 tall, the Communications standard. Desk props were scaled by the same factor.
  - OfficeChairs are 4.28 tall with the seat at 2.0, R6 leg length. They were pushed back so they don't clip desks.
  - The kit copies in `ServerStorage.CityKit` and `Workspace.Props` are still the old size.
- **StaffOffices DocBoxes:** all 235 lowered 0.17 so they sit flush. The model's bounds reach 0.15 below the visible mesh.
- **ServerStorage cleanup:** deleted `TREKGasGrenade_Unused`, `CityArchive` and `TavernPatronTemplates`, with the user's OK. The 14 loose gun Tools were kept because Adonis `:give` uses them.
- **SUR-61 fire animation** (`WeaponStats`, in StarterPack and in ServerStorage):
  - `fireMoveParts = {}`.
  - The user wants `Bolt` and `Charging` to move only on the F rack.
  - The ejection port the user wants animated isn't a separate part. `Grip.Chamber` is just the shell-eject attachment, and the port is baked into the receiver mesh.
  - Not fired in Play yet.

## Open / next
1. **SUR-61:** fire it in Play and confirm nothing moves. If the user wants a moving ejection-port cover, it needs a separate mesh piece.
2. **More than 5 players** (`ServerScriptService.TowerRun`):
   - The van has 5 seats (`insertion()`, about line 698); player 6 and up stay standing in the tavern but are still teleported in.
   - The floor-1 arrival grid is 3 wide and grows backwards (about line 900), so the back rows probably land inside walls past about 9-12 players.
   - Heli extras use `n % 4` standing spots (about line 660), so they overlap from player 10.
   - Enemies don't scale with squad size, and `MaxPlayers` is 60.
   - The user hasn't picked a fix yet: cap MaxPlayers at 5, or add standing spots and a wider grid.
3. **Desks vs chair seat:** desks are 2.55 tall and seats are 2.0, so seated legs may poke through the desks. The likely fix is desks at about 3.4. The user hasn't decided.
4. **Older backlog:**
   - Commander, Sapper and Blackout bosses (need assets).
   - The RPG counter question.
   - Juggernaut faceplate plan: `C:\Users\pbche\.claude\plans\whimsical-hatching-hennessy-of-f1cce718-4a42-4d95-99cd-398b1942d514.md`.

## Gotchas
- Studio ids change when Studio is reopened. Call `list_roblox_studios` first.
- `script_read` range params are `start_line_one_indexed` and `end_line_one_indexed_inclusive`.
- Studio `script_grep` uses Luau patterns, so `\|` alternation doesn't work.
- TowerFloors sync: clone the workspace floor, `PivotTo` the old copy's pivot, destroy the old copy, then parent the clone.

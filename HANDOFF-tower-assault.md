# Handoff: Operation Obsolete Finale (Tower Assault)

Date: 2026-11-23
Place: Operation Obsolete Finale, placeId 112356781991175. All edits were made live in Studio through the MCP.

> **The place is NOT saved.** Every change below lives only in the open Studio session. Save only when the owner asks.

## Working rules
- Never save the place unless asked.
- Stop Play before editing. `script_read` fails during Play.
- Use 90° yaws only.
- Use marketplace meshes only.
- The Studio ID changes when Studio reopens. Get the current one from `list_roblox_studios`. The last ID was `c87dbe03-731b-47fb-821a-6a051bae6d6a`.

## Done this session

### 1. Boss flavor text (`ServerStorage.TowerBosses`)
All text was rewritten in plain military wording.

| Boss | Intro tagline | 50% phase | Other lines |
|---|---|---|---|
| CBRN | `CHEM HAZARD  ·  DON MASKS AT INSERTION POINT` | `AGENT RELEASED ON ENEMY CP` | |
| Signals | `PRIORITY TARGET: ENEMY RTO  ·  DENY COMMS UP-TOWER` | `ENEMY QRF INBOUND` | Flashes: `ENEMY NET ACTIVE`, `UPPER FLOORS ALERTED`, `POSITION COMPROMISED`, `RTO NEUTRALIZED`. Objective: `ENEMY TX  ·  %ds`. Lockdown: `BREACH POINTS SEALED` / `BREACH POINTS OPEN` |
| Spectrum Denial | `EW T█REAT  ·  COM█S DEGRA█ED IN PRO█IMITY` (lightly censored) | `J██MER O█T██T INC███SED` (heavier censorship) | `COMMS JAMMED` / `COMMS RESTORED` are unchanged |
| Juggernaut | `HEAVY ARMOR  ·  ENGAGE FROM REAR OR DEFEAT FACEPLATE` | `JUGGERNAUT ENRAGED` | `JUGGERNAUT DOWN` |

How the cards are driven: BossFX reads TowerStatus attributes. `BossTagline` must be set before `BossName`. `BossWarning` flashes a line and `BossObjective` holds one. The █ glyphs render as solid white blocks.

### 2. Neck and hood gear visible in first person
Fixed in `StarterPlayer.StarterCharacterScripts.SPH_Character.FirstPersonVisibility`. In the conventional-morph loop, gear whose centre sits above `torso.Size.Y/2 - 0.1` keeps LocalTransparencyModifier = 1, so it stays hidden in first person. The cause was the Korblox Low Hood in TorsoGear.

### 3. Armory rework
Edits were made in both `Workspace.Armory` and `ServerStorage.TowerFloors.Armory`. They share the pivot (20300, 8, 0).
- The four cage gates (Z = -22, X = 20263/20288/20312/20337) were widened from 4 to 8 studs.
- The front rifle-rack pairs were spread apart to leave a centre aisle. The back racks were pushed flush to the back wall (Z -46.8).
- EnemySpawns were moved out of the cages to Z = -15.
- Pathfinding with radius 1.5 now reaches every bay. Nobody has walked it in Play yet.

### 4. Lobby/inn performance (`Workspace.Staging`)
This was a single ChangeHistory step named "Lobby shadow optimisation".
- Shadows were turned off on the 12 ceiling SpotLights.
- 669 pines more than 120 studs from the inn no longer cast shadows.
- All 2,109 pine MeshParts went from RenderFidelity Precise to Automatic.
- 3,177 parts smaller than 1.5 studs no longer cast shadows.
- Result: about 17M triangles and 4.2k draw calls became about 1.6-3.1M triangles and 0.5-1.1k draw calls. FPS was not measured on real hardware.

## Not verified
- The 50% phase lines in a real fight.
- Walking through the armory with players.
- Lobby FPS on the owner's machine.

## Next options
- If the lobby still lags, the next things to cut are Lighting DepthOfField and SunRays, then the 202 semi-transparent pine layers (Transparency 0.1).
- After saving, commit any synced scripts.

## References
- Animation ID map: `Reupload/idmap.txt`
- Memory notes: `tower-assault.md`, `asset-reupload-plaguebyte.md`

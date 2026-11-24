# Spearhead handoff (Korblox Spearhead test)

Everything below lives **only in the Studio place** "Korblox Spearhead test" (placeId 91546882172702), not in this repo, except the Dark Magic fixes. Studio changes are unsaved until someone presses Ctrl+S / publishes.

## 1. Kill gore - `ReplicatedStorage.SPH_Assets.Modules.Gore`
- Hooked from `ServerScriptService.SPH_Server`: `Gore.Mark` before the lethal `TakeDamage`, `Gore.ApplyMarked` in the Died handler (on the ragdoll corpse copy from `ragdoll.MakeCorpse`), and from `Modules.ExplosionFX`.
- Assets: `ServerStorage.SPH_Gore.Kit` (R6 gore kit, Creator Store 17473627624, scripts stripped) and `.Streaks` (blood meshes, 133543049676169).
- Rules the user set:
  - Only **shotgun** headshots (`wepStats.shotgun`) remove the head. Other headshots swap the head for the kit's hole-in-head mesh ("Limb", tinted to skin), hide the real head, keep the face decal, and show skull/flesh in the hole. `HeadBurstMiddle3` is excluded (empty hole).
  - Limb hits are **partial** dismemberment: `shorten()` cuts the limb at `CUT_BELOW` (-0.2) and keeps the top; joints/attachments are re-offset.
  - Torso hits: `torsoWound()` places entry and exit wounds front/back (`TorsoBurstUpper[L|R]1`), pushed out 0.12 studs so ribs/guts show over clothing.
  - One blood colour; wall spatter + floor pool appear after **1.5 s** (ragdoll settle); blood despawns after 15 s (`BLOOD_LIFETIME`).
- Blood streaks are Decals (the Streaks' colour maps) on invisible parts. Don't go back to the SurfaceAppearance boxes: they flash as solid red squares for a frame while the alpha loads. `StarterPlayerScripts.GorePreload` downloads the blood textures at join.
- Gotcha: free blood/gore models carried hidden scripts. Insert into a quarantine folder and strip scripts first.

## 2. Dark Magic MELT
- Melted victims skeletonize instead of ragdolling: SPH_Server's Died handler skips the corpse copy when the character has attribute `SuppressRagdoll`.
- Repo fixes in `Dark Magic/src/server/DarkMagic.server.luau` (**uncommitted**; `DarkMagic.rbxm` rebuilt with `rojo build package.project.json -o DarkMagic.rbxm`): failed template loads aren't cached, uniform downloads rate-limited to 1/s per player, hex re-cast no longer cleared by the old fade-out.

## 2b. Death ragdoll - `ReplicatedStorage.SPH_Assets.Modules.RagdollMod`
- R6 joints get limited BallSockets (`R6_JOINTS`: pivot, forward-tilted cone axis, cone and twist degrees), no-bounce/high-grip physics, and joint friction that starts stiff (150) and relaxes to 25 over 1 s ("muscle tone"). Hitboxes are 0.95 of each part (were 0.5, bodies sank into the floor). R15 still gets the old unlimited sockets.
- `SPH_Server` death push now follows the killing shot (`GoreDir`) instead of a fixed local -Z.

## 2c. Weapon animations
- Animations find gun parts by name: a pose only moves a part whose Motor6D Part1 has that exact name (SPH rigs `wepStats.rigParts` as Motor6Ds named after the part). SUR-61 parts are `Bolt`, `ChargingHandle`, `Mag`; name Blender bones the same.
- SUR-61 `rename_Equip` / `rename_Idle` were re-uploaded to the group with those names (120454951952835 / 129219086900853); old ids kept in attribute `OldAnimationId`.

## 3. Team morphs - `ServerScriptService.TeamMorph`
- Templates: `ServerStorage.TeamMorphs/<Team name>/` holding Shirt, Pants, Body Colors, and `HeadGear` / `TorsoGear` models (SPH conventional morph: invisible `Middle` welded to the body part, gear welded to Middle).
  - **Bloxian Commonwealth**: marine uniform (from BloxianMarine.rbxm). AR-18 and the model's hair left out.
  - **Korblox Confederacy**: Korbloxian uniform (from Korbloxian.rbxm), grey skin. Rifle, left-hand item and the stowed goggles removed.
- Players keep their **hair** (Hair accessories) and **face**; all other accessories and clothing are replaced.
- Bloxian skin is random per spawn (`SKIN_TONES`): light 35, tan 35, brown 15, dark brown 10, deep brown 5 (relative weights).
- Gotchas found the hard way:
  - Never name the gear models `Head`/`Torso`: the client then resolves `Character.Head` to the model, SPH first-person scripts error every frame and the viewmodel vanishes.
  - Apply on `CharacterAppearanceLoaded`, not `CharacterAdded`: on respawn `HasAppearanceLoaded()` is still true, so the avatar loaded after the morph and overwrote skin/clothes.
- A team change only takes effect on respawn.
- To add a team: add a folder named after it in `TeamMorphs`.

## Open items
- Save the place (Ctrl+S).
- Commit the Dark Magic fixes (offered, not answered).
- Not visually verified: gore look in play, face decal on hidden heads, morph gear on ragdolls/gore corpses, first-person viewmodel by eye.
- Unrequested audit findings left: raid reset, untracked files, CombatModule `from` check, pcall, objective test.
- Older: move Main Rifle model back to WeaponModels; optional shotgun equip sound; SPH_Locomotion (on hold).

## Working with Studio via MCP
- Avoid `screen_capture` (an earlier timeout locked the user's camera). Verify numerically with `execute_luau` on dummies, then destroy them.
- Local .rbxm files load by copying them into `%LOCALAPPDATA%\Roblox\Versions\<studio version>\content\` and calling `game:GetObjects("rbxasset://<file>.rbxm")`; delete the copy afterwards.

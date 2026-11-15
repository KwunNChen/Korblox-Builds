# Dark Magic

The "Korblox Dark Magic" tool: pick a spell in the panel, click people to select them, then cast.
Spells: Uniform, Melt, Raise, Soul Rip, Shadow Step, Hex. R6 characters.

- `src/server/DarkMagic.server.luau`: every spell's effects and the server-side checks (ServerScriptService "Dark Magic")
- `src/client/DarkMagicClient.client.luau`: the panel and target selection (inside the tool)
- `src/client/SoulControl.client.luau`: soul steering, camera shake and colour drain (StarterPlayerScripts)
- `anims/`: the caster animations as KeyframeSequences (`build_anims.luau` makes them); `vfx/`: the textures

## Putting it in another game

1. Insert `DarkMagic.rbxm` and put the `Dark Magic` Script in **ServerScriptService**. On start it moves
   the tool to StarterPack, the soul script to StarterPlayerScripts and the animations to
   ServerStorage, and creates the RemoteEvents. Every player gets the tool. To limit who gets it,
   move the tool out of StarterPack and hand it out yourself. The server accepts casts from any
   held Tool with the `DarkMagic` attribute.
2. **Animations:** Roblox only plays an animation in games owned by the account or group that
   published it. If the game isn't owned by the group that published these, open each
   KeyframeSequence in `ServerStorage.DarkMagicAnimations`, choose Save to Roblox as the game's
   owner, and paste the new ids into `ANIM_IDS` in the tool's `Client` script (HEX reuses MELT's).
   Until you do, the spells still work, but the caster's body doesn't animate.

No game settings need changing.

## Build

```bash
rojo build package.project.json -o DarkMagic.rbxm
```

Live-sync while editing with `rojo serve` (uses `default.project.json`, which syncs the scripts
straight into their services).

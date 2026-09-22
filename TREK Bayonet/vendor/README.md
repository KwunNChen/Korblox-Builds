# vendor/

Third-party code, kept here **only so Rojo can place it**. None of it is mine and
none of it is part of the TREK Bayonet package.

## TREKCustomBullets

Extracted verbatim from `TREK_Custom_Bullets.rbxm`. It replaces TREK's vanilla
Gun tool handler with one that resolves `BulletType` by module name, which is the
extension point the bayonet fire mode plugs into.

| File | Was |
|---|---|
| `TREKToolHandlers/Gun.client.luau` | `Core/ServerStorage/TREKToolHandlers/Gun` (LocalScript) |
| `TREK_Modules/BulletModule.luau` | requires every module in `BulletTypes` by name |
| `TREK_Modules/BulletTypes/{Hitscan,Projectile,Melee}.luau` | the shipped types |
| `TREK_Modules/ShapecastHitbox/` | ShapecastHitbox by Phin, used by the `Melee` type |
| `Example Weapon.luau` | reference only — not synced anywhere |

**Do not edit these.** They are a verbatim copy so that re-extracting the pack
after an update is a clean overwrite. The bayonet adds its own bullet type from
`src/Bayonet.luau`, which Rojo places alongside these — that is the
supported way to extend the pack, and it means nothing here has to change.

`Melee` is shipped but unused: it detects on the client and reports through
`TREK_Remotes.Damage`, which takes its origin from the client and does not check
it. `Bayonet` sweeps the blade on the server instead. Leaving `Melee` in place
costs nothing and keeps the pack intact for any other weapon that wants it.

## What Rojo does with it

`default.project.json` places the pack as a **TREK plugin**, mirroring the shape the
existing `Sounds&Particles` plugin has:

```
Workspace > Installer  > Plugins > TREKCustomBullets
    ReplicatedStorage/TREK_SERVICES/TREK_Modules/{BulletModule, ShapecastHitbox, BulletTypes/*}
    ServerStorage/TREKToolHandlers/Gun
```

plus `ServerStorage.TREKToolHandlers.Gun` directly, which is place content the installer
does not recreate — delete it and guns stop equipping altogether.

**Nothing is mapped into `ReplicatedStorage.TREK_SERVICES`, and nothing ever should be.**
`TREKServerGeneral` does `WaitForChild('TREK_SERVICES'):GetChildren()` during install; a
folder Rojo created makes that wait return instantly, TREK enumerates a folder the
installer has not filled, and the whole install dies on the next line. That mistake was
made once here and broke the place completely.

The bayonet's own bullet type is placed into the plugin's `BulletTypes` alongside these,
from `src/Bayonet.luau`. Placing it anywhere else means the handler cannot
resolve `BulletType = 'Bayonet'`, which aborts the handler for every weapon in the place.

`package.project.json` does **not** include any of this. The distributable ships only the
bayonet, because redistributing someone else's pack inside it would be wrong and would go
stale the moment they update it.

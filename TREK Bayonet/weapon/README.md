# Weapon configs

Working copies of TREK weapon modules with the bayonet `[9]` block merged in.

**Gitignored on purpose.** These are TREK's files with TREK's documentation in
them; they sit here so they are easy to find next to the package, not so they can
be published. The package's own paste-in snippet lives at
`../src/package/BayonetWeaponMode.luau`, which *is* tracked.

Rojo does not sync these. Paste the contents into
`Workspace > Installer > GunConfigs > <weapon>` in Studio, then restart the
playtest — `SetUpGuns` caches every weapon module at server start.

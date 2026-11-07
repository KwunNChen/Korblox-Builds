# KorbloxAI

The whole AI battle system in one file: Bloxian soldiers, the spawner tool, the
Vehicle Spawner, Warthog, Abrams, Apache, F-4 Phantom, AC-130, AA Truck and
Random Arty.

## Install in a new game

1. In Studio, right-click anything in Explorer and pick **Insert from File**,
   then choose `KorbloxAI.rbxm`.
2. Paste this in the Command Bar and press Enter:

   ```lua
   require(game:FindFirstChild("KorbloxInstall",true))()
   ```

3. Save the place.

Run it again with a newer `KorbloxAI.rbxm` to update. It replaces the system's
files, so copy any settings you changed first.

## The game needs

- A baseplate or map that PathfindingService can walk.
- R6 avatars for artillery gore: Game Settings > Avatar > Rig Type.
- **Team** is optional. The spawner offers `Hostile`, `Friendly` and any teams
  in the Teams service.
- **Models, sounds and animations** must be usable by the new game. Share
  private ones from the Creator Dashboard if Output says it has no permission.

TREK is optional: soldiers only use it to work out what weapon a player carries.

## Spawner access

Anyone holding the **Bloxian Spawner** tool can spawn soldiers and vehicles, call
Kinetic Events and use **Clear all**.

## Building

From this folder:

```bash
/c/Users/pbche/.rokit/bin/rojo.exe build package.project.json -o KorbloxAI.rbxm
```

Check it with `lune run test-install.luau`, which installs it into an empty
place and looks for every part.

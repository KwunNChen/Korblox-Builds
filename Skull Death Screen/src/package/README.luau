--[[

Skull death screen

What this is:
	When you die, the screen fades to black and the Evil Skull Man fades in,
	skull first, then pulls back to show his top half. A clip plays and the
	screen holds until it finishes. Then you respawn behind the black and it
	fades away.

Installing:
	Three folders, each named after the service it goes into.

		ReplicatedStorage    ->  game.ReplicatedStorage
		ServerScriptService  ->  game.ServerScriptService
		StarterPlayerScripts ->  game.StarterPlayer.StarterPlayerScripts

	Move the folder inside each one, not the signpost folder itself.

The sound:
	The id in DeathScreenConfig is mine. Roblox audio is private to the place
	that owns it, so in your game it plays as silence. Upload your own clip and
	paste its id into SoundId. If it fails to load, the screen holds for
	FallbackDuration and warns in Output.

Respawning:
	This turns Players.CharacterAutoLoads off and spawns every character itself.
	If another script in your place also takes over respawning, the two will
	fight, pick one.

	MaxRespawnWait is the safety net: the server respawns you after that long
	even if your client never reports back. Keep it longer than the clip.

Changing the rig:
	Drop any R6 or R15 rig into ReplicatedStorage.SkullDeathScreen and set
	ModelName. It needs a Head (or whatever FocusPartName names) and a Torso or
	UpperTorso. Scripts inside it are stripped before it is shown.

]]

return nil

--[[

TREK VOICELINES

WHAT THIS IS:
	Plays a voice clip out of a character's head when something happens to them:
	they reload, they get hit, they get low, they get a kill, they die.

	It does NOT modify TREK. Nothing in your TREK install is edited, replaced or
	patched. If you uninstall this folder, TREK is exactly as it was.

INSTALLING:
	Three folders, each named after the service it goes into.

		ReplicatedStorage   ->  game.ReplicatedStorage
		ServerScriptService ->  game.ServerScriptService
		StarterPlayerScripts ->  game.StarterPlayer.StarterPlayerScripts

	That is the whole install. It waits for TREK_INSTALLED on its own, so load
	order does not matter.

	The StarterPlayerScripts half is the preloader. Skip it and everything still
	works, but the first use of each clip may be late or silent.

ADDING YOUR CLIPS:
	It ships SILENT. Every sound list in VoicelineConfig is empty, and an event
	with no clips is skipped.

	Roblox audio is private to whichever place owns it. An id copied out of
	another game plays as nothing at all and reports no error, so you have to
	upload your own clips to this place or your group.

	Open ReplicatedStorage.TREKVoicelines.VoicelineConfig and fill in the
	Sounds lists:

		Reload    = { Sounds = { 123456789, 987654321 } },

	A bare number is tidiest, but these all work and can be mixed in one list:

		3526632933
		"3526632933"
		"rbxassetid://3526632933"
		"http://www.roblox.com/asset/?id=3526632933"


	Multiple ids per event is the point. There is no practical limit on how many.
	It picks uniformly among every clip except the one it just played, so you
	never hear the same line twice running and no clip is favoured over another.

THE EVENTS:
	Reload      the player started reloading
	ReloadDone  the reload finished -- "back up"
	LowAmmo     a magazine dropped to LowAmmoFraction or less while firing
	OutOfAmmo   the magazine hit exactly zero -- the dry click
	Incoming    an explosion went off nearby (everyone near it, not the firer)
	Hurt        took a hit
	Kill        killed someone
	Death       died
	PointTaken  a capture point changed hands (needs TObjectiveSystem)

CROWD MIXING:
	Without a limiter, twenty people pushing an objective produce twenty
	simultaneous voices. A bark is dropped if CrowdLimit others already started
	within CrowdWindow seconds and CrowdRadius studs of the speaker.

	It is counted per locality, so a fight across the map does not silence the
	one next to you. Death sets IgnoresCrowd and always lands.

	LowAmmo shares Reload's voice: same clips, same no-repeat memory, same
	cooldown clock. Going low and then reloading a second later cannot repeat a
	line or talk over itself. It keeps its own Priority and Chance.

	To make any two events share a voice, give one of them SharesWith instead of
	a Sounds list:

		LowAmmo = { Priority = 3, Cooldown = 12, Chance = 0.85, SharesWith = "Reload" }

TUNING:
	Every event has Priority, Cooldown and Chance in VoicelineConfig.

	Priority decides who wins when two things happen at once. A line already
	playing is only cut off by something STRICTLY higher, so Death always lands
	and a reload never talks over a low-health call.

	Cooldown is per-event, per-character. Chance is a 0-1 roll, and is there so
	a player who reloads ten times does not get the same bark ten times.

	GlobalCooldown is the quiet gap after any line ends. Turn it up if your
	clips are long.

]]

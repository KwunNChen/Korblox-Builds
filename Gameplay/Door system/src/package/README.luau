--[[

	Give credit to PLAGUEBYTE!!!!! @pb6008 for any inquiries

	Blast door

	A two-leaf door that slides apart from the middle to open and slides back
	together to close. Anyone still standing in the gap when it shuts dies,
	turned to red mist, not a ragdoll.

	Entirely server-side. No client scripts, no remotes, nothing goes in
	StarterPlayer.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder in step 3.


	========================================================
	Install
	========================================================

	1. This package should be sitting in ServerStorage. If it's anywhere else,
	   move it there first, scripts don't execute in ServerStorage, so
	   nothing runs early by mistake.

	2. Open the "ReplicatedStorage" and "ServerScriptService" folders. Move
	   each one's "BlastDoor" child into the matching real service.

	3. Delete the empty KorbloxBlastDoor folder, or keep it. Tools stays in
	   ServerStorage and nothing requires it. It's a Command Bar helper for
	   dropping a test door into Workspace, never runs on its own.

	4. Build a door: two parts or models named "Left" and "Right", built
	   touching in the middle (that's the closed position), grouped in a
	   Model. Tag that Model "BlastDoor" (Properties panel, Tags box at the
	   bottom). The server picks up anything tagged this way, including ones
	   added after the game has started.

	No art yet? Run this from the Command Bar once install is done:

	    require(game.ServerStorage.KorbloxBlastDoor.Tools.BuildExampleDoor).build(workspace)

	Press Play. Walk up to it (or press the button it made for you) and watch
	it split down the middle.


	When you're done

	    ReplicatedStorage
	    +-- BlastDoor              DoorConfig, DoorShared

	    ServerScriptService
	    +-- BlastDoor              DoorService, DoorCrush, DoorRuntime

	    ServerStorage
	    +-- KorbloxBlastDoor/Tools BuildExampleDoor (optional, Studio only)


	========================================================
	Activation
	========================================================

	DoorConfig.ActivationMethod picks how it opens:

	    "Proximity"   opens when anyone with a Humanoid gets within
	                  SenseRadius studs of the door's center, closes
	                  CloseDelay seconds after the last one leaves.

	    "Button"      looks for a ProximityPrompt anywhere inside the tagged
	                  Model. Finds none, it builds one on a part named
	                  "Button", or on "Left" if there's no Button part
	                  either. Press to toggle. AutoCloseDelay closes it again
	                  on its own after that many seconds open; 0 leaves that
	                  entirely to the button.

	    "Both"        either one opens it. AutoCloseDelay is ignored here.
	                  Proximity's own presence check already governs closing,
	                  and a fixed timer on top of it would fight that.

	Want your own button instead of the auto-built one? Just put a
	ProximityPrompt somewhere in the Model yourself: the server finds it
	and leaves it alone rather than building a second one.


	========================================================
	The kill
	========================================================

	While closing, every frame checks a box centered on the shrinking gap
	between Left and Right. Once that gap narrows past CrushGapThreshold,
	anyone with a HumanoidRootPart still inside it dies. Walking through
	while the gap is wide is safe; only the actual pinch is fatal, and the
	door never reverses or pauses for what's in the way.

	CrushZoneHeight and CrushZoneDepth size that detection box, match them
	to your actual doorway, not the default's 4-stud test slabs.

	The kill hides the character first (parts invisible and non-collide),
	then fires a burst of red particles at the last known position, then
	destroys the model a moment later. There is no corpse standing there,
	limp or otherwise, at any point.

	Compatible with RagdollDeath/ragdoll.luau. Before the kill, the victim
	gets a SuppressRagdoll attribute (named in DoorConfig), and that shared
	script checks for it and backs off if it's set. Install both in the same
	place and a crush death still turns to mist instead of ragdolling for a
	frame first. Without it installed, the door behaves identically: it
	never depended on that script existing.


	========================================================
	Tuning: ReplicatedStorage.BlastDoor.DoorConfig
	========================================================

	    SlideAxis, SlideDistance    which local axis the halves travel along,
	                                and how far each one moves to fully open
	    OpenTime, CloseTime         the tween duration each way
	    EasingStyle, EasingDirection
	    ActivationMethod            "Proximity" | "Button" | "Both"
	    SenseRadius, CloseDelay     proximity sensing
	    SenseCheckInterval          how often the proximity check runs
	    ButtonPartName, Button*     where the auto-built prompt goes and how
	                                it reads
	    AutoCloseDelay              button-mode only, see "Activation" above
	    EnableSound, *SoundId       ships silent, see the note below
	    EnableCrushKill             master switch for the kill entirely
	    CrushGapThreshold           how narrow before standing in it is fatal
	    CrushZoneHeight/Depth       size the detection box to your doorway
	    SuppressRagdollAttribute    the attribute name other systems can key
	                                off to skip their own death handling
	    CorpseCleanupDelay          how long the (already invisible) model
	                                lingers before it's destroyed
	    Mist*                       color, particle count, size, speed, sound
	    DebugLog                    prints open/close/crush to Output

	Sound ships silent. Roblox audio is private to whichever place owns it,
	so an id copied from another game plays as nothing at all with no error
	in Output. Paste your own asset ids into OpenSoundId / CloseSoundId /
	MistSoundId.


	========================================================
	If something's off
	========================================================

	The halves move the wrong way, or through each other
	  SlideAxis doesn't match how the door was built. Try the other
	  horizontal axis first, most doors are X or Z, not Y.

	The button doesn't appear
	  Check for a leftover ProximityPrompt already in the Model from a
	  previous test: the server only builds one when it finds none at all.

	Nobody ever dies in the gap
	  CrushZoneHeight/Depth are sized for the built-in 4-stud example slabs.
	  A bigger door needs a bigger box, or the detection zone sits inside
	  the doorway with room to spare on either side.

	Turn on DoorConfig.DebugLog
	  Prints every open, close, and crush to Output, tagged [BlastDoor].

]]

return nil

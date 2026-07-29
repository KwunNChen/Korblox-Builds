--[[

	GIVE CREDIT TO PLAGUEBYTE!!!!! @pb6008 for any inquiries

	VARIABLE SNOWSTORM + THUNDERSTORM

	Storms run on a cycle, snow stops when you walk under a roof, and getting
	caught out in one slows you down.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder in step 5.


	========================================================
	INSTALL
	========================================================

	The folders in this package are named after where they go. Drag each one
	into the matching service.

	1. This package should be sitting in ServerStorage. If it's anywhere else,
	   move it there first. Scripts don't execute in ServerStorage. Leave it in
	   ServerScriptService or Workspace and the server scripts start running
	   before the shared modules exist.

	2. Open the "ReplicatedStorage" folder. Move all three children into the
	   real ReplicatedStorage service:

	       Weather
	       WeatherState
	       ThunderStrike

	   Miss ThunderStrike and lightning turns itself off with a warning in
	   Output. Everything else still runs.

	3. Open the "ServerScriptService" folder. Move both children into the real
	   ServerScriptService service:

	       Weather
	       Common

	   If your game already has a Common folder, open this one and drag
	   SpeedService into yours instead of replacing it.

	4. Open the "StarterPlayerScripts" folder. Move its Weather folder into:

	       StarterPlayer > StarterPlayerScripts

	   Don't skip this one. It's the half that draws the snow. Miss it and the
	   storm still runs and still slows players, but nothing appears on screen,
	   which looks exactly like a broken install.

	5. Delete the empty VariableSnowstorm folder.


	WHEN YOU'RE DONE

	    ReplicatedStorage
	    |-- Weather               WeatherConfig, WeatherShared
	    |-- WeatherState          replicated attributes
	    +-- ThunderStrike         RemoteEvent for lightning

	    ServerScriptService
	    |-- Weather               WeatherService, WeatherRuntime, ThunderService
	    +-- Common                SpeedService

	    StarterPlayer/StarterPlayerScripts
	    +-- Weather               WeatherClient, WeatherAudio, WeatherThunder

	Press Play. A storm builds on its own within a couple of minutes.


	========================================================
	WIND AUDIO NEEDS YOUR OWN ASSET
	========================================================

	Roblox audio is private by default, so the WindSoundId this ships with may
	be silent in your game with no error at all.

	View > Toolbox > Audio, search "wind loop", right click, Copy Asset ID, and
	paste it into WeatherConfig.WindSoundId. It plays continuously, so pick one
	that loops without an audible seam.

	Set it to "" to turn audio off. The system warns once and runs silent.


	========================================================
	TESTING
	========================================================

	The cycle opens with 60 to 120 seconds of clear weather. To skip the wait,
	press Play, set the Client/Server toggle in the toolbar to SERVER, and run:

	    game.ReplicatedStorage.Weather:SetAttribute("DebugStartIntensity", 1)

	Any negative value resumes the normal cycle. Watch Output for:

	    [Weather] debug override -> intensity 1.00

	No print means the command never reached the server, which is almost always
	the toggle sitting on Client.

	SEEING NO SNOW?

	  1. Is there fog? Fog is applied before anything else the client does, so
	     fog means the client is running and the problem is elsewhere. No fog at
	     full intensity means the client scripts aren't running at all, and you
	     probably missed install step 4.

	  2. Are you under a roof? Shelter detection kills snow on purpose. Anything
	     solid within 250 studs overhead counts. Walk into the open.

	  3. Too sparse to notice? Raise WeatherConfig.FlakeSizePeak before you
	     raise ParticleBudget. Bigger flakes read as heavier snow without
	     adding any, though both cost framerate in the end.


	========================================================
	TUNING: ReplicatedStorage.Weather.WeatherConfig
	========================================================

	    ParticleBudget            live flake cap, main performance knob
	    FlakeSizePeak             flake size at full storm, the other perf knob
	    SquashAtPeak              how far flakes streak at full storm
	    PhaseDurations            how long each phase of the cycle lasts
	    WindStormSpeed            how hard a full blizzard blows
	    ShelterRespectCanCollide  turn off if your roofs are non-collidable
	    StormSpeedMultiplier      speed multiplier at full intensity
	    WindDirectionalSwing      how much heading matters, 0 to disable
	    WindAirborneAccel         how hard wind shoves you mid-jump
	    StormJumpMultiplier       jump height at full intensity
	    EnableThunderstorm        lightning window inside each Peak
	    ThunderChance             odds a Peak brings a thunderstorm at all
	    ThunderDuration           seconds a thunderstorm runs
	    ThunderMinDistance        how far off the nearest strikes land
	    ThunderStrikeInterval     seconds between strikes near one player
	    StormDarkenAmount         how far Peak snow darkens the sky by itself
	    ThunderDarkenExposure     how dark the sky goes, lower is darker
	    ThunderDarkenBrightness   sun brightness multiplier during a storm
	    EnableLightingEffects     false if your map drives its own fog
	    DebugStartIntensity       0 to 1 starts every playtest at that intensity


	========================================================
	THUNDERSTORMS
	========================================================

	Some Peaks bring a thunderstorm. It opens with a warning rumble, then runs a
	couple of minutes of distant lightning.

	LIGHTNING IS WEATHER, NOT A THREAT. It does no damage, ignores shelter, and
	never targets anyone. There is nothing to dodge.

	Strikes land well past the fog distance, so fog does the falloff: far ones
	reach you as a flash across the sky and a rumble seconds later, and only the
	nearest show an actual bolt. The light always comes before the sound.

	Players are picked only to decide WHERE a strike happens, so it lands
	somewhere someone can see it rather than in an empty corner of the map.

	The sky darkens as the window opens, and a Peak blizzard darkens it on its
	own too -- at StormDarkenAmount = 1 the sun is fully blotted at Peak whether
	or not there is lightning.

	Thunder needs one audio id of your own in ThunderCrackSoundId, for the same
	reason WindSoundId does. The opening rumble is that same asset slowed down,
	so there is nothing else to source.

	To test one without waiting for a Peak, on SERVER:

	    game.ReplicatedStorage.Weather:SetAttribute("DebugThunder", true)


	========================================================
	SPEED MODIFIERS
	========================================================

	SpeedService is the only thing allowed to assign Humanoid.WalkSpeed or the
	character's jump height. Systems register named modifiers and it folds them
	together:

	    final = base * (all multipliers) + (all additions)

	Pass jumpMul / jumpAdd in the same modifier to affect jumping as well. It
	writes JumpPower or JumpHeight to match the rig's UseJumpPower setting.

	A sprint system plugs in like this and needs to know nothing about weather:

	    local SpeedService = require(game.ServerScriptService.Common.SpeedService)

	    SpeedService.setModifier(humanoid, "Sprint", { mul = 1.5 })
	    SpeedService.clearModifier(humanoid, "Sprint")

	The storm stacks on top by itself, so sprinting in a blizzard lands on
	16 * 1.5 * 0.875 = 21 rather than 24.

	That 0.875 is the crosswind value. The storm multiplier swings with your
	heading, down to 0.70 walking into the wind and up to 1.05 with it behind
	you, and pulses as gusts pass. Jumping in the open blows you downwind too.

	One rule: never assign WalkSpeed directly once a humanoid is managed here.
	Outside writes get overwritten on the next recompute.

]]

return nil

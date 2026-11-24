--[[

	Chat voices

	Roleplay chat. When a player sends a message:
	  * talk blips play from their head, one per few letters. Each life gets
	    its own voice pitch, which changes when they respawn.
	  * the message is formatted like a book:
	        please *he begs*      ->  "Please," he begs.
	        c'mon! *he yells*     ->  "C'mon!" he yells.
	        *he sighs* fine       ->  He sighs. "Fine"
	        where are we?         ->  "Where are we?" PlagueByte asks.
	        get down!             ->  "Get down!" PlagueByte shouts.
	        okay                  ->  "Okay," PlagueByte says.
	    Speech gets quotes. Text between *stars* is a grey italic action and
	    makes no sound. Plain speech with no *action* gets an automatic tag
	    from its punctuation (? asks, ! yells, ... trails off, else says),
	    with a few verbs each so it doesn't repeat.

	Standalone. Needs the default TextChatService chat and nothing else.

	This is a ModuleScript, so it never runs. Read it, then delete it with the
	wrapper folder in step 3.

	==========================================================================
	Install
	==========================================================================

	Drag ChatVoices.rbxm into ServerStorage. The folders inside are signposts:
	each one names where its contents go. Move the folder inside, not the
	signpost.

	1. ServerScriptService/  ->  move  ChatVoices  into  game.ServerScriptService
	2. StarterPlayerScripts/ ->  move  ChatVoices  into
	                             game.StarterPlayer.StarterPlayerScripts
	3. Delete the empty ChatVoices wrapper folder.

	Then press Play and type in chat.

	==========================================================================
	Settings
	==========================================================================

	ServerScriptService.ChatVoices.ChatMurmur, at the top:
	  SOUND_ID             the blip sound
	  PITCH_MIN/PITCH_MAX  voice pitch range per life (0.7 - 1.4)
	  CHARS_PER_BLIP       letters per blip (3)
	  MAX_BLIPS            cap for long messages (12)
	  BLIP_GAP             seconds between blips (0.09)
	  Volume               0.6; heard up to ~60 studs away

	StarterPlayerScripts.ChatVoices.ChatActions:
	  ACTION_FORMAT        how *actions* look (grey italic)
	  Tags                 verbs for auto tags; add or remove freely

	==========================================================================
	Gotchas
	==========================================================================

	* Roblox allows one OnIncomingMessage callback per client. If another
	  script sets it (chat tags, rank colours), the last one to load wins.
	  Merge them into one script.
	* Messages starting with / or : (chat and Adonis commands) are left alone.
	* Team chat and whispers still blip, so people nearby hear that someone
	  spoke, but not what was said.

]]
return nil

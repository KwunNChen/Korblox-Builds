--[[
	Every callout and answer the soldiers use.

	calls.<kind> is split into pools. "any" always fits; the others are only
	used when the situation matches (far away, close, several enemies, a player,
	low health...). An entry is a plain string, or L("line", "answer", ...) when
	the line needs answers that only make sense for it. A string uses the
	generic answers for its kind from replies.<kind>.

	Placeholders: {clock} "two", {dist} "80", {n} "3", {side} "left". Only put {clock} / {dist} /
	{n} in the "spotted", "armor" and "armorAT" calls and in answers to them,
	those are the ones that know where the enemy is.

	An answer can be {"Where?!", back = {...}}: the soldier who made the call
	then says one of the back lines.
]]

local function L(text,...)
	return {text = text, replies = {...}}
end

local lines = {calls = {}, replies = {}}

lines.calls.spotted = {
	any = {
		"Contact!", "Enemy spotted!", "I've got eyes on him!", "Hostile, over there!", "Contact front!",
		"Bogey! Bogey!", "Tango!", "Enemy in the open!", "Movement! Enemy movement!", "I see him!",
		"Got a hostile!", "Enemy sighted!", "Eyes on the enemy!", "There he is!", "Hostile contact!",
		"Enemy! Get ready!", "Target acquired!", "He's right there!", "Looks like trouble!", "Contact, contact, contact!",
		L("Well, hello there.", "Rude of him to drop in.", "Roll out the welcome mat.", "Did he bring snacks?"),
		L("Oh, we've got company.", "Tell him we're not hosting.", "I didn't tidy up!", "Is he the boring kind of company?"),
		L("Somebody's lost.", "Let's help him find the exit.", "Wrong place, wrong time.", "Point him at the ground."),
		L("Uninvited guest!", "Check the guest list.", "Nobody sent him a map?", "Let's make him feel unwelcome."),
		L("There he is, the idiot.", "He really walked right in.", "Fearless or dumb?", "Dumb. Definitely dumb."),
		L("He's not even hiding!", "Insulting, really.", "He thinks we're blind.", "Let's change his mind."),
		L("Guess who showed up.", "Not who I was hoping for.", "Not the pizza guy?", "Tell me it's not the same guy."),
		L("Heads up, fresh meat.", "Dinner's here.", "Let's not play with our food.", "Easy there, tiger."),
		L("Look what the wind blew in.", "The wind has terrible taste.", "Blow him back out.", "Wind needs better aim."),
		L("Is that a hostile or a mirage?", "Mirages don't shoot back.", "Only one way to find out.", "Pinch yourself, then shoot."),
		L("Enemy, and he looks confident.", "That won't last.", "Confidence is cheap.", "Let's audit that confidence."),
		L("I think I found our problem.", "Only one? Lucky us.", "Is it the problem with the gun?", "Problems come in all sizes."),
		L("Somebody ordered a fight?", "Extra large, no onions.", "Put it on my tab.", "Delivery's here, then."),
		L("Hey! You're on the wrong side!", "Tell him slower, he's not listening.", "He's about to learn.", "He can't read the sign."),
		L("Look alive, people!", "I was alive already!", "Alive and ready!", "I'm always alive. Mostly."),
		L("Hostile! Try to look intimidating!", "My face is my weapon.", "I'm doing my best.", "This is my intimidating face."),
		L("Guys. Guys. Enemy.", "We hear you, Gary.", "Can't a guy blink?", "Say it louder, I'm not listening."),
		L("Okay, nobody panic. Enemy.", "I'm panicking a little.", "Calm is my middle name.", "Panic is a state of mind."),
		L("Is that him? That's him.", "Who is him?", "Why do you know him?", "Do you have a fan club?"),
		L("Ooh, a customer!", "Open for business!", "Take his order.", "He pays in lead."),
		L("Surprise visitor, and he's armed.", "At least he brought a gift.", "Return to sender.", "Shall we RSVP?"),
		L("Enemy at the gate!", "Close the gate!", "What gate?", "Good. Gates are overrated."),
		L("Anyone order a bad day?", "He's delivering.", "I'll pay in bullets.", "Tip him with a bullet."),
		L("Visitor! Don't wave, he'll think we're friendly.", "Too late, I waved.", "Waving is polite!", "Wave with the rifle."),
		L("Aha! Found you!", "Hide and seek champion over here.", "Not much of a hider.", "Counting to ten, then shooting."),
		L("Enemy! I knew I wasn't imagining it!", "You imagine plenty of things.", "Told you I wasn't crazy.", "Crazy is a spectrum."),
		L("Eyes front, hostile ahead!", "My eyes were already front.", "Which front?", "Left front or right front?"),
		L("That's a hostile. Pretty sure.", "Pretty sure isn't sure.", "Shoot first, confirm later.", "Is he wearing the wrong color?"),
		L("I see an enemy and it's making my day worse.", "Day's about to get better.", "Mine too, mate.", "Welcome to the club."),
		L("I've got a live one!", "Keep him alive until I get there!", "Don't let him get away!", "A live one? Not for long."),
	},
	far = {
		"Long range contact!", "Enemy, way out there!", "Hostile at distance!", "Far contact!",
		"Enemy far off, {dist} out!", "Contact, {dist} out!", "Distant hostile, {clock} o'clock!",
		L("Enemy at long range, tiny but real.", "Tiny and annoying.", "Is he a bug?", "Zoom in, then."),
		L("Is that a hostile or a very small tree?", "Trees don't wave back.", "Shoot the tree to be sure.", "Small trees can be dangerous."),
		L("Far contact. Try not to trip.", "I only trip in close.", "Don't jinx me.", "Tripping is a talent."),
		L("Someone's brave from way out there.", "Brave or lost.", "He's playing sniper.", "Show him what range is."),
		L("Long haul contact, bring snacks.", "I always bring snacks.", "Share the snacks.", "Save me a sandwich."),
		L("Hostile in the distance, probably checking his watch.", "Probably thinking about lunch.", "Probably lost.", "Probably me in a mirror."),
	},
	close = {
		"Contact, close!", "Enemy right on top of us!", "Hostile in close!", "He's right here!",
		"Enemy, danger close!", "Too close, too close!",
		L("He's way too close!", "Personal space, buddy!", "Knife him!", "Back up, back up!"),
		L("Enemy next to me, I can smell him!", "What does he smell like?", "Don't say it's lunch.", "I can smell it from here too."),
		L("Close contact! Somebody help!", "Coming! Hold on!", "Where? I'll be right there!", "Don't cry, I'm coming!"),
		L("He's practically in my pocket!", "Check your pockets.", "Pickpocket!", "Give him a tip."),
		L("Hostile right in my face!", "Brush your teeth, he'll leave.", "Tell him to back off.", "Hit him with something."),
		L("Enemy in close, and he's not leaving!", "Leave? Where's the fun?", "Make him leave.", "Kindly ask him to go."),
	},
	many = {
		"Multiple contacts!", "Lots of hostiles!", "Several enemies!", "Contacts, {n} of them!",
		"{n} enemies, {clock} o'clock!", "Large group of hostiles!",
		L("There's more than one!", "More than one is a party!", "Count them for me.", "Don't count, shoot."),
		L("Enemies everywhere!", "Everywhere is a big place.", "Where's the worst of it?", "Pick one and start."),
		L("They brought friends!", "Of course they did.", "We brought friends too.", "More targets, more fun."),
		L("Crowd! A crowd of hostiles!", "I hate crowds!", "Let's thin it out.", "Everyone pick a number."),
		L("It's a whole squad of them!", "Ours is bigger.", "Outnumbered?", "Never mind. Aim better."),
		L("Hostile group, {n} of them!", "Which one is the leader?", "Take the loud one first.", "Make every shot count."),
	},
	player = {
		"Live one!", "That's a player!", "Real player contact!",
		L("Looks like a real one, not a bot!", "Bot? Rude.", "Don't embarrass us!", "Make it count!"),
		L("Player! Try to look professional!", "I'm always professional.", "Professional is my middle name.", "I'll fix my hair."),
		L("Somebody's playing hero!", "Let's remind him it's a team game.", "Heroes don't last.", "There's no 'I' in hero."),
		L("That's not an NPC, that's a person!", "People are so loud.", "Persons are my favorite target.", "Be polite, then shoot."),
		L("Player contact! Whoever blinks first loses!", "I don't blink.", "I blink constantly.", "Blink and I shoot."),
		L("Live player! Someone alert the camera crew!", "Smile for the camera!", "We're on TV?", "Look cool."),
		L("A real person! Everybody act normal!", "This is normal.", "I'll act more normal.", "My normal is already weird."),
	},
	clock = {
		"Contact, {clock} o'clock!", "Enemy at {clock} o'clock!", "Hostile, {clock} o'clock, {dist} out!",
		"{clock} o'clock! Enemy!", "Eyes {clock} o'clock!", "Contact, {clock} o'clock, {dist} away!",
		"Enemy! {clock} o'clock!", "Movement at {clock} o'clock!", "Look {clock} o'clock!",
		"Hostile at {clock} o'clock, moving!", "{clock} o'clock, {dist} out, engaging!",
		L("Check your {clock} o'clock!", "Checked. Nothing there.", "I see him now!", "Got him!"),
		L("Hostile at {clock} o'clock, very visible!", "I'll try not to miss him.", "Very visible and very close to dead.", "Spot on, thanks!"),
		L("Enemy, {clock} o'clock, don't look!", "Now I have to look!", "Why would you say that?", "Too late, I looked."),
	},
}

lines.replies.spotted = {
	fresh = {
		"Copy, engaging!", "On me!", "Moving up!", "I see him!", "Got him!", "Rolling in!", "Eyes on!", "Copy that!",
		"On it!", "Tracking!", "Lighting him up!", "Heard you, turning now!", "Covering your flank!", "Say no more!",
		"Right behind you!", "Flanking!", "Turning to engage!", "I'll take the left!", "Taking the right!",
		"Pushing up!", "Roger!", "Understood!", "Acknowledged, engaging!", "Moving to support!", "Contact acknowledged!",
		{"Where?!", back = {"{clock} o'clock!", "Over there, {clock} o'clock!", "{clock} o'clock, {dist} out!", "Dead ahead, look harder!"}},
		{"How many?", back = {"Just one!", "Looks like {n}!", "Count's {n}, I think!", "Enough to be annoying!"}},
		{"Say again?", back = {"Enemy! {clock} o'clock!", "Contact, {clock} o'clock, {dist} out!", "Hostile! Look {clock} o'clock!"}},
		{"Who, him?", back = {"Yes, him!", "Who else?!", "Yes, the one with the gun!"}},
		{"Which direction?", back = {"{clock} o'clock!", "{clock} o'clock, {dist} away!", "Look {clock} o'clock!"}},
	},
	engaged = {
		"I've got one of my own!", "Busy, but copy!", "Same here!", "I've got him too!", "Yeah, I'm on him!",
		"Already on it!", "Me too, he's popular!", "Got my hands full!", "Noted, kinda busy!", "Heard you, one sec!",
		"Already engaged!", "I see him, I'm fighting!", "Working on it!", "Copy, I've got mine!", "Hold on, in the middle of something!",
		"Same enemy, same problem!", "Join the party!", "Keep him busy, I'll finish mine!",
	},
}

lines.calls.reload = {
	any = {
		"Reloading!", "Changing mags!", "Cover me, I'm dry!", "Mag!", "Out of ammo, covering fire!",
		"Reloading, hold the line!", "Swapping mags!", "Empty! Reloading!", "Going dry!", "Out! Cover me!",
		"Reloading, don't die!", "Magazine empty!", "Need a second, reloading!", "Dry! Dry!", "Cover while I reload!",
		L("Out of bullets, out of ideas!", "At least you've got honesty.", "Ideas are for officers.", "Ideas are overrated."),
		L("Hold that thought, reloading!", "I'll hold it, go!", "Don't take forever!", "Take your time. Not really."),
		L("Magazine's empty, my feelings aren't.", "Feelings don't stop bullets.", "Save the feelings for after.", "Me neither, buddy."),
		L("Wait, wait, I need a second!", "Fine, one second.", "You've got ten!", "Counting ten."),
		L("Where did all the bullets go?!", "You shot them, genius.", "Check your pockets.", "Probably in the enemy."),
		L("Dry! Somebody talk to him!", "Hey, enemy, pause!", "I'll keep him busy.", "He's not listening."),
		L("I swear I just loaded this.", "You just loaded it twenty shots ago.", "Count your shots next time.", "They don't last forever."),
		L("Reloading, nobody do anything exciting!", "No promises.", "Excitement is my job.", "I'll try to be boring."),
		L("Out of ammo! Think of me fondly!", "Of course I will.", "You'll be fine, hurry.", "Stop being dramatic."),
		L("Spent! I'm spent!", "You and me both.", "Take a nap while you're at it.", "Hurry up, spent one."),
	},
	close = {
		"Reloading, he's close!", "Mag change, enemy near!", "Dry with a hostile on my face!",
		L("Reloading with a guy right there!", "That's a bold move.", "Bold, dumb, bold.", "Trust me, I've got him."),
		L("Out of ammo and he's close, great!", "Great is a strong word.", "Just keep your head down.", "Do I need to hold your hand?"),
		L("Reloading, don't let him touch me!", "He won't touch you.", "Stay behind me.", "I'll punch him for you."),
	},
}

lines.replies.reload = {
	"I've got you!", "Covering!", "Hurry up, you slowpoke!", "Take your time. Not really, hurry!", "Just stay behind me.",
	"I'll keep him busy.", "Got your back!", "Reload fast!", "Covering fire!", "Copy, I'm on him!",
	"Go, go, I'll hold!", "Don't worry, I'm here!", "Keeping his head down!", "Holding the line!", "Stay low!",
	"I've got the front!", "Roger, covering you!", "You're covered!", "Eyes on him, you load!", "I see him, go!",
}

lines.calls.grenade = {
	any = {
		"Frag out!", "Grenade!", "Fire in the hole!", "Grenade out!", "Frag!",
		"Throwing a grenade!", "Incoming!", "Heads up, grenade!", "Grenade away!", "Frag going out!",
		L("Special delivery!", "Signed, sealed, delivered.", "Return to sender!", "Hope it has a return label."),
		L("Catch!", "I'm not catching that!", "Throw it farther!", "Wrong person, wrong direction!"),
		L("Think fast!", "I'm fast!", "Don't throw it back!", "Think fast? I'm thinking."),
		L("Present for you!", "I didn't get you anything!", "Is it ticking?", "Something dangerous, I assume."),
		L("Hot potato!", "Pass it on!", "I'm not holding that!", "Drop it somewhere else!"),
		L("Duck, everybody!", "Quack.", "I'm already ducking!", "Why are we ducking?"),
		L("Surprise!", "Surprise is a loud word.", "I hate surprises.", "Surprises are the best bit."),
		L("Gift from me to you!", "Gift receipts accepted?", "No refunds.", "Please return to sender."),
		L("Pin's out, don't ask.", "I'm not asking.", "Don't stand there.", "Who pulled it?"),
		L("This one's going to be loud.", "Cover your ears.", "Loud is the whole point.", "Is there a quiet one?"),
		L("This is gonna leave a mark!", "Big mark.", "Bigger than your ego?", "Mark the spot for later."),
		L("Grenade, don't stand in it!", "Obviously!", "I wasn't planning to!", "Who stands in grenades?"),
		L("Time to make a hole!", "Make it a clean one.", "Make it a big one.", "Don't make it near me."),
	},
}

lines.replies.grenade = {
	"Take cover!", "Heads down!", "Not near me you don't!", "Nice arm!", "Everybody get low!",
	"Good throw!", "Getting back!", "Cover your ears!", "Get clear!", "Behind the wall!",
	"I'm backing off!", "Watch the blast!", "Stay out of the blast!", "Gotcha, going low!", "Wait for the boom!",
	"Everyone clear?", "Moving off!", "Clear of the blast!", "Hope you aimed it right!", "Aim it at THEM!",
}

lines.calls.hit = {
	any = {
		"I'm hit!", "Argh, they got me!", "Taking fire!", "Ow! That's coming out of my pay!", "Rude!",
		"I felt that!", "Hit! I'm hit!", "I'm shot!", "Ow, ow, ow!", "I've been hit!",
		"They shot me!", "Contact, I'm hurt!", "Under fire!", "Hit, but still here!", "I'm hurt!",
		L("That one had my name on it!", "Sounds like bad mail.", "Learn to duck.", "Send it back!"),
		L("Medic! Or a hug!", "I can do the hug!", "Medic's busy, sorry.", "Hugs are non-combat approved."),
		L("I just got this uniform!", "It's a bit bloody now.", "The dry cleaner will cry.", "Fashion's overrated."),
		L("Tell my mom I was cool!", "You were not cool.", "Tell her yourself!", "You're fine. Stop being dramatic."),
		L("I felt that in my soul!", "Soul's overrated.", "You have a soul?", "Soul or not, keep fighting!"),
		L("Okay, that stung.", "Walk it off.", "It's just a scratch.", "Rub some dirt on it."),
		L("Somebody shot me. Rude.", "I'd call that normal.", "Aim better next time.", "Shoot back, it's easy."),
		L("They hit me! They actually hit me!", "Congratulations on being a target.", "First time?", "Welcome to the war."),
		L("Ow! My favorite arm!", "You have a favorite arm?", "Use the other one.", "Both arms are the same."),
		L("Hey! I'm using that!", "Using what?", "Use something else.", "Your whole body, probably."),
		L("That's gonna bruise.", "Bruises are tough.", "Put ice on it.", "Bruises heal. Shoot back."),
		L("Is it bad? Don't tell me.", "It's fine. Probably.", "It's, uh, interesting.", "I'm not a doctor."),
		L("I was told this was safe work!", "Who told you that?", "Liar, whoever it was.", "Welcome to reality."),
		L("My lunch is gonna come back up.", "Please do not.", "Aim it at the enemy.", "Gross, go away."),
	},
	low = {
		"I'm bad, I'm real bad!", "Can't take another!", "Need help, now!", "I'm almost out!", "I'm hurting!",
		"One more hit and I'm done!", "I'm barely standing!", "Help, I'm bleeding!",
		L("Medic! Anyone!", "Hold on!", "Hang in there!", "I'm coming!"),
		L("It's a flesh wound! Maybe.", "That's a lot of flesh.", "Looks more like a bone wound.", "Hold on, I'm coming."),
		L("Tell everyone I was a hero!", "You're not dead yet.", "Tell them yourself.", "Hero? You hid behind a crate."),
		L("I can see the light!", "Walk away from the light!", "Too early for that!", "Stay with us."),
		L("Is this what dying feels like?", "Not yet, relax.", "Don't be dramatic, move.", "Dying's worse. Trust me."),
	},
}

lines.replies.hit = {
	"Hang in there!", "Stay with us!", "Walk it off!", "It's just a scratch!", "Shake it off!",
	"I'm coming!", "Shoot back!", "Stay low, stay alive!", "Keep fighting!", "Keep your head down!",
	"You'll be fine!", "Get behind cover!", "Stay up!", "Don't quit now!", "Pull back, I've got you!",
	"I'm covering you!", "Breathe, you're okay!", "Stay in the fight!", "Take cover, I'm here!", "I've got your back!",
}

lines.calls.kill = {
	any = {
		"Target down.", "Got him!", "One less.", "Sit down!", "And stay down!",
		"Enemy down!", "Hostile neutralized!", "He's down!", "Down he goes!", "One down!",
		"That's one!", "Tango down!", "Confirmed kill!", "Got the hostile!", "Took him out!",
		L("Next!", "Hold your horses, I'm reloading.", "Save some for me!", "Who's up?"),
		L("Another one for the wall.", "The wall is getting crowded.", "What wall?", "Add one for me."),
		L("That's gonna leave a mark.", "He's past marks.", "Nice mark.", "Is he okay? I mean, you know."),
		L("Easy.", "Don't get cocky.", "Easy means you got lucky.", "Okay, show-off."),
		L("Better luck next life!", "Hope he has a next life.", "Brutal, but fair.", "Bye bye."),
		L("Did you see that shot?", "I saw it. Impressive.", "Saw it, meh.", "Lucky shot."),
		L("Nothing personal.", "Everything's personal.", "Tell him that.", "Oh, it's a little personal."),
		L("Is he dead? He looks dead.", "He looks dead to me.", "Poke him to be sure.", "Wait, check again."),
		L("And that's how it's done.", "Textbook.", "By the book!", "Bored of how it's done."),
		L("I told him not to move.", "You said no such thing.", "He didn't listen.", "He never listened."),
		L("He never saw it coming.", "Poor guy.", "Neither did I.", "That's the best way."),
		L("Is that all they've got?", "Don't jinx it.", "There's more, there's always more.", "Probably saving the good ones."),
		L("Well, that was easy.", "Don't say that, you'll curse us.", "Stop jinxing everything.", "Easy is relative."),
		L("Ouch, that looked painful.", "Did he feel it?", "He felt something.", "He didn't feel a thing."),
	},
	knife = {
		"Stabbed him!", "Knife work, quiet and clean.", "Got him with the blade!", "Up close and personal!",
		L("Sharp, huh?", "Very.", "Stop talking and sheathe it.", "Too sharp for me."),
		L("Cut him down to size!", "Terrible pun.", "Chop chop.", "That was low."),
		L("Never bring a gun to a knife fight, wait.", "Did he have a gun?", "He did, you did too.", "Rules are for rookies."),
		L("Stuck him good!", "Gross.", "Wipe your blade.", "Disgusting. Nice."),
	},
}

lines.replies.kill = {
	"Nice shot.", "Good kill.", "Show off.", "Beginner's luck!", "Save some for me!",
	"Do that again!", "Okay, that was clean.", "Not bad!", "Good work!", "Keep it up!",
	"Well done!", "Textbook.", "That's how it's done.", "One more and you win a prize.", "Impressive!",
	"Keep your eyes open!", "More where he came from!", "Stay sharp!", "Don't get cocky!", "Good eye!",
}

lines.calls.manDown = {
	any = {
		"Man down!", "No! Medic!", "We lost one!", "He's gone!", "Soldier down!",
		"Not again!", "Somebody's down!", "We've got a casualty!", "He's not moving!", "Oh no, he's out!",
		"One of ours is down!", "We lost a friend!", "He didn't make it!", "They killed him!", "Squadmate down!",
		L("They got Dave!", "Dave was a good man.", "Who's Dave?", "Dave owed me twenty."),
		L("Somebody tell his wife!", "He doesn't have a wife.", "Who's gonna tell her?", "Not it."),
		L("I owed him lunch!", "You can still pay.", "You owed him lunch? Eat it for him.", "Now you never will."),
		L("Who's gonna carry the snacks now?", "Not me.", "That's a deep question.", "We'll divide them."),
		L("That's going in the report!", "What report?", "Write it up, then.", "Include a nice description."),
		L("He was just here a second ago!", "Not anymore.", "Gone, just like that.", "Yeah. That's how it goes."),
		L("I liked him, he lent me stuff!", "Did you give it back?", "Now you can keep it.", "He lent me stuff too."),
		L("He always forgot his helmet.", "That explains it.", "I told him.", "Rest easy, forgetful one."),
		L("One of us is down. Pretend you're not scared.", "I'm not scared.", "I'm a little scared.", "Scared is fine."),
		L("No, no, no, no!", "Yes, yes, yes, yes.", "Stay calm.", "Breathe, please."),
		L("This is not the plan!", "What plan?", "There was never a plan.", "Adapt!"),
		L("That's it, I'm mad now!", "Good, stay mad!", "Mad is useful.", "Take it out on them."),
	},
}

lines.replies.manDown = {
	"Poor guy.", "He was a good soldier.", "Revenge time!", "That's it, I'm mad now!", "Somebody check on him!",
	"Oh man, I liked him!", "Stay focused!", "We'll make them pay!", "Eyes up, there's more!", "Rest easy, buddy.",
	"We'll miss him.", "Don't lose it, keep going!", "No time to mourn, move!", "For him, boys!", "Get back in the fight!",
	"I'll never forgive them!", "Keep your head down!", "He was too young!", "Pay them back!", "We stand, we fight!",
}

lines.calls.lost = {
	any = {
		"Where'd he go?", "Lost him!", "Lost sight of him!", "He's gone!", "Where did he go?",
		"I lost the hostile!", "He vanished!", "Hostile's out of sight!", "Anyone see him?", "No visual!",
		L("He was just here!", "Not anymore.", "Maybe he went to lunch.", "Stop losing people."),
		L("Where did my target go?", "Not my problem.", "Look behind you!", "Maybe he's hiding."),
		L("That coward ran away!", "Smart man.", "Let him go, save your ammo.", "Cowards live longer."),
		L("Wait, wait, where did he go?", "I'm not your babysitter.", "Check around the corner.", "He's playing hide and seek."),
		L("Poof! Gone!", "Magic.", "Wizard?", "Don't believe in magic."),
		L("He ducked behind cover!", "Cover works both ways.", "Wait him out.", "Pop him when he looks."),
	},
}

lines.replies.lost = {
	"Stay sharp.", "Keep your eyes open.", "He'll come back.", "Watch your corners.", "Don't let your guard down.",
	"Check your flanks.", "He's still out there.", "Stay alert.", "Hold position.", "Hold what you have.",
}

lines.calls.cover = {
	any = {
		"Taking cover!", "Moving to cover!", "Getting behind something!", "Need cover!", "Pulling back to cover!",
		"Cover, cover, cover!", "Going to ground!", "Falling back to cover!", "Heading for cover!", "Getting low!",
		L("Time to hide!", "Hide well.", "Hide fast!", "Try not to be obvious."),
		L("Nope, nope, nope, cover!", "Smart move.", "Get behind the wall!", "Don't stop for me."),
		L("That's a lot of bullets, I'm out!", "Fair enough!", "Smart.", "Don't blame you."),
		L("I'm not paid enough for this, cover!", "Nobody is.", "Get low!", "Join the club."),
		L("Behind the wall, see you in a bit!", "I'll keep him busy.", "Go, go!", "Don't take too long."),
		L("Ducking out!", "Ducking is wise.", "Quack.", "Duck faster!"),
		L("Gonna sit this one out for a second.", "Don't be long.", "Take a seat.", "Enjoy the view."),
	},
}

lines.replies.cover = {
	"Go, I've got you!", "Covering!", "Keeping his head down!", "I'll hold him!", "Get behind it!",
	"Move, move!", "I've got the front!", "Right behind you!", "Stay low!", "Don't stop!",
	"Go, go, go!", "I'll keep firing!", "Take your time, I'm here!", "Good call!", "Holding his attention!",
}

lines.calls.advance = {
	any = {
		"Moving up!", "Pushing forward!", "Advancing!", "On the move!", "Moving out!",
		"Moving to flank!", "Going forward!", "Coming out!", "Here I come!", "Time to push!",
		L("Enough hiding, let's go!", "About time!", "Finally!", "I was starting to get bored."),
		L("Alright, moving!", "Go, I'm behind you.", "Watch the corners.", "Move out."),
		L("My turn to be brave!", "Brave is a strong word.", "Try not to die.", "I'll watch the rear."),
		L("Let's end this!", "Let's.", "Aim for the head.", "Follow me."),
	},
}

lines.replies.advance = {
	"Covering you!", "Go, go!", "Moving with you!", "I've got your six!", "Right behind you!",
	"Watch yourself!", "Keep low!", "I'll cover!", "Move up, I'm covering!", "Good luck!",
	"Go ahead!", "I'm with you!", "Hold on, wait for me!", "Lead the way!", "On your left!",
}

--Squad leader orders and the drill calls. {side} is "left" or "right" in orderFlank only.
lines.calls.orderBound = {
	any = {
		"Bounding overwatch, move!", "Bravo, move! Alpha, cover!", "Leapfrog up, by teams!", "Bound up, one team at a time!",
		"Move by bounds!", "Alpha covers, Bravo moves!", "Bounding forward!", "Fire and move, go!",
		L("We're pushing. By the book, people!", "What book?", "Which page?", "The one with the pictures."),
		L("Bound up, and nobody trip this time!", "That was one time!", "No promises.", "I tripped on purpose."),
		L("Move up in bounds! Short rushes!", "Short like your patience?", "Copy, short rushes!", "Rushing short!"),
	},
}

lines.replies.orderBound = {
	"Copy, bounding!", "Roger, moving by bounds!", "Bravo moving!", "Alpha set, covering!", "On your call!",
	"Moving up!", "Got it!", "Covering the move!", "Ready to bound!", "Understood!",
}

lines.calls.orderFlank = {
	any = {
		"Alpha, base of fire! Bravo, flank {side}!", "Bravo, take the {side}! Alpha, keep his head down!",
		"Flank {side}! Alpha, suppress!", "Base of fire here! Bravo, go {side}!", "Pin him down! Bravo, around the {side}!",
		"Hold him here, Bravo goes {side}!",
		L("Bravo, around the {side}, quietly this time!", "We're always quiet.", "Define quietly.", "Quiet as a mouse with a rifle."),
		L("Alpha, make noise! Bravo, sneak {side}!", "Making noise is my specialty!", "Sneaking {side}!", "Loud and proud!"),
	},
}

lines.replies.orderFlank = {
	"Bravo moving!", "Copy, flanking!", "Alpha, base of fire set!", "Suppressing!", "Roger that!",
	"On it, going round!", "Keep him busy!", "Pinning him!", "Moving on the flank!", "Covering Bravo!",
}

lines.calls.orderPincer = {
	any = {
		"Alpha left, Bravo right, pincer him!", "Split up! Hit him from both sides!", "Pincer! Get round both sides!",
		"Both flanks, go quiet, wait for my call!", "Box him in! Teams, opposite sides!",
		L("Pincer. Nobody shoots till I say!", "Not even a little?", "Copy, quiet!", "Waiting on you!"),
	},
}

lines.replies.orderPincer = {
	"Going left!", "Going right!", "Moving round!", "Copy, holding fire!", "Waiting on your call!",
}

lines.calls.orderPincerGo = {
	any = {
		"Both sides, go now!", "Now! Hit him!", "Pincer, go, go!", "Everyone in, now!", "Close it! Go!",
	},
}

lines.replies.orderPincerGo = {
	"Going in!", "Moving!", "Hitting him!", "In we go!", "Closing!",
}

lines.calls.orderAssault = {
	any = {
		"Bravo, assault!", "Bravo's set, assault through!", "Go, go, assault!", "Bravo, take him!",
		"Assault, assault!", "Bravo, in you go!",
		L("Bravo, it's your turn to be heroes!", "Finally!", "Heroes on the move!", "I was born for this!"),
	},
}

lines.replies.orderAssault = {
	"Assaulting!", "Going in!", "Moving through!", "Here we go!", "Bravo moving in!",
	"Pushing through!", "On my way!", "Into the breach!",
}

lines.calls.shiftFire = {
	any = {
		"Shift fire!", "Cease fire, Bravo's in!", "Lift fire, friendlies close!", "Alpha, check fire!",
		"Shift fire, shift fire!", "Hold fire, our guys are in!",
		L("Stop shooting, they're right there!", "Stopping!", "Checking fire!", "Oops, okay!"),
	},
}

lines.replies.shiftFire = {
	"Shifting!", "Fire lifted!", "Checking fire!", "Holding fire!", "Copy, cease fire!", "Weapons tight!",
}

lines.calls.orderBreak = {
	any = {
		"Break contact! Fall back!", "Too many! Fall back by teams!", "Break contact, bound back!", "Pull back, pull back!",
		"We're leaving! Cover each other!", "Fall back, Alpha covers!", "Get out of here, by bounds!",
		L("Nope! Tactical retreat!", "Tactical running away.", "I love tactics!", "Agreed! Agreed!"),
		L("That's a lot of them! Leave!", "Way ahead of you!", "Leaving!", "Right behind you!"),
		L("Fall back, this is a bad day!", "Worst day!", "Copy, falling back!", "Bad day, good legs!"),
	},
}

lines.replies.orderBreak = {
	"Falling back!", "Covering the move!", "Moving back!", "Copy, breaking contact!", "Pulling back!",
	"Go, I've got you!", "Bounding back!", "Right behind you!", "Retreating!", "On your call!",
}

lines.calls.rally = {
	any = {
		"Rally on me!", "Regroup on me!", "On me, everyone!", "Form on me!", "Rally up!",
		"Regroup, regroup!", "Everyone, on me!",
		L("Rally up! Anyone missing?", "All here!", "Count me in.", "Still got all my fingers!"),
		L("On me! Head count!", "One!", "Here!", "Present!"),
	},
}

lines.replies.rally = {
	"Coming!", "On you!", "Moving to you!", "Rallying!", "Here!", "Present!", "Regrouping!", "Right behind you!",
}

lines.calls.rush = {
	any = {
		"I'm up!", "Moving!", "Rushing!", "Going!", "Up, moving!", "On the move!", "Here I go!", "Covering? Good, moving!",
	},
}

lines.calls.set = {
	any = {
		"I'm down!", "Set!", "In position!", "Down, covering!", "Set, covering!", "I'm set!", "Got cover!",
	},
}

--Vehicle crew calls.
lines.calls.mountDriver = {
	any = {
		"I'll drive!", "I've got the wheel!", "Getting in, I'm driving!", "Mount up, I'm driving!", "Keys are mine!",
		L("Shotgun! Wait, no, I'm driving!", "Just drive.", "Nobody calls shotgun on a warthog.", "Fine, drive."),
		L("Everybody in, we're taking the hog!", "Finally!", "Right behind you!", "Don't flip it this time."),
		L("I'm driving. Hold on to something.", "Oh no.", "Seatbelts?", "There are no seatbelts."),
	},
}

lines.replies.mountDriver = {
	"I'll take the gun!", "On the turret!", "Right behind you!", "Don't flip it!", "Go, go!",
	"Drive like you mean it!", "Watch the bumps!",
}

lines.calls.mountGunner = {
	any = {
		"On the gun!", "I've got the turret!", "Gunner up!", "Turret's mine!", "Manning the gun!",
		L("Get me on that gun!", "It's all yours!", "Light them up!", "Spin it up!"),
		L("Drive, I'll shoot!", "Driving!", "Hold on!", "Here we go!"),
	},
}

lines.replies.mountGunner = {
	"Hold on tight!", "Light them up!", "Let's roll!", "Moving!", "Keep that barrel hot!",
	"Here we go!", "Spin it up!",
}

lines.calls.bail = {
	any = {
		"Bail out! Bail out!", "She's going! Get out!", "Out, out, out!", "Abandon the vehicle!", "It's done, bail!",
		L("This thing's on fire! Out!", "Way ahead of you!", "Out!", "I'm out!"),
	},
}

lines.replies.bail = {
	"Out!", "Moving!", "Get clear!", "Run!", "Away from it!", "I'm out!",
}

--The radioman calling in artillery, and his squadmates clearing out.
lines.calls.fireMission = {
	any = {
		"Fire mission! Everyone pull back!", "Artillery inbound! Get clear!", "Rounds on the way, move!",
		"Danger close, fall back now!", "Arty's coming, clear the area!", "Splash incoming, get out of there!",
		"Fire mission called, back off!", "Guns are up, get clear of the target!",
		L("I just called in the big guns, run!", "Running!", "You could have warned us sooner!", "Way ahead of you!"),
		L("Fire mission! Don't stand around admiring it!", "Admiring from far away!", "Moving!", "It's very pretty though."),
		L("Artillery inbound, and I'm not taking it back!", "Nobody asked you to!", "Get clear!", "Good, now run!"),
	},
}

lines.replies.fireMission = {
	"Moving back!", "Clearing out!", "Getting clear!", "Falling back!", "Copy, pulling back!",
	"Out of the way!", "Running!", "Right behind you!", "Heads down, everyone!", "Get clear, get clear!",
}

--A soldier who sees an enemy vehicle: armorAT when an AT team on his side can
--come for it, armor when there is none.
lines.calls.armorAT = {
	any = {
		"Armor, {clock} o'clock, {dist} out! Get AT on it!", "Enemy vehicle, {clock} o'clock! Calling the Javelin!",
		"Vehicle at {clock} o'clock! AT team, you're up!", "Armor spotted, {dist} out! Send the AT team!",
		"Contact, vehicle, {clock} o'clock! Need AT up here!", "Tank! {clock} o'clock! Get me a Javelin!",
		L("Big metal problem at {clock} o'clock! Get AT!", "Calling it in!", "AT's on the way!", "Javelin's coming!"),
		L("That's a vehicle! Somebody call the tube guys!", "Already done!", "They're coming!", "Radioing AT!"),
	},
}

lines.replies.armorAT = {
	"Calling AT!", "AT's on the way!", "Copy, armor!", "Javelin's coming!", "Radioing it in!",
	"Keep your heads down till AT gets here!", "Don't shoot it with that, wait for AT!",
}

lines.calls.armor = {
	any = {
		"Armor, {clock} o'clock! Get down!", "Enemy vehicle, {clock} o'clock, {dist} out!", "Vehicle! {clock} o'clock! Take cover!",
		"Tank, {clock} o'clock! Find something solid!", "Armor spotted, {dist} out!",
		L("Vehicle! We've got nothing for that!", "Then hide!", "Rifles won't cut it!", "Find cover, find cover!"),
	},
}

lines.replies.armor = {
	"Get down!", "Find cover!", "Copy, armor!", "Rifles won't do it!", "Stay out of its sights!",
}

--The rocketeer taking a vehicle someone called in, and firing at it.
lines.calls.atMoving = {
	any = {
		"AT moving! We'll take that vehicle!", "Javelin's on the way!", "Copy armor, AT moving!", "On it! Loader, with me!",
		"AT team, moving to engage!", "We've got the armor, moving!",
		L("Somebody ordered a Javelin?", "Right behind you!", "Got your reload!", "Let's go hunting!"),
		L("Armor called in, let's go kill it!", "With you!", "Got the spare tube!", "Moving!"),
	},
}

lines.replies.atMoving = {
	"Right behind you!", "Got your reload!", "With you!", "Moving!", "Spare tube's ready!",
}

lines.calls.javelinOut = {
	any = {
		"Javelin out!", "Missile away!", "Backblast clear! Firing!", "Rocket away!", "Firing Javelin!",
		L("Javelin out! Watch it fly!", "Good launch!", "Get some!", "Reloading you!"),
	},
}

lines.replies.javelinOut = {
	"Good launch!", "Get some!", "Reloading!", "Next tube coming!", "Watch it dive!",
}

--A sniper moving off a spot the enemy has found.
lines.calls.relocate = {
	any = {
		"Relocating!", "Moving positions!", "They've got my spot, moving!", "Displacing!", "New position, moving!",
		"Too many shots from here, moving!", "No shot from here, moving!", "Can't see them, shifting!",
		L("They know where I am. Moving!", "With you!", "Covering you!", "Go, I've got you!"),
	},
}

lines.replies.relocate = {
	"With you!", "Covering you!", "Moving!", "Right behind you!", "Go, I've got you!",
}

--The enemy is reloading or healing: push him.
lines.calls.enemyReloading = {
	any = {
		"He's reloading, push!", "He's dry! Go, go!", "Reloading! Move up!", "He's changing mags, push him!",
		"He's out! Get on him!", L("I hear him reloading!", "Pushing!", "Go now!", "Moving up!"),
	},
}

lines.replies.enemyReloading = {
	"Pushing!", "Moving up!", "Go now!", "On him!", "Covering!",
}

lines.calls.enemyHealing = {
	any = {
		"He's patching up, push!", "He's healing, get on him!", "He's hurt, go now!", "Don't let him heal, push!",
		L("He's bandaging up!", "Pushing!", "Finish him!", "Moving!"),
	},
}

lines.replies.enemyHealing = {
	"Pushing!", "Finish him!", "Moving up!", "On him!",
}

--Holding an angle instead of pushing.
lines.calls.holdAngle = {
	any = {
		"Holding this angle!", "Watching that gap!", "Eyes on the treeline!", "I've got this side!",
		"Holding here, let them come!", "Not walking into that. Holding!", "Covering that lane!",
		L("Anyone want to go first? No? Holding.", "Holding!", "Not me!", "Same."),
	},
}

lines.replies.holdAngle = {
	"Copy, holding!", "Got the other side!", "Watching left!", "Watching right!", "Holding with you!",
}

--Morale: losing his nerve, breaking and running, and pulling himself together.
lines.calls.shaken = {
	any = {
		"This is bad, this is really bad!", "They're tearing us apart!", "We're getting slaughtered out here!",
		"I don't like this!", "How many of them are there?!", "We're dropping like flies!",
		L("I can't do this!", "Yes you can!", "Stay with me!", "Breathe, keep shooting!"),
		L("Too many of us are down!", "Keep it together!", "Then fight harder!", "Focus!"),
	},
}

lines.replies.shaken = {
	"Keep it together!", "Stay with me!", "Eyes up!", "Hold it together!", "Breathe!", "Don't lose it now!",
}

lines.calls.broken = {
	any = {
		"I'm out of here!", "Run! Run!", "Retreat! They're everywhere!", "Every man for himself!",
		"I'm not dying here!", "Forget this, I'm gone!", "Fall back! Fall back!",
		L("I'm done! I'm done!", "Get back here!", "Coward!", "Don't leave us!"),
	},
}

lines.replies.broken = {
	"Get back here!", "Hold the line!", "Don't leave us!", "Coward!", "Where are you going?!", "Stay and fight!",
}

lines.calls.rallied = {
	any = {
		"Okay. Okay. I'm good.", "Alright, I'm back in it!", "Pull it together... I'm good.", "Sorry. I'm back.",
		L("I'm alright now, I'm alright.", "Welcome back!", "Good, now fight!", "Took you long enough."),
	},
}

lines.replies.rallied = {
	"Welcome back!", "Good, now fight!", "Glad you're with us!", "There he is!",
}

lines.solo = {
	"Quiet.", "Too quiet.", "Hmm.", "Nothing to see here.", "Still nothing.",
	"I wonder what's for dinner.", "Man, my feet hurt.", "Just another day.", "Another boring shift.", "Nothing happening.",
	"This beats being at the office.", "I should've gone to college.", "I should call my mom.", "I could use a nap.", "Coffee. I need coffee.",
	"Is it lunch yet?", "My boots are too tight.", "I'm bored.", "Bored, bored, bored.", "Sunny day, huh?",
	"I wonder what the enemy is doing.", "I hope I locked the barracks.", "Stay alert, they said.", "It's fine. Everything's fine.", "Do I have a spare mag? Yep.",
	"I think I'm getting a cold.", "Guard duty. Glamorous.", "Look at me, guarding things.", "I've been standing here for hours.", "I wonder if I'll get promoted.",
	"Is that a cloud or a plane?", "I wish I had a radio.", "Whistling in the dark.", "Mm-hm.", "Okay, okay.",
	"Humming a tune.", "Is this thing on?", "Any minute now.", "I think I heard something. Nope.", "Just me and my rifle.",
	"I should write my memoirs.", "They never give us enough water.", "My helmet's itchy.", "Why are the rations always beans?", "At ease, me.",
	"My rifle needs a name.", "I'll be fine. I'll be fine.", "Nice weather for a war.", "I miss my bunk.", "No news is good news.",
	"One more hour, one more hour.", "I should stretch.", "Stay frosty, soldier.", "Do I smell smoke?", "Everything's under control.",
}

lines.calls.pilotJoin = {
	any = {
		"I'm down! Linking up with the nearest squad!", "Bird's gone. Heading for friendlies!",
		"Pilot on foot, moving to you!", "I need a rifle squad, coming to you!",
	},
}
lines.replies.pilotJoin = {
	"Come on in, flyboy!", "We've got you!", "Welcome to the mud!", "On us!",
}

lines.calls.reconReport = {
	any = {
		"Eyes on hostiles, sending it up!", "Recon here, contact marked!", "Target located, passing grid!",
		"Got eyes on them. Phantoms, you're cleared on my mark!", "Spotted, relaying position!",
	},
}
lines.replies.reconReport = {
	"Copy, staying low.", "Logged it.", "Good copy, we stay hidden.",
}
lines.calls.airCall = {
	any = {
		"Enemy air overhead, requesting fast movers!", "Need a Phantom on station, now!",
		"Bandit in the sky! Calling it in!", "Fast movers requested, enemy aircraft!",
	},
}
lines.replies.airCall = {
	"Phantom inbound!", "Copy, birds on the way!", "Hang tight, air's coming!",
}

lines.calls.armorAirCall = {
	any = {
		"Armor spotted, requesting fast movers!", "Tank in the open, need a Phantom on it!",
		"Heavy armor! Calling air!", "Need a Maverick on that tank, now!",
	},
}
lines.replies.armorAirCall = {
	"Phantom inbound!", "Copy, air's coming for it!", "Keep eyes on it!",
}

lines.calls.groundAirCall = {
	any = {
		"Requesting gun run on my position, danger close!", "Need a Phantom on those troops!",
		"Fast movers, infantry in the open!", "Calling air on them, keep your heads down!",
	},
}
lines.replies.groundAirCall = {
	"Phantom inbound!", "Copy, gun run coming!", "Mark it and get low!",
}

lines.calls.reconTasked = {
	any = {
		"Recon's got a target for us, move!", "Grid from recon, let's go!", "Recon spotted them, go get them!",
	},
}
lines.replies.reconTasked = {
	"Moving!", "On it!", "Right behind you!",
}

lines.calls.findShooter = {
	any = {
		"Where's that coming from?!", "Find that shooter!", "He's hit! Get the guy who did it!",
		"Shooter! Over there, go!", "Somebody find that rifleman!",
	},
}
lines.replies.findShooter = {
	"On it!", "Looking!", "Moving!", "I see where it came from!",
}

lines.calls.air = {
	any = {
		"Aircraft! Get under cover!", "Air! Air! Hide!", "Jet inbound, find a roof!", "Bird overhead, stay out of sight!",
		"Get off the open ground, he's strafing!",
	},
}
lines.replies.air = {
	"Taking cover!", "Under cover!", "Staying hidden!", "Moving!",
}

lines.calls.unitSplit = {
	any = {
		"We're spread too thin, split up!", "Break into two groups!", "Second group, you're on your own, go!",
		"Split the unit, half on me!", "Too few for this, split it!",
	},
}
lines.replies.unitSplit = {
	"Copy, splitting!", "Second group, on me!", "Roger, breaking off!", "Moving out!",
}

lines.calls.enemyShotgun = {
	any = {
		"He's got a shotgun, keep your distance!", "Shotgun! Don't let him close!", "Stay back, he's got a scattergun!",
		"Keep him at range!", "Don't get close to that one!",
	},
}
lines.replies.enemyShotgun = {
	"Keeping back!", "Copy, distance!", "Not getting close!", "Staying out of his reach!",
}

lines.calls.enemySniper = {
	any = {
		"Sniper! Keep your heads down!", "He's scoped in, don't peek long!", "Marksman! Rush him!",
		"Sniper! Close the distance!", "Scope glint! Get on him!",
	},
}
lines.replies.enemySniper = {
	"Heads down!", "Moving in!", "Copy!", "Short peeks!",
}

lines.calls.enemyMG = {
	any = {
		"Machine gun! Wait out the bursts!", "MG! Stay down!", "Automatic fire! Keep your heads down!",
		"He's got a bullet hose! Stay in cover!",
	},
}
lines.replies.enemyMG = {
	"Staying down!", "Copy!", "Waiting it out!", "Pinned!",
}

return lines

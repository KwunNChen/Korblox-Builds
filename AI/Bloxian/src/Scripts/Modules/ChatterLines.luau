--[[
	Every callout and answer the soldiers use.

	calls.<kind> is split into pools. "any" always fits; the others are only
	used when the situation matches (far away, close, several enemies, a player,
	low health...). An entry is a plain string, or L("line", "answer", ...) when
	the line needs answers that only make sense for it. A string uses the
	generic answers for its kind from replies.<kind>.

	Placeholders: {clock} "two", {dist} "80", {n} "3", {side} "left". Only put {clock} / {dist} /
	{n} in the "spotted", "armor" and "armorAT" calls and in answers to them,
	those are the ones that know where the enemy is. {grid} "503-498" and {compass}
	"northeast" are only for chatter.radio's reports.

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
		"Enemy in the open!", "Movement! Enemy movement!", "I see him!",
		"Got a hostile!", "Enemy sighted!", "Eyes on the enemy!", "There he is!", "Hostile contact!",
		"Enemy! Get ready!", "He's right there!", "Contact, contact, contact!",
	},
	far = {
		"Long range contact!", "Enemy, way out there!", "Hostile at distance!", "Far contact!",
		"Enemy far off, {dist} out!", "Contact, {dist} out!", "Distant hostile, {clock} o'clock!",
	},
	close = {
		"Contact, close!", "Enemy right on top of us!", "Hostile in close!", "He's right here!",
		"Enemy, danger close!", "Too close, too close!",
		L("He's way too close!", "Back up!", "Knife him!", "Hit him!"),
		L("Close contact! Somebody help!", "Coming! Hold on!", "Where? I'll be right there!", "Hold on, I'm coming!"),
	},
	many = {
		"Multiple contacts!", "Lots of hostiles!", "Several enemies!", "Contacts, {n} of them!",
		"{n} enemies, {clock} o'clock!", "Large group of hostiles!",
		L("There's more than one!", "Count them for me.", "Pick your targets.", "Don't count, shoot."),
		L("Enemies everywhere!", "Where's the worst of it?", "Pick one and start.", "Watch your sector!"),
		L("It's a whole squad of them!", "Hold your ground!", "Make every shot count.", "Stay in cover!"),
		L("Hostile group, {n} of them!", "Which one is the leader?", "Take the loud one first.", "Make every shot count."),
	},
	player = {
		"This one's different, watch him!", "Careful, this one knows what he's doing!", "Priority target!",
		"Watch this one, he's good!", "That one's dangerous!", "Stay on that one!",
	},
	clock = {
		"Contact, {clock} o'clock!", "Enemy at {clock} o'clock!", "Hostile, {clock} o'clock, {dist} out!",
		"{clock} o'clock! Enemy!", "Eyes {clock} o'clock!", "Contact, {clock} o'clock, {dist} away!",
		"Enemy! {clock} o'clock!", "Movement at {clock} o'clock!", "Look {clock} o'clock!",
		"Hostile at {clock} o'clock, moving!", "{clock} o'clock, {dist} out, engaging!",
		L("Check your {clock} o'clock!", "Checked. Nothing there.", "I see him now!", "Got him!"),
	},
}

lines.replies.spotted = {
	fresh = {
		"Copy, engaging!", "On me!", "Moving up!", "I see him!", "Got him!", "Rolling in!", "Eyes on!", "Copy that!",
		"On it!", "Tracking!", "Lighting him up!", "Heard you, turning now!", "Covering your flank!", 
		"Right behind you!", "Flanking!", "Turning to engage!", "I'll take the left!", "Taking the right!",
		"Pushing up!", "Roger!", "Understood!", "Acknowledged, engaging!", "Moving to support!", "Contact acknowledged!",
		{"Where?!", back = {"{clock} o'clock!", "Over there, {clock} o'clock!", "{clock} o'clock, {dist} out!", "Dead ahead, look harder!"}},
		{"How many?", back = {"Just one!", "Looks like {n}!", "Count's {n}, I think!"}},
		{"Say again?", back = {"Enemy! {clock} o'clock!", "Contact, {clock} o'clock, {dist} out!", "Hostile! Look {clock} o'clock!"}},
		{"Which direction?", back = {"{clock} o'clock!", "{clock} o'clock, {dist} away!", "Look {clock} o'clock!"}},
	},
	engaged = {
		"I've got one of my own!", "Busy, but copy!", "Same here!", "I've got him too!", "Yeah, I'm on him!",
		"Already on it!", "Got my hands full!", "Heard you, one sec!",
		"Already engaged!", "I see him, I'm fighting!", "Working on it!", "Copy, I've got mine!", "Hold on, in the middle of something!",
		"Keep him busy, I'll finish mine!",
	},
}

lines.calls.reload = {
	any = {
		"Reloading!", "Changing mags!", "Cover me, I'm dry!", "Mag!", "Out of ammo, covering fire!",
		"Reloading, hold the line!", "Swapping mags!", "Empty! Reloading!", "Going dry!", "Out! Cover me!",
		"Magazine empty!", "Need a second, reloading!", "Dry! Dry!", "Cover while I reload!",
	},
	close = {
		"Reloading, he's close!", "Mag change, enemy near!", "Dry with a hostile on my face!",
	},
}

lines.replies.reload = {
	"I've got you!", "Covering!", "Just stay behind me.",
	"I'll keep him busy.", "Got your back!", "Reload fast!", "Covering fire!", "Copy, I'm on him!",
	"Go, go, I'll hold!", "Don't worry, I'm here!", "Keeping his head down!", "Holding the line!", "Stay low!",
	"I've got the front!", "Roger, covering you!", "You're covered!", "Eyes on him, you load!", "I see him, go!",
}

lines.calls.grenade = {
	any = {
		"Frag out!", "Grenade!", "Fire in the hole!", "Grenade out!", "Frag!",
		"Throwing a grenade!", "Incoming!", "Heads up, grenade!", "Grenade away!", "Frag going out!",
	},
}

lines.replies.grenade = {
	"Take cover!", "Heads down!", "Nice arm!", "Everybody get low!",
	"Good throw!", "Getting back!", "Cover your ears!", "Get clear!", "Behind the wall!",
	"I'm backing off!", "Watch the blast!", "Stay out of the blast!", "Gotcha, going low!", "Wait for the boom!",
	"Everyone clear?", "Moving off!", "Clear of the blast!", "Hope you aimed it right!", 
}

lines.calls.hit = {
	any = {
		"I'm hit!", "Argh, they got me!", "Taking fire!", 
		"I felt that!", "Hit! I'm hit!", "I'm shot!", "I've been hit!",
		"They shot me!", "Contact, I'm hurt!", "Under fire!", "Hit, but still here!", "I'm hurt!",
	},
	low = {
		"I'm bad, I'm real bad!", "Can't take another!", "Need help, now!", "I'm almost out!", "I'm hurting!",
		"One more hit and I'm done!", "I'm barely standing!", "Help, I'm bleeding!",
		L("Medic! Anyone!", "Hold on!", "Hang in there!", "I'm coming!"),
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
		"Target down.", "Got him!", "One less.", 
		"Enemy down!", "Hostile neutralized!", "He's down!", "Down he goes!", "One down!",
		"That's one!", "Tango down!", "Confirmed kill!", "Got the hostile!", "Took him out!",
	},
	knife = {
		"Knifed him!", "Stabbed him!", "Got him with the blade!", 
	},
}

lines.replies.kill = {
	"Nice shot.", "Good kill.", "Save some for me!",
	"Okay, that was clean.", "Not bad!", "Good work!", "Keep it up!",
	"Well done!", "Textbook.", "That's how it's done.", "Impressive!",
	"Keep your eyes open!", "More where he came from!", "Stay sharp!", "Don't get cocky!", "Good eye!",
}

lines.calls.manDown = {
	any = {
		"Man down!", "No! Medic!", "We lost one!", "He's gone!", "Soldier down!",
		"Not again!", "Somebody's down!", "We've got a casualty!", "He's not moving!", 
		"One of ours is down!", "We lost a friend!", "He didn't make it!", "They killed him!", "Squadmate down!",
		L("He was just here a second ago!", "Gone, just like that.", "Yeah. That's how it goes.", "Keep moving."),
		L("No, no, no, no!", "Stay calm.", "Breathe.", "Eyes up!"),
	},
}

lines.replies.manDown = {
	"Poor guy.", "He was a good soldier.", "Somebody check on him!",
	"Stay focused!", "We'll make them pay!", "Eyes up, there's more!", "Rest easy, buddy.",
	"We'll miss him.", "Don't lose it, keep going!", "No time to mourn, move!", "Get back in the fight!",
	"Keep your head down!", "Pay them back!", 
}

lines.calls.lost = {
	any = {
		"Where'd he go?", "Lost him!", "Lost sight of him!", "He's gone!", "Where did he go?",
		"I lost the hostile!", "He vanished!", "Hostile's out of sight!", "Anyone see him?", "No visual!",
		L("He ducked behind cover!", "Wait him out.", "Pop him when he looks.", "Watch that corner."),
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
		"Moving to flank!", "Going forward!", "Coming out!", "Time to push!",
		L("Alright, moving!", "Go, I'm behind you.", "Watch the corners.", "Move out."),
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
		L("Move up in bounds! Short rushes!", "Copy, short rushes!", "Moving!", "Rushing!"),
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
		L("Pincer. Nobody shoots till I say!", "Copy, holding fire!", "Waiting on you!", "Set!"),
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
	},
}

lines.replies.orderAssault = {
	"Assaulting!", "Going in!", "Moving through!", "Here we go!", "Bravo moving in!",
	"Pushing through!", "On my way!", 
}

lines.calls.shiftFire = {
	any = {
		"Shift fire!", "Cease fire, Bravo's in!", "Lift fire, friendlies close!", "Alpha, check fire!",
		"Shift fire, shift fire!", "Hold fire, our guys are in!",
		L("Stop shooting, they're right there!", "Stopping!", "Checking fire!", "Fire lifted!"),
	},
}

lines.replies.shiftFire = {
	"Shifting!", "Fire lifted!", "Checking fire!", "Holding fire!", "Copy, cease fire!", "Weapons tight!",
}

lines.calls.orderBreak = {
	any = {
		"Break contact! Fall back!", "Too many! Fall back by teams!", "Break contact, bound back!", "Pull back, pull back!",
		"We're leaving! Cover each other!", "Fall back, Alpha covers!", "Get out of here, by bounds!",
		L("That's a lot of them! Leave!", "Way ahead of you!", "Leaving!", "Right behind you!"),
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
		L("On me! Head count!", "One!", "Here!", "Present!"),
	},
}

lines.replies.rally = {
	"Coming!", "On you!", "Moving to you!", "Rallying!", "Here!", "Present!", "Regrouping!", "Right behind you!",
}

lines.calls.rush = {
	any = {
		"I'm up!", "Moving!", "Rushing!", "Going!", "Up, moving!", "On the move!", "Here I go!", 
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
		"I'll drive!", "I've got the wheel!", "Getting in, I'm driving!", "Mount up, I'm driving!", 
	},
}

lines.replies.mountDriver = {
	"I'll take the gun!", "On the turret!", "Right behind you!", "Don't flip it!", "Go, go!",
	"Watch the bumps!",
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

--A soldier who sees an enemy vehicle: armorAT when an at team on his side can
--come for it, armor when there is none.
lines.calls.armorAT = {
	any = {
		"Armor, {clock} o'clock, {dist} out! Get AT on it!", "Enemy vehicle, {clock} o'clock! Calling the Javelin!",
		"Vehicle at {clock} o'clock! AT team, you're up!", "Armor spotted, {dist} out! Send the AT team!",
		"Contact, vehicle, {clock} o'clock! Need AT up here!", "Tank! {clock} o'clock! Get me a Javelin!",
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
	"Quiet.", "Too quiet.", "Hmm.", "Still nothing.",
	"I wonder what's for dinner.", "Man, my feet hurt.", "Just another day.", "Another boring shift.", "Nothing happening.",
	"I should call my mom.", "I could use a nap.", "Coffee. I need coffee.",
	"My boots are too tight.", "I'm bored.", 
	"I wonder what the enemy is doing.", "Do I have a spare mag? Yep.",
	"I think I'm getting a cold.", "I've been standing here for hours.", 
	"Is that a cloud or a plane?", "I wish I had a radio.", 
	"Any minute now.", "I think I heard something. Nope.", 
	"They never give us enough water.", "My helmet's itchy.", 
	"I'll be fine. I'll be fine.", "I miss my bunk.", "No news is good news.",
	"One more hour, one more hour.", "I should stretch.", "Do I smell smoke?", 
}

lines.calls.pilotJoin = {
	any = {
		"I'm down! Linking up with the nearest squad!", "Bird's gone. Heading for friendlies!",
		"Pilot on foot, moving to you!", "I need a rifle squad, coming to you!",
	},
}
lines.replies.pilotJoin = {
	"We've got you!", "On us!",
}

lines.calls.reconReport = {
	any = {
		"Hostile at grid {grid}, {dist} studs {compass} of me, over.",
		"Eyes on, grid {grid}. Staying dark, out.",
		"Contact {compass}, {dist} studs, grid {grid}, over.",
		"Target located, grid {grid}. How copy, over?",
		"Tracking one, {compass} of me, grid {grid}, over.",
	},
}
lines.calls.breakContact = {
	any = {"We're compromised, break contact!", "Compromised, moving!", "They've made us, peel off!"},
}
lines.calls.contactRelay = {
	any = {
		"New fix on the net, shift!", "Radio's got him, adjust!", "Net's got a position, move!",
		"Contact on the net, moving to it!",
	},
}
lines.replies.contactRelay = {
	"Copy, moving!", "On it!", "Good copy!",
}

lines.calls.unitCall = {
	any = {
		"Unit's under attack, moving to support!", "They're calling for help, let's go!",
		"Friendlies taking fire, get over there!", "Radio says they're hit, move!",
	},
}
lines.replies.unitCall = {
	"Moving!", "Right behind you!", "On the way!",
}

lines.calls.sniperHeard = {
	any = {"Sniper! Get to cover!", "Sniper fire, get down!", "Sniper! Get behind something!"},
}

lines.calls.grenadeIncoming = {
	any = {"Grenade! Move!", "Frag out, get clear!", "Grenade, grenade!", "Incoming frag!"},
}

lines.calls.counterSnipe = {
	any = {"Enemy sniper, moving for a shot!", "I hear their sniper, finding him.", "Counter-sniper, on it."},
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
	},
}
lines.replies.enemyMG = {
	"Staying down!", "Copy!", "Waiting it out!", "Pinned!",
}

return lines

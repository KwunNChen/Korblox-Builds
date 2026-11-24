--[[
	Special operations lines: clipped, tactical radio speak only. Same shape as
	ChatterLines (every call and reply kind, with the same situation pools), so
	ChatterModule can use either. No solo or banter: they don't make small talk.
	Placeholders as in ChatterLines: {clock} {dist} {n} {side} {grid} {compass}.
]]

local lines = {calls = {}, replies = {}, solo = {}}
local calls,replies = lines.calls,lines.replies

calls.spotted = {
	any = {"Contact.", "Tango, eyes on.", "Contact front.", "One tango, visual.", "Hostile, marked.", "Eyes on, one pax."},
	clock = {"Tango, {clock} o'clock, {dist}.", "Contact, {clock} o'clock.", "Hostile {clock} o'clock, {dist} out.",
		"Eyes on, {clock} o'clock."},
	close = {"Contact, danger close.", "Tango, close.", "Hostile on top of us.", "Close contact."},
	far = {"Contact, {dist} out.", "Tango at distance, {dist}.", "Far contact, {clock} o'clock."},
	many = {"Multiple tangos, {n}.", "{n} pax, {clock} o'clock.", "Contacts, count {n}.", "Hostile element, {n} pax."},
	player = {"Priority tango.", "High-value target, marked.", "That one's trained. Priority.", "Primary target, eyes on."},
}
replies.spotted = {
	fresh = {"Copy.", "Tally.", "Eyes on.", "Copy, engaging.", "Say direction.", "Moving to support.", "Covering.", "Good copy."},
	engaged = {"Engaged, mine.", "Copy, tied up.", "Already engaged.", "Mine's live, stand by.", "Copy, busy."},
}

calls.reload = {
	any = {"Reloading.", "Changing mags.", "Mag.", "Dry. Cover.", "Reloading, cover me."},
	close = {"Reloading, tango close.", "Mag change, danger close.", "Dry, he's close."},
}
replies.reload = {"Covering.", "Got you.", "Covering, go.", "On him.", "You're covered."}

calls.hit = {
	any = {"Hit.", "I'm hit, still in it.", "Took one.", "Hit, still effective."},
	low = {"Hit bad.", "Combat ineffective soon.", "Need a tourniquet.", "Hit, bleeding out."},
}
replies.hit = {"Copy, stay in it.", "Covering, get down.", "Tourniquet up.", "Hold. Coming to you.", "Copy, keep firing."}

calls.kill = {
	any = {"Tango down.", "Target down.", "Down.", "One down.", "Hostile neutralized."},
	knife = {"Down. Quiet.", "Tango down, blade.", "Silent kill."},
}
replies.kill = {"Good effect.", "Copy.", "Confirmed.", "Next."}

calls.manDown = {any = {"Man down.", "Casualty.", "We've lost one.", "Friendly down."}}
replies.manDown = {"Copy. Stay on task.", "Copy, push on.", "Noted. Eyes up.", "Copy."}

calls.grenade = {any = {"Frag out.", "Frag.", "Grenade out.", "Fire in the hole."}}
replies.grenade = {"Copy, frag.", "Clear.", "Down."}

calls.grenadeIncoming = {any = {"Frag, move.", "Grenade, clear.", "Incoming frag."}}

calls.cover = {any = {"Moving to cover.", "Covered.", "Getting low.", "Taking cover."}}
replies.cover = {"Covering.", "Got you.", "Go."}

calls.advance = {any = {"Moving.", "Pushing.", "Advancing.", "Moving up.", "On the move."}}
replies.advance = {"Covering.", "Go.", "With you.", "Got your six."}

calls.lost = {any = {"Lost visual.", "No visual.", "Tango out of sight.", "Lost him."}}
replies.lost = {"Copy, hold.", "Watch your sector.", "Copy, eyes out."}

calls.air = {any = {"Air threat. Get under cover.", "Fast mover. Go to ground.", "Aircraft, take cover."}}
replies.air = {"Copy.", "Under cover.", "Down."}

calls.armor = {any = {"Armor, {clock} o'clock, {dist}. Get to cover.", "Vehicle, {clock} o'clock.",
	"Armor, {dist} out. Small arms ineffective."}}
replies.armor = {"Copy, armor.", "Get low.", "Copy, avoid."}

calls.armorAT = {any = {"Armor, {clock} o'clock, {dist}. Need AT.", "Vehicle, {clock} o'clock. AT up.",
	"Armor, {dist} out. Send AT."}}
replies.armorAT = {"Copy, calling AT.", "AT's tasked.", "Copy, hold till AT."}

calls.atMoving = {any = {"AT moving.", "Copy armor, AT moving.", "AT team, moving to engage."}}
replies.atMoving = {"With you.", "Tube ready.", "Moving."}

calls.javelinOut = {any = {"Javelin out.", "Missile away.", "Backblast clear. Firing."}}
replies.javelinOut = {"Good launch.", "Reloading.", "Tube up."}

calls.bail = {any = {"Bail out.", "Vehicle's done. Out.", "Dismount, now."}}
replies.bail = {"Out.", "Clear of it.", "Moving."}

calls.mountDriver = {any = {"Driving.", "I've got the wheel.", "Mount up."}}
replies.mountDriver = {"Gun's mine.", "Up.", "Go."}

calls.mountGunner = {any = {"On the gun.", "Gunner up.", "Turret's up."}}
replies.mountGunner = {"Moving.", "Copy.", "Rolling."}

calls.orderBound = {any = {"Bound by teams.", "Bravo move, Alpha cover.", "Bounding overwatch. Go."}}
replies.orderBound = {"Copy, bounding.", "Alpha set.", "Bravo moving.", "Copy."}

calls.orderFlank = {any = {"Alpha, base of fire. Bravo, flank {side}.", "Bravo, take the {side}.", "Fix him. Bravo, {side}."}}
replies.orderFlank = {"Copy, flanking.", "Base of fire set.", "Bravo moving.", "Copy."}

calls.orderPincer = {any = {"Pincer. Alpha left, Bravo right.", "Split. Both flanks, hold fire till my call.",
	"Box him in. Weapons tight till I call it."}}
replies.orderPincer = {"Copy, left.", "Copy, right.", "Weapons tight.", "Copy."}

calls.orderPincerGo = {any = {"Execute.", "Both sides, go.", "Now. Execute."}}
replies.orderPincerGo = {"Executing.", "Moving.", "In."}

calls.orderAssault = {any = {"Bravo, assault through.", "Assault.", "Bravo, take him."}}
replies.orderAssault = {"Assaulting.", "Moving through.", "Copy, in."}

calls.orderBreak = {any = {"Break contact. Bound back.", "Break contact.", "Peel back by teams."}}
replies.orderBreak = {"Copy, breaking.", "Moving back.", "Covering."}

calls.shiftFire = {any = {"Shift fire.", "Lift fire, friendlies in.", "Check fire."}}
replies.shiftFire = {"Shifting.", "Fire lifted.", "Weapons tight."}

calls.rally = {any = {"Rally on me.", "Consolidate on me.", "Regroup. Head count."}}
replies.rally = {"Up.", "On you.", "Present."}

calls.rush = {any = {"Moving.", "I'm up.", "Rushing."}}

calls.set = {any = {"Set.", "In position.", "Set, covering."}}

calls.relocate = {any = {"Displacing.", "Relocating.", "Position's burned. Moving."}}
replies.relocate = {"Covering.", "With you.", "Go."}

calls.holdAngle = {any = {"Holding this angle.", "Sector covered.", "Holding."}}
replies.holdAngle = {"Copy, holding.", "Other side covered."}

calls.enemyReloading = {any = {"He's dry. Push.", "Tango reloading. Go.", "Mag change. Move."}}
replies.enemyReloading = {"Pushing.", "On him.", "Moving."}

calls.enemyHealing = {any = {"He's treating. Push.", "Tango's down to treat. Go."}}
replies.enemyHealing = {"Pushing.", "On him."}

calls.enemyShotgun = {any = {"Shotgun. Keep standoff.", "Scattergun. Stay at range."}}
replies.enemyShotgun = {"Copy, standoff.", "Holding range."}

calls.enemySniper = {any = {"Marksman. Short exposures.", "Sniper. Close him down.", "Glint. Sniper."}}
replies.enemySniper = {"Copy, short peeks.", "Moving on him."}

calls.enemyMG = {any = {"Gun team. Stay down between bursts.", "Automatic fire. Heads down."}}
replies.enemyMG = {"Copy.", "Down.", "Waiting it out."}

calls.findShooter = {any = {"Taking fire. Find the shooter.", "Shooter. Locate.", "Where's that from? Find him."}}
replies.findShooter = {"Searching.", "Moving.", "Got the direction."}

calls.sniperHeard = {any = {"Sniper. Get to cover.", "Sniper fire. Down."}}

calls.counterSnipe = {any = {"Enemy sniper. Moving for a shot.", "Counter-sniper, on it."}}

calls.contactRelay = {any = {"New fix on the net. Shift.", "Updated position. Moving."}}
replies.contactRelay = {"Copy.", "Good copy, moving."}

calls.unitCall = {any = {"Friendlies in contact. Moving to support.", "Unit taking fire. Moving."}}
replies.unitCall = {"Moving.", "With you."}

calls.reconTasked = {any = {"Recon has a target. Move.", "Tasking from recon. Go."}}
replies.reconTasked = {"Moving.", "Copy."}

calls.reconReport = {any = {
	"Hostile at grid {grid}, {dist} studs {compass} of me, over.",
	"Eyes on, grid {grid}. Staying dark, out.",
	"Contact {compass}, {dist} studs, grid {grid}, over.",
	"Target located, grid {grid}. How copy, over?",
	"Tracking one, {compass} of me, grid {grid}, over.",
}}

calls.breakContact = {any = {"Compromised. Break contact.", "Compromised, moving.", "They've made us. Peel off."}}

calls.pilotJoin = {any = {"Pilot on foot. Linking up.", "Downed aircrew, moving to you."}}
replies.pilotJoin = {"Copy, on us."}

calls.unitSplit = {any = {"Too thin. Split the element.", "Second group, on me."}}
replies.unitSplit = {"Copy, splitting.", "Moving out."}

calls.shaken = {any = {"Heavy contact. Stay on task.", "We're taking losses. Hold."}}
replies.shaken = {"Copy. Holding.", "Steady."}

calls.broken = {any = {"Falling back.", "Withdrawing."}}
replies.broken = {"Hold the line.", "Get back in position."}

calls.rallied = {any = {"Back in it.", "Good to go."}}
replies.rallied = {"Copy.", "Good."}

return lines

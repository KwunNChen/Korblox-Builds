--[[

Terminology:
	Terminal: A hill, an objective, a point you capture to increase the amount of points your team is getting
	Terms: Terminals (see above)
	Admin: The ability to control this objective system(start the raid, end the raid, change the objective, etc)
	
Setting up your terminals:
	The folder called 'Points' houses your terminals. You can clone them to add more terminals and delete them
	to reduce their amount.
	Inside each terminal you have two configurable values: "Progress" and "Value"
	
	Progress has a MaxValue and MinValue. The MinValue has to be a negative number. The larger both of them are(or smaller in
	case of the MinValue), the longer it takes to capture that terminal.
	
	Value determines how much points the team owning the terminal will get every second
	
	CaptureRadius determines how far away the player must be to capture the objective. 
	If the value doesn't exist, it'll try to use the X or Z sizes of the point.
	If both sizes are under 1, it'll use a hardcoded distance of 16.

Configuring your objective system:
	The folder(displayed as a cogwheel icon as of roblox's last icons update) called 'Settings' houses all the configuration
	for your system.

	The "AdminControls" folder has 2 values: GroupId and UserId, with a value called RankId inside the GroupId
	You can set the GroupId value to the ID of your groupa nd set the RankId to a rank that should be able to control
	this objective system. Anyone who is of the required rank in the required group will be able to start the raid,
	end the raid, change the objective and set the raider and defender groups
	You can also grant that power to individual users by using the UserId value. (change the value to a user's id)
	NOTE: You can clone GROUPID and USERID as much as you want to add more admin groups or users

	
	The "DefendingTeams", "NeutralTeams" and "RaidingTeams" folders represent team categories: defenders, raiders and neutrals
	The teams in the DefendingTeams folder will count as defenders
	The teams in the RaidingTeams folder will count as raiders
	The teams in the NeutralTeams folder will count as neutrals, they can not capture terminals
	
	In order to add a team to one of those 3 categories, select the object called "Team" inside the category you're working
	with, click on its Value and then click on a team you want to add to the category. (go to the Teams folder in your workspace)
	and find the team in it, you should know this.)
	You can clone the "Team" object and add more teams to each category
	
	The value called "Objective" is the amount of score a team has to reach to win the raid. Each team gets a certain
	amount of score per second. That amount is the sum of values of every terminal they own

	When a team of certain category captures a point, its marker on the terminals list UI will change colour to the category's
	color. In order to change the colour of the category, check the properties of the "DefendingTeams" and "RaidingTeams"
	folders, both located in the Settings folder.

Admin commands:
	!begin - starts the raid
	!end - ends the raid
	!defenderId ID - sets the defending group (replace the ID with the actual group ID)
	!raiderId ID - sets the raiding group (replace the ID with the actual group ID)
	!score - sets the objective (amount of score required to win)
]]
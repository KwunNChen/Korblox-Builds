-- Checks who hears the spec ops relay and the infantry radio call, outside Studio.
-- Run from the AI folder:
--     lune run Shared/tests/radio.test.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Vector3 = require("@lune/roblox").Vector3

local MODULES = "Bloxian/src/Scripts/Modules/"
local noop = function() end

local function settingsFor(team,unit,role)
	local values = {Team = {Value = team}, Unit = {Value = unit}, Role = {Value = role}}
	local settings = {Team = values.Team}
	function settings:FindFirstChild(name)
		return values[name]
	end
	return settings
end

local function soldier(radio,heard,team,unit,role,squadId,isPlayer)
	local attributes = {Unit = unit, Role = role}
	local model = {
		Settings = settingsFor(team,unit,role),
		M4 = {FindFirstChild = noop},
		isPlayer = isPlayer,
	}
	function model:GetAttribute(name)
		return attributes[name]
	end
	function model:SetAttribute(name,value)
		attributes[name] = value
	end
	radio[model] = {
		root = {Parent = model},
		human = {Health = 100},
		team = {Value = team},
		squadId = squadId,
		allyShot = function(target,call)
			heard[model] = call
		end,
	}
	return model
end

--Loads a real module as this soldier, with the rest of the game stubbed out.
local function load(file,marine,radio,status,clock,extra)
	local modules = {
		CoreModule = {checkSight = function() return true end},
		Status = status or {},
		ChatterModule = {},
		ThreatModule = {of = function(target) return target.long and "long" or nil end},
		Troubleshoot = {log = noop},
		UniformModule = {},
		Parent = {Parent = marine},
	}
	for name,module in pairs(extra or {}) do
		modules[name] = module
	end
	local services = {
		Players = {GetPlayerFromCharacter = function(_,model) return model.isPlayer end},
		ReplicatedStorage = {WaitForChild = noop},
	}
	return luau.load(fs.readFile(MODULES..file),{
		debugName = file,
		environment = {
			_G = {BloxianRadio = radio},
			Vector3 = Vector3,
			OverlapParams = {new = function() return {} end},
			os = {clock = clock or os.clock},
			game = {GetService = function(_,name) return services[name] end},
			script = {Parent = modules},
			require = function(module) return module end,
			task = {spawn = function(callback,...) callback(...) end},
		},
	})()
end

local function check(condition,message)
	assert(condition,message)
end

--A spec ops radioman's relay.
do
	local radio,heard = {},{}
	local sender = soldier(radio,heard,"Hostile","Special Recon","Radioman",1)
	local squadmate = soldier(radio,heard,"Hostile","Special Recon","Rifleman",1)
	local otherRadioman = soldier(radio,heard,"Hostile","Special Recon","Radioman",2)
	local otherSquad = soldier(radio,heard,"Hostile","Special Recon","Rifleman",2)
	local noRadioman = soldier(radio,heard,"Hostile","Special Recon","Rifleman",3)
	local infantry = soldier(radio,heard,"Hostile","Infantry","Radioman",4)
	local enemyRadioman = soldier(radio,heard,"Friendly","Special Recon","Radioman",5)
	local dead = soldier(radio,heard,"Hostile","Special Recon","Rifleman",2)
	radio[dead].human.Health = 0

	local sof = load("SofModule.luau",sender,radio)
	local player = {isPlayer = true, Name = "Player"}
	local target = {Parent = player}

	sof.relay({Parent = {isPlayer = false}})
	check(next(heard) == nil,"relay: a Bloxian target was relayed")

	sof.relay(target)
	check(heard[sender] == "contactRelay","relay: his own unit missed it")
	check(heard[squadmate] == "contactRelay","relay: his squadmate missed it")
	check(heard[otherRadioman] == "contactRelay","relay: the other radioman missed it")
	check(heard[otherSquad] == "contactRelay","relay: the other radioman's squad missed it")
	check(heard[noRadioman] == nil,"relay: a squad with no radioman heard it")
	check(heard[infantry] == nil,"relay: line infantry heard it")
	check(heard[enemyRadioman] == nil,"relay: the enemy heard it")
	check(heard[dead] == nil,"relay: a dead man heard it")

	table.clear(heard)
	sof.relay(target)
	check(next(heard) == nil,"relay: repeated inside RELAY_INTERVAL")

	check(sof.closesOn({Parent = soldier(radio,heard,"Friendly","Sniper","Rifleman",6)}),"sniper: a Bloxian sniper was not closed on")
	check(sof.closesOn({Parent = {GetAttribute = noop},long = true}),"sniper: a player with a scoped gun was not closed on")
	check(not sof.closesOn({Parent = soldier(radio,heard,"Friendly","Infantry","Rifleman",7)}),"sniper: a rifleman was closed on")

	check(sof.observes(sof.OBSERVE_MIN,true),"post: he did not hold at the near edge")
	check(not sof.observes(sof.OBSERVE_MIN - 1,true),"post: he held inside the ring")
	check(not sof.observes(251,true),"post: he held too far off")
	check(not sof.observes(200,false),"post: he held with no line")

	local rifleman = load("SofModule.luau",squadmate,radio)
	rifleman.relay(target)
	check(next(heard) == nil,"relay: a rifleman relayed")
end

--Shot at, a spec ops soldier does not go quiet on an enemy he can see.
do
	local radio,heard = {},{}
	local clock = 1000
	local lastHit = -math.huge
	local status = {}
	function status:get(name)
		return name == "lastHit" and lastHit or nil
	end
	local marine = soldier(radio,heard,"Hostile","Special Recon","Rifleman",1)
	marine.HumanoidRootPart = {Position = Vector3.zero}
	local sof = load("SofModule.luau",marine,radio,status,function() return clock end)
	local enemy = {
		Parent = {GetAttribute = noop},
		Position = Vector3.new(100,0,0),
		CFrame = {LookVector = Vector3.new(-1,0,0)},
	}

	check(not sof.engaged(enemy),"engaged: an enemy 100 studs off set him off unprovoked")
	lastHit = clock
	check(sof.engaged(enemy),"engaged: being hit did not count")
	clock += 10
	check(sof.engaged(enemy),"engaged: he forgot who shot him, in plain sight")
	clock += 30
	check(not sof.engaged(enemy),"engaged: he never went back to watching")
end

--An AT team stays with the unit it came with.
do
	local function at(radio,model,x)
		radio[model].root.Position = Vector3.new(x,0,0)
		return model
	end
	local function team(unit,fighting)
		local radio,heard = {},{}
		local clock = 1000
		local goals = {}
		local marine = at(radio,soldier(radio,heard,"Friendly",unit,"Rifleman",1),0)
		marine.HumanoidRootPart = radio[marine].root
		marine:SetAttribute("AttachedTo",7)
		local status = {set = noop}
		function status:get(name)
			return name == "currentTarget" and fighting or nil
		end
		local special = load("SpecialTeamModule.luau",marine,radio,status,function() return clock end,{
			CoreModule = {checkDist = function() return 200 end},
			MovementModule = {
				navigate = function(goal) goals[#goals+1] = goal end,
				stop = noop,
			},
			SofModule = {UNITS = {["Special Recon"] = true}, kindOf = function(model)
				return model:GetAttribute("Unit") == "Special Recon" and "Special Recon" or nil
			end},
			WeaponProfiles = {current = {range = 300}},
		})
		return {
			special = special, marine = marine, goals = goals,
			add = function(side,kind,squad,x)
				local model = at(radio,soldier(radio,heard,side,kind,"Rifleman",1),x)
				model:SetAttribute("SquadId",squad)
				model:SetAttribute("SquadSize",9)
				return model
			end,
			wait = function(seconds) clock += seconds end,
		}
	end

	--Follows the nearest of his unit, in a fight too, and never wanders off to hunt.
	local fight = {Parent = {}}
	local rocketeer = team("Rocketeer",fight)
	rocketeer.special.hunt = function() error("hunting while he has a unit") end
	rocketeer.add("Friendly","Infantry",7,300)
	rocketeer.add("Friendly","Infantry",7,100)
	rocketeer.add("Friendly","Infantry",8,50)
	check(rocketeer.special.update(),"AT: the brain took him back")
	check(rocketeer.goals[1] and rocketeer.goals[1].X == 100,"AT: he did not head for the nearest of his unit")

	--Close enough he stands, free to fire.
	rocketeer = team("Rocketeer")
	rocketeer.add("Friendly","Infantry",7,15)
	rocketeer.special.update()
	check(#rocketeer.goals == 0,"AT: he crowded the unit")

	--His unit's id is gone: the nearest friendly infantry unit, after spawn settles.
	rocketeer = team("Rocketeer")
	rocketeer.add("Friendly","Infantry",9,60)
	rocketeer.add("Friendly","Sniper",9,10)
	rocketeer.add("Friendly","Special Recon",9,20)
	rocketeer.add("Hostile","Infantry",9,30)
	rocketeer.special.update()
	check(rocketeer.marine:GetAttribute("AttachedTo") == 7,"AT: he left his unit while it was starting up")
	rocketeer.wait(10)
	rocketeer.special.update()
	check(rocketeer.marine:GetAttribute("AttachedTo") == 9,"AT: he did not take the nearest unit")
	check(rocketeer.goals[1] and rocketeer.goals[1].X == 60,"AT: he took the wrong men")

	--No unit left: the team goes back to hunting by itself.
	rocketeer = team("Rocketeer")
	local hunted = false
	rocketeer.special.hunt = function() hunted = true end
	rocketeer.special.update()
	check(hunted,"AT: with no unit he stopped hunting")

	--Rocketeer gone, the Loader joins the unit as a rifleman.
	local loader = team("Loader")
	loader.add("Friendly","Infantry",7,40)
	check(not loader.special.update(),"AT: the Loader kept guarding nobody")
	check(loader.marine:GetAttribute("SquadId") == 7,"AT: the Loader did not join the unit")
	check(loader.marine:GetAttribute("SquadSize") == 9,"AT: the Loader joined with no unit size")
end

--An infantryman calling in his attacker.
do
	local radio,heard = {},{}
	local sender = soldier(radio,heard,"Hostile","Infantry","Rifleman",1)
	local squadmate = soldier(radio,heard,"Hostile","Infantry","Rifleman",1)
	local otherUnit = soldier(radio,heard,"Hostile","Infantry","Rifleman",2)
	local enemy = soldier(radio,heard,"Friendly","Infantry","Rifleman",3)
	local dead = soldier(radio,heard,"Hostile","Infantry","Rifleman",2)
	local recon = soldier(radio,heard,"Hostile","Special Recon","Radioman",4)
	radio[dead].human.Health = 0

	local attacker = {}
	load("RadioModule.luau",recon,radio).callUnits(attacker)
	check(next(heard) == nil,"unit call: spec ops made one")

	local net = load("RadioModule.luau",sender,radio)
	net.callUnits(attacker)
	check(heard[otherUnit] == "unitCall","unit call: another unit missed it")
	check(heard[recon] == "unitCall","unit call: spec ops missed it")
	check(heard[squadmate] == nil,"unit call: his own unit was called")
	check(heard[enemy] == nil,"unit call: the enemy heard it")
	check(heard[dead] == nil,"unit call: a dead man heard it")

	table.clear(heard)
	net.callUnits(attacker)
	check(next(heard) == nil,"unit call: repeated inside UNIT_CALL_INTERVAL")
end

print("radio: all checks pass")

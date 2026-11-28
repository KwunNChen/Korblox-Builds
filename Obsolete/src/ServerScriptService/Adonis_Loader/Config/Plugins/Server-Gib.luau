--[[
	SERVER PLUGINS' NAMES MUST START WITH "Server:" OR "Server-"
	CLIENT PLUGINS' NAMES MUST START WITH "Client:" OR "Client-"

	Plugins have full access to the server/client tables and most variables.

	You can use the MakePluginEvent to use the script instead of setting up an event.
	PlayerJoined will fire after the player finishes initial loading
	CharacterAdded will also fire after the player is loaded, it does not use the CharacterAdded event.

	service.Events.PlayerAdded(function(p)
		print(`{p.Name} Joined! Example Plugin`)
	end)

	service.Events.CharacterAdded(function(p)
		server.RunCommand('name', plr.Name, 'BobTest Example Plugin')
	end)

--]]
server = nil -- Mutes warnings about unknown globals
service = nil
return function()
server.Commands.GibCommand = {
	Prefix = server.Settings.Prefix;
	Commands = {"gib";};
	Args = {"player";};
	Hidden = false;
	Description = "pop goes the weasel";
	Fun = true;
	AdminLevel = "Moderators";
	Function = function(plr,args)
			local volume = 1
			local looped = false
			local espuma = "rbxassetid://8164951181"
			local playonremove = true
			local audio = service.New("Sound", {
				Volume = volume;
				Looped = looped;
				Pitch = 1;
				Name = "ADONIS_AUDIO";
				SoundId = espuma;
				PlayOnRemove = playonremove;
			})
			local new = audio:Clone().Parent==game.Workspace
			audio:Destroy()
			local repeatCount = tonumber(7)
		for i = 1, repeatCount do
			for i,v in pairs(service.GetPlayers(plr,args[1])) do
				local char = v.Character
					v.CameraMinZoomDistance=3			
					local primparychar = char.Torso
					local bigblood = service.New("ParticleEmitter")
					bigblood.Parent = primparychar
					bigblood.Rate = 30
					bigblood.Color = ColorSequence.new(Color3.fromRGB(70, 0, 0))
					bigblood.Orientation = Enum.ParticleOrientation.FacingCamera
					bigblood.Size = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 1.5), 
						NumberSequenceKeypoint.new(0.5, 1.7),
						NumberSequenceKeypoint.new(1, 1.3), }
					bigblood.Squash = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 0, 0.3), 
						NumberSequenceKeypoint.new(1, 0, 0), }
					bigblood.Transparency = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 1), 
						NumberSequenceKeypoint.new(0.5, 0.5), 
						NumberSequenceKeypoint.new(1, 1), }
					bigblood.Texture = "rbxassetid://6430908053"
					bigblood.EmissionDirection = Enum.NormalId.Bottom
					bigblood.Lifetime = NumberRange.new(1, 1.2)
					bigblood.Rotation = NumberRange.new(-180, 180)
					bigblood.RotSpeed = NumberRange.new(0, 0)
					bigblood.Speed = NumberRange.new(5,7)
					bigblood.SpreadAngle = Vector2.new(20, 30)
					bigblood.Shape = Enum.ParticleEmitterShape.Disc
					bigblood.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
					bigblood.ShapePartial = 0.05
					bigblood.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
					bigblood.Acceleration = Vector3.new(0, -8, 0)
					bigblood.LockedToPart = false
					bigblood.Enabled = true
					local limbs = char:GetDescendants()
					local limbvelocity = Vector3.new(math.random(-25, 25), 30, math.random(-25, 25))

					for _, part in pairs(limbs) do
						if part:IsA("BasePart") then
							if part.Name == "Right Arm" or part.Name == "Left Arm" then
								part.Velocity = limbvelocity
							elseif part.Name == "Torso" or part.Name == "Head" then
								part.Velocity = limbvelocity
							elseif part.Name == "Right Leg" or part.Name == "Left Leg" then
								part.Velocity = limbvelocity
							end
						end
					end
				local gib = service.New("Part",char)
					gib.BrickColor = BrickColor.new("Maroon")
					gib.Material = "Slate"
					gib.Size = Vector3.new(1.2, 0.2, 1.2)
					gib.CFrame = char.Torso.CFrame*CFrame.new(0,2,0)
					gib.CanCollide = true
					gib.Anchored = false
					local mesh = service.New("SpecialMesh")
					local randomizedscale = Vector3.new(math.random(1, 1.5), math.random(2.4, 4.8), math.random(1, 1.6))
						mesh.Parent = gib
						mesh.MeshType = Enum.MeshType.Sphere
						mesh.Scale = randomizedscale
					local gibvelocity = Vector3.new(math.random(-25, 25), (30), math.random(-25, 50))
					gib.Velocity = gibvelocity
				local puddle = service.New("ParticleEmitter")
					puddle.Parent = gib
					puddle.Rate = 9
					puddle.Color = ColorSequence.new(Color3.fromRGB(70, 0, 0))
					puddle.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
					puddle.Size = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 1.25), 
						NumberSequenceKeypoint.new(0.5, 2.7),
						NumberSequenceKeypoint.new(1, 1.5), }
					puddle.Squash = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 0, 0.3), 
						NumberSequenceKeypoint.new(1, 0, 0), }
					puddle.Transparency = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 1), 
						NumberSequenceKeypoint.new(0.5, 0), 
						NumberSequenceKeypoint.new(1, 1), }
					puddle.Texture = "rbxassetid://6430908053"
					puddle.Lifetime = NumberRange.new(3, 3.5)
					puddle.Rotation = NumberRange.new(-180, 180)
					puddle.RotSpeed = NumberRange.new(0, 0)
					puddle.Speed = NumberRange.new(0.013, 0.0131)
					puddle.Shape = Enum.ParticleEmitterShape.Disc
					puddle.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
					puddle.ShapePartial = 0.05
					puddle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
					puddle.LockedToPart = true
					puddle.Enabled = true
				local gibnoise = service.New("Sound",char)
					local randomizenoise = {"rbxassetid://3802437361","rbxassetid://255661850","rbxassetid://3802437696"}
					local randomizednoise = randomizenoise[math.random(1,#randomizenoise)]
					local randomizedvolume = math.random(0.5,1)
					gibnoise.Name = "GibNoise"
					gibnoise.RollOffMaxDistance = 95
					gibnoise.RollOffMinDistance = 10
					gibnoise.RollOffMode = Enum.RollOffMode.Linear
					gibnoise.SoundId = randomizednoise
					gibnoise.Volume = randomizedvolume
					gibnoise.Parent = primparychar
					gibnoise.PlayOnRemove = true
					gibnoise:Destroy()
				
					local hum = char.Humanoid
				hum:TakeDamage(50)
				hum.WalkSpeed=0
				hum.JumpPower=0
					task.wait(0.04)
					v.CameraMinZoomDistance=0					
			end
		end
			for i,v in pairs(service.GetPlayers(plr,args[1])) do
				local char = v.Character
				local bloodnoise = service.New("Sound")
				bloodnoise.Parent = char.Torso
				bloodnoise.Name = "bloodNoise"
				bloodnoise.RollOffMaxDistance = 95
				bloodnoise.RollOffMinDistance = 10
				bloodnoise.RollOffMode = Enum.RollOffMode.Linear 
				local randomizedvolume = math.random(1,1.5)
				bloodnoise.SoundId = "rbxassetid://9114519855"
				bloodnoise.Volume = randomizedvolume
				bloodnoise.PlayOnRemove = true
				bloodnoise:Destroy()
					local bloodnoise2 = service.New("Sound")
					bloodnoise2.Parent = char.Torso
					bloodnoise2.Name = "bloodNoise2"
					bloodnoise2.RollOffMaxDistance = 50
					bloodnoise2.RollOffMinDistance = 10
					bloodnoise2.RollOffMode = Enum.RollOffMode.Linear 
					bloodnoise2.SoundId = "rbxassetid://5845688763"
					bloodnoise2.Volume = randomizedvolume
					bloodnoise2.PlayOnRemove = true
					bloodnoise2:Destroy()
				local bloodnoise3 = service.New("Sound")
				bloodnoise3.Parent = char.Torso
				bloodnoise3.Name = "bloodNoise3"
				bloodnoise3.RollOffMaxDistance = 50
				bloodnoise3.RollOffMinDistance = 10
				bloodnoise3.RollOffMode = Enum.RollOffMode.Linear 
				bloodnoise3.SoundId = "rbxassetid://9120584093"
				bloodnoise3.Volume = 7
				bloodnoise3.PlayOnRemove = true
				bloodnoise3:Destroy()
			end
	end

}
end

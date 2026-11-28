--Sinahi

--[[ReadMe*
	Please improve upon this script as needed, I'm a noob scripter and I only script 
	through ways I know that work. This loop works, so I'm happy with it. But please, 
	edit as you may.
	
	This model uses MeshParts to animate the flag. The previous frame turns transparent
	while the next frame becomes visible.
	
	If you would like to use your own custom flag, for your ROBLOX group or country, 
	select all the children in the "Flag" model and paste in a ROBLOX decal asset in 
	the "TextureID" slot. If you receive an error, try subtracting 1 from the decal id.
		
		http://www.roblox.com/asset/?id={decal id}
		rbxassetid://{decal id}
	
	Any ROBLOX decal in the Developers Library will work, or you may upload your own 
	flag decal to insert in. Rectangular decals are recommended for this flag. 
		*If you use a decal with a transparent background in the MeshPart's TextureID, 
		the transparent background will default to black. Instead, insert the actual
		decal into every MeshPart in "Flag." This will allow you to change the BrickColor
		of the flag with the decal on top.
	
	The flags have been UV mapped to flip the flag design on the other side. 
		e.g. You won't see the blue box of the United States flag on the other side
			 of the flag on its end, but close to the pole for both sides.
				
	Thank you and have a wonderful day.
	(MeshParts rendered using Blender)
--]]

sp=script.Parent
flag=sp.Flag

reset=function()
	for _,meshpart in pairs (flag:GetChildren()) do
		if meshpart:IsA("MeshPart") then
			meshpart.Transparency=1
		end
	end
end

waittime=.01 --Time between each "Frame"

while true do
	wait(waittime)
	reset()
	flag["2"].Transparency=0.05
	wait(waittime)
	reset()
	flag["3"].Transparency=0.05
	wait(waittime)
	reset()
	flag["4"].Transparency=0.05	
	wait(waittime)
	reset()
	flag["5"].Transparency=0.05
	wait(waittime)
	reset()
	flag["6"].Transparency=0.05
	wait(waittime)
	reset()
	flag["7"].Transparency=0.05
	wait(waittime)
	reset()
	flag["8"].Transparency=0.05
	wait(waittime)
	reset()
	flag["9"].Transparency=0.05
	wait(waittime)
	reset()
	flag["10"].Transparency=0.05
	wait(waittime)
	reset()
	flag["11"].Transparency=0.05
	wait(waittime)
	reset()
	flag["12"].Transparency=0.05
	wait(waittime)
	reset()
	flag["13"].Transparency=0.05
	wait(waittime)
	reset()
	flag["14"].Transparency=0.05
	wait(waittime)
	reset()
	flag["15"].Transparency=0.05
	wait(waittime)
	reset()
	flag["16"].Transparency=0.05
	wait(waittime)
	reset()
	flag["17"].Transparency=0.05
	wait(waittime)
	reset()
	flag["18"].Transparency=0.05
	wait(waittime)
	reset()
	flag["19"].Transparency=0.05	
	wait(waittime)
	reset()
	flag["20"].Transparency=0.05
	wait(waittime)
	reset()
	flag["21"].Transparency=0.05
	wait(waittime)
	reset()
	flag["22"].Transparency=0.05
	wait(waittime)
	reset()
	flag["23"].Transparency=0.05
	wait(waittime)
	reset()
	flag["24"].Transparency=0.05
	wait(waittime)
	reset()
	flag["25"].Transparency=0.05
	wait(waittime)
	reset()
	flag["26"].Transparency=0.05
	wait(waittime)
	reset()
	flag["27"].Transparency=0.05
	wait(waittime)
	reset()
	flag["28"].Transparency=0.05
	wait(waittime)
	reset()
	flag["29"].Transparency=0.05
	wait(waittime)
	reset()
	flag["30"].Transparency=0.05
	wait(waittime)
	reset()
	flag["31"].Transparency=0.05
	wait(waittime)
	reset()
	flag["32"].Transparency=0.05
	wait(waittime)
	reset()
	flag["33"].Transparency=0.05
	wait(waittime)
	reset()
	flag["34"].Transparency=0.05
	wait(waittime)
	reset()
	flag["35"].Transparency=0.05
	wait(waittime)
	reset()
	flag["36"].Transparency=0.05
	wait(waittime)
	reset()
	flag["37"].Transparency=0.05
	wait(waittime)
	reset()
	flag["38"].Transparency=0.05
	wait(waittime)
	reset()
	flag["39"].Transparency=0.05
	wait(waittime)
	reset()
	flag["40"].Transparency=0.05
	wait(waittime)
	reset()
	flag["41"].Transparency=0.05	
	wait(waittime)
	reset()
	flag["42"].Transparency=0.05
	wait(waittime)
	reset()
	flag["43"].Transparency=0.05
	wait(waittime)
	reset()
	flag["44"].Transparency=0.05
	wait(waittime)
	reset()
	flag["45"].Transparency=0.05
	wait(waittime)
	reset()
	flag["46"].Transparency=0.05
	wait(waittime)
	reset()
	flag["47"].Transparency=0.05
	wait(waittime)
	reset()
	flag["48"].Transparency=0.05
	wait(waittime)
	reset()
	flag["49"].Transparency=0.05
	wait(waittime)
	reset()
	flag["50"].Transparency=0.05
	wait(waittime)
	reset()
	flag["51"].Transparency=0.05
	wait(waittime)
	reset()
	flag["52"].Transparency=0.05
	wait(waittime)
	reset()
	flag["53"].Transparency=0.05
	wait(waittime)
	reset()
	flag["54"].Transparency=0.05
	wait(waittime)
	reset()
	flag["55"].Transparency=0.05
	wait(waittime)
	reset()
	flag["56"].Transparency=0.05
	wait(waittime)
	reset()
	flag["57"].Transparency=0.05
	wait(waittime)
	reset()
	flag["58"].Transparency=0.05
	wait(waittime)
	reset()
	flag["59"].Transparency=0.05
	wait(waittime)
	reset()
	flag["60"].Transparency=0.05
	wait(waittime)
	reset()
	flag["61"].Transparency=0.05
	wait(waittime)
	reset()
	flag["62"].Transparency=0.05
	wait(waittime)
	reset()
	flag["63"].Transparency=0.05
	wait(waittime)
	reset()
	flag["64"].Transparency=0.05
	wait(waittime)
	reset()
	flag["65"].Transparency=0.05
	wait(waittime)
	reset()
	flag["66"].Transparency=0.05
	wait(waittime)
	reset()
	flag["67"].Transparency=0.05
	wait(waittime)
	reset()
	flag["68"].Transparency=0.05
	wait(waittime)
	reset()
	flag["69"].Transparency=0.05
	wait(waittime)
	reset()
	flag["70"].Transparency=0.05
	wait(waittime)
	reset()
	flag["71"].Transparency=0.05
	wait(waittime)
	reset()
	flag["72"].Transparency=0.05	
	wait(waittime)
	reset()
	flag["73"].Transparency=0.05
	wait(waittime)
	reset()
	flag["74"].Transparency=0.05
	wait(waittime)
	reset()
	flag["75"].Transparency=0.05
	wait(waittime)
	reset()
	flag["76"].Transparency=0.05
	wait(waittime)
	reset()
	flag["77"].Transparency=0.05
	wait(waittime)
	reset()
	flag["78"].Transparency=0.05
	wait(waittime)
	reset()
	flag["79"].Transparency=0.05
	wait(waittime)
	reset()
	flag["80"].Transparency=0.05
	wait(waittime)
	reset()
	flag["81"].Transparency=0.05
	wait(waittime)
	reset()
	flag["82"].Transparency=0.05
	wait(waittime)
	reset()
	flag["83"].Transparency=0.05
	wait(waittime)
	reset()
	flag["84"].Transparency=0.05
	wait(waittime)
	reset()
	flag["85"].Transparency=0.05
	wait(waittime)
	reset()
	flag["86"].Transparency=0.05
	wait(waittime)
	reset()
	flag["88"].Transparency=0.05
	wait(waittime)
	reset()
	flag["89"].Transparency=0.05
	wait(waittime)
	reset()
	flag["90"].Transparency=0.05
	wait(waittime)
	reset()
	flag["91"].Transparency=0.05
	wait(waittime)
	reset()
	flag["92"].Transparency=0.05
	wait(waittime)
	reset()
	flag["93"].Transparency=0.05
	wait(waittime)
	reset()
	flag["94"].Transparency=0.05
	wait(waittime)
	reset()
	flag["95"].Transparency=0.05
	wait(waittime)
	reset()
	flag["96"].Transparency=0.05
	wait(waittime)
	reset()
	flag["97"].Transparency=0.05
	wait(waittime)
	reset()
	flag["98"].Transparency=0.05
	wait(waittime)
	reset()
	flag["99"].Transparency=0.05
	wait(waittime)
	reset()
	flag["100"].Transparency=0.05
	wait(waittime)
	reset()
	flag["1"].Transparency=0.05
end
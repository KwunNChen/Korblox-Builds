--[[
	These commands were made by walkcube on 9/9/24 for all 3ND projects, specifically NOOBFALL
	This system was exculsively made for the Third Noob Division and NOOBFALL.
	
	Unauthorized use of these systems outside of personal modification is disallowed - but there isn't really anything I can do about it.
	
	Have fun!
--]]

return function(Vargs)
	local server, service = Vargs.Server, Vargs.Service
	local Functions, Commands, Admin, Anti, Core, HTTP, Logs, Remote, Process, Variables, Deps =
		server.Functions, server.Commands, server.Admin, server.Anti, server.Core, server.HTTP, server.Logs, server.Remote, server.Process, server.Variables, server.Deps
	-- LORE ANNOUNCEMENTS, NOTIFICATIONS, AND MORE.
	-- MISC COMMANDS

	server.Commands.actorAvatarItem = {
		Prefix = server.Settings.Prefix;
		Commands = {"customhat", "customaccessory"};
		Args = {"player", "Accessory ID", "Texture ID"};
		Description = "Gives yourself a hat accessory and modifies its texture";
		AdminLevel = "Moderators";
		Function = function(plr: Player, args: {[number]:string}, data)
			local accessoryId = assert(tonumber(args[2]), "Accessory ID (Argument 2) is missing or invalid")
			local textureId = assert(tonumber(args[3]), "Texture ID (Argument 3) is missing or invalid")

			local success, productInfo = pcall(service.MarketplaceService.GetProductInfo, service.MarketplaceService, accessoryId)
			assert(success and productInfo, "Invalid accessory ID")

			local typeId = productInfo.AssetTypeId
			local typeEnum
			for _, enum in pairs(Enum.AvatarAssetType:GetEnumItems()) do
				if enum.Value == typeId then
					typeEnum = enum
					break
				end
			end

			local allowedAccessoryTypes = { -- surely there was a better way of doing this
				Enum.AvatarAssetType.Hat,
				Enum.AvatarAssetType.FrontAccessory,
				Enum.AvatarAssetType.BackAccessory,
				Enum.AvatarAssetType.NeckAccessory,
				Enum.AvatarAssetType.ShoulderAccessory,
				Enum.AvatarAssetType.WaistAccessory,
				Enum.AvatarAssetType.HairAccessory,
			}
			
			-- check if its a valid accessory, if it isn't then just error the damn thing
			assert(table.find(allowedAccessoryTypes, typeEnum), `The asset ID {accessoryId} is not a valid accessory type`)

			for _, v: Player in service.GetPlayers(plr, args[1]) do
				local character = v.Character
				local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					if character:GetAttribute("LoadingSavedOutfit") then continue end

					local customHats = 0
					for _, x in character:GetChildren() do
						if x.Name == "CustomAdonisAccessory" then
							customHats += 1
						end
					end

					if customHats > 7 then
						continue
					end

					-- i was under the idea that SecureAccessory returned something, but it didnt
					-- guess i gotta use this poop method of comparing children and finding the odd ones out
					local existingAccessories = {}
					for _, child in ipairs(character:GetChildren()) do
						if child:IsA("Accessory") then
							table.insert(existingAccessories, child)
						end
					end

					service.SecureAccessory(v, accessoryId)

					-- if it finds a new accessory (it should), it'll change the texture if you provided it one
					local newAccessory
					for _, child in ipairs(character:GetChildren()) do
						if child:IsA("Accessory") and not table.find(existingAccessories, child) then
							newAccessory = child
							break
						end
					end

					if newAccessory then
						local handle = newAccessory:FindFirstChild("Handle")
						if handle then
							local mesh = handle:FindFirstChildWhichIsA("Mesh") 
								or handle:FindFirstChildWhichIsA("SpecialMesh")
							local meshPart = handle:IsA("MeshPart") and handle

							if mesh then
								mesh.TextureId = `rbxassetid://{textureId}`
							elseif meshPart then
								meshPart.TextureID = `rbxassetid://{textureId}`
							else
								warn(`No applicable mesh or texture found in accessory {newAccessory.Name}`)
							end
						else
							warn(`Accessory {newAccessory.Name} does not contain a Handle`)
						end
					else
						warn(`Failed to detect the newly added accessory for player {v.Name}`)
					end
				end
			end
		end
	};
end

--[[
	Moves this package into a place. Insert KorbloxAI.rbxm, then paste this in the
	Command Bar once:

		require(game:FindFirstChild("KorbloxInstall",true))()

	Each folder here is named after where its contents go. A folder already in the
	place is merged with the new one; anything else of the same name is replaced,
	so running it on a newer build updates the place. Save the place afterwards.
]]

local function destination(name)
	if name == "StarterPlayerScripts" then
		return game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
	end
	return game:GetService(name)
end

local function move(item,parent)
	local old = parent:FindFirstChild(item.Name)
	if old and old:IsA("Folder") and item:IsA("Folder") then
		for _,child in ipairs(item:GetChildren()) do
			move(child,old)
		end
		item:Destroy()
		return
	end
	if old then
		old:Destroy()
	end
	item.Parent = parent
end

return function()
	local package = script.Parent
	script.Parent = nil
	for _,signpost in ipairs(package:GetChildren()) do
		local parent = destination(signpost.Name)
		for _,item in ipairs(signpost:GetChildren()) do
			move(item,parent)
		end
		print("[KorbloxAI] installed into "..parent:GetFullName())
	end
	package:Destroy()
	print("[KorbloxAI] done. Save the place.")
end

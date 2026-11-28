-- Download the blood textures at join, so the first kill doesn't hitch while they load.
-- Keep in sync with ReplicatedStorage.SPH_Assets.Modules.Gore (SPLASH, ServerStorage.SPH_Gore.Streaks colour maps).
-- Bare ids here load as images, so sounds can't go in this list.
game:GetService("ContentProvider"):PreloadAsync({
	"rbxassetid://243457340",
	"rbxassetid://81646923926055", "rbxassetid://127452682916979", "rbxassetid://114518386374542",
	"rbxassetid://72104641594251", "rbxassetid://101377218425579",
})

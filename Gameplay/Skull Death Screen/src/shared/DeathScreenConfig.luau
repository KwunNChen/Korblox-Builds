--!strict
-- Every tunable for the skull death screen.
--
-- The sound id is mine. Roblox audio is private to the place that owns it, so
-- in your game it plays as silence and reports no error, upload your own clip
-- and paste its id in. If it fails to load, the screen holds for
-- FallbackDuration instead and warns in Output.

local Config = {
	-- Audio. The screen stays up until this finishes playing.
	SoundId = "rbxassetid://112267069111459",
	Volume = 1,

	-- The rig shown on screen. Must sit next to this module.
	ModelName = "Evil Skull Man",
	-- Part the close-up frames. Falls back to "Head" if the rig has none.
	FocusPartName = "Skull",

	-- Camera. Padding multiplies how much of the rig fits in shot: bigger
	-- numbers pull the camera further back.
	FieldOfView = 40,
	CloseUpPadding = 1.3, -- skull close-up
	WidePadding = 1.15, -- top of the skull down to the waist
	SwayHeight = 0.08, -- studs the camera drifts up while the clip plays
	SwayAngle = 0.8, -- degrees it turns while drifting. 0 and 0 for a still shot

	-- Timing, in seconds.
	FadeTime = 0.8, -- each fade: to black, skull in, skull out, black out
	ZoomTime = 1.6, -- close-up pulling back to the top half
	SwayTime = 2, -- one drift of the idle sway while the clip plays
	LoadTimeout = 5, -- how long to wait for the audio before giving up
	FallbackDuration = 5, -- how long to hold if the audio never loads

	-- Server safety net: respawn anyway after this long, in case the client
	-- never reports back (left, crashed, errored). Keep it longer than the clip.
	MaxRespawnWait = 60,

	-- Lighting inside the viewport.
	Ambient = Color3.fromRGB(140, 140, 140),
	LightColor = Color3.fromRGB(255, 244, 220),
	LightDirection = Vector3.new(-0.4, -1, -0.8),
}

return Config

--[[
	BlastDoor
	Every tunable for the door lives here.
]]

local DoorConfig = {}

-- ============================================================
-- SETUP
-- ============================================================

-- CollectionService tag that marks a door Model for this system.
DoorConfig.DoorTag = "BlastDoor"

-- Names of the two halves inside a tagged door Model. Each can be a single
-- BasePart or a Model (with any part arrangement -- PivotTo moves the whole
-- thing).
DoorConfig.LeftPartName = "Left"
DoorConfig.RightPartName = "Right"

-- Local axis the halves slide along, "X" | "Y" | "Z". Build the door closed
-- (the two halves touching in the middle) and pick whichever axis actually
-- separates them.
DoorConfig.SlideAxis = "Z"

-- Studs each half travels outward to fully open.
DoorConfig.SlideDistance = 4

-- ============================================================
-- MOTION
-- ============================================================

DoorConfig.OpenTime = 4
DoorConfig.CloseTime = 4
DoorConfig.EasingStyle = Enum.EasingStyle.Quad
DoorConfig.EasingDirection = Enum.EasingDirection.Out

-- ============================================================
-- ACTIVATION
-- ============================================================

-- "Proximity" | "Button" | "Both"
DoorConfig.ActivationMethod = "Both"

-- Proximity: opens when anyone with a Humanoid comes within this many studs
-- of the door's center, closes CloseDelay seconds after everyone leaves.
DoorConfig.SenseRadius = 10
DoorConfig.CloseDelay = 3
DoorConfig.SenseCheckInterval = 0.2

-- Button: looks for a ProximityPrompt anywhere inside the door Model first.
-- If none exists, one is created on ButtonPartName (or the left half, if
-- that part is missing too) using the settings below.
DoorConfig.ButtonPartName = "Button"
DoorConfig.ButtonActionText = "Open"
DoorConfig.ButtonObjectText = "Blast Door"
DoorConfig.ButtonHoldDuration = 0.3
DoorConfig.ButtonMaxDistance = 10
DoorConfig.ButtonRequiresLineOfSight = true

-- Button-mode only: seconds after fully opening before the door closes
-- itself. 0 disables auto-close, leaving the button as the only way shut.
-- Ignored in Proximity/Both, where CloseDelay already governs closing.
DoorConfig.AutoCloseDelay = 6

-- ============================================================
-- SOUND
-- ============================================================

DoorConfig.EnableSound = true

-- Ships silent -- Roblox audio is private per place, paste your own ids in.
DoorConfig.OpenSoundId = "rbxassetid://113066589392010"
DoorConfig.CloseSoundId = "rbxassetid://92664808815201"
DoorConfig.OpenSoundVolume = 1
DoorConfig.CloseSoundVolume = 1

-- ============================================================
-- CRUSH KILL / MIST
-- ============================================================

DoorConfig.EnableCrushKill = true

-- How narrow the gap between the halves has to be, in studs, before anyone
-- still standing in it dies. Raise it to kill earlier in the close -- set it
-- to SlideDistance for "any presence at all while closing is fatal".
DoorConfig.CrushGapThreshold = 4

-- Detection box centered on the gap: doorway height, and how deep along the
-- walk-through direction it reaches. Match these to the actual opening.
DoorConfig.CrushZoneHeight = 9
DoorConfig.CrushZoneDepth = 6
DoorConfig.CrushZoneMinDepth = 1

-- Set on a victim before Health hits 0, so any other death system (like
-- RagdollDeath/ragdoll.luau) knows to leave this kill alone.
DoorConfig.SuppressRagdollAttribute = "SuppressRagdoll"

-- Seconds the (already invisible) corpse model lingers before it's removed.
DoorConfig.CorpseCleanupDelay = 0.2

DoorConfig.MistColorBright = Color3.fromRGB(200, 20, 20)
DoorConfig.MistColorDark = Color3.fromRGB(80, 5, 5)
DoorConfig.MistParticleCount = 60
DoorConfig.MistStartSize = 1.4
DoorConfig.MistEndSize = 4.5
DoorConfig.MistSpeedMin = 8
DoorConfig.MistSpeedMax = 20
DoorConfig.MistGravity = 12
DoorConfig.MistLifetimeMin = 0.8
DoorConfig.MistLifetimeMax = 1.6
DoorConfig.MistEffectLifetime = 4

-- Engine path, not an asset id -- see the note in ArtilleryConfig if this
-- ever gets swapped out. A ParticleEmitter with no texture falls back to a
-- white sparkle, not an empty puff.
DoorConfig.MistTexture = "rbxasset://textures/particles/smoke_main.dds"

DoorConfig.EnableMistSound = true
DoorConfig.MistSoundId = ""
DoorConfig.MistSoundVolume = 1.2

-- ============================================================
-- DEBUG
-- ============================================================

DoorConfig.DebugLog = false

return table.freeze(DoorConfig)

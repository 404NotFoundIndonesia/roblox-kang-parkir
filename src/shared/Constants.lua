-- All tunable game values live here. No magic numbers in any other file.
local Constants = table.freeze({
	-- Whistle
	WhistleBaseRadius     = 10,    -- studs
	WhistleStatScale      = 1.5,   -- studs per WhistleLevel point
	WhistleMaxRadius      = 22,    -- studs (hard cap)
	WhistleCooldownOnLoss = 0.5,   -- seconds after losing a TugOfWar
	WhistleRateLimit      = 0.5,   -- min seconds between activations per player

	-- Tug-of-War
	TugOfWarDuration = 1.5,  -- seconds
	TugOfWarAPMCap   = 10,   -- max accepted inputs/second per player during tug

	-- Dash / PvP
	DashDuration        = 0.3,   -- seconds (hit-detection window)
	DashStaminaCost     = 30,    -- stamina units
	DashCooldown        = 1.0,   -- seconds
	DashMaxAngleDeg     = 45,    -- max degrees deviation from LookVector
	DashRagdollDuration = 1.5,   -- seconds target stays ragdolled
	MeleeRange          = 3,     -- studs forward
	MeleeWidth          = 2,     -- studs wide

	-- Stamina
	StaminaMax          = 100,  -- base max
	StaminaRegenRate    = 8,    -- units/second passive regen
	WhistleStaminaDrain = 4,    -- units/second while whistling

	-- Vehicle drag / physics
	TipOverThreshold     = 15,    -- rad/s angular velocity trigger
	TipOverPenaltyPct    = 0.30,  -- fraction of base payout deducted on tip
	TipOverDominoRadius  = 1.5,   -- studs radius for domino chain check
	AlignmentDotThreshold = 0.98, -- DotProduct required for alignment bonus
	AlignmentBonusMax    = 15,    -- max currency units bonus

	-- Vehicle timing
	VehicleEntranceTimeout = 15,  -- seconds before entrance vehicle returns to traffic
	TrespasEjectDelay      = 5,   -- seconds before foreign vehicle is ejected

	-- Combat tools
	SpikeStripPlaceRadius = 5,  -- max studs from player to place strip

	-- Helmet Thief
	ThiefInteractDuration   = 3,   -- seconds for steal animation
	ThiefRagdollDuration    = 1,   -- seconds thief stays ragdolled after hit
	ThiefRespawnDelayMin    = 45,  -- seconds
	ThiefRespawnDelayMax    = 90,  -- seconds
	ThiefMaxAlive           = 2,
	ThiefRetargetCooldown   = 10,  -- seconds before thief re-targets after interrupt

	-- Police (Satpol PP)
	PoliceProximityCaught    = 3,     -- studs to start caught timer
	PoliceCaughtTimer        = 2,     -- seconds inside proximity before "Caught"
	PoliceCaughtPenaltyPct   = 0.20,  -- fraction of unbanked lost on catch
	PoliceCaughtStunDuration = 3,     -- seconds input locked after catch
	PoliceSpawnCount         = 3,     -- NPCs per Raid (min 2, max 4)

	-- Events
	EventCooldownMin = 180,   -- seconds between events
	EventCooldownMax = 420,   -- seconds

	-- Monsoon Rain
	MonsoonFriction         = 0.1,   -- Friction applied to ground parts
	MonsoonSpeedMultiplier  = 0.85,  -- WalkSpeed multiplier during rain

	-- Flash Mob
	FlashMobDuration        = 10,    -- seconds of burst injection
	FlashMobVehicleCount    = 30,    -- minimum vehicles injected
	FlashMobEventMultiplier = 0.5,   -- payout EventMultiplier during burst
	FlashMobScooterWeight   = 0.95,  -- spawn weight for Scooter during burst

	-- Session phases
	SessionWarmUpDuration    = 60,   -- seconds
	SessionPeakDuration      = 420,  -- seconds (7 min)
	SessionRushHourDuration  = 120,  -- seconds (2 min)
	SessionShiftEndBuffer    = 30,   -- seconds buffer after shift ends

	-- Data / leaderboard
	BankAutoSaveInterval     = 60,   -- seconds between ProfileService auto-saves
	LeaderboardCacheInterval = 300,  -- seconds between leaderboard refreshes

	-- Traffic / spawn
	TrafficSpawnInterval        = 3.5,  -- seconds between normal vehicle spawns
	TrafficVehiclesPerPlayer    = 8,    -- max live vehicles per connected player (cap = this × playerCount, max 40)
	TrafficFlashMobInterval     = 0.3,  -- spawn interval override during FlashMob burst

	-- Shop prices (shift currency)
	ShopPrices = table.freeze({
		SpikeStrip  = 50,
		EnergyDrink = 30,
		BribeMoney  = 75,
	}),

	-- Vehicle spawn probability weights (must sum to 1.0)
	SpawnWeights = table.freeze({
		Scooter   = 0.45,
		SportBike = 0.25,
		FamilyCar = 0.18,
		AggroSUV  = 0.10,
		Supercar  = 0.02,
	}),

	-- Base payout per vehicle type (currency units)
	VehicleBasePayouts = table.freeze({
		Scooter   = 10,
		SportBike = 15,
		FamilyCar = 30,
		AggroSUV  = 40,
		Supercar  = 100,
	}),

	-- Roblox Developer Product IDs (set to real IDs before publishing)
	ProductId_EnergyDrink = 0,  -- placeholder
	ProductId_BribeMoney  = 0,  -- placeholder

	-- Roblox Gamepass IDs (set to real IDs before publishing)
	GamepassId_VIPWhistle = 0,  -- placeholder
	GamepassId_Landlord   = 0,  -- placeholder
})

return Constants

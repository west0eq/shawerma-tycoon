--!strict
--[[
	Constants.luau

	Single source of truth for tunables. Every magic number lives here so that
	balance changes don't require touching gameplay code.
]]

local Constants = {}

Constants.SchemaVersion = 3

Constants.Economy = {
	StartingCash = 250,
	MaxBankableCash = 1_000_000_000,
	-- Selling a placed item refunds this fraction of its purchase price.
	SellRefundRatio = 0.5,
}

Constants.Customer = {
	-- Base spawn cadence (seconds). Modulated by atmosphere score. Starts
	-- slow so a brand-new kiosk doesn't feel overwhelmed.
	SpawnIntervalSeconds = 16,
	-- Lowest cadence atmosphere can push spawning down to.
	SpawnIntervalMinSeconds = 5,
	-- Highest cadence atmosphere can stretch spawning out to.
	SpawnIntervalMaxSeconds = 26,
	-- Starting cap on simultaneous customers per plot. Upgrades raise it.
	MaxConcurrent = 2,
	-- How many extra simultaneous customers each spawn-rate upgrade level
	-- adds on top of MaxConcurrent.
	MaxConcurrentPerUpgrade = 2,
	-- Customers slow down a touch so the rig animation reads better.
	WalkSpeed = 10,
	-- Patience: how long the customer will wait between Ordering and being
	-- Served before they leave angry. Used for satisfaction scoring.
	PatienceSeconds = 60,
	-- Eat duration after sitting at a table.
	EatDurationSeconds = 10,
	-- How long the customer waits for a free seat after being served before
	-- giving up and leaving (so most customers actually sit at a table).
	SeatWaitTimeoutSeconds = 12,
	-- Probability a served customer wants to sit at a table to eat. The
	-- rest take their order to-go and leave directly.
	DineInProbability = 0.85,
	-- When true, customers and staff are built from real Roblox player
	-- avatars via Players:GetHumanoidDescriptionFromUserId. Falls back
	-- automatically to the procedural rig if the API errors out.
	UseRealisticRigs = true,
	-- Probability of pulling in the local player's friends as the avatar
	-- pool (instead of the curated default list). Friends are appended
	-- on join, not replacing the defaults.
	UseFriendsAsCustomers = true,
}

Constants.Trash = {
	-- Probability a customer leaves a dirty plate after dining in.
	PlateDropChance = 0.45,
	-- Probability a takeout customer drops a wrapper near the exit.
	WrapperDropChance = 0.18,
	-- How often the cleaner AI scans for trash and walks to the
	-- nearest item (per-plot).
	CleanerTickIntervalSeconds = 4,
	-- Distance (studs) the cleaner uses to "reach" trash before it pops.
	CleanerReachDistance = 4,
}

Constants.Cooking = {
	StationSpeedMultiplier = 1.0,
	-- How long an idle station waits before a hired cook starts the next
	-- pending order on it. Smaller = staff feel responsive.
	StaffCookCheckIntervalSeconds = 0.5,
}

Constants.Tips = {
	BaseRatio = 0.10,
	Jitter = 0.05,
	-- Bonus tip multiplier when served well within patience window.
	FastServiceBonus = 0.5,
	FastServiceThreshold = 12,
	-- Atmosphere score (0..1) multiplier on tips.
	AtmosphereTipMultiplier = 0.5,
}

Constants.Rating = {
	-- Combined star score is a weighted average of three axes (each 0..1).
	WeightService = 0.5,
	WeightFood = 0.3,
	WeightAtmosphere = 0.2,
	-- How many recent service events factor into the service axis.
	ServiceWindow = 30,
	-- How many recent food-quality events factor into the food axis.
	FoodWindow = 30,
}

Constants.Atmosphere = {
	-- Caps so a single decor type can't dominate the score.
	DiminishingThreshold = 6,
	-- Ceiling on the overall atmosphere score; dampens infinite scaling.
	MaxRawScore = 60,
}

Constants.Staff = {
	-- Maximum number of hires per role.
	MaxPerRole = 6,
	-- Walk speed of staff NPCs.
	WalkSpeed = 14,
	-- Period at which the staff loop re-scans pending tasks.
	TickIntervalSeconds = 0.4,
}

Constants.World = {
	Origin = Vector3.new(0, 0, 0),
	FloorSize = Vector3.new(60, 1, 60),
	WallHeight = 14,
	WallThickness = 1,
	NumStarterTables = 2,
	SeatsPerTable = 2,
	-- Multi-plot: every player gets one of N pre-built shawarma plots
	-- arranged in a 4×2 grid centred on Origin.
	NumPlots = 8,
	PlotsPerRow = 4,
	-- World-space spacing between plot centres on each axis.
	PlotSpacingX = 110,
	PlotSpacingZ = 110,
	-- Footprint of a single plot's interior (excluding exterior walls).
	PlotInteriorSize = Vector3.new(46, 1, 46),
	-- Outer shell extents (slightly larger than interior so walls sit outside).
	PlotShellSize = Vector3.new(54, 16, 54),
	-- Width of the door opening cut into the front wall.
	DoorWidth = 8,
	-- Distance the spawn pad sits in front of the door.
	SpawnPadOffset = 12,
}

Constants.Build = {
	-- Stud grid items snap to. Smaller = finer placement; larger = cleaner
	-- looking restaurants. 2 studs feels good for shawarma-scale geometry.
	GridSize = 2,
	-- Maximum number of placed items per player (anti-abuse cap).
	MaxPlacedItems = 256,
	-- How far below the eye the camera ray treats the ground as.
	GroundY = 1, -- floor top is at y=1 (floor is 1 stud thick at y=0..1)
	-- Half-extents within which placement is allowed (relative to Origin).
	PlotHalfExtents = Vector2.new(28, 28),
	-- Allowed Y-rotations during build mode.
	RotationStepDegrees = 15,
}

Constants.Save = {
	-- Bumped each schema version so abandoned-session locks reset cleanly.
	KeyPrefix = "ShawermaTycoon_v3_Player_",
	AutosaveIntervalSeconds = 60,
	MaxRetries = 4,
	RetryBackoffSeconds = 2,
	-- Session lock TTL: any save older than this can be reclaimed if the
	-- previous server crashed before releasing it.
	SessionLockTtlSeconds = 120,
}

Constants.Remotes = {
	-- Server -> all clients.
	OrderStateChanged = "OrderStateChanged",
	StationStateChanged = "StationStateChanged",
	-- Server -> owning player only.
	MoneyChanged = "MoneyChanged",
	Notify = "Notify",
	InventoryChanged = "InventoryChanged",
	PlacedItemsChanged = "PlacedItemsChanged",
	MenuUnlocksChanged = "MenuUnlocksChanged",
	StaffChanged = "StaffChanged",
	UpgradesChanged = "UpgradesChanged",
	RatingChanged = "RatingChanged",
	PlotAssigned = "PlotAssigned",
	-- Server -> player on join: list of free plots so the client can show
	-- a selection screen (cycle through with arrow keys, name + claim).
	PlotsAvailable = "PlotsAvailable",
	-- Client -> server (intent only; server validates).
	RequestBuy = "RequestBuy",
	RequestPlace = "RequestPlace",
	RequestRemove = "RequestRemove",
	RequestSell = "RequestSell",
	RequestHireStaff = "RequestHireStaff",
	RequestFireStaff = "RequestFireStaff",
	RequestUpgradeStaff = "RequestUpgradeStaff",
	RequestPurchaseUpgrade = "RequestPurchaseUpgrade",
	-- Client -> server: claim a specific plot by index with a chosen name.
	RequestClaimPlot = "RequestClaimPlot",
}

Constants.PlotName = {
	-- Max characters allowed in a plot's display name. Anything past this
	-- is trimmed server-side.
	MaxLength = 24,
	MinLength = 2,
}

table.freeze(Constants.Economy)
table.freeze(Constants.Customer)
table.freeze(Constants.Cooking)
table.freeze(Constants.Tips)
table.freeze(Constants.Rating)
table.freeze(Constants.Atmosphere)
table.freeze(Constants.Staff)
table.freeze(Constants.World)
table.freeze(Constants.Build)
table.freeze(Constants.Save)
table.freeze(Constants.Remotes)
table.freeze(Constants.PlotName)
table.freeze(Constants)

return Constants

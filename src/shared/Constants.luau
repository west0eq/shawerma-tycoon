--!strict
--[[
	Constants.luau

	Single source of truth for tunables. Every magic number lives here so that
	balance changes don't require touching gameplay code.
]]

local Constants = {}

Constants.SchemaVersion = 2

Constants.Economy = {
	StartingCash = 250,
	MaxBankableCash = 1_000_000_000,
	-- Selling a placed item refunds this fraction of its purchase price.
	SellRefundRatio = 0.5,
}

Constants.Customer = {
	SpawnIntervalSeconds = 8,
	MaxConcurrent = 6,
	WalkSpeed = 12,
	-- Patience: how long the customer will wait between Ordering and being
	-- Served before they leave angry. Used for satisfaction scoring.
	PatienceSeconds = 60,
	EatDurationSeconds = 8,
}

Constants.Cooking = {
	StationSpeedMultiplier = 1.0,
}

Constants.Tips = {
	BaseRatio = 0.10,
	Jitter = 0.05,
	-- Bonus tip multiplier when served well within patience window.
	FastServiceBonus = 0.5,
	FastServiceThreshold = 12,
}

Constants.World = {
	Origin = Vector3.new(0, 0, 0),
	FloorSize = Vector3.new(60, 1, 60),
	WallHeight = 14,
	WallThickness = 1,
	NumStarterTables = 2,
	SeatsPerTable = 2,
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
	KeyPrefix = "ShawermaTycoon_v2_Player_",
	AutosaveIntervalSeconds = 60,
	MaxRetries = 4,
	RetryBackoffSeconds = 2,
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
	-- Client -> server (intent only; server validates).
	RequestBuy = "RequestBuy",
	RequestPlace = "RequestPlace",
	RequestRemove = "RequestRemove",
	RequestSell = "RequestSell",
}

table.freeze(Constants.Economy)
table.freeze(Constants.Customer)
table.freeze(Constants.Cooking)
table.freeze(Constants.Tips)
table.freeze(Constants.World)
table.freeze(Constants.Build)
table.freeze(Constants.Save)
table.freeze(Constants.Remotes)
table.freeze(Constants)

return Constants

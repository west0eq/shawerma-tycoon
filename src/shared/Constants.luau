--!strict
--[[
	Constants.luau

	Single source of truth for tunables. Every magic number lives here so that
	balance changes don't require touching gameplay code.
]]

local Constants = {}

Constants.SchemaVersion = 1

Constants.Economy = {
	StartingCash = 250,
	MaxBankableCash = 1_000_000_000,
}

Constants.Customer = {
	SpawnIntervalSeconds = 8,
	MaxConcurrent = 6,
	WalkSpeed = 12,
	-- How long the customer is willing to wait at the counter before they get
	-- annoyed. P1 uses this only for ambient feedback; Phase 3 will tie it to
	-- service score.
	PatienceSeconds = 60,
	EatDurationSeconds = 8,
}

Constants.Cooking = {
	-- Default prep time is also stored per-dish in DishCatalog. The station
	-- multiplies the dish's prep time by this factor (Phase 2 upgrades will
	-- lower it).
	StationSpeedMultiplier = 1.0,
}

Constants.Tips = {
	-- Base tip = price * BaseRatio, modulated by service speed in Phase 3.
	BaseRatio = 0.10,
	-- Random jitter +/- this fraction so tips don't feel mechanical.
	Jitter = 0.05,
}

Constants.World = {
	-- All world coordinates are anchored around this origin; moving the
	-- restaurant is just changing this value.
	Origin = Vector3.new(0, 0, 0),
	FloorSize = Vector3.new(60, 1, 60),
	WallHeight = 14,
	WallThickness = 1,
	NumStarterTables = 2,
	SeatsPerTable = 2,
}

Constants.Save = {
	-- DataStore key prefix; bumping this forces a fresh save namespace
	-- (used during open beta to invalidate stale data).
	KeyPrefix = "ShawermaTycoon_v1_Player_",
	AutosaveIntervalSeconds = 60,
	MaxRetries = 4,
	RetryBackoffSeconds = 2,
}

Constants.Remotes = {
	-- Server -> clients: broadcasts the visible order queue (counter line).
	OrderStateChanged = "OrderStateChanged",
	-- Server -> clients: cooking station state for HUD/proximity hints.
	StationStateChanged = "StationStateChanged",
	-- Server -> player: cash updates (no client mutation path on purpose).
	MoneyChanged = "MoneyChanged",
	-- Server -> player: transient toast messages.
	Notify = "Notify",
}

table.freeze(Constants.Economy)
table.freeze(Constants.Customer)
table.freeze(Constants.Cooking)
table.freeze(Constants.Tips)
table.freeze(Constants.World)
table.freeze(Constants.Save)
table.freeze(Constants.Remotes)
table.freeze(Constants)

return Constants

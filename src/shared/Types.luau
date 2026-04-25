--!strict
--[[
	Types.luau

	Shared Luau type aliases. Importing this module (`local T = require(...)`)
	gives access to every concept the gameplay services exchange.
]]

export type DishId = string

export type Dish = {
	id: DishId,
	displayName: string,
	prepSeconds: number,
	basePrice: number,
	-- Stations / unlock requirements come online in Phase 2. Carried as
	-- optional fields here so the catalog stays forward-compatible.
	unlockTier: number?,
	tags: { string }?,
}

export type OrderState = "Pending" | "Prepping" | "Ready" | "Served" | "Cancelled"

export type Order = {
	id: number,
	dishId: DishId,
	customerId: number,
	state: OrderState,
	createdAt: number,
}

export type CustomerState =
	"Spawning"
	| "WalkingToCounter"
	| "Ordering"
	| "Waiting"
	| "WalkingToSeat"
	| "Eating"
	| "Leaving"

export type StationState = "Idle" | "Prepping" | "Ready"

export type PlayerSave = {
	schemaVersion: number,
	cash: number,
	totalEarned: number,
	customersServed: number,
	unlocks: { [string]: boolean },
	-- Reserved for Phase 2+ (placed furniture, menu unlocks, staff data).
	build: { [string]: any }?,
	staff: { [string]: any }?,
	menu: { [string]: any }?,
}

return {}

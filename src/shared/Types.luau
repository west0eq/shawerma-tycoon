--!strict
--[[
	Types.luau

	Shared Luau type aliases. Importing this module (`local T = require(...)`)
	gives access to every concept the gameplay services exchange.
]]

export type DishId = string

export type DishCategory =
	"wrap"      -- shawarma family
	| "plate"   -- grill / rice plates
	| "side"    -- fries, salads
	| "drink"   -- soft drinks, ayran
	| "dessert" -- baklava etc.

export type Dish = {
	id: DishId,
	displayName: string,
	category: DishCategory,
	prepSeconds: number,
	basePrice: number,
	-- 0 = unlocked from start. Larger values gate behind progression
	-- (cash earned, customers served, explicit menu unlock).
	unlockTier: number,
	-- Tier requirements live alongside the dish so the catalog stays
	-- declarative. Keys correspond to PlayerSave fields.
	unlockRequires: { totalEarned: number?, customersServed: number? }?,
	-- 0..1 baseline food-quality score; modifiers (station tier, prep speed)
	-- nudge the actual review event up or down from this baseline.
	baseQuality: number?,
	tags: { string }?,
}

export type OrderState = "Pending" | "Prepping" | "Ready" | "Served" | "Cancelled" | "Abandoned"

export type Order = {
	id: number,
	dishId: DishId,
	customerId: number,
	state: OrderState,
	createdAt: number,
	-- Set when the dish has been served, used for satisfaction scoring.
	servedAt: number?,
	-- Multi-plot tag: which plot the order belongs to, so cooking is scoped
	-- to that plot's stations and pay-out goes to that plot's owner.
	plotIndex: number?,
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

-- Stations either come built-in (the starter shawarma counter) or are placed
-- by the player via build mode. Type drives which dish category they accept.
export type StationType = "shawarma" | "grill" | "side" | "drink" | "dessert"

export type BuildItemCategory = "furniture" | "station" | "decor" | "structure"

export type PlacedItem = {
	-- Unique id for this placement (independent of the catalog id).
	uid: string,
	catalogId: string,
	posX: number,
	posY: number,
	posZ: number,
	yawDegrees: number,
}

export type InventoryEntry = {
	catalogId: string,
	count: number,
}

export type StaffRole = "cook" | "cashier" | "server" | "cleaner"

export type StaffMember = {
	-- Stable identifier across saves so we can address a specific hire.
	uid: string,
	role: StaffRole,
	level: number,
	-- Display nickname picked from a procedural list at hire time.
	nickname: string,
}

export type UpgradeId = string

export type Upgrade = {
	id: UpgradeId,
	displayName: string,
	description: string,
	-- Ordered list of tier costs; index 1 = first level, etc.
	tierCosts: { number },
	-- Effect descriptor; gameplay services read this to apply the upgrade.
	effect: { kind: string, value: number },
}

export type PlayerSave = {
	schemaVersion: number,
	cash: number,
	totalEarned: number,
	customersServed: number,
	unlocks: { [string]: boolean },
	-- v2 fields.
	inventory: { [string]: number }?,             -- catalogId -> count
	placed: { PlacedItem }?,                       -- placed-in-world items
	menuUnlocks: { [string]: boolean }?,           -- dishId -> unlocked
	-- v3 fields.
	staff: { StaffMember }?,                       -- list of hired staff
	upgrades: { [UpgradeId]: number }?,            -- upgradeId -> tier owned
}

return {}

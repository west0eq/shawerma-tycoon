--!strict
--[[
	DishCatalog.luau

	Data-driven dish definitions. The catalog is the single source of truth
	for what the player can sell — gameplay services never hardcode dishes,
	they iterate or look up by id.

	Categories map to station types: a dish of category "wrap" requires a
	station of type "shawarma"; "plate" → "grill"; etc.
]]

local Types = require(script.Parent.Types)

type Dish = Types.Dish

-- Mapping from dish category → station type that can prepare it. Keep in sync
-- when adding a new category.
local CATEGORY_TO_STATION: { [Types.DishCategory]: Types.StationType } = {
	wrap = "shawarma",
	plate = "grill",
	side = "side",
	drink = "drink",
	dessert = "dessert",
}

local DishCatalog: { [Types.DishId]: Dish } = {
	-- ---- Wraps (shawarma station) ----
	shawarma_classic = {
		id = "shawarma_classic",
		displayName = "Classic Shawarma",
		category = "wrap",
		prepSeconds = 4,
		basePrice = 12,
		unlockTier = 0,
		tags = { "starter", "wrap" },
	},
	shawarma_spicy = {
		id = "shawarma_spicy",
		displayName = "Spicy Shawarma",
		category = "wrap",
		prepSeconds = 5,
		basePrice = 16,
		unlockTier = 1,
		unlockRequires = { totalEarned = 200 },
		tags = { "wrap", "spicy" },
	},
	falafel_wrap = {
		id = "falafel_wrap",
		displayName = "Falafel Wrap",
		category = "wrap",
		prepSeconds = 4,
		basePrice = 14,
		unlockTier = 1,
		unlockRequires = { customersServed = 8 },
		tags = { "wrap", "veggie" },
	},
	-- ---- Plates (grill station) ----
	chicken_plate = {
		id = "chicken_plate",
		displayName = "Chicken Plate",
		category = "plate",
		prepSeconds = 7,
		basePrice = 28,
		unlockTier = 2,
		unlockRequires = { totalEarned = 1000 },
		tags = { "plate", "premium" },
	},
	lamb_plate = {
		id = "lamb_plate",
		displayName = "Lamb Plate",
		category = "plate",
		prepSeconds = 9,
		basePrice = 38,
		unlockTier = 3,
		unlockRequires = { totalEarned = 5000 },
		tags = { "plate", "premium" },
	},
	-- ---- Sides ----
	fries_basic = {
		id = "fries_basic",
		displayName = "Crispy Fries",
		category = "side",
		prepSeconds = 5,
		basePrice = 8,
		unlockTier = 1,
		unlockRequires = { totalEarned = 300 },
		tags = { "side" },
	},
	-- ---- Drinks ----
	ayran = {
		id = "ayran",
		displayName = "Ayran",
		category = "drink",
		prepSeconds = 1,
		basePrice = 5,
		unlockTier = 1,
		unlockRequires = { customersServed = 4 },
		tags = { "drink", "cold" },
	},
	soda = {
		id = "soda",
		displayName = "Soda",
		category = "drink",
		prepSeconds = 1,
		basePrice = 4,
		unlockTier = 1,
		unlockRequires = { customersServed = 4 },
		tags = { "drink", "cold" },
	},
	-- ---- Desserts ----
	baklava = {
		id = "baklava",
		displayName = "Baklava",
		category = "dessert",
		prepSeconds = 3,
		basePrice = 12,
		unlockTier = 2,
		unlockRequires = { totalEarned = 2000 },
		tags = { "dessert", "sweet" },
	},
}

local function get(id: Types.DishId): Dish
	local dish = DishCatalog[id]
	assert(dish ~= nil, "DishCatalog: unknown dish id '" .. tostring(id) .. "'")
	return dish
end

local function all(): { Dish }
	local out: { Dish } = {}
	for _, dish in pairs(DishCatalog) do
		table.insert(out, dish)
	end
	return out
end

local function categoryToStation(category: Types.DishCategory): Types.StationType
	return CATEGORY_TO_STATION[category]
end

local function isUnlocked(dish: Dish, save: { totalEarned: number, customersServed: number }, menuUnlocks: { [string]: boolean }?): boolean
	-- Explicit menu unlock from save trumps requirements.
	if menuUnlocks and menuUnlocks[dish.id] then
		return true
	end
	if dish.unlockTier == 0 then
		return true
	end
	local req = dish.unlockRequires
	if not req then
		return true
	end
	if req.totalEarned and save.totalEarned < req.totalEarned then
		return false
	end
	if req.customersServed and save.customersServed < req.customersServed then
		return false
	end
	return true
end

return {
	get = get,
	all = all,
	categoryToStation = categoryToStation,
	isUnlocked = isUnlocked,
}

--!strict
--[[
	DishCatalog.luau

	Data-driven dish definitions. Phase 1 ships only `shawarma_classic`; later
	phases append entries here without touching gameplay code.
]]

local Types = require(script.Parent.Types)

type Dish = Types.Dish

local DishCatalog: { [Types.DishId]: Dish } = {
	shawarma_classic = {
		id = "shawarma_classic",
		displayName = "Classic Shawarma",
		prepSeconds = 4,
		basePrice = 12,
		unlockTier = 0,
		tags = { "starter", "wrap" },
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

local function unlocked(tier: number): { Dish }
	local out: { Dish } = {}
	for _, dish in pairs(DishCatalog) do
		if (dish.unlockTier or 0) <= tier then
			table.insert(out, dish)
		end
	end
	return out
end

return {
	get = get,
	all = all,
	unlocked = unlocked,
}

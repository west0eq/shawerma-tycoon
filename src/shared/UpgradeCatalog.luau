--!strict
--[[
	UpgradeCatalog.luau

	Restaurant-wide upgrades. Effects are read at runtime by the relevant
	services (e.g. CustomerService for spawn rate, StationService for
	cooking speed). Each upgrade has a list of tier costs; index 1 is the
	cost of the first level. Length defines the max tier.
]]

local Types = require(script.Parent:WaitForChild("Types"))

type Upgrade = Types.Upgrade

local UpgradeCatalog: { [string]: Upgrade } = {
	customer_flow = {
		id = "customer_flow",
		displayName = "Foot Traffic",
		description = "More customers can be inside at once.",
		tierCosts = { 800, 2000, 5000, 12000 },
		effect = { kind = "concurrent_customers_bonus", value = 1 },
	},
	prep_speed = {
		id = "prep_speed",
		displayName = "Sharper Knives",
		description = "Every station preps 10% faster per tier.",
		tierCosts = { 500, 1500, 4000, 9000 },
		effect = { kind = "station_speed_multiplier", value = 0.10 },
	},
	tip_jar = {
		id = "tip_jar",
		displayName = "Tip Jar",
		description = "Customers leave higher tips per tier.",
		tierCosts = { 400, 1200, 3000, 7000 },
		effect = { kind = "tip_ratio_bonus", value = 0.05 },
	},
	patience = {
		id = "patience",
		displayName = "Comfortable Waiting Area",
		description = "Customers wait longer before walking out.",
		tierCosts = { 600, 1800, 4500, 9500 },
		effect = { kind = "patience_bonus_seconds", value = 15 },
	},
	plot_size = {
		id = "plot_size",
		displayName = "Bigger Lot",
		description = "Expands the buildable area.",
		tierCosts = { 2000, 6000, 15000 },
		effect = { kind = "plot_extents_bonus", value = 6 },
	},
}

local M = {}

function M.get(id: string): Upgrade
	local up = UpgradeCatalog[id]
	assert(up, "UpgradeCatalog: unknown upgrade " .. tostring(id))
	return up
end

function M.exists(id: string): boolean
	return UpgradeCatalog[id] ~= nil
end

function M.all(): { Upgrade }
	local out: { Upgrade } = {}
	for _, up in pairs(UpgradeCatalog) do
		table.insert(out, up)
	end
	return out
end

function M.maxTier(id: string): number
	return #M.get(id).tierCosts
end

-- Cost to go from `currentTier` (0 means "not bought yet") to the next.
function M.nextTierCost(id: string, currentTier: number): number?
	local up = M.get(id)
	local idx = currentTier + 1
	if idx < 1 or idx > #up.tierCosts then
		return nil
	end
	return up.tierCosts[idx]
end

return M

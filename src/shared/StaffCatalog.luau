--!strict
--[[
	StaffCatalog.luau

	Declarative catalog of every staff role. Each role describes:
	  • hire cost
	  • per-level upgrade costs (length determines max level)
	  • per-level effects (read by StaffService at runtime)

	Adding a new role is a one-file change here.
]]

local Types = require(script.Parent:WaitForChild("Types"))

type StaffRole = Types.StaffRole

export type StaffSpec = {
	role: StaffRole,
	displayName: string,
	description: string,
	hireCost: number,
	-- index = level (1 = freshly hired). Length = max level.
	upgradeCosts: { number },
	-- Per-level multipliers / values keyed by effect.
	effectsByLevel: { [number]: { [string]: number } },
	bodyColor: Color3,
}

local StaffCatalog: { [StaffRole]: StaffSpec } = {
	cook = {
		role = "cook",
		displayName = "Cook",
		description = "Auto-preps pending orders at any matching station.",
		hireCost = 400,
		upgradeCosts = { 0, 250, 500, 900, 1500 },
		effectsByLevel = {
			[1] = { speed = 1.0, qualityBonus = 0.0 },
			[2] = { speed = 1.15, qualityBonus = 0.05 },
			[3] = { speed = 1.3, qualityBonus = 0.10 },
			[4] = { speed = 1.5, qualityBonus = 0.15 },
			[5] = { speed = 1.8, qualityBonus = 0.20 },
		},
		bodyColor = Color3.fromRGB(220, 200, 170),
	},
	cashier = {
		role = "cashier",
		displayName = "Cashier",
		description = "Tightens the order pipeline; tips trend higher.",
		hireCost = 350,
		upgradeCosts = { 0, 250, 450, 800, 1200 },
		effectsByLevel = {
			[1] = { tipBonus = 0.05 },
			[2] = { tipBonus = 0.08 },
			[3] = { tipBonus = 0.12 },
			[4] = { tipBonus = 0.16 },
			[5] = { tipBonus = 0.22 },
		},
		bodyColor = Color3.fromRGB(120, 160, 220),
	},
	server = {
		role = "server",
		displayName = "Server",
		description = "Walks ready dishes to seated customers.",
		hireCost = 300,
		upgradeCosts = { 0, 200, 400, 700, 1100 },
		effectsByLevel = {
			[1] = { speed = 1.0, fastServiceBonus = 0.0 },
			[2] = { speed = 1.15, fastServiceBonus = 0.05 },
			[3] = { speed = 1.3, fastServiceBonus = 0.10 },
			[4] = { speed = 1.5, fastServiceBonus = 0.15 },
			[5] = { speed = 1.8, fastServiceBonus = 0.20 },
		},
		bodyColor = Color3.fromRGB(180, 220, 160),
	},
	cleaner = {
		role = "cleaner",
		displayName = "Cleaner",
		description = "Resets tables faster so seats free up sooner.",
		hireCost = 250,
		upgradeCosts = { 0, 180, 360, 650, 1000 },
		effectsByLevel = {
			[1] = { tableResetSpeed = 1.0 },
			[2] = { tableResetSpeed = 1.3 },
			[3] = { tableResetSpeed = 1.6 },
			[4] = { tableResetSpeed = 2.0 },
			[5] = { tableResetSpeed = 2.5 },
		},
		bodyColor = Color3.fromRGB(220, 180, 220),
	},
}

local M = {}

function M.get(role: StaffRole): StaffSpec
	local spec = StaffCatalog[role]
	assert(spec, "StaffCatalog: unknown role " .. tostring(role))
	return spec
end

function M.exists(role: string): boolean
	return StaffCatalog[role :: any] ~= nil
end

function M.all(): { StaffSpec }
	local out: { StaffSpec } = {}
	for _, spec in pairs(StaffCatalog) do
		table.insert(out, spec)
	end
	return out
end

function M.maxLevel(role: StaffRole): number
	return #M.get(role).upgradeCosts
end

-- Cost to go from `fromLevel` to `fromLevel + 1` (inclusive of upgrade).
-- Returns nil if `fromLevel` is already at max.
function M.upgradeCostFor(role: StaffRole, fromLevel: number): number?
	local spec = M.get(role)
	local idx = fromLevel + 1
	if idx < 2 or idx > #spec.upgradeCosts then
		return nil
	end
	return spec.upgradeCosts[idx]
end

function M.effects(role: StaffRole, level: number): { [string]: number }
	local spec = M.get(role)
	local clamped = math.clamp(level, 1, M.maxLevel(role))
	return spec.effectsByLevel[clamped]
end

return M

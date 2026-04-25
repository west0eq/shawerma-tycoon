--!strict
--[[
	Util.luau

	Tiny utility helpers shared by both contexts. Keep this module dependency
	free — it must be safe to require from anywhere.
]]

local Util = {}

function Util.clamp(value: number, min: number, max: number): number
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.formatMoney(amount: number): string
	-- Group thousands with a comma. Avoids string.format("%'d", ...) which
	-- isn't reliable across locales in Roblox.
	local sign = amount < 0 and "-" or ""
	local int = tostring(math.floor(math.abs(amount) + 0.5))
	local formatted = int:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return string.format("$%s%s", sign, formatted)
end

function Util.weightedRandom<T>(items: { { value: T, weight: number } }, rng: Random?): T
	local generator = rng or Random.new()
	local total = 0
	for _, entry in ipairs(items) do
		total += entry.weight
	end
	assert(total > 0, "weightedRandom: total weight must be positive")
	local roll = generator:NextNumber(0, total)
	local acc = 0
	for _, entry in ipairs(items) do
		acc += entry.weight
		if roll <= acc then
			return entry.value
		end
	end
	-- Fallback for floating-point drift.
	return items[#items].value
end

function Util.shallowCopy<T>(t: T): T
	local copy = {} :: any
	for k, v in pairs(t :: any) do
		copy[k] = v
	end
	return copy
end

function Util.roundTo(value: number, step: number): number
	if step <= 0 then
		return value
	end
	return math.floor(value / step + 0.5) * step
end

return Util

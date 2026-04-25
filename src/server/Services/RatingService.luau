--!strict
--[[
	RatingService.luau

	Phase 2 implementation: tracks satisfaction events emitted by other
	services and computes a rolling restaurant star rating from them.
	Phase 3 will expand this with food quality and atmosphere components
	per the brief.

	Public API:
	  RatingService.recordEvent(kind, payload) — called by gameplay services
	  RatingService.getStars()                  — number 1..5
	  RatingService.getServiceScore()           — 0..1, "service" axis only

	Internally we keep a fixed-size sliding window so rating responds to
	recent service quality, not lifetime average.
]]

local RatingService = {}

local WINDOW_SIZE = 30

-- Each entry is a number in [-1, 1]: positive = good event, negative = bad.
local window: { number } = {}

local EVENT_WEIGHTS: { [string]: number } = {
	served = 0.6,
	served_fast = 1.0,
	served_slow = 0.0,
	customer_left_angry = -1.0,
	dish_unlocked = 0.3,
}

function RatingService.init() end

function RatingService.recordEvent(kind: string, _payload: any?)
	local weight = EVENT_WEIGHTS[kind]
	if weight == nil then
		return
	end
	table.insert(window, weight)
	if #window > WINDOW_SIZE then
		table.remove(window, 1)
	end
end

function RatingService.getServiceScore(): number
	if #window == 0 then
		return 1.0
	end
	local sum = 0
	for _, value in ipairs(window) do
		sum += value
	end
	local avg = sum / #window
	-- Map [-1, 1] → [0, 1].
	return math.clamp((avg + 1) / 2, 0, 1)
end

function RatingService.getStars(): number
	-- Five-star rounded from the service score until food/atmosphere axes
	-- come online in Phase 3.
	local score = RatingService.getServiceScore()
	local stars = math.floor(score * 4 + 0.5) + 1
	return math.clamp(stars, 1, 5)
end

return RatingService

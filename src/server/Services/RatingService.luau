--!strict
--[[
	RatingService.luau

	Phase 1 stub. The real star/service/food/atmosphere scoring lands in
	Phase 3; this module exists now so other services can already depend on
	a stable API (`getStars`, `recordEvent`) without churn later.
]]

local RatingService = {}

local stars = 5

function RatingService.init() end

function RatingService.getStars(): number
	return stars
end

function RatingService.recordEvent(_kind: string, _payload: any?)
	-- No-op in P1. Phase 3 will translate kinds like "served_in_time",
	-- "long_wait", "tip_received" into score changes.
end

return RatingService

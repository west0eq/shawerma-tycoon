--!strict
--[[
	RatingService.luau

	Restaurant star rating along three axes:
	  • Service  — derived from a sliding window of customer events.
	  • Food     — sliding window of food-quality samples (0..1) emitted by
	                StationService whenever a dish is served.
	  • Atmosphere — read live from AtmosphereService (0..1).

	`getStars()` blends them with the weights in Constants.Rating and emits
	a `RatingChanged` remote so the HUD can show stars in real time.

	Implementation note: a single-host server keeps the rating global. The
	module deliberately uses module-level state instead of per-player so a
	multiplayer extension only has to introduce a key.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Signal = require(Shared:WaitForChild("Signal"))

local RatingService = {}

RatingService.Changed = Signal.new()

local AtmosphereService: any
local ratingRemote: RemoteEvent?

-- Service axis: each entry is in [-1..1].
local serviceWindow: { number } = {}
-- Food axis: each entry is in [0..1].
local foodWindow: { number } = {}

local SERVICE_WEIGHTS: { [string]: number } = {
	served = 0.6,
	served_fast = 1.0,
	served_slow = -0.2,
	customer_left_angry = -1.0,
	dish_unlocked = 0.3,
}

local lastBroadcast = { service = -1, food = -1, atmosphere = -1, stars = -1 }

local function pushBounded(arr: { number }, value: number, cap: number)
	table.insert(arr, value)
	if #arr > cap then
		table.remove(arr, 1)
	end
end

local function avg(arr: { number }, fallback: number): number
	if #arr == 0 then
		return fallback
	end
	local sum = 0
	for _, v in ipairs(arr) do
		sum += v
	end
	return sum / #arr
end

local function broadcastIfChanged()
	local svc = RatingService.getServiceScore()
	local food = RatingService.getFoodScore()
	local atm = RatingService.getAtmosphereScore()
	local stars = RatingService.getStars()
	if math.abs(svc - lastBroadcast.service) < 0.005
		and math.abs(food - lastBroadcast.food) < 0.005
		and math.abs(atm - lastBroadcast.atmosphere) < 0.005
		and stars == lastBroadcast.stars
	then
		return
	end
	lastBroadcast = { service = svc, food = food, atmosphere = atm, stars = stars }
	if ratingRemote then
		for _, player in ipairs(Players:GetPlayers()) do
			ratingRemote:FireClient(player, {
				stars = stars,
				service = svc,
				food = food,
				atmosphere = atm,
			})
		end
	end
	RatingService.Changed:Fire(stars, svc, food, atm)
end

function RatingService.recordEvent(kind: string, _payload: any?)
	local weight = SERVICE_WEIGHTS[kind]
	if weight == nil then
		return
	end
	pushBounded(serviceWindow, weight, Constants.Rating.ServiceWindow)
	broadcastIfChanged()
end

function RatingService.recordFoodEvent(quality: number, _dishId: string?)
	pushBounded(foodWindow, math.clamp(quality, 0, 1), Constants.Rating.FoodWindow)
	broadcastIfChanged()
end

function RatingService.getServiceScore(): number
	local a = avg(serviceWindow, 1.0)
	-- Service-event weights are in [-1..1]; map to 0..1.
	return math.clamp((a + 1) / 2, 0, 1)
end

function RatingService.getFoodScore(): number
	return math.clamp(avg(foodWindow, 0.6), 0, 1)
end

function RatingService.getAtmosphereScore(): number
	if not AtmosphereService then
		return 0
	end
	return math.clamp(AtmosphereService.getScore(), 0, 1)
end

function RatingService.getOverallScore(): number
	local w = Constants.Rating
	local total = w.WeightService + w.WeightFood + w.WeightAtmosphere
	local svc = RatingService.getServiceScore()
	local food = RatingService.getFoodScore()
	local atm = RatingService.getAtmosphereScore()
	return (svc * w.WeightService + food * w.WeightFood + atm * w.WeightAtmosphere) / total
end

function RatingService.getStars(): number
	local score = RatingService.getOverallScore()
	-- 0..1 → 1..5.
	local stars = math.floor(score * 4 + 0.5) + 1
	return math.clamp(stars, 1, 5)
end

function RatingService.init(deps: { remotes: { [string]: RemoteEvent }, atmosphereService: any? }?)
	if deps then
		ratingRemote = deps.remotes.RatingChanged
		AtmosphereService = deps.atmosphereService
		if AtmosphereService and AtmosphereService.Changed then
			AtmosphereService.Changed:Connect(function()
				broadcastIfChanged()
			end)
		end
	end
end

return RatingService

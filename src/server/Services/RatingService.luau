--!strict
--[[
	RatingService.luau

	Per-player restaurant rating along three axes:
	  • Service  — sliding window of customer events for that player.
	  • Food     — sliding window of food-quality samples (0..1).
	  • Atmosphere — read live from AtmosphereService for that player.

	Each player gets their own service/food windows because plots run
	independent businesses in the multi-plot world.

	Public:
	  • init({ remotes, atmosphereService })
	  • recordEvent(player, kind, payload)
	  • recordFoodEvent(player, quality, dishId)
	  • getStars(player), getServiceScore(player), getFoodScore(player)
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

type RatingState = {
	service: { number },
	food: { number },
	last: { service: number, food: number, atmosphere: number, stars: number },
}

local SERVICE_WEIGHTS: { [string]: number } = {
	served = 0.6,
	served_fast = 1.0,
	served_slow = -0.2,
	customer_left_angry = -1.0,
	dish_unlocked = 0.3,
}

local statesByPlayer: { [Player]: RatingState } = {}

local function ensureState(player: Player): RatingState
	local s = statesByPlayer[player]
	if s then
		return s
	end
	s = {
		service = {},
		food = {},
		last = { service = -1, food = -1, atmosphere = -1, stars = -1 },
	}
	statesByPlayer[player] = s
	return s
end

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

local function serviceScore(state: RatingState): number
	local a = avg(state.service, 1.0)
	return math.clamp((a + 1) / 2, 0, 1)
end

local function foodScore(state: RatingState): number
	return math.clamp(avg(state.food, 0.6), 0, 1)
end

local function atmosphereScore(player: Player): number
	if not AtmosphereService then
		return 0
	end
	return math.clamp(AtmosphereService.getScore(player), 0, 1)
end

local function overallScore(player: Player, state: RatingState): number
	local w = Constants.Rating
	local total = w.WeightService + w.WeightFood + w.WeightAtmosphere
	return (
		serviceScore(state) * w.WeightService
		+ foodScore(state) * w.WeightFood
		+ atmosphereScore(player) * w.WeightAtmosphere
	) / total
end

local function starsFromScore(score: number): number
	return math.clamp(math.floor(score * 4 + 0.5) + 1, 1, 5)
end

local function broadcastIfChanged(player: Player)
	local state = ensureState(player)
	local svc = serviceScore(state)
	local food = foodScore(state)
	local atm = atmosphereScore(player)
	local stars = starsFromScore(overallScore(player, state))
	if math.abs(svc - state.last.service) < 0.005
		and math.abs(food - state.last.food) < 0.005
		and math.abs(atm - state.last.atmosphere) < 0.005
		and stars == state.last.stars
	then
		return
	end
	state.last = { service = svc, food = food, atmosphere = atm, stars = stars }
	if ratingRemote then
		ratingRemote:FireClient(player, {
			stars = stars,
			service = svc,
			food = food,
			atmosphere = atm,
		})
	end
	RatingService.Changed:Fire(player, stars, svc, food, atm)
end

function RatingService.recordEvent(player: Player?, kind: string, _payload: any?)
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return
	end
	local weight = SERVICE_WEIGHTS[kind]
	if weight == nil then
		return
	end
	local state = ensureState(subject)
	pushBounded(state.service, weight, Constants.Rating.ServiceWindow)
	broadcastIfChanged(subject)
end

function RatingService.recordFoodEvent(player: Player?, quality: number, _dishId: string?)
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return
	end
	local state = ensureState(subject)
	pushBounded(state.food, math.clamp(quality, 0, 1), Constants.Rating.FoodWindow)
	broadcastIfChanged(subject)
end

function RatingService.getServiceScore(player: Player?): number
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return 0
	end
	return serviceScore(ensureState(subject))
end

function RatingService.getFoodScore(player: Player?): number
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return 0
	end
	return foodScore(ensureState(subject))
end

function RatingService.getAtmosphereScore(player: Player?): number
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return 0
	end
	return atmosphereScore(subject)
end

function RatingService.getOverallScore(player: Player?): number
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return 0
	end
	return overallScore(subject, ensureState(subject))
end

function RatingService.getStars(player: Player?): number
	return starsFromScore(RatingService.getOverallScore(player))
end

function RatingService.init(deps: { remotes: { [string]: RemoteEvent }, atmosphereService: any? }?)
	if deps then
		ratingRemote = deps.remotes.RatingChanged
		AtmosphereService = deps.atmosphereService
		if AtmosphereService and AtmosphereService.Changed then
			AtmosphereService.Changed:Connect(function(player: Player)
				if player then
					broadcastIfChanged(player)
				end
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		statesByPlayer[player] = nil
	end)
end

return RatingService

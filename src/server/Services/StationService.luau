--!strict
--[[
	StationService.luau

	Manages every cooking station in the world — both the built-in starter
	shawarma counter and any stations placed by the player via build mode.

	Each station owns:
	  • A `ProximityPrompt` parented to its model so the host player can
	    cook by hand.
	  • Its own `Idle → Prepping → Ready → Idle` state machine.
	  • A reference to the order it's currently working on (if any).

	StaffService drives stations programmatically via the public
	`startPrepOnStation` / `serveOnStation` entry points, bypassing prompts
	but reusing the same FSM transitions so behaviour stays identical.

	Trust model: prompts are server-created, so `Triggered` already runs
	server-side with a verified `Player`. No client-driven RemoteEvent
	is involved in cooking.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local DishCatalog = require(Shared:WaitForChild("DishCatalog"))
local Types = require(Shared:WaitForChild("Types"))

type StationType = Types.StationType
type DishCategory = Types.DishCategory

local StationService = {}

-- ---- module state -------------------------------------------------------

local OrderService: any
local EconomyService: any
local RatingService: any
local UpgradeService: any
local AtmosphereService: any
local stationStateRemote: RemoteEvent

-- uid → Station record
local stations: { [string]: any } = {}

-- A built-in station gets a stable UID so it survives restarts.
local STARTER_STATION_UID = "starter_shawarma"

-- ---- helpers ------------------------------------------------------------

local function categoryFor(stationType: StationType): DishCategory
	if stationType == "shawarma" then
		return "wrap"
	elseif stationType == "grill" then
		return "plate"
	elseif stationType == "side" then
		return "side"
	elseif stationType == "drink" then
		return "drink"
	elseif stationType == "dessert" then
		return "dessert"
	end
	error("Unknown stationType " .. tostring(stationType))
end

local function broadcast(station: any)
	if not stationStateRemote then
		return
	end
	stationStateRemote:FireAllClients({
		uid = station.uid,
		stationType = station.stationType,
		state = station.state,
		activeOrderId = station.activeOrderId,
	})
end

local function refreshPrompt(station: any)
	local prompt: ProximityPrompt = station.prompt
	if station.state == "Prepping" then
		prompt.Enabled = false
		prompt.ActionText = "Cooking..."
	elseif station.state == "Ready" then
		prompt.Enabled = true
		prompt.ActionText = "Serve"
	else
		local nextOrder = OrderService.peekPendingForCategory(categoryFor(station.stationType))
		if nextOrder then
			local dish = DishCatalog.get(nextOrder.dishId)
			prompt.Enabled = true
			prompt.ActionText = "Prep " .. dish.displayName
		else
			prompt.Enabled = false
			prompt.ActionText = "Idle"
		end
	end
end

local function setState(station: any, newState: string)
	station.state = newState
	refreshPrompt(station)
	broadcast(station)
end

local function speedMultiplier(agentEffects: { [string]: number }?): number
	local mult = Constants.Cooking.StationSpeedMultiplier
	if UpgradeService then
		mult += UpgradeService.getEffectValue("station_speed_multiplier") or 0
	end
	if agentEffects and agentEffects.speed then
		mult *= agentEffects.speed
	end
	if mult < 0.1 then
		mult = 0.1
	end
	return mult
end

local function payOut(player: Player, dish: any, order: any, agentEffects: { [string]: number }?)
	local elapsed = order.servedAt - order.createdAt
	local jitter = (math.random() * 2 - 1) * Constants.Tips.Jitter
	local tipRatio = Constants.Tips.BaseRatio + jitter
	if elapsed <= Constants.Tips.FastServiceThreshold then
		tipRatio += Constants.Tips.FastServiceBonus
	end
	if agentEffects then
		tipRatio += agentEffects.tipBonus or 0
		tipRatio += agentEffects.fastServiceBonus or 0
	end
	if UpgradeService then
		tipRatio += UpgradeService.getEffectValue("tip_ratio_bonus") or 0
	end
	if AtmosphereService then
		tipRatio += AtmosphereService.getScore() * Constants.Tips.AtmosphereTipMultiplier
	end
	local tip = math.max(0, math.floor(dish.basePrice * tipRatio + 0.5))
	local total = dish.basePrice + tip
	EconomyService.addCash(player, total, "Sold " .. dish.displayName)
	EconomyService.recordCustomerServed(player)
	if elapsed <= Constants.Tips.FastServiceThreshold then
		RatingService.recordEvent("served_fast", { dishId = dish.id, elapsed = elapsed })
	else
		RatingService.recordEvent("served_slow", { dishId = dish.id, elapsed = elapsed })
	end

	-- Food quality axis: dish baseline + cook quality bonus, clamped 0..1.
	local quality = dish.baseQuality or 0.6
	if agentEffects and agentEffects.qualityBonus then
		quality += agentEffects.qualityBonus
	end
	quality = math.clamp(quality, 0, 1)
	if RatingService.recordFoodEvent then
		RatingService.recordFoodEvent(quality, dish.id)
	end
end

local function startPrep(station: any, agent: Player?, agentEffects: { [string]: number }?): boolean
	if station.state ~= "Idle" then
		return false
	end
	local order = OrderService.peekPendingForCategory(categoryFor(station.stationType))
	if not order then
		return false
	end
	if not OrderService.startPrep(order.id) then
		return false
	end
	station.activeOrderId = order.id
	station.activeChef = agent
	station.activeAgentEffects = agentEffects
	setState(station, "Prepping")

	local dish = DishCatalog.get(order.dishId)
	local prepDuration = dish.prepSeconds / speedMultiplier(agentEffects)
	task.delay(prepDuration, function()
		if station.activeOrderId ~= order.id then
			return
		end
		if not OrderService.markReady(order.id) then
			station.activeOrderId = nil
			station.activeChef = nil
			station.activeAgentEffects = nil
			setState(station, "Idle")
			return
		end
		setState(station, "Ready")
		-- Auto-serve when a non-player agent (staff cook) prepped this.
		if not agent then
			task.defer(function()
				StationService.serveOnStation(station, nil, agentEffects)
			end)
		end
	end)
	return true
end

local function serve(station: any, recipientHint: Player?, agentEffects: { [string]: number }?): boolean
	if station.state ~= "Ready" then
		return false
	end
	if station.activeOrderId == nil then
		setState(station, "Idle")
		return false
	end
	local order = OrderService.findById(station.activeOrderId)
	if not order then
		station.activeOrderId = nil
		station.activeChef = nil
		station.activeAgentEffects = nil
		setState(station, "Idle")
		return false
	end
	local dish = DishCatalog.get(order.dishId)
	OrderService.complete(order.id)
	local recipient = recipientHint or station.activeChef or Players:GetPlayers()[1]
	if recipient then
		local effects = agentEffects or station.activeAgentEffects
		payOut(recipient, dish, order, effects)
	end
	station.activeOrderId = nil
	station.activeChef = nil
	station.activeAgentEffects = nil
	setState(station, "Idle")
	return true
end

local function onPromptTriggered(station: any, triggeringPlayer: Player)
	if station.state == "Idle" then
		startPrep(station, triggeringPlayer, nil)
	elseif station.state == "Ready" then
		serve(station, triggeringPlayer, nil)
	end
end

-- ---- public API for staff -----------------------------------------------

function StationService.getAllStations(): { any }
	local out = {}
	for _, s in pairs(stations) do
		table.insert(out, s)
	end
	return out
end

function StationService.getStationsByType(stationType: StationType): { any }
	local out = {}
	for _, s in pairs(stations) do
		if s.stationType == stationType then
			table.insert(out, s)
		end
	end
	return out
end

function StationService.startPrepOnStation(station: any, agent: Player?, agentEffects: { [string]: number }?): boolean
	return startPrep(station, agent, agentEffects)
end

function StationService.serveOnStation(station: any, recipient: Player?, agentEffects: { [string]: number }?): boolean
	return serve(station, recipient, agentEffects)
end

function StationService.getCategoriesAvailable(): { [DishCategory]: boolean }
	local out: { [DishCategory]: boolean } = {}
	for _, station in pairs(stations) do
		out[categoryFor(station.stationType)] = true
	end
	return out
end

function StationService.hasStationOfType(stationType: StationType): boolean
	for _, station in pairs(stations) do
		if station.stationType == stationType then
			return true
		end
	end
	return false
end

-- ---- registration -------------------------------------------------------

function StationService.registerStation(spec: { model: Model, stationType: StationType, uid: string })
	if stations[spec.uid] then
		return
	end
	local model = spec.model
	local primary = model.PrimaryPart
	if not primary then
		warn("[StationService] model has no PrimaryPart: " .. model.Name)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShawermaStationPrompt"
	prompt.ActionText = "Idle"
	prompt.ObjectText = model.Name
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Enabled = false
	prompt.Parent = primary

	local station = {
		uid = spec.uid,
		model = model,
		stationType = spec.stationType,
		prompt = prompt,
		state = "Idle",
		activeOrderId = nil :: number?,
		activeChef = nil :: Player?,
		activeAgentEffects = nil :: { [string]: number }?,
	}
	stations[spec.uid] = station

	prompt.Triggered:Connect(function(player)
		onPromptTriggered(station, player)
	end)

	refreshPrompt(station)
	broadcast(station)
end

function StationService.unregisterStation(uid: string)
	local station = stations[uid]
	if not station then
		return
	end
	if station.activeOrderId then
		OrderService.cancel(station.activeOrderId)
	end
	if station.prompt then
		station.prompt:Destroy()
	end
	stations[uid] = nil
end

-- ---- init ---------------------------------------------------------------

function StationService.init(deps: {
	starterStation: BasePart,
	remotes: { [string]: RemoteEvent },
	orderService: any,
	economyService: any,
	ratingService: any,
	upgradeService: any?,
	atmosphereService: any?,
})
	OrderService = deps.orderService
	EconomyService = deps.economyService
	RatingService = deps.ratingService
	UpgradeService = deps.upgradeService
	AtmosphereService = deps.atmosphereService
	stationStateRemote = deps.remotes.StationStateChanged

	local originalParent = deps.starterStation.Parent
	local model = Instance.new("Model")
	model.Name = "starter_shawarma"
	model.Parent = originalParent or workspace
	deps.starterStation.Parent = model
	model.PrimaryPart = deps.starterStation

	StationService.registerStation({
		model = model,
		stationType = "shawarma",
		uid = STARTER_STATION_UID,
	})

	OrderService.OrderEnqueued:Connect(function()
		for _, station in pairs(stations) do
			if station.state == "Idle" then
				refreshPrompt(station)
				broadcast(station)
			end
		end
	end)
	OrderService.OrderCancelled:Connect(function(order)
		for _, station in pairs(stations) do
			if station.activeOrderId == order.id then
				station.activeOrderId = nil
				station.activeChef = nil
				station.activeAgentEffects = nil
				setState(station, "Idle")
			end
		end
	end)
end

return StationService

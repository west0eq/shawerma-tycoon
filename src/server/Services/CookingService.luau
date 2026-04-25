--!strict
--[[
	CookingService.luau

	Owns the cooking station's ProximityPrompt and the prep state machine.

	Trust model: the prompt itself is server-created, so `PromptTriggered`
	already runs server-side with a verified `Player`. We never accept a
	client-driven RemoteEvent for cooking actions.

	State machine:
		Idle  → (player triggers, order pending)        → Prepping
		Prepping → (timer elapses, dish prepSeconds)    → Ready
		Ready → (player triggers)                       → Idle (order complete, paid)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local DishCatalog = require(Shared:WaitForChild("DishCatalog"))
local Types = require(Shared:WaitForChild("Types"))

type StationState = Types.StationState
type Order = Types.Order

local CookingService = {}

local station: BasePart
local prompt: ProximityPrompt
local stateChangedRemote: RemoteEvent

local OrderService: any
local EconomyService: any

local state: StationState = "Idle"
local activeOrderId: number? = nil
local activeChef: Player? = nil

-- ---------- prompt label management ----------------------------------------

local function setPromptLabel()
	if state == "Prepping" then
		prompt.Enabled = false
		prompt.ActionText = "Cooking..."
		prompt.ObjectText = "Shawarma Station"
	elseif state == "Ready" then
		prompt.Enabled = true
		prompt.ActionText = "Serve"
		prompt.ObjectText = "Shawarma Ready"
	else
		local nextOrder = OrderService.peekNext("Pending")
		if nextOrder then
			local dish = DishCatalog.get(nextOrder.dishId)
			prompt.Enabled = true
			prompt.ActionText = "Prep " .. dish.displayName
			prompt.ObjectText = "Shawarma Station"
		else
			prompt.Enabled = false
			prompt.ActionText = "Idle"
			prompt.ObjectText = "Shawarma Station"
		end
	end
end

local function broadcastState()
	if not stateChangedRemote then
		return
	end
	stateChangedRemote:FireAllClients({
		state = state,
		activeOrderId = activeOrderId,
	})
end

local function setState(newState: StationState)
	state = newState
	setPromptLabel()
	broadcastState()
end

-- ---------- payment --------------------------------------------------------

local function payOut(player: Player, dish: any)
	local jitter = (math.random() * 2 - 1) * Constants.Tips.Jitter
	local tipRatio = Constants.Tips.BaseRatio + jitter
	local tip = math.max(0, math.floor(dish.basePrice * tipRatio + 0.5))
	local total = dish.basePrice + tip
	EconomyService.addCash(player, total, "Sold " .. dish.displayName)
	EconomyService.recordCustomerServed(player)
end

-- ---------- prompt handler -------------------------------------------------

local function onPromptTriggered(triggeringPlayer: Player)
	if state == "Idle" then
		local order = OrderService.peekNext("Pending")
		if not order then
			return
		end
		if not OrderService.startPrep(order.id) then
			return
		end
		activeOrderId = order.id
		activeChef = triggeringPlayer
		setState("Prepping")

		local dish = DishCatalog.get(order.dishId)
		local prepDuration = dish.prepSeconds * Constants.Cooking.StationSpeedMultiplier

		task.delay(prepDuration, function()
			-- Validate the order didn't get cancelled while we waited.
			if activeOrderId ~= order.id then
				return
			end
			if not OrderService.markReady(order.id) then
				-- Order disappeared; bail out cleanly.
				activeOrderId = nil
				activeChef = nil
				setState("Idle")
				return
			end
			setState("Ready")
		end)
	elseif state == "Ready" then
		if activeOrderId == nil then
			setState("Idle")
			return
		end
		local order = OrderService.findById(activeOrderId)
		if not order then
			activeOrderId = nil
			activeChef = nil
			setState("Idle")
			return
		end
		local dish = DishCatalog.get(order.dishId)
		OrderService.complete(order.id)
		-- Pay the player who actually pressed Serve, fall back to whoever
		-- started the prep, fall back to anyone in the server (single-player
		-- friendly default).
		local recipient = triggeringPlayer or activeChef or Players:GetPlayers()[1]
		if recipient then
			payOut(recipient, dish)
		end
		activeOrderId = nil
		activeChef = nil
		setState("Idle")
	end
end

-- ---------- public ---------------------------------------------------------

function CookingService.init(deps: {
	station: BasePart,
	remotes: { [string]: RemoteEvent },
	orderService: any,
	economyService: any,
})
	station = deps.station
	stateChangedRemote = deps.remotes.StationStateChanged
	OrderService = deps.orderService
	EconomyService = deps.economyService

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShawarmaPrompt"
	prompt.ActionText = "Idle"
	prompt.ObjectText = "Shawarma Station"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Enabled = false
	prompt.Parent = station

	prompt.Triggered:Connect(onPromptTriggered)

	-- React to queue / order state changes so the prompt label stays fresh.
	OrderService.OrderEnqueued:Connect(function()
		if state == "Idle" then
			setPromptLabel()
			broadcastState()
		end
	end)
	OrderService.OrderCancelled:Connect(function(order: Order)
		if activeOrderId == order.id then
			activeOrderId = nil
			activeChef = nil
			setState("Idle")
		end
	end)

	setPromptLabel()
end

return CookingService

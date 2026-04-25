--!strict
--[[
	CustomerService.luau

	Per-plot customer lifecycle. Each plot runs its own spawn loop, FIFO
	queue, seat pool, and order routing. A plot only spawns customers
	while it has an owner; ownership changes (PlotAssigned / PlotReleased)
	start or stop that plot's loop.

	Customer FSM: Spawning → WalkingToCounter → Ordering → Waiting →
	WalkingToSeat → Eating → Leaving → (despawn).

	Phase 5 changes:
	  • Per-plot state (queue slots, customers, scheduler) instead of a
	    single global pipeline.
	  • Orders carry `plotIndex`; cooking is scoped via StationService.
	  • Customers only order dishes for which the *owner* has unlocked the
	    menu, not the global host player.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local DishCatalog = require(Shared:WaitForChild("DishCatalog"))
local Types = require(Shared:WaitForChild("Types"))

local World = script.Parent.Parent:WaitForChild("World")
local CharacterRig = require(World:WaitForChild("CharacterRig"))

type CustomerState = Types.CustomerState
type SeatRef = { seat: Seat, model: Model }
type Dish = Types.Dish

local CustomerService = {}

-- ---- module state -------------------------------------------------------

local OrderService: any
local EconomyService: any
local StationService: any
local RatingService: any
local DataService: any
local UpgradeService: any
local AtmosphereService: any
local StaffService: any
local PlotService: any
local notify: RemoteEvent

local customersFolder: Folder
local nextCustomerId = 1
local customersById: { [number]: any } = {}
local rng = Random.new()

type PlotState = {
	plot: any,
	queueSlots: { any? },
	seatOccupancy: { [Seat]: boolean },
	running: boolean,
}

local plotStates: { [number]: PlotState } = {}

-- Customer name pool — picked at random for the floating nameplate.
local CUSTOMER_NAMES = {
	"Liam", "Noah", "Sofia", "Mia", "Elena", "Yusuf", "Leyla", "Omar",
	"Aria", "Ezra", "Maya", "Jonas", "Ines", "Idris", "Zara", "Sami",
}

local function ensurePlotState(plot: any): PlotState
	local state = plotStates[plot.index]
	if state then
		return state
	end
	state = {
		plot = plot,
		queueSlots = {},
		seatOccupancy = {},
		running = false,
	}
	plotStates[plot.index] = state
	return state
end

local function currentMaxConcurrent(owner: Player?): number
	local base = Constants.Customer.MaxConcurrent
	if UpgradeService then
		base += UpgradeService.getEffectValue("concurrent_customers_bonus", owner) or 0
	end
	return math.max(1, math.floor(base))
end

-- ---- model ------------------------------------------------------------

local function buildBody(): Model
	local palette = CharacterRig.CUSTOMER_PALETTES[rng:NextInteger(1, #CharacterRig.CUSTOMER_PALETTES)]
	local name = CUSTOMER_NAMES[rng:NextInteger(1, #CUSTOMER_NAMES)]
	return CharacterRig.build({
		name = "Customer",
		skinTone = palette.skinTone,
		shirtColor = palette.shirtColor,
		pantsColor = palette.pantsColor,
		hairColor = palette.hairColor,
		nameplate = name,
	})
end

-- ---- movement ---------------------------------------------------------

local function tweenTo(part: BasePart, targetPos: Vector3): Tween
	local startPos = part.Position
	local delta = targetPos - startPos
	local distance = delta.Magnitude
	local duration = distance / Constants.Customer.WalkSpeed
	if duration < 0.1 then
		duration = 0.1
	end
	local lookCFrame: CFrame
	if distance < 0.05 then
		lookCFrame = CFrame.new(targetPos) * (part.CFrame - part.CFrame.Position)
	else
		lookCFrame = CFrame.lookAt(targetPos, targetPos + Vector3.new(delta.X, 0, delta.Z).Unit)
	end
	local tween = TweenService:Create(
		part,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ CFrame = lookCFrame }
	)
	tween:Play()
	return tween
end

local function walkTo(part: BasePart, targetPos: Vector3)
	local tween = tweenTo(part, targetPos)
	tween.Completed:Wait()
end

-- Y position the torso CFrame should sit at so the rig's feet land on
-- the floor surface. Floor.Position is the centre of a 1-stud-thick slab,
-- so the floor surface is `floor.Y + 0.5`; CharacterRig torsos sit 2.8
-- studs above feet.
local function torsoY(state: PlotState): number
	return state.plot.floor.Position.Y + state.plot.floor.Size.Y / 2 + 2.8
end

local function queueSlotPosition(state: PlotState, index: number): Vector3
	local p = state.plot.counterSpot.Position
	return Vector3.new(p.X, torsoY(state), p.Z + (index - 1) * 4)
end

local function findFreeSeat(state: PlotState): SeatRef?
	for _, ref in ipairs(state.plot.seats) do
		if not state.seatOccupancy[ref.seat] then
			return ref
		end
	end
	return nil
end

-- ---- queue ------------------------------------------------------------

local function placeInQueue(state: PlotState, customer: any, owner: Player?): number?
	local cap = currentMaxConcurrent(owner)
	for index = 1, cap do
		if state.queueSlots[index] == nil then
			state.queueSlots[index] = customer
			customer.queueIndex = index
			return index
		end
	end
	return nil
end

local function leaveQueue(state: PlotState, customer: any, owner: Player?)
	if customer.queueIndex == nil then
		return
	end
	state.queueSlots[customer.queueIndex] = nil
	customer.queueIndex = nil
	local cap = currentMaxConcurrent(owner)
	for i = 1, cap - 1 do
		if state.queueSlots[i] == nil and state.queueSlots[i + 1] ~= nil then
			local moving = state.queueSlots[i + 1]
			state.queueSlots[i] = moving
			state.queueSlots[i + 1] = nil
			moving.queueIndex = i
			task.spawn(function()
				if moving.body and moving.body.Parent then
					tweenTo(moving.body, queueSlotPosition(state, i))
				end
			end)
		end
	end
end

-- ---- order routing ----------------------------------------------------

local function getOrderableDishes(plot: any, owner: Player?): { Dish }
	local availableCategories = StationService.getCategoriesAvailable(plot.index)
	local ownerSave = owner and DataService.get(owner) or nil
	local out: { Dish } = {}
	for _, dish in ipairs(DishCatalog.all()) do
		if availableCategories[dish.category] then
			if ownerSave then
				if DishCatalog.isUnlocked(dish, ownerSave, ownerSave.menuUnlocks) then
					table.insert(out, dish)
				end
			else
				if dish.unlockTier == 0 then
					table.insert(out, dish)
				end
			end
		end
	end
	return out
end

-- ---- state machine ----------------------------------------------------

local function setState(customer: any, state: CustomerState)
	customer.state = state
end

local function despawn(customer: any)
	customersById[customer.id] = nil
	if customer.body and customer.body.Parent then
		(customer.body.Parent :: Instance):Destroy()
	end
end

local function runCustomer(customer: any)
	local state = plotStates[customer.plotIndex]
	if not state then
		despawn(customer)
		return
	end
	local owner = PlotService and PlotService.getOwnerByIndex(customer.plotIndex) or nil

	setState(customer, "WalkingToCounter")
	local slot = placeInQueue(state, customer, owner)
	if not slot then
		despawn(customer)
		return
	end

	walkTo(customer.body, queueSlotPosition(state, slot))

	while customer.queueIndex ~= 1 do
		task.wait(0.25)
		if not customer.body.Parent then
			return
		end
	end

	setState(customer, "Ordering")
	local pickList = getOrderableDishes(state.plot, owner)
	if #pickList == 0 then
		notify:FireAllClients("A customer left: nothing on the menu")
		leaveQueue(state, customer, owner)
		setState(customer, "Leaving")
		walkTo(customer.body, Vector3.new(state.plot.exitPad.Position.X, torsoY(state), state.plot.exitPad.Position.Z))
		despawn(customer)
		return
	end
	local choice = pickList[rng:NextInteger(1, #pickList)]
	customer.dishId = choice.id
	local order = OrderService.enqueue(customer.id, choice.id, customer.plotIndex)
	customer.orderId = order.id
	setState(customer, "Waiting")

	local patience = Constants.Customer.PatienceSeconds
	if UpgradeService then
		patience += UpgradeService.getEffectValue("patience_bonus_seconds", owner) or 0
	end

	local timeoutEvent = Instance.new("BindableEvent")
	local served = false
	task.delay(patience, function()
		if not served then
			timeoutEvent:Fire()
		end
	end)
	local readyConn
	readyConn = customer.readyEvent.Event:Connect(function()
		served = true
		readyConn:Disconnect()
		timeoutEvent:Fire()
	end)
	timeoutEvent.Event:Wait()

	if not served then
		OrderService.abandon(order.id)
		RatingService.recordEvent(owner, "customer_left_angry", { dishId = choice.id })
		if owner then
			notify:FireClient(owner, "A customer left angry — too long a wait!")
		end
		leaveQueue(state, customer, owner)
		setState(customer, "Leaving")
		walkTo(customer.body, Vector3.new(state.plot.exitPad.Position.X, torsoY(state), state.plot.exitPad.Position.Z))
		despawn(customer)
		return
	end

	if owner then
		notify:FireClient(owner, string.format("[Order #%d] Served", customer.id))
	end
	RatingService.recordEvent(owner, "served", { dishId = choice.id })
	leaveQueue(state, customer, owner)

	-- Most customers want to dine in. The rest take their order to-go and
	-- leave directly — that variety stops every plot from looking like a
	-- waiting room.
	local wantsDineIn = rng:NextNumber() < Constants.Customer.DineInProbability
	if wantsDineIn then
		setState(customer, "WalkingToSeat")
		-- Wait up to SeatWaitTimeoutSeconds for a free seat. Without this
		-- the early-game (4 seats, 2-customer cap) frequently shoves
		-- customers straight back out the door.
		local seatRef = findFreeSeat(state)
		local waited = 0
		while seatRef == nil and waited < Constants.Customer.SeatWaitTimeoutSeconds do
			task.wait(0.5)
			waited += 0.5
			if not customer.body.Parent then
				return
			end
			seatRef = findFreeSeat(state)
		end
		if seatRef then
			state.seatOccupancy[seatRef.seat] = true
			walkTo(customer.body, Vector3.new(seatRef.seat.Position.X, seatRef.seat.Position.Y + seatRef.seat.Size.Y / 2 + 2.8, seatRef.seat.Position.Z))
			setState(customer, "Eating")
			task.wait(Constants.Customer.EatDurationSeconds)
			local resetSpeed = 1.0
			if StaffService and owner then
				local effects = StaffService.getAggregateEffects("cleaner", owner)
				if effects.tableResetSpeed then
					resetSpeed = effects.tableResetSpeed
				end
			end
			local cooldown = math.max(0.2, 1.5 / resetSpeed)
			task.wait(cooldown)
			state.seatOccupancy[seatRef.seat] = false
		end
	end

	setState(customer, "Leaving")
	walkTo(customer.body, Vector3.new(state.plot.exitPad.Position.X, torsoY(state), state.plot.exitPad.Position.Z))
	despawn(customer)
end

-- ---- spawn ------------------------------------------------------------

local function spawnCustomer(state: PlotState)
	if not customersFolder.Parent then
		return
	end
	local owner = PlotService and PlotService.getOwnerByIndex(state.plot.index) or nil
	if owner == nil then
		-- Don't spawn for unclaimed plots.
		return
	end
	local cap = currentMaxConcurrent(owner)
	local hasRoom = false
	for i = 1, cap do
		if state.queueSlots[i] == nil then
			hasRoom = true
			break
		end
	end
	if not hasRoom then
		return
	end
	if #getOrderableDishes(state.plot, owner) == 0 then
		return
	end

	local id = nextCustomerId
	nextCustomerId += 1

	local model = buildBody()
	model.Name = string.format("Customer_%d", id)
	local spawnPos = state.plot.spawnPad.Position
	model:PivotTo(CFrame.new(spawnPos.X, torsoY(state), spawnPos.Z))
	model.Parent = customersFolder

	local customer = {
		id = id,
		plotIndex = state.plot.index,
		body = model.PrimaryPart,
		model = model,
		state = "Spawning" :: CustomerState,
		queueIndex = nil :: number?,
		dishId = nil :: string?,
		orderId = nil :: number?,
		readyEvent = Instance.new("BindableEvent"),
	}
	customersById[id] = customer

	task.spawn(function()
		local ok, err = pcall(runCustomer, customer)
		if not ok then
			warn("[CustomerService] runCustomer error: " .. tostring(err))
			despawn(customer)
		end
	end)
end

local function startSpawnLoop(state: PlotState)
	if state.running then
		return
	end
	state.running = true
	task.spawn(function()
		task.wait(2)
		while state.running do
			spawnCustomer(state)
			local owner = PlotService and PlotService.getOwnerByIndex(state.plot.index) or nil
			local atm = 0
			if AtmosphereService then
				atm = AtmosphereService.getScore(owner) or 0
			end
			local lo = Constants.Customer.SpawnIntervalMinSeconds
			local hi = Constants.Customer.SpawnIntervalMaxSeconds
			local base = Constants.Customer.SpawnIntervalSeconds
			local interval = base + (1 - atm) * 0.5 * (hi - base) - atm * (base - lo)
			interval = math.clamp(interval, lo, hi)
			task.wait(interval)
		end
	end)
end

local function stopSpawnLoop(state: PlotState)
	state.running = false
end

-- ---- public ----------------------------------------------------------

function CustomerService.init(deps: {
	world: any,
	remotes: { [string]: RemoteEvent },
	orderService: any,
	economyService: any,
	stationService: any,
	ratingService: any,
	dataService: any,
	upgradeService: any?,
	atmosphereService: any?,
	staffService: any?,
	plotService: any?,
})
	OrderService = deps.orderService
	EconomyService = deps.economyService
	StationService = deps.stationService
	RatingService = deps.ratingService
	DataService = deps.dataService
	UpgradeService = deps.upgradeService
	AtmosphereService = deps.atmosphereService
	StaffService = deps.staffService
	PlotService = deps.plotService
	notify = deps.remotes.Notify

	customersFolder = Workspace:FindFirstChild("ShawermaTycoonCustomers") :: Folder
	if not customersFolder then
		customersFolder = Instance.new("Folder")
		customersFolder.Name = "ShawermaTycoonCustomers"
		customersFolder.Parent = Workspace
	end

	for _, plot in ipairs(deps.world.plots) do
		ensurePlotState(plot)
	end

	OrderService.OrderCompleted:Connect(function(order)
		local customer = customersById[order.customerId]
		if customer and customer.readyEvent then
			customer.readyEvent:Fire()
		end
	end)
	OrderService.OrderCancelled:Connect(function(order)
		local customer = customersById[order.customerId]
		if customer and customer.readyEvent then
			customer.readyEvent:Fire()
		end
	end)

	if PlotService then
		-- Spawn loops follow plot ownership so empty plots stay quiet.
		PlotService.PlotAssigned:Connect(function(_player: Player, plot: any)
			local state = ensurePlotState(plot)
			startSpawnLoop(state)
		end)
		PlotService.PlotReleased:Connect(function(_player: Player, plot: any)
			local state = plotStates[plot.index]
			if state then
				stopSpawnLoop(state)
			end
		end)
		-- Bring loops alive for any pre-existing assignments.
		for _, plot in ipairs(PlotService.getOwnedPlots()) do
			startSpawnLoop(ensurePlotState(plot))
		end
	else
		-- Fallback: no PlotService → run all loops unconditionally.
		for _, plot in ipairs(deps.world.plots) do
			startSpawnLoop(ensurePlotState(plot))
		end
	end
end

return CustomerService

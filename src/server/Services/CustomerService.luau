--!strict
--[[
	CustomerService.luau

	Customer lifecycle:
		Spawning → WalkingToCounter → Ordering → Waiting → WalkingToSeat
		         → Eating → Leaving → (despawn)

	Phase 2 changes:
	  • Customers pick orders only from the dishes whose station is currently
	    placed AND the host player has unlocked. New stations placed via
	    build mode become orderable on the next spawn cycle.
	  • Patience: while in `Waiting`, if the order hasn't been served within
	    `PatienceSeconds`, the customer abandons the order, the
	    `RatingService` records `customer_left_angry`, and they leave.
	  • A `served_in_time` / `served_late` event is recorded when the order
	    completes successfully so Phase 3 can compute service score.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local DishCatalog = require(Shared:WaitForChild("DishCatalog"))
local Types = require(Shared:WaitForChild("Types"))

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
local notify: RemoteEvent

local customersFolder: Folder
local spawnPad: BasePart
local exitPad: BasePart
local counterSpot: BasePart
local seats: { SeatRef }
local seatOccupancy: { [Seat]: boolean } = {}

local nextCustomerId = 1
local customersById: { [number]: any } = {}

-- The concurrent cap is recomputed each spawn pass; the queueSlots array is
-- grown lazily so the customer-flow upgrade can extend capacity at runtime.
local queueSlots: { any? } = {}
for i = 1, Constants.Customer.MaxConcurrent do
	queueSlots[i] = nil
end

local function currentMaxConcurrent(): number
	local base = Constants.Customer.MaxConcurrent
	if UpgradeService then
		base += UpgradeService.getEffectValue("concurrent_customers_bonus") or 0
	end
	return math.max(1, math.floor(base))
end

local function ensureQueueCapacity(target: number)
	while #queueSlots < target do
		table.insert(queueSlots, nil)
	end
end

local rng = Random.new()

local CUSTOMER_COLORS = {
	Color3.fromRGB(220, 80, 80),
	Color3.fromRGB(80, 140, 220),
	Color3.fromRGB(60, 180, 110),
	Color3.fromRGB(220, 180, 60),
	Color3.fromRGB(170, 90, 200),
	Color3.fromRGB(240, 140, 70),
}

local SKIN_TONES = {
	Color3.fromRGB(243, 207, 169),
	Color3.fromRGB(225, 175, 140),
	Color3.fromRGB(190, 130, 90),
	Color3.fromRGB(135, 90, 60),
	Color3.fromRGB(90, 60, 40),
}

-- ---- model ------------------------------------------------------------

local function buildBody(): Model
	local model = Instance.new("Model")
	model.Name = "Customer"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 4, 1)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Material = Enum.Material.Fabric
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Color = CUSTOMER_COLORS[rng:NextInteger(1, #CUSTOMER_COLORS)]
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Anchored = false
	head.CanCollide = false
	head.CanQuery = false
	head.CanTouch = false
	head.Material = Enum.Material.SmoothPlastic
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	head.Color = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
	head.CFrame = body.CFrame * CFrame.new(0, body.Size.Y / 2 + head.Size.Y / 2, 0)
	head.Parent = model

	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = head
	weld.C0 = CFrame.new(0, body.Size.Y / 2 + head.Size.Y / 2, 0)
	weld.Parent = body

	model.PrimaryPart = body
	return model
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

local function queueSlotPosition(index: number): Vector3
	return counterSpot.Position + Vector3.new(0, 0, (index - 1) * 4)
end

local function findFreeSeat(): SeatRef?
	for _, ref in ipairs(seats) do
		if not seatOccupancy[ref.seat] then
			return ref
		end
	end
	return nil
end

-- ---- queue ------------------------------------------------------------

local function placeInQueue(customer: any): number?
	local cap = currentMaxConcurrent()
	ensureQueueCapacity(cap)
	for index = 1, cap do
		if queueSlots[index] == nil then
			queueSlots[index] = customer
			customer.queueIndex = index
			return index
		end
	end
	return nil
end

local function leaveQueue(customer: any)
	if customer.queueIndex == nil then
		return
	end
	queueSlots[customer.queueIndex] = nil
	customer.queueIndex = nil
	local cap = currentMaxConcurrent()
	ensureQueueCapacity(cap)
	for i = 1, cap - 1 do
		if queueSlots[i] == nil and queueSlots[i + 1] ~= nil then
			local moving = queueSlots[i + 1]
			queueSlots[i] = moving
			queueSlots[i + 1] = nil
			moving.queueIndex = i
			task.spawn(function()
				if moving.body and moving.body.Parent then
					tweenTo(moving.body, queueSlotPosition(i))
				end
			end)
		end
	end
end

-- ---- order routing ----------------------------------------------------

local function getHostSave(): { totalEarned: number, customersServed: number, menuUnlocks: { [string]: boolean }? }?
	local host = Players:GetPlayers()[1]
	if not host then
		return nil
	end
	return DataService.get(host)
end

local function getOrderableDishes(): { Dish }
	local availableCategories = StationService.getCategoriesAvailable()
	local hostSave = getHostSave()
	local out: { Dish } = {}
	for _, dish in ipairs(DishCatalog.all()) do
		if availableCategories[dish.category] then
			if hostSave then
				if DishCatalog.isUnlocked(dish, hostSave, hostSave.menuUnlocks) then
					table.insert(out, dish)
				end
			else
				-- No host yet: only the unconditional starter dishes.
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
	setState(customer, "WalkingToCounter")
	local slot = placeInQueue(customer)
	if not slot then
		despawn(customer)
		return
	end

	walkTo(customer.body, queueSlotPosition(slot))

	while customer.queueIndex ~= 1 do
		task.wait(0.25)
		if not customer.body.Parent then
			return
		end
	end

	-- Place an order from currently-orderable dishes.
	setState(customer, "Ordering")
	local pickList = getOrderableDishes()
	if #pickList == 0 then
		-- Nothing to order — bail out cleanly so the customer doesn't soft-lock.
		notify:FireAllClients("A customer left: nothing on the menu they can order")
		leaveQueue(customer)
		setState(customer, "Leaving")
		walkTo(customer.body, exitPad.Position)
		despawn(customer)
		return
	end
	local choice = pickList[rng:NextInteger(1, #pickList)]
	customer.dishId = choice.id
	local order = OrderService.enqueue(customer.id, choice.id)
	customer.orderId = order.id
	setState(customer, "Waiting")

	-- Patience extends with the comfortable-waiting-area upgrade.
	local patience = Constants.Customer.PatienceSeconds
	if UpgradeService then
		patience += UpgradeService.getEffectValue("patience_bonus_seconds") or 0
	end

	-- Race: order ready vs patience timeout.
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
		-- Customer ran out of patience.
		OrderService.abandon(order.id)
		RatingService.recordEvent("customer_left_angry", { dishId = choice.id })
		notify:FireAllClients("A customer left angry — too long a wait!")
		leaveQueue(customer)
		setState(customer, "Leaving")
		walkTo(customer.body, exitPad.Position)
		despawn(customer)
		return
	end

	notify:FireAllClients(string.format("[Order #%d] Served", customer.id))
	RatingService.recordEvent("served", { dishId = choice.id })
	leaveQueue(customer)

	setState(customer, "WalkingToSeat")
	local seatRef = findFreeSeat()
	if seatRef then
		seatOccupancy[seatRef.seat] = true
		walkTo(customer.body, seatRef.seat.Position + Vector3.new(0, 1.5, 0))
		setState(customer, "Eating")
		task.wait(Constants.Customer.EatDurationSeconds)
		-- Cleaner staff resets tables faster; emulate the reset by holding the
		-- seat for an extra cool-down before freeing it. Higher level → shorter.
		local resetSpeed = 1.0
		if StaffService then
			local effects = StaffService.getAggregateEffects("cleaner")
			if effects.tableResetSpeed then
				resetSpeed = effects.tableResetSpeed
			end
		end
		local cooldown = math.max(0.2, 1.5 / resetSpeed)
		task.wait(cooldown)
		seatOccupancy[seatRef.seat] = false
	end

	setState(customer, "Leaving")
	walkTo(customer.body, exitPad.Position)
	despawn(customer)
end

-- ---- spawn ------------------------------------------------------------

local function spawnCustomer()
	if not customersFolder.Parent then
		return
	end
	local cap = currentMaxConcurrent()
	ensureQueueCapacity(cap)
	local hasRoom = false
	for i = 1, cap do
		if queueSlots[i] == nil then
			hasRoom = true
			break
		end
	end
	if not hasRoom then
		return
	end
	-- Don't spawn if there's nothing on the menu yet (no stations registered).
	if #getOrderableDishes() == 0 then
		return
	end

	local id = nextCustomerId
	nextCustomerId += 1

	local model = buildBody()
	model.Name = string.format("Customer_%d", id)
	model:PivotTo(CFrame.new(spawnPad.Position + Vector3.new(0, 2, 0)))
	model.Parent = customersFolder

	local customer = {
		id = id,
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
})
	OrderService = deps.orderService
	EconomyService = deps.economyService
	StationService = deps.stationService
	RatingService = deps.ratingService
	DataService = deps.dataService
	UpgradeService = deps.upgradeService
	AtmosphereService = deps.atmosphereService
	StaffService = deps.staffService
	notify = deps.remotes.Notify

	spawnPad = deps.world.spawnPad
	exitPad = deps.world.exitPad
	counterSpot = deps.world.counterSpot
	seats = deps.world.seats

	customersFolder = Workspace:FindFirstChild("ShawermaTycoonCustomers") :: Folder
	if not customersFolder then
		customersFolder = Instance.new("Folder")
		customersFolder.Name = "ShawermaTycoonCustomers"
		customersFolder.Parent = Workspace
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

	task.spawn(function()
		task.wait(2)
		while true do
			spawnCustomer()
			-- Atmosphere modulates spawn cadence: a cosier place draws more
			-- foot traffic. Linear interpolation between min and max bounds.
			local atm = 0
			if AtmosphereService then
				atm = AtmosphereService.getScore() or 0
			end
			local lo = Constants.Customer.SpawnIntervalMinSeconds
			local hi = Constants.Customer.SpawnIntervalMaxSeconds
			local base = Constants.Customer.SpawnIntervalSeconds
			-- Atmosphere 0 → base..hi; atmosphere 1 → lo. Clamp to bounds.
			local interval = base + (1 - atm) * 0.5 * (hi - base) - atm * (base - lo)
			interval = math.clamp(interval, lo, hi)
			task.wait(interval)
		end
	end)
end

return CustomerService

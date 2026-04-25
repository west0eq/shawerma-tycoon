--!strict
--[[
	CustomerService.luau

	Customer lifecycle:
		Spawning → WalkingToCounter → Ordering → Waiting → WalkingToSeat
		         → Eating → Leaving → (despawn)

	Phase 1 design choices:
	  • Customers are *not* full Humanoid rigs. They are anchored two-part
	    "blockies" (body + welded head) tweened between waypoints. This
	    sidesteps every rig/pathfinding edge case Phase 1 would otherwise hit
	    and lets us replace the visual representation in Phase 4 without
	    touching the state machine.
	  • There is exactly one queue. The first slot is the counter; slots 2..N
	    are line-up positions stretching back toward the door. When the front
	    customer walks away, everyone behind shifts up.
	  • A customer claims a seat exclusively for the duration of `Eating`, then
	    releases it. If no seat is free they skip eating and leave (rare in
	    P1 because spawn rate is gated).
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local DishCatalog = require(Shared:WaitForChild("DishCatalog"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

type CustomerState = Types.CustomerState
type SeatRef = { seat: Seat, model: Model }

local CustomerService = {}

-- ---------- module state ---------------------------------------------------

local OrderService: any
local EconomyService: any
local notify: RemoteEvent

local customersFolder: Folder
local spawnPad: BasePart
local exitPad: BasePart
local counterSpot: BasePart
local seats: { SeatRef }
local seatOccupancy: { [Seat]: boolean } = {}

local nextCustomerId = 1
local customersById: { [number]: any } = {}

-- A fixed-size queue (counter slot + lineup). Index 1 is the counter.
local QUEUE_SLOTS = Constants.Customer.MaxConcurrent
local queueSlots: { any? } = {}
for i = 1, QUEUE_SLOTS do
	queueSlots[i] = nil
end

-- ---------- helpers --------------------------------------------------------

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

	-- Rigid weld so the head follows the (anchored) body without the head
	-- needing to be anchored itself.
	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = head
	weld.C0 = CFrame.new(0, body.Size.Y / 2 + head.Size.Y / 2, 0)
	weld.Parent = body

	model.PrimaryPart = body
	return model
end

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
	-- Slot 1 = counter, subsequent slots line up behind, away from the counter
	-- in +Z direction.
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

-- ---------- queue management ----------------------------------------------

local function placeInQueue(customer: any): number?
	for index = 1, QUEUE_SLOTS do
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

	-- Compact: shift everyone behind one slot forward and re-walk them.
	for i = 1, QUEUE_SLOTS - 1 do
		if queueSlots[i] == nil and queueSlots[i + 1] ~= nil then
			local moving = queueSlots[i + 1]
			queueSlots[i] = moving
			queueSlots[i + 1] = nil
			moving.queueIndex = i
			-- Trigger them to advance asynchronously so we don't block the
			-- caller's state machine.
			task.spawn(function()
				if moving.body and moving.body.Parent then
					tweenTo(moving.body, queueSlotPosition(i))
				end
			end)
		end
	end
end

-- ---------- per-customer FSM ----------------------------------------------

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
	-- Spawn → walk to queue.
	setState(customer, "WalkingToCounter")
	local slot = placeInQueue(customer)
	if not slot then
		-- Server full; bail.
		despawn(customer)
		return
	end

	walkTo(customer.body, queueSlotPosition(slot))

	-- Wait until we reach slot 1 (counter).
	while customer.queueIndex ~= 1 do
		task.wait(0.25)
		if not customer.body.Parent then
			return
		end
	end

	-- Place order.
	setState(customer, "Ordering")
	local pickList = DishCatalog.unlocked(0)
	local choice = pickList[rng:NextInteger(1, #pickList)]
	customer.dishId = choice.id
	OrderService.enqueue(customer.id, choice.id)
	setState(customer, "Waiting")

	-- Wait for our order to come back as Served.
	customer.readyEvent.Event:Wait()
	notify:FireAllClients(string.format("[Order #%d] Served", customer.id))

	-- Free the counter so the next person advances.
	leaveQueue(customer)

	-- Pick a seat to eat at.
	setState(customer, "WalkingToSeat")
	local seatRef = findFreeSeat()
	if seatRef then
		seatOccupancy[seatRef.seat] = true
		walkTo(customer.body, seatRef.seat.Position + Vector3.new(0, 1.5, 0))
		setState(customer, "Eating")
		task.wait(Constants.Customer.EatDurationSeconds)
		seatOccupancy[seatRef.seat] = false
	end

	-- Leave.
	setState(customer, "Leaving")
	walkTo(customer.body, exitPad.Position)
	despawn(customer)
end

-- ---------- spawn ----------------------------------------------------------

local function spawnCustomer()
	if not customersFolder.Parent then
		return
	end
	-- Don't spawn if all queue slots are full; back-pressure on the spawner.
	local hasRoom = false
	for i = 1, QUEUE_SLOTS do
		if queueSlots[i] == nil then
			hasRoom = true
			break
		end
	end
	if not hasRoom then
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

-- ---------- public ---------------------------------------------------------

function CustomerService.init(deps: {
	world: any,
	remotes: { [string]: RemoteEvent },
	orderService: any,
	economyService: any,
})
	OrderService = deps.orderService
	EconomyService = deps.economyService
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

	-- Wire the OrderCompleted signal back to whichever customer placed the
	-- order so the customer's coroutine can resume.
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

	-- Spawn loop.
	task.spawn(function()
		-- Stagger first spawn slightly so it doesn't collide with bootstrap.
		task.wait(2)
		while true do
			spawnCustomer()
			task.wait(Constants.Customer.SpawnIntervalSeconds)
		end
	end)
end

return CustomerService

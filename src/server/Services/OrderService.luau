--!strict
--[[
	OrderService.luau

	Tracks the current order queue (FIFO). Customers `enqueue` an order when
	they reach the counter; the cooking flow consumes orders by id; satisfied
	orders are `complete`d which fires the order-paid signal.

	The service is intentionally pure — it owns no Roblox instances. Visual
	side effects belong to CookingService and CustomerService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

type Order = Types.Order
type OrderState = Types.OrderState

local OrderService = {}

local nextId: number = 1
local queue: { Order } = {}

OrderService.OrderEnqueued = Signal.new()   -- (order)
OrderService.OrderStateChanged = Signal.new() -- (order, oldState, newState)
OrderService.OrderCompleted = Signal.new() -- (order)
OrderService.OrderCancelled = Signal.new() -- (order)

local stateChangedRemote: RemoteEvent

function OrderService.init(deps: { remotes: { [string]: RemoteEvent } })
	stateChangedRemote = deps.remotes.OrderStateChanged
end

local function broadcast()
	if not stateChangedRemote then
		return
	end
	-- Ship a compact, replication-friendly payload (no metatables, no funcs).
	local snapshot: { [number]: { id: number, dishId: string, state: string, customerId: number } } = {}
	for index, order in ipairs(queue) do
		snapshot[index] = {
			id = order.id,
			dishId = order.dishId,
			state = order.state,
			customerId = order.customerId,
		}
	end
	stateChangedRemote:FireAllClients(snapshot)
end

local function setState(order: Order, newState: OrderState)
	local old = order.state
	if old == newState then
		return
	end
	order.state = newState
	OrderService.OrderStateChanged:Fire(order, old, newState)
	broadcast()
end

function OrderService.enqueue(customerId: number, dishId: string): Order
	local order: Order = {
		id = nextId,
		dishId = dishId,
		customerId = customerId,
		state = "Pending",
		createdAt = os.clock(),
	}
	nextId += 1
	table.insert(queue, order)
	OrderService.OrderEnqueued:Fire(order)
	broadcast()
	return order
end

function OrderService.peekNext(state: OrderState?): Order?
	for _, order in ipairs(queue) do
		if state == nil or order.state == state then
			return order
		end
	end
	return nil
end

function OrderService.findById(id: number): Order?
	for _, order in ipairs(queue) do
		if order.id == id then
			return order
		end
	end
	return nil
end

function OrderService.startPrep(id: number): boolean
	local order = OrderService.findById(id)
	if not order or order.state ~= "Pending" then
		return false
	end
	setState(order, "Prepping")
	return true
end

function OrderService.markReady(id: number): boolean
	local order = OrderService.findById(id)
	if not order or order.state ~= "Prepping" then
		return false
	end
	setState(order, "Ready")
	return true
end

function OrderService.complete(id: number): Order?
	local order = OrderService.findById(id)
	if not order then
		return nil
	end
	setState(order, "Served")
	for index, candidate in ipairs(queue) do
		if candidate.id == id then
			table.remove(queue, index)
			break
		end
	end
	OrderService.OrderCompleted:Fire(order)
	broadcast()
	return order
end

function OrderService.cancel(id: number): Order?
	local order = OrderService.findById(id)
	if not order then
		return nil
	end
	setState(order, "Cancelled")
	for index, candidate in ipairs(queue) do
		if candidate.id == id then
			table.remove(queue, index)
			break
		end
	end
	OrderService.OrderCancelled:Fire(order)
	broadcast()
	return order
end

function OrderService.queueLength(): number
	return #queue
end

return OrderService

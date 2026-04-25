--!strict
--[[
	OrderService.luau

	Tracks the current order queue (FIFO). Customers `enqueue` an order when
	they reach the counter; cooking stations consume orders by id; satisfied
	orders are `complete`d which fires the order-completed signal.

	Phase 2: orders carry their dish category so multiple stations can each
	claim the orders they're equipped to cook. `peekPendingForCategory`
	returns the next pending order whose category matches a given filter.

	The service owns no Roblox instances on purpose — visual side effects
	belong to StationService and CustomerService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishCatalog = require(Shared:WaitForChild("DishCatalog"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

type Order = Types.Order
type OrderState = Types.OrderState
type DishCategory = Types.DishCategory

local OrderService = {}

local nextId: number = 1
local queue: { Order } = {}

OrderService.OrderEnqueued = Signal.new()
OrderService.OrderStateChanged = Signal.new()
OrderService.OrderCompleted = Signal.new()
OrderService.OrderCancelled = Signal.new()

local stateChangedRemote: RemoteEvent

function OrderService.init(deps: { remotes: { [string]: RemoteEvent } })
	stateChangedRemote = deps.remotes.OrderStateChanged
end

local function broadcast()
	if not stateChangedRemote then
		return
	end
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
	if order.state == newState then
		return
	end
	local old = order.state
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

function OrderService.findById(id: number): Order?
	for _, order in ipairs(queue) do
		if order.id == id then
			return order
		end
	end
	return nil
end

function OrderService.peekPendingForCategory(category: DishCategory?): Order?
	for _, order in ipairs(queue) do
		if order.state == "Pending" then
			if category == nil then
				return order
			end
			local dish = DishCatalog.get(order.dishId)
			if dish.category == category then
				return order
			end
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
	order.servedAt = os.clock()
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

function OrderService.abandon(id: number): Order?
	-- Customer ran out of patience and walked away; equivalent to cancel but
	-- recorded as a separate event for satisfaction scoring.
	local order = OrderService.findById(id)
	if not order then
		return nil
	end
	setState(order, "Abandoned")
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

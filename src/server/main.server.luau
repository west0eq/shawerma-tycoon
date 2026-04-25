--!strict
--[[
	main.server.luau

	Server entry point. Wired top-down so the boot order is obvious:

		Remotes
		  → World
		  → DataService
		  → EconomyService
		  → RatingService
		  → OrderService
		  → StationService
		  → InventoryService
		  → ShopService
		  → BuildService
		  → CustomerService

	Everything below is intentionally synchronous (no `task.wait` between init
	calls) so a failure stops the boot loudly instead of half-starting.
]]

print("[ShawermaTycoon] Booting server (Phase 2)...")

local pkg = script.Parent

local network = pkg:WaitForChild("Network")
local services = pkg:WaitForChild("Services")
local world = pkg:WaitForChild("World")

local RemotesInit = require(network:WaitForChild("RemotesInit"))
local RestaurantBuilder = require(world:WaitForChild("RestaurantBuilder"))
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local OrderService = require(services:WaitForChild("OrderService"))
local StationService = require(services:WaitForChild("StationService"))
local InventoryService = require(services:WaitForChild("InventoryService"))
local ShopService = require(services:WaitForChild("ShopService"))
local BuildService = require(services:WaitForChild("BuildService"))
local CustomerService = require(services:WaitForChild("CustomerService"))
local RatingService = require(services:WaitForChild("RatingService"))

local remotes = RemotesInit.start()
local builtWorld = RestaurantBuilder.build()

DataService.init()
EconomyService.init({ remotes = remotes, dataService = DataService })
RatingService.init()
OrderService.init({ remotes = remotes })
StationService.init({
	starterStation = builtWorld.station,
	remotes = remotes,
	orderService = OrderService,
	economyService = EconomyService,
	ratingService = RatingService,
})
InventoryService.init({ remotes = remotes, dataService = DataService })
ShopService.init({
	remotes = remotes,
	economyService = EconomyService,
	inventoryService = InventoryService,
})
BuildService.init({
	remotes = remotes,
	dataService = DataService,
	economyService = EconomyService,
	inventoryService = InventoryService,
	stationService = StationService,
})
CustomerService.init({
	world = builtWorld,
	remotes = remotes,
	orderService = OrderService,
	economyService = EconomyService,
	stationService = StationService,
	ratingService = RatingService,
	dataService = DataService,
})

print("[ShawermaTycoon] Server ready.")

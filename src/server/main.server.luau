--!strict
--[[
	main.server.luau

	Server entry point. Wired top-down so the boot order is obvious:

		Remotes  → World  → DataService  → EconomyService  → OrderService
		         → CookingService  → CustomerService  → RatingService

	Everything below is intentionally synchronous (no `task.wait` between init
	calls) so a failure stops the boot loudly instead of half-starting.
]]

print("[ShawermaTycoon] Booting server (Phase 1)...")

-- `script` is the boot Script; siblings under the package folder hold the
-- service modules. Resolve them via the parent folder.
local pkg = script.Parent

local network = pkg:WaitForChild("Network")
local services = pkg:WaitForChild("Services")
local world = pkg:WaitForChild("World")

local RemotesInit = require(network:WaitForChild("RemotesInit"))
local RestaurantBuilder = require(world:WaitForChild("RestaurantBuilder"))
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local OrderService = require(services:WaitForChild("OrderService"))
local CookingService = require(services:WaitForChild("CookingService"))
local CustomerService = require(services:WaitForChild("CustomerService"))
local RatingService = require(services:WaitForChild("RatingService"))

local remotes = RemotesInit.start()
local builtWorld = RestaurantBuilder.build()

DataService.init()
EconomyService.init({ remotes = remotes, dataService = DataService })
OrderService.init({ remotes = remotes })
CookingService.init({
	station = builtWorld.station,
	remotes = remotes,
	orderService = OrderService,
	economyService = EconomyService,
})
CustomerService.init({
	world = builtWorld,
	remotes = remotes,
	orderService = OrderService,
	economyService = EconomyService,
})
RatingService.init()

print("[ShawermaTycoon] Server ready.")

--!strict
--[[
	main.server.luau

	Server entry point. Wired top-down so the boot order is obvious:

		Lighting
		  → Remotes
		  → World (8 plots)
		  → DataService
		  → EconomyService
		  → UpgradeService
		  → OrderService
		  → InventoryService
		  → ShopService
		  → PlotService          (must precede services that filter by plot)
		  → BuildService         (uses PlotService for placement bounds)
		  → AtmosphereService    (after BuildService)
		  → RatingService
		  → StationService       (registers a starter station per plot)
		  → StaffService
		  → CustomerService

	Everything below is intentionally synchronous (no `task.wait` between init
	calls) so a failure stops the boot loudly instead of half-starting.
]]

print("[ShawermaTycoon] Booting server (Phase 5)...")

local pkg = script.Parent

local network = pkg:WaitForChild("Network")
local services = pkg:WaitForChild("Services")
local world = pkg:WaitForChild("World")

local RemotesInit = require(network:WaitForChild("RemotesInit"))
local RestaurantBuilder = require(world:WaitForChild("RestaurantBuilder"))
local LightingSetup = require(world:WaitForChild("LightingSetup"))
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local OrderService = require(services:WaitForChild("OrderService"))
local StationService = require(services:WaitForChild("StationService"))
local InventoryService = require(services:WaitForChild("InventoryService"))
local ShopService = require(services:WaitForChild("ShopService"))
local BuildService = require(services:WaitForChild("BuildService"))
local CustomerService = require(services:WaitForChild("CustomerService"))
local RatingService = require(services:WaitForChild("RatingService"))
local UpgradeService = require(services:WaitForChild("UpgradeService"))
local AtmosphereService = require(services:WaitForChild("AtmosphereService"))
local StaffService = require(services:WaitForChild("StaffService"))
local PlotService = require(services:WaitForChild("PlotService"))

LightingSetup.apply()
local remotes = RemotesInit.start()
local builtWorld = RestaurantBuilder.build()

DataService.init()
EconomyService.init({ remotes = remotes, dataService = DataService })
UpgradeService.init({
	remotes = remotes,
	dataService = DataService,
	economyService = EconomyService,
})
OrderService.init({ remotes = remotes })
InventoryService.init({ remotes = remotes, dataService = DataService })
ShopService.init({
	remotes = remotes,
	economyService = EconomyService,
	inventoryService = InventoryService,
})

PlotService.init({ remotes = remotes, world = builtWorld })

BuildService.init({
	remotes = remotes,
	dataService = DataService,
	economyService = EconomyService,
	inventoryService = InventoryService,
	stationService = StationService,
	plotService = PlotService,
})

AtmosphereService.init({ buildService = BuildService, plotService = PlotService })

RatingService.init({
	remotes = remotes,
	atmosphereService = AtmosphereService,
})

StationService.init({
	plots = builtWorld.plots,
	remotes = remotes,
	orderService = OrderService,
	economyService = EconomyService,
	ratingService = RatingService,
	upgradeService = UpgradeService,
	atmosphereService = AtmosphereService,
	plotService = PlotService,
})

StaffService.init({
	remotes = remotes,
	dataService = DataService,
	economyService = EconomyService,
	stationService = StationService,
	plotService = PlotService,
})

CustomerService.init({
	world = builtWorld,
	remotes = remotes,
	orderService = OrderService,
	economyService = EconomyService,
	stationService = StationService,
	ratingService = RatingService,
	dataService = DataService,
	upgradeService = UpgradeService,
	atmosphereService = AtmosphereService,
	staffService = StaffService,
	plotService = PlotService,
})

print("[ShawermaTycoon] Server ready.")

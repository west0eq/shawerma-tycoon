--!strict
--[[
	ShopService.luau

	Wires the `RequestBuy` remote: client requests "buy item X", server
	debits cash, adds item to inventory. The client is *not* trusted with
	any of this — only the request itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))

local ShopService = {}

local EconomyService: any
local InventoryService: any
local notify: RemoteEvent

function ShopService.init(deps: {
	remotes: { [string]: RemoteEvent },
	economyService: any,
	inventoryService: any,
})
	EconomyService = deps.economyService
	InventoryService = deps.inventoryService
	notify = deps.remotes.Notify

	deps.remotes.RequestBuy.OnServerEvent:Connect(function(player: Player, catalogId: any)
		ShopService.tryBuy(player, catalogId)
	end)
end

function ShopService.tryBuy(player: Player, catalogId: any): boolean
	if typeof(catalogId) ~= "string" then
		return false
	end
	if not BuildCatalog.exists(catalogId) then
		notify:FireClient(player, "Unknown item")
		return false
	end
	local item = BuildCatalog.get(catalogId)
	if not EconomyService.tryDebit(player, item.price, item.displayName) then
		return false
	end
	InventoryService.add(player, catalogId, 1)
	notify:FireClient(player, "Bought " .. item.displayName)
	return true
end

return ShopService

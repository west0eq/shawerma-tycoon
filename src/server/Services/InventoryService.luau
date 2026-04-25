--!strict
--[[
	InventoryService.luau

	Tracks how many of each catalog item a player owns *but has not placed
	yet*. The store of truth is `PlayerSave.inventory` (catalogId → count); we
	just provide the API and the change-broadcast remote on top of it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Constants = require(Shared:WaitForChild("Constants"))

local InventoryService = {}

local DataService: any
local inventoryChangedRemote: RemoteEvent

local function ensureInventory(save: any)
	if not save.inventory then
		save.inventory = {}
	end
end

local function broadcast(player: Player)
	local save = DataService.get(player)
	if not save then
		return
	end
	ensureInventory(save)
	inventoryChangedRemote:FireClient(player, save.inventory)
end

function InventoryService.init(deps: { remotes: { [string]: RemoteEvent }, dataService: any })
	DataService = deps.dataService
	inventoryChangedRemote = deps.remotes.InventoryChanged

	DataService.ProfileLoaded:Connect(function(player: Player, save)
		ensureInventory(save)
		broadcast(player)
	end)
end

function InventoryService.get(player: Player): { [string]: number }
	local save = DataService.get(player)
	if not save then
		return {}
	end
	ensureInventory(save)
	return save.inventory
end

function InventoryService.add(player: Player, catalogId: string, count: number?)
	if not BuildCatalog.exists(catalogId) then
		return
	end
	local amount = count or 1
	if amount <= 0 then
		return
	end
	DataService.mutate(player, function(save)
		ensureInventory(save)
		save.inventory[catalogId] = (save.inventory[catalogId] or 0) + amount
	end)
	broadcast(player)
end

function InventoryService.remove(player: Player, catalogId: string, count: number?): boolean
	local save = DataService.get(player)
	if not save then
		return false
	end
	ensureInventory(save)
	local amount = count or 1
	local current = save.inventory[catalogId] or 0
	if current < amount then
		return false
	end
	DataService.mutate(player, function(s)
		s.inventory[catalogId] = current - amount
		if s.inventory[catalogId] <= 0 then
			s.inventory[catalogId] = nil
		end
	end)
	broadcast(player)
	return true
end

function InventoryService.has(player: Player, catalogId: string, count: number?): boolean
	local save = DataService.get(player)
	if not save then
		return false
	end
	ensureInventory(save)
	return (save.inventory[catalogId] or 0) >= (count or 1)
end

return InventoryService

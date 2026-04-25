--!strict
--[[
	BuildService.luau

	Owns the world-side state for player-placed items:
	  • Validates `RequestPlace`/`RequestRemove`/`RequestSell` requests.
	  • Constructs the visual model via `BuildCatalog.build`.
	  • Persists `PlayerSave.placed` so a rejoin restores the restaurant.
	  • Notifies `StationService` when a station-category item is placed or
	    removed so the cooking pipeline gains/loses a station live.

	Validation rules (all server-side):
	  • Catalog id must exist.
	  • Player must own one of that item in inventory.
	  • Position must snap to the build grid.
	  • Position must lie inside the plot bounds.
	  • Bounding box must not overlap any other placed item.
	  • Player must have fewer than `MaxPlacedItems` placed.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))

local BuildService = {}

-- ---- module state --------------------------------------------------------

local DataService: any
local EconomyService: any
local InventoryService: any
local StationService: any
local notify: RemoteEvent
local placedItemsRemote: RemoteEvent

local placedFolder: Folder
-- uid → { player, catalogId, model, size, posX, posY, posZ, yawDegrees }
local liveItems: { [string]: any } = {}

-- ---- helpers -------------------------------------------------------------

local function ensurePlaced(save: any)
	if not save.placed then
		save.placed = {}
	end
end

local function broadcast(player: Player)
	local save = DataService.get(player)
	if not save then
		return
	end
	ensurePlaced(save)
	placedItemsRemote:FireClient(player, save.placed)
end

local function snapToGrid(value: number): number
	return Util.roundTo(value, Constants.Build.GridSize)
end

local function withinPlot(posX: number, posZ: number, sizeX: number, sizeZ: number): boolean
	local origin = Constants.World.Origin
	local hx = Constants.Build.PlotHalfExtents.X
	local hz = Constants.Build.PlotHalfExtents.Y
	local minX = origin.X - hx + sizeX / 2
	local maxX = origin.X + hx - sizeX / 2
	local minZ = origin.Z - hz + sizeZ / 2
	local maxZ = origin.Z + hz - sizeZ / 2
	return posX >= minX and posX <= maxX and posZ >= minZ and posZ <= maxZ
end

local function aabbOverlap(ax: number, az: number, asx: number, asz: number, bx: number, bz: number, bsx: number, bsz: number): boolean
	-- Treat all bounding boxes as axis-aligned; rotated items use their
	-- catalog footprint un-rotated for collision. Imperfect for 90° rotated
	-- non-square items but Phase 2 catalog is mostly square.
	local axMin = ax - asx / 2
	local axMax = ax + asx / 2
	local azMin = az - asz / 2
	local azMax = az + asz / 2
	local bxMin = bx - bsx / 2
	local bxMax = bx + bsx / 2
	local bzMin = bz - bsz / 2
	local bzMax = bz + bsz / 2
	return axMax > bxMin and axMin < bxMax and azMax > bzMin and azMin < bzMax
end

local function overlapsAnything(posX: number, posZ: number, sizeX: number, sizeZ: number, ignoreUid: string?): boolean
	for uid, entry in pairs(liveItems) do
		if uid ~= ignoreUid then
			if aabbOverlap(posX, posZ, sizeX, sizeZ, entry.posX, entry.posZ, entry.size.X, entry.size.Z) then
				return true
			end
		end
	end
	return false
end

local function buildCFrame(posX: number, posY: number, posZ: number, yawDegrees: number): CFrame
	return CFrame.new(posX, posY, posZ) * CFrame.Angles(0, math.rad(yawDegrees), 0)
end

local function spawnModel(player: Player, catalogId: string, posX: number, posY: number, posZ: number, yaw: number, uid: string): any?
	local item = BuildCatalog.get(catalogId)
	local cf = buildCFrame(posX, posY, posZ, yaw)
	local ok, modelOrErr = pcall(item.build, cf)
	if not ok then
		warn("[BuildService] factory failed for " .. catalogId .. ": " .. tostring(modelOrErr))
		return nil
	end
	local model = modelOrErr :: Model
	model.Name = string.format("%s_%s", catalogId, uid:sub(1, 8))
	-- Tag for runtime queries.
	local idValue = Instance.new("StringValue")
	idValue.Name = "PlacedUid"
	idValue.Value = uid
	idValue.Parent = model
	local catalogValue = Instance.new("StringValue")
	catalogValue.Name = "CatalogId"
	catalogValue.Value = catalogId
	catalogValue.Parent = model
	local ownerValue = Instance.new("IntValue")
	ownerValue.Name = "OwnerUserId"
	ownerValue.Value = player.UserId
	ownerValue.Parent = model
	model.Parent = placedFolder

	local entry = {
		uid = uid,
		player = player,
		catalogId = catalogId,
		model = model,
		size = item.size,
		posX = posX,
		posY = posY,
		posZ = posZ,
		yawDegrees = yaw,
	}
	liveItems[uid] = entry

	-- Notify station service if applicable.
	if item.category == "station" and item.stationType then
		StationService.registerStation({
			model = model,
			stationType = item.stationType,
			uid = uid,
		})
	end
	return entry
end

local function despawnModel(uid: string)
	local entry = liveItems[uid]
	if not entry then
		return
	end
	if entry.model and entry.model.Parent then
		StationService.unregisterStation(uid)
		entry.model:Destroy()
	end
	liveItems[uid] = nil
end

-- ---- restoration ---------------------------------------------------------

local function restorePlayer(player: Player)
	local save = DataService.get(player)
	if not save then
		return
	end
	ensurePlaced(save)
	for _, placed in ipairs(save.placed) do
		spawnModel(player, placed.catalogId, placed.posX, placed.posY, placed.posZ, placed.yawDegrees, placed.uid)
	end
	broadcast(player)
end

-- ---- placement ----------------------------------------------------------

function BuildService.tryPlace(player: Player, catalogId: any, posX: any, posZ: any, yaw: any): boolean
	if typeof(catalogId) ~= "string"
		or typeof(posX) ~= "number"
		or typeof(posZ) ~= "number"
		or typeof(yaw) ~= "number"
	then
		return false
	end
	if not BuildCatalog.exists(catalogId) then
		notify:FireClient(player, "Unknown item")
		return false
	end
	if not InventoryService.has(player, catalogId, 1) then
		notify:FireClient(player, "Item not in inventory")
		return false
	end
	local item = BuildCatalog.get(catalogId)

	posX = snapToGrid(posX)
	posZ = snapToGrid(posZ)
	yaw = math.floor(yaw / Constants.Build.RotationStepDegrees + 0.5) * Constants.Build.RotationStepDegrees

	if not withinPlot(posX, posZ, item.size.X, item.size.Z) then
		notify:FireClient(player, "Outside the plot")
		return false
	end
	if overlapsAnything(posX, posZ, item.size.X, item.size.Z, nil) then
		notify:FireClient(player, "That spot is occupied")
		return false
	end

	local save = DataService.get(player)
	if not save then
		return false
	end
	ensurePlaced(save)
	if #save.placed >= Constants.Build.MaxPlacedItems then
		notify:FireClient(player, "Build limit reached")
		return false
	end

	local uid = HttpService:GenerateGUID(false)
	-- Floor sits with top at y=1; place item so its base rests on the floor.
	local posY = Constants.Build.GroundY

	if not InventoryService.remove(player, catalogId, 1) then
		return false
	end

	local entry = spawnModel(player, catalogId, posX, posY, posZ, yaw, uid)
	if not entry then
		-- Spawn failed; restore inventory so we don't eat the player's item.
		InventoryService.add(player, catalogId, 1)
		return false
	end

	DataService.mutate(player, function(s)
		ensurePlaced(s)
		table.insert(s.placed, {
			uid = uid,
			catalogId = catalogId,
			posX = posX,
			posY = posY,
			posZ = posZ,
			yawDegrees = yaw,
		})
	end)
	broadcast(player)
	return true
end

local function tryFindPlaced(player: Player, uid: string): (any?, number?)
	local save = DataService.get(player)
	if not save then
		return nil, nil
	end
	ensurePlaced(save)
	for index, placed in ipairs(save.placed) do
		if placed.uid == uid then
			return placed, index
		end
	end
	return nil, nil
end

function BuildService.tryRemove(player: Player, uid: any): boolean
	if typeof(uid) ~= "string" then
		return false
	end
	local entry = liveItems[uid]
	if not entry or entry.player ~= player then
		return false
	end
	local _, index = tryFindPlaced(player, uid)
	if not index then
		return false
	end
	DataService.mutate(player, function(s)
		ensurePlaced(s)
		table.remove(s.placed, index :: number)
	end)
	despawnModel(uid)
	InventoryService.add(player, entry.catalogId, 1)
	broadcast(player)
	return true
end

function BuildService.trySell(player: Player, uid: any): boolean
	if typeof(uid) ~= "string" then
		return false
	end
	local entry = liveItems[uid]
	if not entry or entry.player ~= player then
		return false
	end
	local _, index = tryFindPlaced(player, uid)
	if not index then
		return false
	end
	local item = BuildCatalog.get(entry.catalogId)
	local refund = math.floor(item.price * Constants.Economy.SellRefundRatio + 0.5)
	DataService.mutate(player, function(s)
		ensurePlaced(s)
		table.remove(s.placed, index :: number)
	end)
	despawnModel(uid)
	EconomyService.addCash(player, refund, "Sold " .. item.displayName)
	broadcast(player)
	return true
end

-- ---- init ---------------------------------------------------------------

function BuildService.init(deps: {
	remotes: { [string]: RemoteEvent },
	dataService: any,
	economyService: any,
	inventoryService: any,
	stationService: any,
})
	DataService = deps.dataService
	EconomyService = deps.economyService
	InventoryService = deps.inventoryService
	StationService = deps.stationService
	notify = deps.remotes.Notify
	placedItemsRemote = deps.remotes.PlacedItemsChanged

	placedFolder = Workspace:FindFirstChild("ShawermaTycoonPlaced") :: Folder
	if not placedFolder then
		placedFolder = Instance.new("Folder")
		placedFolder.Name = "ShawermaTycoonPlaced"
		placedFolder.Parent = Workspace
	end

	deps.remotes.RequestPlace.OnServerEvent:Connect(function(player, catalogId, posX, posZ, yaw)
		BuildService.tryPlace(player, catalogId, posX, posZ, yaw)
	end)
	deps.remotes.RequestRemove.OnServerEvent:Connect(function(player, uid)
		BuildService.tryRemove(player, uid)
	end)
	deps.remotes.RequestSell.OnServerEvent:Connect(function(player, uid)
		BuildService.trySell(player, uid)
	end)

	DataService.ProfileLoaded:Connect(function(player: Player)
		restorePlayer(player)
	end)
end

return BuildService

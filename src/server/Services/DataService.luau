--!strict
--[[
	DataService.luau

	DataStore wrapper that:
	  • Versions every save (`schemaVersion`) so future schemas can migrate.
	  • Wraps every read/write in `pcall` with bounded retry + exponential
	    backoff — DataStore failures never crash the session.
	  • Holds an in-memory profile per player so gameplay services don't have
	    to touch DataStoreService directly.
	  • Saves on PlayerRemoving and on game:BindToClose so leaving the game
	    never costs the player progress.

	Phase 1 only persists money + lifetime stats + an `unlocks` set, but the
	schema is intentionally open-ended so Phase 2's build/menu/staff payloads
	can be added without churn.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

type PlayerSave = Types.PlayerSave

local DataService = {}

local store: DataStore? = nil
local profiles: { [Player]: PlayerSave } = {}
local saving: { [Player]: boolean } = {}

DataService.ProfileLoaded = Signal.new()
DataService.ProfileSaved = Signal.new()

-- ---------- helpers --------------------------------------------------------

local function defaultSave(): PlayerSave
	return {
		schemaVersion = Constants.SchemaVersion,
		cash = Constants.Economy.StartingCash,
		totalEarned = 0,
		customersServed = 0,
		unlocks = {},
		inventory = {},
		placed = {},
		menuUnlocks = {},
	}
end

local function migrate(save: PlayerSave): PlayerSave
	-- Schema migrations chain forward by version. Each branch only handles
	-- the delta between v(N) and v(N+1) so additions stay localized.
	if save.schemaVersion == nil then
		save.schemaVersion = 1
	end
	if save.cash == nil then
		save.cash = Constants.Economy.StartingCash
	end
	if save.totalEarned == nil then
		save.totalEarned = 0
	end
	if save.customersServed == nil then
		save.customersServed = 0
	end
	if save.unlocks == nil then
		save.unlocks = {}
	end

	-- v1 → v2: introduce build/inventory/menuUnlocks payloads.
	if (save.schemaVersion :: number) < 2 then
		if save.inventory == nil then
			save.inventory = {}
		end
		if save.placed == nil then
			save.placed = {}
		end
		if save.menuUnlocks == nil then
			save.menuUnlocks = {}
		end
	end

	save.schemaVersion = Constants.SchemaVersion
	return save
end

local function keyFor(player: Player): string
	return Constants.Save.KeyPrefix .. tostring(player.UserId)
end

local function withRetry<T>(action: () -> T): (boolean, T?)
	local attempt = 0
	local lastError: any
	while attempt < Constants.Save.MaxRetries do
		attempt += 1
		local ok, result = pcall(action)
		if ok then
			return true, result
		end
		lastError = result
		warn(string.format("[DataService] attempt %d failed: %s", attempt, tostring(result)))
		task.wait(Constants.Save.RetryBackoffSeconds * attempt)
	end
	warn("[DataService] gave up after retries: " .. tostring(lastError))
	return false, nil
end

-- ---------- lifecycle ------------------------------------------------------

function DataService.init()
	-- DataStores are unavailable in offline Studio sessions ("data stores can
	-- only be accessed by published games"). We tolerate that gracefully and
	-- fall back to per-session in-memory profiles so Phase 1 still plays.
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("ShawermaTycoon_v2")
	end)
	if ok then
		store = result :: DataStore
	else
		warn("[DataService] DataStore unavailable; using in-memory profiles")
		store = nil
	end

	Players.PlayerAdded:Connect(DataService.loadProfile)
	Players.PlayerRemoving:Connect(function(player)
		DataService.saveProfile(player, true)
		profiles[player] = nil
	end)

	game:BindToClose(function()
		-- BindToClose has 30s. Save every active profile in parallel and
		-- yield until they finish.
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				DataService.saveProfile(player, true)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(0.1)
		end
	end)

	-- Periodic autosave.
	task.spawn(function()
		while true do
			task.wait(Constants.Save.AutosaveIntervalSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				DataService.saveProfile(player, false)
			end
		end
	end)
end

function DataService.loadProfile(player: Player)
	if profiles[player] then
		return
	end

	local save: PlayerSave = defaultSave()

	if store then
		local ok, raw = withRetry(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok and typeof(raw) == "table" then
			save = migrate(raw :: PlayerSave)
		elseif not ok then
			-- Refuse to overwrite unknown state with defaults: kick the
			-- player rather than wiping their progress on transient errors.
			player:Kick("Failed to load save data. Please rejoin in a moment.")
			return
		end
	end

	profiles[player] = save
	DataService.ProfileLoaded:Fire(player, save)
end

function DataService.saveProfile(player: Player, force: boolean)
	local save = profiles[player]
	if not save then
		return
	end
	if saving[player] and not force then
		return
	end
	saving[player] = true

	if store then
		local ok = withRetry(function()
			(store :: DataStore):SetAsync(keyFor(player), save)
			return true
		end)
		if not ok then
			warn("[DataService] save failed for " .. player.Name)
		end
	end

	saving[player] = false
	DataService.ProfileSaved:Fire(player, save)
end

-- ---------- accessors ------------------------------------------------------

function DataService.get(player: Player): PlayerSave?
	return profiles[player]
end

function DataService.mutate(player: Player, mutator: (PlayerSave) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	mutator(profile)
end

function DataService.isReady(player: Player): boolean
	return profiles[player] ~= nil
end

return DataService

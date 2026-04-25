--!strict
--[[
	UpgradeService.luau

	Restaurant-wide tier upgrades. Persists per-player tiers in
	`PlayerSave.upgrades` and exposes `getTier()` so other services can
	apply effects without coupling to UpgradeCatalog.

	Each gameplay service that wants to be "upgrade-aware" calls
	`UpgradeService.getEffectValue(kind)` to fetch the *aggregated* value
	currently applicable for the host player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Signal = require(Shared:WaitForChild("Signal"))
local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))

local UpgradeService = {}

UpgradeService.Changed = Signal.new()

local DataService: any
local EconomyService: any
local notify: RemoteEvent
local upgradesRemote: RemoteEvent

local function ensureUpgrades(save: any)
	if not save.upgrades then
		save.upgrades = {}
	end
end

local function broadcast(player: Player)
	local save = DataService.get(player)
	if not save then
		return
	end
	ensureUpgrades(save)
	upgradesRemote:FireClient(player, save.upgrades)
	UpgradeService.Changed:Fire(player, save.upgrades)
end

function UpgradeService.getTier(player: Player, id: string): number
	local save = DataService.get(player)
	if not save then
		return 0
	end
	ensureUpgrades(save)
	return save.upgrades[id] or 0
end

-- Aggregated value of an effect kind for a specific player. If `player` is
-- nil we fall back to the first connected player so legacy single-host
-- callers keep working during migration. Returns 0 when no save exists.
function UpgradeService.getEffectValue(kind: string, player: Player?): number
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return 0
	end
	local total = 0
	for _, up in ipairs(UpgradeCatalog.all()) do
		if up.effect.kind == kind then
			local tier = UpgradeService.getTier(subject, up.id)
			total += tier * up.effect.value
		end
	end
	return total
end

function UpgradeService.tryPurchase(player: Player, id: any): boolean
	if typeof(id) ~= "string" or not UpgradeCatalog.exists(id) then
		notify:FireClient(player, "Unknown upgrade")
		return false
	end
	local save = DataService.get(player)
	if not save then
		return false
	end
	ensureUpgrades(save)
	local tier = save.upgrades[id] or 0
	local cost = UpgradeCatalog.nextTierCost(id, tier)
	if not cost then
		notify:FireClient(player, "Upgrade maxed out")
		return false
	end
	if not EconomyService.tryDebit(player, cost, "Upgrade " .. id) then
		notify:FireClient(player, "Not enough cash")
		return false
	end
	DataService.mutate(player, function(s)
		ensureUpgrades(s)
		s.upgrades[id] = (s.upgrades[id] or 0) + 1
	end)
	broadcast(player)
	return true
end

function UpgradeService.init(deps: {
	remotes: { [string]: RemoteEvent },
	dataService: any,
	economyService: any,
})
	DataService = deps.dataService
	EconomyService = deps.economyService
	notify = deps.remotes.Notify
	upgradesRemote = deps.remotes.UpgradesChanged

	deps.remotes.RequestPurchaseUpgrade.OnServerEvent:Connect(function(player, id)
		UpgradeService.tryPurchase(player, id)
	end)

	DataService.ProfileLoaded:Connect(function(player: Player)
		broadcast(player)
	end)
end

return UpgradeService

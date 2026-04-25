--!strict
--[[
	EconomyService.luau

	The single authoritative source of player money. Gameplay services call
	`addCash` / `tryDebit`; nothing else mutates `profile.cash` directly. Every
	change emits `MoneyChanged` to the owning client only.

	No remote here is ever wired client→server, on purpose: the client cannot
	mutate money under any circumstance.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))

local EconomyService = {}

local moneyChanged: RemoteEvent
local notify: RemoteEvent
local DataService: any

function EconomyService.init(deps: { remotes: { [string]: RemoteEvent }, dataService: any })
	moneyChanged = deps.remotes.MoneyChanged
	notify = deps.remotes.Notify
	DataService = deps.dataService

	DataService.ProfileLoaded:Connect(function(player: Player, save)
		moneyChanged:FireClient(player, save.cash)
	end)
end

local function fireMoney(player: Player)
	local save = DataService.get(player)
	if save then
		moneyChanged:FireClient(player, save.cash)
	end
end

function EconomyService.getCash(player: Player): number
	local save = DataService.get(player)
	return save and save.cash or 0
end

function EconomyService.addCash(player: Player, amount: number, reason: string?)
	if amount == 0 then
		return
	end
	DataService.mutate(player, function(save)
		save.cash = math.floor(Util.clamp(save.cash + amount, 0, Constants.Economy.MaxBankableCash))
		if amount > 0 then
			save.totalEarned += amount
		end
	end)
	fireMoney(player)

	if reason and amount > 0 then
		notify:FireClient(player, string.format("+%s — %s", Util.formatMoney(amount), reason))
	end
end

function EconomyService.tryDebit(player: Player, amount: number, reason: string?): boolean
	assert(amount >= 0, "tryDebit: amount must be non-negative")
	local save = DataService.get(player)
	if not save then
		return false
	end
	if save.cash < amount then
		if reason then
			notify:FireClient(player, "Not enough cash for " .. reason)
		end
		return false
	end
	DataService.mutate(player, function(s)
		s.cash -= amount
	end)
	fireMoney(player)
	return true
end

function EconomyService.recordCustomerServed(player: Player)
	DataService.mutate(player, function(save)
		save.customersServed += 1
	end)
end

return EconomyService

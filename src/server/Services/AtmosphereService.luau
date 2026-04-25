--!strict
--[[
	AtmosphereService.luau

	Per-plot atmosphere score (0..1) computed from each owner's placed
	items. Other services pass a `Player` (or `plotIndex`, internally
	resolved to the owner) and receive that plot's score. Falls back to
	the first connected player when no argument is supplied so legacy
	single-host call sites keep working.

	Public:
	  • init({ buildService, plotService })
	  • getScore(player?): number
	  • getScoreForPlot(plotIndex): number
	  • Changed: Signal(player, score)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Constants = require(Shared:WaitForChild("Constants"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

type PlacedItem = Types.PlacedItem

local AtmosphereService = {}

AtmosphereService.Changed = Signal.new()

local BuildService: any = nil
local PlotService: any = nil
local cachedByPlayer: { [Player]: number } = {}

local function diminishingContribution(count: number, perItem: number): number
	local threshold = Constants.Atmosphere.DiminishingThreshold
	if count <= threshold then
		return count * perItem
	end
	local extra = count - threshold
	local taper = math.min(extra, threshold) * 0.5 * perItem
	return threshold * perItem + taper
end

local function recomputeFor(player: Player)
	if not BuildService then
		cachedByPlayer[player] = 0
		AtmosphereService.Changed:Fire(player, 0)
		return
	end
	local placed: { PlacedItem } = BuildService.getPlaced(player) or {}
	local counts: { [string]: number } = {}
	for _, item in ipairs(placed) do
		counts[item.catalogId] = (counts[item.catalogId] or 0) + 1
	end

	local raw = 0
	local distinct = 0
	for catalogId, count in pairs(counts) do
		if BuildCatalog.exists(catalogId) then
			local spec = BuildCatalog.get(catalogId)
			local per = spec.atmosphereScore or 0
			if per > 0 then
				raw += diminishingContribution(count, per)
				distinct += 1
			end
		end
	end
	raw += math.min(distinct, 8) * 0.4

	local cap = Constants.Atmosphere.MaxRawScore
	local normalized = math.clamp(raw / cap, 0, 1)
	local prev = cachedByPlayer[player] or 0
	if math.abs(normalized - prev) > 0.0005 then
		cachedByPlayer[player] = normalized
		AtmosphereService.Changed:Fire(player, normalized)
	end
end

function AtmosphereService.init(deps: { buildService: any, plotService: any? })
	BuildService = deps.buildService
	PlotService = deps.plotService

	if BuildService.PlacementChanged then
		BuildService.PlacementChanged:Connect(function(player: Player)
			if player then
				recomputeFor(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			recomputeFor(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		cachedByPlayer[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			recomputeFor(player)
		end)
	end
end

function AtmosphereService.getScore(player: Player?): number
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return 0
	end
	return cachedByPlayer[subject] or 0
end

function AtmosphereService.getScoreForPlot(plotIndex: number): number
	if not PlotService then
		return 0
	end
	local owner = PlotService.getOwnerByIndex(plotIndex)
	if not owner then
		return 0
	end
	return cachedByPlayer[owner] or 0
end

function AtmosphereService.recomputeNow(player: Player?)
	if player then
		recomputeFor(player)
	else
		for _, p in ipairs(Players:GetPlayers()) do
			recomputeFor(p)
		end
	end
end

return AtmosphereService

--!strict
--[[
	AtmosphereService.luau

	Computes the restaurant's atmosphere score (0..1) from the host player's
	placed items. Uses a per-id diminishing-returns curve so flooding the
	plot with one decor type can't push the score arbitrarily high.

	Public:
	  • init({ buildService })  — wire dependencies
	  • getScore(): number       — current 0..1 atmosphere
	  • Changed: Signal           — fired whenever the score changes
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
local cachedScore: number = 0

local function diminishingContribution(count: number, perItem: number): number
	-- Logistic-like curve: linear up to threshold, then heavy taper. Hard
	-- cap at 2x the threshold's worth.
	local threshold = Constants.Atmosphere.DiminishingThreshold
	if count <= threshold then
		return count * perItem
	end
	local extra = count - threshold
	-- Each extra item is worth half as much, with a hard cap.
	local taper = math.min(extra, threshold) * 0.5 * perItem
	return threshold * perItem + taper
end

local function host(): Player?
	return Players:GetPlayers()[1]
end

local function recompute()
	local player = host()
	if not player or not BuildService then
		cachedScore = 0
		AtmosphereService.Changed:Fire(0)
		return
	end

	local placed: { PlacedItem } = BuildService.getPlaced(player) or {}
	local counts: { [string]: number } = {}
	for _, item in ipairs(placed) do
		counts[item.catalogId] = (counts[item.catalogId] or 0) + 1
	end

	local raw = 0
	for catalogId, count in pairs(counts) do
		if BuildCatalog.exists(catalogId) then
			local spec = BuildCatalog.get(catalogId)
			local per = spec.atmosphereScore or 0
			if per > 0 then
				raw += diminishingContribution(count, per)
			end
		end
	end

	-- Variety bonus: the more distinct atmosphere-positive ids, the better.
	local distinct = 0
	for catalogId, count in pairs(counts) do
		if count > 0 and BuildCatalog.exists(catalogId) then
			local spec = BuildCatalog.get(catalogId)
			if (spec.atmosphereScore or 0) > 0 then
				distinct += 1
			end
		end
	end
	raw += math.min(distinct, 8) * 0.4

	local cap = Constants.Atmosphere.MaxRawScore
	local normalized = math.clamp(raw / cap, 0, 1)
	if math.abs(normalized - cachedScore) > 0.0005 then
		cachedScore = normalized
		AtmosphereService.Changed:Fire(normalized)
	end
end

function AtmosphereService.init(deps: { buildService: any })
	BuildService = deps.buildService
	-- BuildService fires this whenever placed items change.
	if BuildService.PlacementChanged then
		BuildService.PlacementChanged:Connect(function()
			recompute()
		end)
	end
	-- Initial computation once a host is around.
	task.defer(recompute)
	Players.PlayerAdded:Connect(function()
		task.defer(recompute)
	end)
end

function AtmosphereService.getScore(): number
	return cachedScore
end

function AtmosphereService.recomputeNow()
	recompute()
end

return AtmosphereService

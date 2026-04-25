--!strict
--[[
	TrashService.luau

	Per-plot trash spawn + cleanup. Customers occasionally drop a wrapper
	when they leave or a dirty plate when they finish eating; the cleaner
	staffer (or the player walking up to it) removes them. This gives
	hired staff something visible to do beyond cooking and ties food
	rating to "is this place dirty?".

	Trash item layout (ad-hoc Model):
	    Trash.Model
	      ├─ Primary BasePart (CanCollide, anchored)
	      └─ ProximityPrompt for manual cleanup
	    Each trash entry stores its plotIndex as an attribute so the
	    cleaner AI can scope to its own plot.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local TrashService = {}

type TrashEntry = {
	model: Model,
	primary: BasePart,
	plotIndex: number,
	prompt: ProximityPrompt?,
}

local trashFolder: Folder
local trashEntries: { TrashEntry } = {}
local nextTrashId = 1
local rng = Random.new()

local PlotService: any
local RatingService: any

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

local function buildPlateModel(position: Vector3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "DirtyPlate"
	-- Plate base.
	local plate = makePart({
		Name = "Plate",
		Size = Vector3.new(2.2, 0.15, 2.2),
		Shape = Enum.PartType.Cylinder,
		Position = position,
		Orientation = Vector3.new(0, 0, 90),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(230, 225, 215),
	})
	plate.Parent = model
	-- Leftover wrapper / scrap on top.
	local scrap = makePart({
		Name = "Scrap",
		Size = Vector3.new(1.0, 0.25, 1.0),
		Position = position + Vector3.new(0, 0.2, 0),
		Material = Enum.Material.Foil,
		Color = Color3.fromRGB(180, 170, 130),
	})
	scrap.Parent = model
	model.PrimaryPart = plate
	return model, plate
end

local function buildWrapperModel(position: Vector3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Wrapper"
	local wrap = makePart({
		Name = "Wrap",
		Size = Vector3.new(0.9, 0.4, 0.9),
		Position = position,
		Material = Enum.Material.Foil,
		Color = Color3.fromRGB(200, 195, 170),
		Orientation = Vector3.new(0, rng:NextNumber(0, 360), rng:NextNumber(-15, 15)),
	})
	wrap.Parent = model
	model.PrimaryPart = wrap
	return model, wrap
end

local function attachPrompt(entry: TrashEntry)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Clean up"
	prompt.ObjectText = entry.model.Name
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = entry.primary
	prompt.Triggered:Connect(function(player: Player)
		TrashService.remove(entry, player)
	end)
	entry.prompt = prompt
end

local function ensureFolder()
	if trashFolder and trashFolder.Parent then
		return
	end
	trashFolder = Instance.new("Folder")
	trashFolder.Name = "ShawermaTycoonTrash"
	trashFolder.Parent = Workspace
end

local function spawn(model: Model, primary: BasePart, plotIndex: number): TrashEntry
	ensureFolder()
	model:SetAttribute("PlotIndex", plotIndex)
	model:SetAttribute("TrashId", nextTrashId)
	nextTrashId += 1
	model.Parent = trashFolder
	local entry: TrashEntry = {
		model = model,
		primary = primary,
		plotIndex = plotIndex,
	}
	attachPrompt(entry)
	table.insert(trashEntries, entry)
	-- Atmosphere/rating dings if the plot is owned and dirty.
	if RatingService and PlotService then
		local owner = PlotService.getOwnerByIndex(plotIndex)
		if owner then
			RatingService.recordEvent(owner, "trash_appeared", { trashId = nextTrashId - 1 })
		end
	end
	return entry
end

-- Public: drop a dirty plate at the given seat-table position.
function TrashService.dropPlate(plotIndex: number, position: Vector3)
	local model, primary = buildPlateModel(position + Vector3.new(0, 0.4, 0))
	spawn(model, primary, plotIndex)
end

-- Public: drop a wrapper at the given (usually exit-pad) position.
function TrashService.dropWrapper(plotIndex: number, position: Vector3)
	local model, primary = buildWrapperModel(position + Vector3.new(rng:NextNumber(-3, 3), 0.5, rng:NextNumber(-3, 3)))
	spawn(model, primary, plotIndex)
end

-- Public: list trash for a plot. Used by the cleaner AI.
function TrashService.listForPlot(plotIndex: number): { TrashEntry }
	local out: { TrashEntry } = {}
	for _, entry in ipairs(trashEntries) do
		if entry.model and entry.model.Parent and entry.plotIndex == plotIndex then
			table.insert(out, entry)
		end
	end
	return out
end

-- Public: remove a trash entry, optionally crediting `player`.
function TrashService.remove(entry: TrashEntry, player: Player?)
	for i, e in ipairs(trashEntries) do
		if e == entry then
			table.remove(trashEntries, i)
			break
		end
	end
	if entry.prompt then
		entry.prompt:Destroy()
	end
	if entry.model and entry.model.Parent then
		-- Tween out so it doesn't pop.
		local primary = entry.model.PrimaryPart
		if primary then
			TweenService:Create(
				primary,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = primary.Size * 0.1, Transparency = 1 }
			):Play()
		end
		task.delay(0.3, function()
			if entry.model.Parent then
				entry.model:Destroy()
			end
		end)
	end
	if player and RatingService then
		RatingService.recordEvent(player, "trash_cleaned", {})
	end
end

-- Public: pick a roll to decide if this customer drops a plate / wrapper.
function TrashService.maybeDropPlate(plotIndex: number, position: Vector3): boolean
	if rng:NextNumber() < (Constants.Trash and Constants.Trash.PlateDropChance or 0.45) then
		TrashService.dropPlate(plotIndex, position)
		return true
	end
	return false
end

function TrashService.maybeDropWrapper(plotIndex: number, position: Vector3): boolean
	if rng:NextNumber() < (Constants.Trash and Constants.Trash.WrapperDropChance or 0.20) then
		TrashService.dropWrapper(plotIndex, position)
		return true
	end
	return false
end

function TrashService.init(deps: {
	plotService: any?,
	ratingService: any?,
})
	PlotService = deps.plotService
	RatingService = deps.ratingService
	ensureFolder()
end

return TrashService

--!strict
--[[
	BuildCatalog.luau

	Defines every item the player can buy, place, and remove via build mode.
	Each entry owns a `build` factory that creates the visual model — we
	deliberately *don't* use Studio assets so the project plays clean after
	a Rojo sync. Phase 4 will swap factories for richer prefabs.

	Stations carry an extra `stationType` field so the cooking pipeline knows
	which dish category each placed station can prepare.
]]

local Types = require(script.Parent.Types)

type StationType = Types.StationType
type BuildItemCategory = Types.BuildItemCategory

export type BuildItem = {
	id: string,
	displayName: string,
	category: BuildItemCategory,
	price: number,
	-- World footprint (X/Z used for grid snapping + collision check, Y for
	-- visual placement above the floor).
	size: Vector3,
	stationType: StationType?,
	-- How much this item contributes to the atmosphere score when placed.
	-- Higher = more pleasant restaurant. Diminishing returns are applied in
	-- AtmosphereService so flooding one item type doesn't dominate the score.
	atmosphereScore: number?,
	-- Procedural model factory. Receives the desired CFrame; must return a
	-- Model with PrimaryPart set.
	build: (CFrame) -> Model,
	tags: { string }?,
}

-- ---------- helpers --------------------------------------------------------

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = true
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

local function newModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	return model
end

-- ---------- factories ------------------------------------------------------

local function buildTableBasic(cf: CFrame): Model
	local model = newModel("table_basic")
	-- Modern bistro table: white marble round-ish top, brushed-steel
	-- pedestal leg with a chrome foot disk.
	local top = makePart({
		Name = "Top",
		Size = Vector3.new(4, 0.3, 4),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(232, 230, 224),
		CFrame = cf * CFrame.new(0, 1.55, 0),
	})
	top.Parent = model
	local trim = makePart({
		Name = "Trim",
		Size = Vector3.new(4.04, 0.05, 4.04),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(195, 145, 70),
		CFrame = cf * CFrame.new(0, 1.4, 0),
	})
	trim.Parent = model
	local pedestal = makePart({
		Name = "Pedestal",
		Size = Vector3.new(0.5, 1.4, 0.5),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(200, 200, 205),
		CFrame = cf * CFrame.new(0, 0.7, 0),
	})
	pedestal.Parent = model
	local foot = makePart({
		Name = "Foot",
		Size = Vector3.new(2.0, 0.15, 2.0),
		Shape = Enum.PartType.Cylinder,
		Orientation = Vector3.new(0, 0, 90),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(180, 180, 188),
		CFrame = cf * CFrame.new(0, 0.075, 0),
	})
	foot.Parent = model
	model.PrimaryPart = top
	return model
end

local function buildChairBasic(cf: CFrame): Model
	local model = newModel("chair_basic")
	-- Modern bistro chair: dark teal upholstered seat, chrome cantilever
	-- frame, padded backrest. The Seat itself is the actual sittable
	-- object so customers can Seat:Sit on it.
	local seatCushion = makePart({
		Name = "Cushion",
		Size = Vector3.new(1.4, 0.25, 1.4),
		Color = Color3.fromRGB(38, 60, 78),
		Material = Enum.Material.Fabric,
		CFrame = cf * CFrame.new(0, 0.9, 0),
	})
	seatCushion.Parent = model
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Anchored = true
	seat.Size = Vector3.new(1.2, 0.05, 1.2)
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Material = Enum.Material.Fabric
	seat.Color = Color3.fromRGB(38, 60, 78)
	seat.Transparency = 1
	seat.CFrame = cf * CFrame.new(0, 1.05, 0)
	seat.Parent = model
	local back = makePart({
		Name = "Back",
		Size = Vector3.new(1.4, 1.6, 0.18),
		Color = Color3.fromRGB(38, 60, 78),
		Material = Enum.Material.Fabric,
		CFrame = cf * CFrame.new(0, 1.85, -0.6),
	})
	back.Parent = model
	-- Chrome cantilever frame (two thin parallel rails).
	local function rail(xOffset: number)
		local r = makePart({
			Name = "Rail",
			Size = Vector3.new(0.15, 1.0, 1.4),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(210, 210, 215),
			CFrame = cf * CFrame.new(xOffset, 0.5, 0),
		})
		r.Parent = model
	end
	rail(0.55)
	rail(-0.55)
	model.PrimaryPart = seatCushion
	return model
end

local function buildCounterSegment(cf: CFrame): Model
	local model = newModel("counter_segment")
	-- Modern counter: dark cabinet body + light marble countertop slab
	-- with a thin brass trim along the front edge.
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(4, 3.6, 2),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(34, 38, 48),
		CFrame = cf * CFrame.new(0, 1.8, 0),
	})
	body.Parent = model
	local slab = makePart({
		Name = "Slab",
		Size = Vector3.new(4.2, 0.35, 2.2),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(232, 230, 224),
		CFrame = cf * CFrame.new(0, 3.78, 0),
	})
	slab.Parent = model
	local trim = makePart({
		Name = "Trim",
		Size = Vector3.new(4.05, 0.08, 0.08),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(195, 145, 70),
		CFrame = cf * CFrame.new(0, 3.6, 1.05),
	})
	trim.Parent = model
	model.PrimaryPart = body
	return model
end

local function buildStation(stationType: StationType, color: Color3, name: string): (CFrame) -> Model
	return function(cf: CFrame): Model
		local model = newModel(name)
		local body = makePart({
			Name = "Body",
			Size = Vector3.new(4, 5, 4),
			Material = Enum.Material.Metal,
			Color = color,
			CFrame = cf * CFrame.new(0, 2.5, 0),
		})
		body.Parent = model
		-- Tag the model so CookingStationService can discover stations placed
		-- via build mode and register them on the fly.
		local marker = Instance.new("StringValue")
		marker.Name = "StationType"
		marker.Value = stationType
		marker.Parent = model
		model.PrimaryPart = body
		return model
	end
end

local function buildDecorPlant(cf: CFrame): Model
	local model = newModel("decor_plant")
	local pot = makePart({
		Name = "Pot",
		Size = Vector3.new(1, 1, 1),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(120, 80, 60),
		CFrame = cf * CFrame.new(0, 0.5, 0),
	})
	pot.Parent = model
	local foliage = makePart({
		Name = "Foliage",
		Size = Vector3.new(1.4, 2, 1.4),
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(60, 130, 60),
		CFrame = cf * CFrame.new(0, 2, 0),
	})
	foliage.Parent = model
	model.PrimaryPart = pot
	return model
end

local function buildDecorLamp(cf: CFrame): Model
	local model = newModel("decor_lamp")
	local pole = makePart({
		Name = "Pole",
		Size = Vector3.new(0.4, 4, 0.4),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(40, 40, 40),
		CFrame = cf * CFrame.new(0, 2, 0),
	})
	pole.Parent = model
	local shade = makePart({
		Name = "Shade",
		Size = Vector3.new(1.6, 1, 1.6),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(240, 220, 140),
		CFrame = cf * CFrame.new(0, 4.5, 0),
	})
	shade.Parent = model
	local light = Instance.new("PointLight")
	light.Brightness = 1.5
	light.Range = 12
	light.Color = Color3.fromRGB(255, 230, 180)
	light.Parent = shade
	model.PrimaryPart = pole
	return model
end

-- ---------- catalog --------------------------------------------------------

local Catalog: { [string]: BuildItem } = {
	-- Furniture.
	table_basic = {
		id = "table_basic",
		displayName = "Bistro Table",
		category = "furniture",
		price = 50,
		size = Vector3.new(4, 1.6, 4),
		atmosphereScore = 1.0,
		build = buildTableBasic,
	},
	chair_basic = {
		id = "chair_basic",
		displayName = "Bistro Chair",
		category = "furniture",
		price = 20,
		size = Vector3.new(1.4, 2.4, 1.4),
		atmosphereScore = 0.4,
		build = buildChairBasic,
	},
	counter_segment = {
		id = "counter_segment",
		displayName = "Counter Segment",
		category = "furniture",
		price = 80,
		size = Vector3.new(4, 4, 2),
		atmosphereScore = 0.6,
		build = buildCounterSegment,
	},
	-- Stations.
	station_grill = {
		id = "station_grill",
		displayName = "Grill Station",
		category = "station",
		price = 600,
		size = Vector3.new(4, 5, 4),
		stationType = "grill",
		build = buildStation("grill", Color3.fromRGB(180, 80, 40), "station_grill"),
	},
	station_drink = {
		id = "station_drink",
		displayName = "Drinks Bar",
		category = "station",
		price = 350,
		size = Vector3.new(4, 5, 4),
		stationType = "drink",
		build = buildStation("drink", Color3.fromRGB(60, 110, 200), "station_drink"),
	},
	station_side = {
		id = "station_side",
		displayName = "Fries Fryer",
		category = "station",
		price = 450,
		size = Vector3.new(4, 5, 4),
		stationType = "side",
		build = buildStation("side", Color3.fromRGB(220, 180, 60), "station_side"),
	},
	station_dessert = {
		id = "station_dessert",
		displayName = "Pastry Counter",
		category = "station",
		price = 800,
		size = Vector3.new(4, 5, 4),
		stationType = "dessert",
		build = buildStation("dessert", Color3.fromRGB(180, 130, 200), "station_dessert"),
	},
	-- Decor.
	decor_plant = {
		id = "decor_plant",
		displayName = "Potted Plant",
		category = "decor",
		price = 30,
		size = Vector3.new(1.6, 3, 1.6),
		atmosphereScore = 1.5,
		build = buildDecorPlant,
	},
	decor_lamp = {
		id = "decor_lamp",
		displayName = "Floor Lamp",
		category = "decor",
		price = 40,
		size = Vector3.new(1.6, 5, 1.6),
		atmosphereScore = 1.2,
		build = buildDecorLamp,
	},
}

local function get(id: string): BuildItem
	local item = Catalog[id]
	assert(item ~= nil, "BuildCatalog: unknown item id '" .. tostring(id) .. "'")
	return item
end

local function all(): { BuildItem }
	local out: { BuildItem } = {}
	for _, item in pairs(Catalog) do
		table.insert(out, item)
	end
	return out
end

local function exists(id: string): boolean
	return Catalog[id] ~= nil
end

return {
	get = get,
	all = all,
	exists = exists,
}

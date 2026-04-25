--!strict
--[[
	RestaurantBuilder.luau

	Builds the Phase 1 starter restaurant procedurally so the project is
	playable straight after a Rojo sync — no manual Studio setup required.

	Returns a `World` table with named anchors that gameplay services use to
	reason about the layout (counter spot, kitchen, tables, exit, etc.).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local RestaurantBuilder = {}

export type SeatRef = {
	seat: Seat,
	model: Model,
}

export type World = {
	root: Folder,
	floor: BasePart,
	counter: BasePart,
	counterSpot: BasePart, -- where the customer stands to order
	station: BasePart,     -- cooking station (proximity prompt host)
	stationServeSpot: BasePart,
	spawnPad: BasePart,
	exitPad: BasePart,
	seats: { SeatRef },
	staffAnchors: { [string]: BasePart },
}

-- ---------- helpers --------------------------------------------------------

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

local function attach(part: Part, parent: Instance): Part
	part.Parent = parent
	return part
end

local function spotPart(name: string, position: Vector3, parent: Instance): Part
	-- Invisible "anchor" parts that gameplay services target with MoveTo.
	return attach(
		makePart({
			Name = name,
			Size = Vector3.new(2, 1, 2),
			Position = position,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}),
		parent
	)
end

-- ---------- main build -----------------------------------------------------

function RestaurantBuilder.build(): World
	local origin = Constants.World.Origin
	local floorSize = Constants.World.FloorSize
	local wallH = Constants.World.WallHeight
	local wallT = Constants.World.WallThickness

	local root = Workspace:FindFirstChild("ShawermaTycoonWorld")
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "ShawermaTycoonWorld"
	root.Parent = Workspace

	-- Floor.
	local floor = attach(
		makePart({
			Name = "Floor",
			Size = floorSize,
			Position = origin + Vector3.new(0, floorSize.Y / 2, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(120, 90, 60),
		}),
		root
	)

	-- Walls (4 sides). The front wall has a door gap centred on +X.
	local hx = floorSize.X / 2
	local hz = floorSize.Z / 2
	local wallY = origin.Y + floor.Size.Y + wallH / 2
	local doorWidth = 8

	local function buildWall(name: string, size: Vector3, position: Vector3)
		attach(
			makePart({
				Name = name,
				Size = size,
				Position = position,
				Material = Enum.Material.Concrete,
				Color = Color3.fromRGB(220, 215, 200),
			}),
			root
		)
	end

	-- Back wall (-Z).
	buildWall("WallBack", Vector3.new(floorSize.X, wallH, wallT), origin + Vector3.new(0, wallY, -hz))
	-- Left wall (-X).
	buildWall("WallLeft", Vector3.new(wallT, wallH, floorSize.Z), origin + Vector3.new(-hx, wallY, 0))
	-- Right wall (+X).
	buildWall("WallRight", Vector3.new(wallT, wallH, floorSize.Z), origin + Vector3.new(hx, wallY, 0))
	-- Front wall (+Z) split into two segments around the door.
	local frontHalf = (floorSize.X - doorWidth) / 2
	buildWall(
		"WallFrontA",
		Vector3.new(frontHalf, wallH, wallT),
		origin + Vector3.new(-(doorWidth / 2 + frontHalf / 2), wallY, hz)
	)
	buildWall(
		"WallFrontB",
		Vector3.new(frontHalf, wallH, wallT),
		origin + Vector3.new((doorWidth / 2 + frontHalf / 2), wallY, hz)
	)

	-- Counter (long bar mid-room separating dining area from kitchen).
	local counter = attach(
		makePart({
			Name = "Counter",
			Size = Vector3.new(20, 4, 2),
			Position = origin + Vector3.new(0, floor.Size.Y + 2, -8),
			Material = Enum.Material.Marble,
			Color = Color3.fromRGB(85, 60, 40),
		}),
		root
	)

	-- Cooking station behind the counter (kitchen side, -Z).
	local station = attach(
		makePart({
			Name = "CookingStation",
			Size = Vector3.new(6, 5, 4),
			Position = origin + Vector3.new(0, floor.Size.Y + 2.5, -16),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(160, 70, 40),
		}),
		root
	)

	local stationServeSpot = spotPart(
		"StationServeSpot",
		station.Position + Vector3.new(0, -station.Size.Y / 2 + 1.5, 6),
		root
	)

	-- Customer ordering anchor (dining side of counter).
	local counterSpot = spotPart(
		"CounterSpot",
		counter.Position + Vector3.new(0, -counter.Size.Y / 2 + 1.5, 4),
		root
	)

	-- Customer spawn / exit pads outside the door.
	local spawnPad = spotPart(
		"SpawnPad",
		origin + Vector3.new(-3, floor.Size.Y + 1.5, hz + 8),
		root
	)
	local exitPad = spotPart(
		"ExitPad",
		origin + Vector3.new(3, floor.Size.Y + 1.5, hz + 12),
		root
	)

	-- Tables. Each table = 1 BasePart top + N Seats arranged around it.
	local seats: { SeatRef } = {}
	local tableCount = Constants.World.NumStarterTables
	local seatsPerTable = Constants.World.SeatsPerTable

	for tableIndex = 1, tableCount do
		local tableX = -10 + (tableIndex - 1) * 20
		local tablePos = origin + Vector3.new(tableX, floor.Size.Y + 1.5, 8)
		local tableTop = attach(
			makePart({
				Name = "Table_" .. tableIndex,
				Size = Vector3.new(5, 0.4, 5),
				Position = tablePos,
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(95, 65, 35),
			}),
			root
		)
		-- Single pedestal leg.
		attach(
			makePart({
				Name = "TableLeg_" .. tableIndex,
				Size = Vector3.new(0.6, 1.4, 0.6),
				Position = tablePos - Vector3.new(0, 0.9, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(40, 40, 40),
			}),
			root
		)

		for seatIndex = 1, seatsPerTable do
			local seatModel = Instance.new("Model")
			seatModel.Name = string.format("SeatModel_T%d_S%d", tableIndex, seatIndex)
			seatModel.Parent = root

			local angle = (seatIndex - 1) * (2 * math.pi / seatsPerTable)
			local offset = Vector3.new(math.sin(angle) * 3.5, -0.5, math.cos(angle) * 3.5)
			local seatBase = attach(
				makePart({
					Name = "Base",
					Size = Vector3.new(1.4, 0.4, 1.4),
					Position = tablePos + offset,
					Material = Enum.Material.SmoothPlastic,
					Color = Color3.fromRGB(60, 60, 60),
				}),
				seatModel
			)
			local seat = Instance.new("Seat")
			seat.Name = "Seat"
			seat.Anchored = true
			seat.Size = Vector3.new(1.2, 0.4, 1.2)
			seat.Position = seatBase.Position + Vector3.new(0, 0.4, 0)
			seat.TopSurface = Enum.SurfaceType.Smooth
			seat.Material = Enum.Material.SmoothPlastic
			seat.Color = Color3.fromRGB(180, 60, 40)
			seat.Parent = seatModel
			seatModel.PrimaryPart = seat

			table.insert(seats, { seat = seat, model = seatModel })
		end
	end

	-- Anchors that StaffService uses to position hired NPCs. Kept invisible
	-- and non-collidable; staff bodies stand near them.
	local cookSpot = spotPart(
		"CookSpot",
		station.Position + Vector3.new(-4, -station.Size.Y / 2 + 1.5, 0),
		root
	)
	local cashierSpot = spotPart(
		"CashierSpot",
		counter.Position + Vector3.new(8, -counter.Size.Y / 2 + 1.5, -2),
		root
	)
	local serverSpot = spotPart(
		"ServerSpot",
		counter.Position + Vector3.new(-8, -counter.Size.Y / 2 + 1.5, 4),
		root
	)
	local cleanerSpot = spotPart(
		"CleanerSpot",
		origin + Vector3.new(-12, floor.Size.Y + 1.5, 14),
		root
	)

	return {
		root = root,
		floor = floor,
		counter = counter,
		counterSpot = counterSpot,
		station = station,
		stationServeSpot = stationServeSpot,
		spawnPad = spawnPad,
		exitPad = exitPad,
		seats = seats,
		staffAnchors = {
			cookSpot = cookSpot,
			cashierSpot = cashierSpot,
			serverSpot = serverSpot,
			cleanerSpot = cleanerSpot,
		},
	}
end

return RestaurantBuilder

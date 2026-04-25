--!strict
--[[
	RestaurantBuilder.luau

	Builds the multi-plot world: a grid of N pre-built shawarma kiosks, one
	per player. Each plot ships with a complete exterior (walls, roof, sign,
	door frame) so the player only ever decorates the interior. The interior
	starts equipped with the bare minimum to play: counter, starter station,
	two tables with seats, customer spawn / exit pads, and four invisible
	staff anchors.

	Returns `{ plots = { Plot, ... } }`. Gameplay services pick a plot by
	`index` (assigned via PlotService) and read its anchors for placement,
	pathing, and customer routing.
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

export type Plot = {
	index: number,
	origin: Vector3,
	root: Folder,
	shellRoot: Folder,
	interiorRoot: Folder,
	floor: BasePart,
	counter: BasePart,
	counterSpot: BasePart,
	station: BasePart,
	stationServeSpot: BasePart,
	spawnPad: BasePart,
	exitPad: BasePart,
	claimPad: BasePart,
	sign: BasePart,
	signLabel: TextLabel,
	-- Sandwich-board out front. Updated with rating + stars + plot owner.
	boardLabel: TextLabel?,
	seats: { SeatRef },
	staffAnchors: { [string]: BasePart },
}

export type World = {
	root: Folder,
	plots: { Plot },
	ground: BasePart,
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

-- Origin of plot `index` in the 4xN grid centred on `Constants.World.Origin`.
function RestaurantBuilder.plotOriginFor(index: number): Vector3
	local perRow = Constants.World.PlotsPerRow
	local row = math.floor((index - 1) / perRow)
	local col = (index - 1) % perRow
	local cx = (col - (perRow - 1) / 2) * Constants.World.PlotSpacingX
	local rows = math.ceil(Constants.World.NumPlots / perRow)
	local cz = (row - (rows - 1) / 2) * Constants.World.PlotSpacingZ
	return Constants.World.Origin + Vector3.new(cx, 0, cz)
end

-- ---------- per-plot builder ----------------------------------------------

local function buildPlot(parent: Folder, index: number): Plot
	local origin = RestaurantBuilder.plotOriginFor(index)
	local interior = Constants.World.PlotInteriorSize
	local shell = Constants.World.PlotShellSize
	local wallH = shell.Y
	local wallT = Constants.World.WallThickness
	local doorWidth = Constants.World.DoorWidth

	local plotRoot = Instance.new("Folder")
	plotRoot.Name = string.format("Plot_%02d", index)
	plotRoot.Parent = parent

	local shellRoot = Instance.new("Folder")
	shellRoot.Name = "Shell"
	shellRoot.Parent = plotRoot

	local interiorRoot = Instance.new("Folder")
	interiorRoot.Name = "Interior"
	interiorRoot.Parent = plotRoot

	-- Floor (interior). Polished dark wood inside, charcoal trim near walls.
	local floor = attach(
		makePart({
			Name = "Floor",
			Size = interior,
			Position = origin + Vector3.new(0, interior.Y / 2, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(60, 45, 35),
		}),
		interiorRoot
	)

	-- ---- exterior shell ------------------------------------------------
	local shellHx = shell.X / 2
	local shellHz = shell.Z / 2
	local wallY = origin.Y + floor.Size.Y + wallH / 2

	local WALL_COLOR = Color3.fromRGB(245, 247, 250)
	local WALL_TRIM_COLOR = Color3.fromRGB(35, 40, 50)
	local GLASS_TINT = Color3.fromRGB(180, 220, 240)

	-- Solid wall panel.
	local function buildWallPanel(name: string, size: Vector3, position: Vector3, parentFolder: Instance, color: Color3?)
		attach(
			makePart({
				Name = name,
				Size = size,
				Position = position,
				Material = Enum.Material.SmoothPlastic,
				Color = color or WALL_COLOR,
			}),
			parentFolder
		)
	end

	-- Glass pane (transparent, no shadow).
	local function buildGlass(name: string, size: Vector3, position: Vector3, parentFolder: Instance)
		attach(
			makePart({
				Name = name,
				Size = size,
				Position = position,
				Material = Enum.Material.Glass,
				Color = GLASS_TINT,
				Transparency = 0.55,
				Reflectance = 0.15,
				CastShadow = false,
			}),
			parentFolder
		)
	end

	-- Window mullion (dark vertical strip between glass panes).
	local function buildMullion(name: string, position: Vector3, height: number, parentFolder: Instance)
		attach(
			makePart({
				Name = name,
				Size = Vector3.new(0.4, height, wallT + 0.1),
				Position = position,
				Material = Enum.Material.Metal,
				Color = WALL_TRIM_COLOR,
			}),
			parentFolder
		)
	end

	-- ----- back wall (solid white) -----
	buildWallPanel(
		"WallBack",
		Vector3.new(shell.X, wallH, wallT),
		origin + Vector3.new(0, wallY, -shellHz),
		shellRoot
	)

	-- ----- left wall: solid lower band + tall glass + solid top band -----
	local solidBandH = 1.2
	local glassH = wallH - solidBandH * 2
	local function buildSideWall(name: string, xSign: number)
		local wx = xSign * shellHx
		buildWallPanel(
			name .. "_Lower",
			Vector3.new(wallT, solidBandH, shell.Z),
			origin + Vector3.new(wx, origin.Y + floor.Size.Y + solidBandH / 2, 0),
			shellRoot
		)
		buildWallPanel(
			name .. "_Upper",
			Vector3.new(wallT, solidBandH, shell.Z),
			origin + Vector3.new(wx, origin.Y + floor.Size.Y + wallH - solidBandH / 2, 0),
			shellRoot
		)
		-- Glass with vertical mullions every ~6 studs.
		local panes = 4
		local paneZ = shell.Z / panes
		for i = 0, panes - 1 do
			local cz = -shell.Z / 2 + paneZ * (i + 0.5)
			buildGlass(
				name .. "_Glass_" .. i,
				Vector3.new(wallT, glassH, paneZ - 0.4),
				origin + Vector3.new(wx, origin.Y + floor.Size.Y + solidBandH + glassH / 2, cz),
				shellRoot
			)
		end
		for i = 0, panes do
			local cz = -shell.Z / 2 + paneZ * i
			buildMullion(
				name .. "_Mullion_" .. i,
				origin + Vector3.new(wx, origin.Y + floor.Size.Y + solidBandH + glassH / 2, cz),
				glassH,
				shellRoot
			)
		end
	end
	buildSideWall("WallLeft", -1)
	buildSideWall("WallRight", 1)

	-- ----- front wall split around door opening (white panels + glass band) -----
	local frontHalf = (shell.X - doorWidth) / 2
	buildWallPanel(
		"WallFrontA_Lower",
		Vector3.new(frontHalf, solidBandH, wallT),
		origin + Vector3.new(-(doorWidth / 2 + frontHalf / 2), origin.Y + floor.Size.Y + solidBandH / 2, shellHz),
		shellRoot
	)
	buildWallPanel(
		"WallFrontB_Lower",
		Vector3.new(frontHalf, solidBandH, wallT),
		origin + Vector3.new((doorWidth / 2 + frontHalf / 2), origin.Y + floor.Size.Y + solidBandH / 2, shellHz),
		shellRoot
	)
	buildWallPanel(
		"WallFrontA_Upper",
		Vector3.new(frontHalf, solidBandH, wallT),
		origin + Vector3.new(-(doorWidth / 2 + frontHalf / 2), origin.Y + floor.Size.Y + wallH - solidBandH / 2, shellHz),
		shellRoot
	)
	buildWallPanel(
		"WallFrontB_Upper",
		Vector3.new(frontHalf, solidBandH, wallT),
		origin + Vector3.new((doorWidth / 2 + frontHalf / 2), origin.Y + floor.Size.Y + wallH - solidBandH / 2, shellHz),
		shellRoot
	)
	-- Front glass between solid bands, on each side of the door.
	buildGlass(
		"WallFrontA_Glass",
		Vector3.new(frontHalf - 0.2, glassH, wallT),
		origin + Vector3.new(-(doorWidth / 2 + frontHalf / 2), origin.Y + floor.Size.Y + solidBandH + glassH / 2, shellHz),
		shellRoot
	)
	buildGlass(
		"WallFrontB_Glass",
		Vector3.new(frontHalf - 0.2, glassH, wallT),
		origin + Vector3.new((doorWidth / 2 + frontHalf / 2), origin.Y + floor.Size.Y + solidBandH + glassH / 2, shellHz),
		shellRoot
	)
	-- Vertical mullions outlining the front glass panes.
	for _, x in ipairs({ -shellHx, -doorWidth / 2 - frontHalf, -doorWidth / 2, doorWidth / 2, doorWidth / 2 + frontHalf, shellHx }) do
		buildMullion(
			"FrontMullion_" .. tostring(x),
			origin + Vector3.new(x, origin.Y + floor.Size.Y + solidBandH + glassH / 2, shellHz),
			glassH,
			shellRoot
		)
	end

	-- Door header lintel above the gap so the front isn't open at the top.
	local lintelHeight = solidBandH
	buildWallPanel(
		"DoorLintel",
		Vector3.new(doorWidth, lintelHeight, wallT),
		origin + Vector3.new(0, origin.Y + floor.Size.Y + wallH - lintelHeight / 2, shellHz),
		shellRoot
	)

	-- Door panel (dark accent, half-height).
	attach(
		makePart({
			Name = "Door",
			Size = Vector3.new(doorWidth - 0.4, wallH - lintelHeight - 0.2, 0.3),
			Position = origin + Vector3.new(0, origin.Y + floor.Size.Y + (wallH - lintelHeight) / 2, shellHz - 0.2),
			Material = Enum.Material.Glass,
			Color = GLASS_TINT,
			Transparency = 0.5,
			Reflectance = 0.15,
			CastShadow = false,
		}),
		shellRoot
	)
	-- Door frame trim.
	attach(
		makePart({
			Name = "DoorFrame",
			Size = Vector3.new(doorWidth + 0.4, 0.4, 0.4),
			Position = origin + Vector3.new(0, origin.Y + floor.Size.Y + wallH - lintelHeight - 0.2, shellHz - 0.4),
			Material = Enum.Material.Metal,
			Color = WALL_TRIM_COLOR,
		}),
		shellRoot
	)

	-- Roof: white slab with a dark trim band along the front edge.
	local roofThick = 0.6
	attach(
		makePart({
			Name = "Roof",
			Size = Vector3.new(shell.X, roofThick, shell.Z),
			Position = origin + Vector3.new(0, origin.Y + floor.Size.Y + wallH + roofThick / 2, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = WALL_COLOR,
		}),
		shellRoot
	)
	attach(
		makePart({
			Name = "RoofTrim",
			Size = Vector3.new(shell.X + 0.4, 1.2, 0.4),
			Position = origin + Vector3.new(0, origin.Y + floor.Size.Y + wallH + 0.2, shellHz),
			Material = Enum.Material.Metal,
			Color = WALL_TRIM_COLOR,
		}),
		shellRoot
	)

	-- Awning over the door — flat white extension with a dark underside.
	local awning = attach(
		makePart({
			Name = "Awning",
			Size = Vector3.new(shell.X * 0.55, 0.5, 5),
			Position = origin + Vector3.new(0, origin.Y + floor.Size.Y + wallH - 0.5, shellHz + 2.6),
			Material = Enum.Material.SmoothPlastic,
			Color = WALL_COLOR,
		}),
		shellRoot
	)
	attach(
		makePart({
			Name = "AwningTrim",
			Size = Vector3.new(shell.X * 0.55, 0.2, 5),
			Position = awning.Position - Vector3.new(0, 0.4, 0),
			Material = Enum.Material.Metal,
			Color = WALL_TRIM_COLOR,
		}),
		shellRoot
	)

	-- Sign above the awning — a slim modern marquee across the storefront.
	local sign = attach(
		makePart({
			Name = "Sign",
			Size = Vector3.new(shell.X * 0.65, 2.4, 0.4),
			Position = origin + Vector3.new(0, origin.Y + floor.Size.Y + wallH + 2.0, shellHz + 0.2),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(20, 25, 35),
		}),
		shellRoot
	)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SignSurface"
	surface.Face = Enum.NormalId.Front
	surface.Adornee = sign
	surface.LightInfluence = 0
	surface.AlwaysOnTop = false
	surface.Parent = sign

	local signLabel = Instance.new("TextLabel")
	signLabel.Name = "Label"
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.TextScaled = true
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextColor3 = Color3.fromRGB(255, 230, 170)
	signLabel.Text = string.format("Plot %02d  ·  AVAILABLE", index)
	signLabel.Parent = surface

	-- ---- sandwich-board out front ---------------------------------------
	-- Wood-look A-frame with rating + plot owner. Mirrors the RT3 reference.
	local boardX = origin.X + Constants.World.PlotShellSize.X * 0.45
	local boardZ = origin.Z + shellHz + Constants.World.SpawnPadOffset - 2
	local boardBase = attach(
		makePart({
			Name = "Sandwich",
			Size = Vector3.new(4.2, 0.3, 2.2),
			Position = Vector3.new(boardX, origin.Y + floor.Size.Y + 0.15, boardZ),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(85, 55, 35),
		}),
		shellRoot
	)
	local boardPanel = attach(
		makePart({
			Name = "SandwichPanel",
			Size = Vector3.new(4, 4, 0.3),
			Position = boardBase.Position + Vector3.new(0, 2.1, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(30, 30, 35),
			Orientation = Vector3.new(0, 0, 0),
		}),
		shellRoot
	)
	local boardSurface = Instance.new("SurfaceGui")
	boardSurface.Name = "BoardSurface"
	boardSurface.Face = Enum.NormalId.Front
	boardSurface.Adornee = boardPanel
	boardSurface.LightInfluence = 0
	boardSurface.PixelsPerStud = 50
	boardSurface.Parent = boardPanel
	local boardLabel = Instance.new("TextLabel")
	boardLabel.Name = "Label"
	boardLabel.Size = UDim2.new(1, -8, 1, -8)
	boardLabel.Position = UDim2.new(0, 4, 0, 4)
	boardLabel.BackgroundTransparency = 1
	boardLabel.TextScaled = true
	boardLabel.Font = Enum.Font.GothamBold
	boardLabel.TextColor3 = Color3.fromRGB(245, 230, 200)
	boardLabel.TextWrapped = true
	boardLabel.Text = string.format("Plot %02d\n☆ ☆ ☆ ☆ ☆\nAvailable", index)
	boardLabel.Parent = boardSurface

	-- ---- interior fixtures --------------------------------------------
	local counter = attach(
		makePart({
			Name = "Counter",
			Size = Vector3.new(18, 4, 2),
			Position = origin + Vector3.new(0, floor.Size.Y + 2, -6),
			Material = Enum.Material.Marble,
			Color = Color3.fromRGB(85, 60, 40),
		}),
		interiorRoot
	)
	local station = attach(
		makePart({
			Name = "CookingStation",
			Size = Vector3.new(6, 5, 4),
			Position = origin + Vector3.new(0, floor.Size.Y + 2.5, -14),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(160, 70, 40),
		}),
		interiorRoot
	)
	local stationServeSpot = spotPart(
		"StationServeSpot",
		station.Position + Vector3.new(0, -station.Size.Y / 2 + 1.5, 6),
		interiorRoot
	)
	local counterSpot = spotPart(
		"CounterSpot",
		counter.Position + Vector3.new(0, -counter.Size.Y / 2 + 1.5, 4),
		interiorRoot
	)

	-- Spawn / exit pads outside the door (in front of plot).
	local spawnPad = spotPart(
		"SpawnPad",
		origin + Vector3.new(-3, floor.Size.Y + 1.5, shellHz + Constants.World.SpawnPadOffset),
		plotRoot
	)
	local exitPad = spotPart(
		"ExitPad",
		origin + Vector3.new(3, floor.Size.Y + 1.5, shellHz + Constants.World.SpawnPadOffset + 4),
		plotRoot
	)

	-- Claim pad: a small glowing tile a player walks onto to claim the plot.
	local claimPad = attach(
		makePart({
			Name = "ClaimPad",
			Size = Vector3.new(6, 0.5, 6),
			Position = origin + Vector3.new(0, floor.Size.Y + 0.25, shellHz + Constants.World.SpawnPadOffset),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 200, 100),
			Transparency = 0.2,
			CanCollide = false,
			CanTouch = true,
		}),
		plotRoot
	)
	local claimGui = Instance.new("BillboardGui")
	claimGui.Name = "ClaimGui"
	claimGui.Adornee = claimPad
	claimGui.Size = UDim2.new(0, 200, 0, 60)
	claimGui.StudsOffset = Vector3.new(0, 4, 0)
	claimGui.AlwaysOnTop = true
	claimGui.Parent = claimPad
	local claimLabel = Instance.new("TextLabel")
	claimLabel.Size = UDim2.new(1, 0, 1, 0)
	claimLabel.BackgroundTransparency = 1
	claimLabel.Text = "Step here to claim"
	claimLabel.TextColor3 = Color3.new(1, 1, 1)
	claimLabel.TextStrokeTransparency = 0.2
	claimLabel.Font = Enum.Font.GothamBold
	claimLabel.TextSize = 22
	claimLabel.Parent = claimGui

	-- Tables.
	local seats: { SeatRef } = {}
	local tableCount = Constants.World.NumStarterTables
	local seatsPerTable = Constants.World.SeatsPerTable
	for tableIndex = 1, tableCount do
		local tableX = -8 + (tableIndex - 1) * 16
		local tablePos = origin + Vector3.new(tableX, floor.Size.Y + 1.5, 8)
		local tableTop = attach(
			makePart({
				Name = "Table_" .. tableIndex,
				Size = Vector3.new(5, 0.4, 5),
				Position = tablePos,
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(95, 65, 35),
			}),
			interiorRoot
		)
		attach(
			makePart({
				Name = "TableLeg_" .. tableIndex,
				Size = Vector3.new(0.6, 1.4, 0.6),
				Position = tableTop.Position - Vector3.new(0, 0.9, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(40, 40, 40),
			}),
			interiorRoot
		)

		for seatIndex = 1, seatsPerTable do
			local seatModel = Instance.new("Model")
			seatModel.Name = string.format("SeatModel_T%d_S%d", tableIndex, seatIndex)
			seatModel.Parent = interiorRoot

			local angle = (seatIndex - 1) * (2 * math.pi / seatsPerTable)
			local offset = Vector3.new(math.sin(angle) * 3.5, -0.5, math.cos(angle) * 3.5)
			local seatBase = attach(
				makePart({
					Name = "Base",
					Size = Vector3.new(1.4, 0.4, 1.4),
					Position = tableTop.Position + offset,
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

	-- Staff anchors.
	local cookSpot = spotPart(
		"CookSpot",
		station.Position + Vector3.new(-4, -station.Size.Y / 2 + 1.5, 0),
		interiorRoot
	)
	local cashierSpot = spotPart(
		"CashierSpot",
		counter.Position + Vector3.new(8, -counter.Size.Y / 2 + 1.5, -2),
		interiorRoot
	)
	local serverSpot = spotPart(
		"ServerSpot",
		counter.Position + Vector3.new(-8, -counter.Size.Y / 2 + 1.5, 4),
		interiorRoot
	)
	local cleanerSpot = spotPart(
		"CleanerSpot",
		origin + Vector3.new(-12, floor.Size.Y + 1.5, 14),
		interiorRoot
	)

	-- Warm interior ceiling lights so the inside doesn't look flat.
	local function ceilingLight(xOffset: number, zOffset: number)
		local fixture = attach(
			makePart({
				Name = "Light",
				Size = Vector3.new(2, 0.2, 2),
				Position = origin + Vector3.new(xOffset, origin.Y + floor.Size.Y + wallH - 0.2, zOffset),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 245, 220),
				CastShadow = false,
			}),
			interiorRoot
		)
		local pl = Instance.new("PointLight")
		pl.Name = "Glow"
		pl.Color = Color3.fromRGB(255, 230, 190)
		pl.Brightness = 1.6
		pl.Range = 18
		pl.Shadows = false
		pl.Parent = fixture
	end
	ceilingLight(-12, -10)
	ceilingLight(12, -10)
	ceilingLight(-12, 10)
	ceilingLight(12, 10)

	return {
		index = index,
		origin = origin,
		root = plotRoot,
		shellRoot = shellRoot,
		interiorRoot = interiorRoot,
		floor = floor,
		counter = counter,
		counterSpot = counterSpot,
		station = station,
		stationServeSpot = stationServeSpot,
		spawnPad = spawnPad,
		exitPad = exitPad,
		claimPad = claimPad,
		sign = sign,
		signLabel = signLabel,
		boardLabel = boardLabel,
		seats = seats,
		staffAnchors = {
			cookSpot = cookSpot,
			cashierSpot = cashierSpot,
			serverSpot = serverSpot,
			cleanerSpot = cleanerSpot,
		},
	}
end

-- ---------- main build -----------------------------------------------------

function RestaurantBuilder.build(): World
	local root = Workspace:FindFirstChild("ShawermaTycoonWorld")
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "ShawermaTycoonWorld"
	root.Parent = Workspace

	-- A large ground plate so plots have something to sit on. Darker, more
	-- saturated grass tone reads as park-grass in the night-time lighting.
	local perRow = Constants.World.PlotsPerRow
	local rows = math.ceil(Constants.World.NumPlots / perRow)
	local groundX = perRow * Constants.World.PlotSpacingX + 80
	local groundZ = rows * Constants.World.PlotSpacingZ + 80
	local ground = attach(
		makePart({
			Name = "Ground",
			Size = Vector3.new(groundX, 1, groundZ),
			Position = Constants.World.Origin - Vector3.new(0, 0.5, 0),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(55, 90, 55),
		}),
		root
	)

	local Environment = require(script.Parent:WaitForChild("Environment"))
	Environment.build(root)

	local plots: { Plot } = {}
	for i = 1, Constants.World.NumPlots do
		table.insert(plots, buildPlot(root, i))
	end

	return {
		root = root,
		ground = ground,
		plots = plots,
	}
end

return RestaurantBuilder

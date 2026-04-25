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
	-- Plot model (so the whole plot can be rotated 180° for the front row).
	root: Model,
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
	-- 1 for back row (door faces +Z), -1 for front row (door faces -Z).
	facing: number,
}

export type World = {
	root: Folder,
	plots: { Plot },
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

	local plotRoot = Instance.new("Model")
	plotRoot.Name = string.format("Plot_%02d", index)
	plotRoot.Parent = parent

	local shellRoot = Instance.new("Folder")
	shellRoot.Name = "Shell"
	shellRoot.Parent = plotRoot

	local interiorRoot = Instance.new("Folder")
	interiorRoot.Name = "Interior"
	interiorRoot.Parent = plotRoot

	-- Floor. Sized to the inner face of the shell walls (shell minus
	-- one wall thickness on each side) so there's no visible gap between
	-- the floor and the walls. Build-mode placement still uses the
	-- smaller PlotInteriorSize as bounds. Polished dark wood. Acts as
	-- the plot Model's PrimaryPart so the whole plot can be rotated 180°
	-- via Model:PivotTo() (used for the front row of plots so they face
	-- the road).
	local floorSize = Vector3.new(shell.X - wallT, interior.Y, shell.Z - wallT)
	local floor = attach(
		makePart({
			Name = "Floor",
			Size = floorSize,
			Position = origin + Vector3.new(0, floorSize.Y / 2, 0),
			-- Polished concrete with a faint warm tint reads as a
			-- contemporary commercial-kitchen / café floor without
			-- repeating the wood-plank tile pattern.
			Material = Enum.Material.Concrete,
			Color = Color3.fromRGB(72, 70, 68),
		}),
		interiorRoot
	)
	plotRoot.PrimaryPart = floor

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

	-- Door panel: a glass slab that the player can walk through. Visually
	-- there's a door, but CanCollide=false so the doorway is a real opening.
	attach(
		makePart({
			Name = "Door",
			Size = Vector3.new(doorWidth - 0.4, wallH - lintelHeight - 0.2, 0.2),
			Position = origin + Vector3.new(0, origin.Y + floor.Size.Y + (wallH - lintelHeight) / 2, shellHz - 0.2),
			Material = Enum.Material.Glass,
			Color = GLASS_TINT,
			Transparency = 0.5,
			Reflectance = 0.15,
			CastShadow = false,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
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
	-- Modern service counter: dark cabinet body + light marble top + thin
	-- brass trim along the customer-facing edge. Same overall footprint
	-- as before so all the existing spot offsets still line up.
	local counterBody = attach(
		makePart({
			Name = "Counter",
			Size = Vector3.new(18, 3.6, 2),
			Position = origin + Vector3.new(0, floor.Size.Y + 1.8, -6),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(34, 38, 48),
		}),
		interiorRoot
	)
	attach(
		makePart({
			Name = "CounterSlab",
			Size = Vector3.new(18.2, 0.35, 2.2),
			Position = origin + Vector3.new(0, floor.Size.Y + 3.78, -6),
			Material = Enum.Material.Marble,
			Color = Color3.fromRGB(232, 230, 224),
		}),
		interiorRoot
	)
	attach(
		makePart({
			Name = "CounterTrim",
			Size = Vector3.new(18.05, 0.08, 0.08),
			Position = origin + Vector3.new(0, floor.Size.Y + 3.6, -6 + 1.05),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(195, 145, 70),
		}),
		interiorRoot
	)
	local counter = counterBody
	-- ---- cooking station: brushed-steel kitchen with rotisserie ---------
	-- Designed to read as a real shawarma kitchen rather than a coloured
	-- block. Body + top cooktop with two glowing burners + tall vertical
	-- rotisserie spit on the side + dark extractor hood floating above.
	-- The `station` Part itself (the stove body) is what StationService
	-- uses as the anchor for ProximityPrompt and state.
	-- Station coords in world space, derived from plot origin so each
	-- plot's stove sits inside its own shell. The plot Model is rotated
	-- 180° via PivotTo() for the front row; all child parts rotate
	-- together, so we keep these as the pre-rotation positions.
	local stationBaseY = origin.Y + floor.Size.Y
	local stationCx = origin.X
	local stationCz = origin.Z - 14
	local STEEL_BODY_COLOR = Color3.fromRGB(190, 195, 205)
	local STEEL_DARK_COLOR = Color3.fromRGB(50, 55, 65)

	local station = attach(
		makePart({
			Name = "CookingStation",
			Size = Vector3.new(10, 3.4, 3.4),
			Position = Vector3.new(stationCx, stationBaseY + 1.7, stationCz),
			Material = Enum.Material.Metal,
			Color = STEEL_BODY_COLOR,
			Reflectance = 0.05,
		}),
		interiorRoot
	)
	-- Cooktop slab on top.
	local cooktop = attach(
		makePart({
			Name = "Cooktop",
			Size = Vector3.new(10, 0.2, 3.4),
			Position = Vector3.new(stationCx, stationBaseY + 3.4 + 0.1, stationCz),
			Material = Enum.Material.Metal,
			Color = STEEL_DARK_COLOR,
			Reflectance = 0.1,
		}),
		interiorRoot
	)
	-- Two glowing burners sunk into the cooktop.
	for i, off in ipairs({ -2.4, 2.4 }) do
		local burner = makePart({
			Name = "Burner_" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, 1.4, 1.4),
			Position = Vector3.new(stationCx + off, cooktop.Position.Y + 0.1, stationCz),
			Orientation = Vector3.new(0, 0, 90),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 130, 60),
		})
		burner.Parent = interiorRoot
		local glow = Instance.new("PointLight")
		glow.Brightness = 1.2
		glow.Range = 8
		glow.Color = Color3.fromRGB(255, 160, 90)
		glow.Parent = burner
	end
	-- Stainless prep slab between the burners (where the wrap is built).
	attach(
		makePart({
			Name = "PrepSlab",
			Size = Vector3.new(2.6, 0.2, 2.4),
			Position = Vector3.new(stationCx, cooktop.Position.Y + 0.15, stationCz),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(225, 225, 230),
			Reflectance = 0.2,
		}),
		interiorRoot
	)
	-- Three decorative knobs along the front face.
	for i = 1, 3 do
		attach(
			makePart({
				Name = "Knob_" .. i,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, 0.4, 0.4),
				Position = Vector3.new(stationCx - 1.6 + (i - 1) * 1.6, stationBaseY + 0.8, stationCz + 1.7 + 0.1),
				Orientation = Vector3.new(0, 0, 90),
				Material = Enum.Material.Metal,
				Color = STEEL_DARK_COLOR,
			}),
			interiorRoot
		)
	end
	-- Vertical rotisserie spit (the iconic shawarma column) to the right.
	local spitX = stationCx + 5.6
	attach(
		makePart({
			Name = "RotisserieBase",
			Size = Vector3.new(2.4, 0.6, 2.4),
			Position = Vector3.new(spitX, stationBaseY + 0.3, stationCz),
			Material = Enum.Material.Metal,
			Color = STEEL_DARK_COLOR,
		}),
		interiorRoot
	)
	-- Heat element (thin neon strip behind the meat column).
	attach(
		makePart({
			Name = "RotisserieHeat",
			Size = Vector3.new(0.3, 4.5, 1.6),
			Position = Vector3.new(spitX + 0.9, stationBaseY + 3.2, stationCz),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 90, 50),
		}),
		interiorRoot
	)
	-- Meat column (stacked layers of roasted-meat brown).
	for i = 1, 4 do
		attach(
			makePart({
				Name = "MeatLayer_" .. i,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.95, 1.4 - (i - 1) * 0.1, 1.4 - (i - 1) * 0.1),
				Position = Vector3.new(spitX, stationBaseY + 1.2 + (i - 1) * 0.95, stationCz),
				Orientation = Vector3.new(0, 0, 90),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(120 - i * 6, 60 - i * 4, 32),
			}),
			interiorRoot
		)
	end
	-- Spit rod sticking out the top.
	attach(
		makePart({
			Name = "SpitRod",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.18, 6, 0.18),
			Position = Vector3.new(spitX, stationBaseY + 3.2, stationCz),
			Orientation = Vector3.new(0, 0, 90),
			Material = Enum.Material.Metal,
			Color = STEEL_DARK_COLOR,
		}),
		interiorRoot
	)
	-- Extractor hood floating above the cooktop.
	attach(
		makePart({
			Name = "Hood",
			Size = Vector3.new(11, 1.2, 3.6),
			Position = Vector3.new(stationCx, stationBaseY + 7.5, stationCz - 0.1),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(70, 75, 85),
			Reflectance = 0.08,
		}),
		interiorRoot
	)
	-- Hood sloped front (just a thinner block to suggest the angle).
	attach(
		makePart({
			Name = "HoodLip",
			Size = Vector3.new(11, 0.4, 0.6),
			Position = Vector3.new(stationCx, stationBaseY + 6.7, stationCz + 1.7),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 65, 75),
		}),
		interiorRoot
	)
	-- Tall vent pipe rising into the ceiling.
	attach(
		makePart({
			Name = "HoodVent",
			Size = Vector3.new(1.4, 4.4, 1.4),
			Position = Vector3.new(stationCx, stationBaseY + 10.3, stationCz - 0.4),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 65, 75),
		}),
		interiorRoot
	)

	local stationServeSpot = spotPart(
		"StationServeSpot",
		Vector3.new(stationCx, stationBaseY + 1.5, stationCz + 4.2),
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

	-- Claim pad: kept as a visual marker so unowned plots are obvious from
	-- the camera preview, but the actual claiming is done from the UI now
	-- (no "Step here to claim" prompt in-world).
	local claimPad = attach(
		makePart({
			Name = "ClaimPad",
			Size = Vector3.new(6, 0.5, 6),
			Position = origin + Vector3.new(0, floor.Size.Y + 0.25, shellHz + Constants.World.SpawnPadOffset),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 200, 100),
			Transparency = 0.4,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
		}),
		plotRoot
	)

	-- Tables.
	local seats: { SeatRef } = {}
	local tableCount = Constants.World.NumStarterTables
	local seatsPerTable = Constants.World.SeatsPerTable
	for tableIndex = 1, tableCount do
		local tableX = -8 + (tableIndex - 1) * 16
		local tablePos = origin + Vector3.new(tableX, floor.Size.Y + 1.5, 8)
		-- Modern bistro table: white marble top + brass trim + chrome
		-- pedestal with foot disc.
		local tableTop = attach(
			makePart({
				Name = "Table_" .. tableIndex,
				Size = Vector3.new(5, 0.3, 5),
				Position = tablePos,
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(232, 230, 224),
			}),
			interiorRoot
		)
		attach(
			makePart({
				Name = "TableTrim_" .. tableIndex,
				Size = Vector3.new(5.04, 0.05, 5.04),
				Position = tableTop.Position - Vector3.new(0, 0.15, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(195, 145, 70),
			}),
			interiorRoot
		)
		attach(
			makePart({
				Name = "TableLeg_" .. tableIndex,
				Size = Vector3.new(0.5, 1.4, 0.5),
				Position = tableTop.Position - Vector3.new(0, 0.85, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(200, 200, 205),
			}),
			interiorRoot
		)
		attach(
			makePart({
				Name = "TableFoot_" .. tableIndex,
				Size = Vector3.new(2.0, 0.15, 2.0),
				Shape = Enum.PartType.Cylinder,
				Orientation = Vector3.new(0, 0, 90),
				Position = tableTop.Position - Vector3.new(0, 1.55, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(180, 180, 188),
			}),
			interiorRoot
		)

		for seatIndex = 1, seatsPerTable do
			local seatModel = Instance.new("Model")
			seatModel.Name = string.format("SeatModel_T%d_S%d", tableIndex, seatIndex)
			seatModel.Parent = interiorRoot

			local angle = (seatIndex - 1) * (2 * math.pi / seatsPerTable)
			-- Place chairs slightly farther out so customers don't clip
			-- into the table when Seat:Sit aligns them.
			local offset = Vector3.new(math.sin(angle) * 4.0, -0.45, math.cos(angle) * 4.0)
			-- Modern padded chair: dark teal cushion, chrome rails,
			-- upholstered backrest oriented toward the table.
			local backOffset = -Vector3.new(math.sin(angle), 0, math.cos(angle))
			local cushion = attach(
				makePart({
					Name = "Cushion",
					Size = Vector3.new(1.4, 0.25, 1.4),
					Position = tableTop.Position + offset + Vector3.new(0, 0.25, 0),
					Material = Enum.Material.Fabric,
					Color = Color3.fromRGB(38, 60, 78),
				}),
				seatModel
			)
			-- Back oriented away from the table (so customer faces table).
			attach(
				makePart({
					Name = "Back",
					Size = Vector3.new(1.4, 1.4, 0.18),
					Position = cushion.Position + Vector3.new(0, 0.85, 0) + backOffset * 0.6,
					Material = Enum.Material.Fabric,
					Color = Color3.fromRGB(38, 60, 78),
					Orientation = Vector3.new(0, math.deg(angle), 0),
				}),
				seatModel
			)
			local function rail(xOff: number)
				attach(
					makePart({
						Name = "Rail",
						Size = Vector3.new(0.15, 1.0, 1.4),
						Position = cushion.Position - Vector3.new(0, 0.625, 0) + Vector3.new(xOff, 0, 0),
						Material = Enum.Material.Metal,
						Color = Color3.fromRGB(210, 210, 215),
					}),
					seatModel
				)
			end
			rail(0.55)
			rail(-0.55)
			local seat = Instance.new("Seat")
			seat.Name = "Seat"
			seat.Anchored = true
			seat.Size = Vector3.new(1.2, 0.05, 1.2)
			seat.Position = cushion.Position + Vector3.new(0, 0.15, 0)
			seat.TopSurface = Enum.SurfaceType.Smooth
			seat.Material = Enum.Material.Fabric
			seat.Color = Color3.fromRGB(38, 60, 78)
			seat.Transparency = 1
			-- Face the table so customers Sit() oriented inward.
			local lookTowardTable = (tableTop.Position - seat.Position).Unit
			seat.CFrame = CFrame.lookAt(seat.Position, seat.Position + Vector3.new(lookTowardTable.X, 0, lookTowardTable.Z))
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

	-- ---- modern interior decor -----------------------------------------
	-- Dark accent panel on the back wall (behind the cooking station)
	-- breaks up the all-white shell so the interior reads as a deliberate
	-- modern restaurant rather than an empty box.
	local insideZ = origin.Z - shellHz + wallT / 2 + 0.05
	attach(
		makePart({
			Name = "BackAccentPanel",
			Size = Vector3.new(shell.X - 4, wallH - 2.5, 0.2),
			Position = Vector3.new(origin.X, origin.Y + floor.Size.Y + (wallH - 2.5) / 2 + 1.2, insideZ),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(34, 38, 48),
			CastShadow = false,
		}),
		interiorRoot
	)
	-- Brass-coloured horizontal strip across the accent panel.
	attach(
		makePart({
			Name = "BackAccentTrim",
			Size = Vector3.new(shell.X - 4, 0.3, 0.25),
			Position = Vector3.new(origin.X, origin.Y + floor.Size.Y + wallH - 4, insideZ + 0.05),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(195, 145, 70),
			CastShadow = false,
		}),
		interiorRoot
	)
	-- Skirting / baseboard around the inside perimeter (just a dark band
	-- where the floor meets the walls — instantly looks more finished).
	local skirtH = 0.6
	local function skirt(name: string, size: Vector3, pos: Vector3)
		attach(
			makePart({
				Name = name,
				Size = size,
				Position = pos,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(28, 30, 38),
				CastShadow = false,
			}),
			interiorRoot
		)
	end
	skirt(
		"SkirtBack",
		Vector3.new(shell.X - 0.4, skirtH, 0.2),
		Vector3.new(origin.X, origin.Y + floor.Size.Y + skirtH / 2, insideZ)
	)
	skirt(
		"SkirtLeft",
		Vector3.new(0.2, skirtH, shell.Z - 0.4),
		Vector3.new(origin.X - shellHx + wallT / 2 + 0.05, origin.Y + floor.Size.Y + skirtH / 2, origin.Z)
	)
	skirt(
		"SkirtRight",
		Vector3.new(0.2, skirtH, shell.Z - 0.4),
		Vector3.new(origin.X + shellHx - wallT / 2 - 0.05, origin.Y + floor.Size.Y + skirtH / 2, origin.Z)
	)

	-- Front row of the grid (row 1 in the 4×2 layout) gets rotated 180°
	-- around the floor's Y-centre so its door faces the road in the
	-- middle. Model:PivotTo updates the CFrame of every descendant Part
	-- (welds, BillboardGuis, etc. are preserved automatically).
	local perRow = Constants.World.PlotsPerRow
	local row = math.floor((index - 1) / perRow)
	local facing = (row == 0) and 1 or -1
	if facing == -1 then
		plotRoot:PivotTo(floor.CFrame * CFrame.Angles(0, math.pi, 0))
	end

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
		facing = facing,
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

	-- Remove Studio's default Baseplate / SpawnLocation if they were
	-- still in the place. Otherwise they sit at Y=0 with Material=Grass
	-- and z-fight with our flat green ground (the "flickering tiles"
	-- the user saw when moving the camera).
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local stale = Workspace:FindFirstChild(name)
		if stale then
			stale:Destroy()
		end
	end

	-- Environment.build creates the single source of truth for the
	-- ground plane (a flat solid-colour SmoothPlastic plate at Y=0).
	-- We don't add a second ground here on purpose — the previous build
	-- did, and the two planes at the same Y caused brutal z-fighting.
	local Environment = require(script.Parent:WaitForChild("Environment"))
	Environment.build(root)

	local plots: { Plot } = {}
	for i = 1, Constants.World.NumPlots do
		table.insert(plots, buildPlot(root, i))
	end

	return {
		root = root,
		plots = plots,
	}
end

return RestaurantBuilder

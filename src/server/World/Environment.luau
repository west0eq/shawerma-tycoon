--!strict
--[[
	Environment.luau

	Builds the surrounding scenery for the plot grid:

	  - Road running through the middle of the grid (between the two rows
	    of plots, which face each other across it).
	  - Concrete sidewalks bracketing the road and along the back of each
	    row.
	  - Per-plot concrete walkway from each plot's door to the road
	    sidewalk.
	  - Procedurally scattered trees, bushes, and rocks avoiding plot
	    footprints.
	  - Street lamps lining both sidewalks (front and back), so the world
	    is readable at dusk.

	Pure procedural — no Studio assets. Build is keyed off Constants.World
	so plot grid changes flow through automatically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local Environment = {}

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

-- A bigger, fuller tree silhouette: chunkier trunk, 5 leaf-balls in a
-- vaguely conical canopy. Procedural variation per tree.
local function buildTree(parent: Folder, position: Vector3, rng: Random)
	local tree = Instance.new("Model")
	tree.Name = "Tree"
	tree.Parent = parent

	local trunkH = rng:NextNumber(11, 15)
	local trunkR = rng:NextNumber(1.6, 2.4)
	local trunk = makePart({
		Name = "Trunk",
		Size = Vector3.new(trunkR, trunkH, trunkR),
		Position = position + Vector3.new(0, trunkH / 2, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(75, 50, 35),
	})
	trunk.Parent = tree

	local foliageColor = Color3.fromRGB(
		50 + rng:NextInteger(-10, 15),
		120 + rng:NextInteger(-15, 25),
		55 + rng:NextInteger(-10, 15)
	)
	local function leafBall(yOffset: number, size: number, xJitter: number, zJitter: number)
		local b = makePart({
			Name = "Foliage",
			Size = Vector3.new(size, size * 0.9, size),
			Shape = Enum.PartType.Ball,
			Position = position + Vector3.new(xJitter, trunkH + yOffset, zJitter),
			Material = Enum.Material.Grass,
			Color = foliageColor,
		})
		b.Parent = tree
	end
	leafBall(0, 9, 0, 0)
	leafBall(2.5, 7, 1.5, -1.0)
	leafBall(2.5, 7, -1.5, 1.0)
	leafBall(-1.5, 7, 1.0, 1.0)
	leafBall(-1.5, 7, -1.0, -1.0)
	leafBall(4.5, 5.5, 0, 0)

	tree.PrimaryPart = trunk
end

-- Low rounded bush — 3 squat spheres clustered together.
local function buildBush(parent: Folder, position: Vector3, rng: Random)
	local bush = Instance.new("Model")
	bush.Name = "Bush"
	bush.Parent = parent

	local color = Color3.fromRGB(
		45 + rng:NextInteger(-10, 15),
		115 + rng:NextInteger(-15, 25),
		50 + rng:NextInteger(-10, 10)
	)
	local function ball(offset: Vector3, size: number)
		local b = makePart({
			Name = "BushPart",
			Size = Vector3.new(size, size * 0.8, size),
			Shape = Enum.PartType.Ball,
			Position = position + offset,
			Material = Enum.Material.Grass,
			Color = color,
		})
		b.Parent = bush
	end
	ball(Vector3.new(0, 1.5, 0), 4.5)
	ball(Vector3.new(2, 1.2, 0.5), 3.5)
	ball(Vector3.new(-1.5, 1.2, -1), 3.5)
end

-- Cluster of grey rocks. 1–3 spheres of varying size in a tight cluster.
local function buildRockCluster(parent: Folder, position: Vector3, rng: Random)
	local rocks = Instance.new("Model")
	rocks.Name = "Rocks"
	rocks.Parent = parent

	local count = rng:NextInteger(1, 3)
	local baseGrey = 110 + rng:NextInteger(-15, 25)
	for i = 1, count do
		local size = rng:NextNumber(2.5, 4.5)
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(0, 2.2)
		local rock = makePart({
			Name = "Rock",
			Size = Vector3.new(size, size * 0.7, size * 0.9),
			Shape = Enum.PartType.Ball,
			Position = position + Vector3.new(math.cos(angle) * dist, size * 0.3, math.sin(angle) * dist),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(baseGrey, baseGrey, baseGrey + 5),
		})
		rock.Parent = rocks
		if i == 1 then
			rocks.PrimaryPart = rock
		end
	end
end

local function buildLamp(parent: Folder, position: Vector3, armDirection: number)
	local lamp = Instance.new("Model")
	lamp.Name = "StreetLamp"
	lamp.Parent = parent

	local pole = makePart({
		Name = "Pole",
		Size = Vector3.new(0.5, 14, 0.5),
		Position = position + Vector3.new(0, 7, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(45, 45, 50),
	})
	pole.Parent = lamp

	local arm = makePart({
		Name = "Arm",
		Size = Vector3.new(0.4, 0.4, 2.6),
		Position = position + Vector3.new(0, 13.4, armDirection * 1.3),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(45, 45, 50),
	})
	arm.Parent = lamp

	local bulb = makePart({
		Name = "Bulb",
		Size = Vector3.new(1.2, 0.6, 1.2),
		Position = position + Vector3.new(0, 13, armDirection * 2.4),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 230, 180),
	})
	bulb.Parent = lamp

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Range = 32
	light.Brightness = 2.4
	light.Shadows = true
	light.Parent = bulb

	lamp.PrimaryPart = pole
end

local function buildSidewalkBlock(parent: Folder, position: Vector3, size: Vector3)
	local block = makePart({
		Name = "Sidewalk",
		Size = size,
		Position = position,
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(195, 195, 200),
	})
	block.Parent = parent
end

local function buildRoadSegment(parent: Folder, centre: Vector3, length: number, width: number)
	local road = makePart({
		Name = "Road",
		Size = Vector3.new(length, 0.3, width),
		Position = centre + Vector3.new(0, 0.15, 0),
		Material = Enum.Material.Asphalt,
		Color = Color3.fromRGB(45, 45, 50),
	})
	road.Parent = parent

	-- Dashed centre line.
	local dashLen = 6
	local dashGap = 6
	local stripWidth = 0.6
	local x = -length / 2 + dashLen / 2
	while x <= length / 2 - dashLen / 2 do
		local stripe = makePart({
			Name = "Stripe",
			Size = Vector3.new(dashLen, 0.31, stripWidth),
			Position = centre + Vector3.new(x, 0.16, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(245, 230, 120),
		})
		stripe.Parent = parent
		x += dashLen + dashGap
	end
end

-- The grid is centred on Constants.World.Origin. Two rows of plots face
-- each other across the road, which runs along Z=0.
function Environment.build(parent: Folder)
	local rng = Random.new(8675309)

	local sceneryRoot = Instance.new("Folder")
	sceneryRoot.Name = "Environment"
	sceneryRoot.Parent = parent

	local perRow = Constants.World.PlotsPerRow
	local rows = math.ceil(Constants.World.NumPlots / perRow)
	local gridWidth = perRow * Constants.World.PlotSpacingX
	local plotShellHalfZ = Constants.World.PlotShellSize.Z / 2
	local rowCentreZ = Constants.World.PlotSpacingZ / 2

	-- Big grass ground plane underneath everything so empty areas
	-- between plots / behind the row read as turf instead of bare void.
	-- Sits at Y=0 with a tiny bit of thickness so the road / sidewalk
	-- blocks (top surfaces around Y=0.30) overlay cleanly above it.
	local groundSize = Vector3.new(gridWidth + 320, 1, Constants.World.PlotSpacingZ * rows + 280)
	local groundCentre = Vector3.new(
		Constants.World.Origin.X,
		-0.5,
		Constants.World.Origin.Z
	)
	makePart({
		Name = "GrassGround",
		Size = groundSize,
		Position = groundCentre,
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(75, 130, 70),
	}).Parent = sceneryRoot

	-- Front-edge Z of the back row (door faces +Z) — toward the road.
	local backRowFrontZ = -rowCentreZ + plotShellHalfZ
	-- Front-edge Z of the front row (door faces -Z post-rotation) — also
	-- toward the road; same magnitude, opposite sign.
	local frontRowFrontZ = rowCentreZ - plotShellHalfZ

	-- Road dimensions.
	local roadWidth = 18
	local roadHalf = roadWidth / 2

	-- Sidewalks fill the gap between road edge and plot front edge.
	local sidewalkDepthFront = (frontRowFrontZ - roadHalf)
	local sidewalkLength = gridWidth + 60

	-- Road in the middle.
	buildRoadSegment(
		sceneryRoot,
		Vector3.new(Constants.World.Origin.X, 0, Constants.World.Origin.Z),
		sidewalkLength + 20,
		roadWidth
	)

	-- Front sidewalk for each row (the strip the doors face onto).
	buildSidewalkBlock(
		sceneryRoot,
		Vector3.new(
			Constants.World.Origin.X,
			0.15,
			Constants.World.Origin.Z + roadHalf + sidewalkDepthFront / 2
		),
		Vector3.new(sidewalkLength, 0.3, sidewalkDepthFront)
	)
	buildSidewalkBlock(
		sceneryRoot,
		Vector3.new(
			Constants.World.Origin.X,
			0.15,
			Constants.World.Origin.Z - roadHalf - sidewalkDepthFront / 2
		),
		Vector3.new(sidewalkLength, 0.3, sidewalkDepthFront)
	)

	-- Back sidewalks behind each row (so the world reads as a proper
	-- block, not just a strip).
	local backDepth = 8
	local backRowBackZ = -rowCentreZ - plotShellHalfZ
	local frontRowBackZ = rowCentreZ + plotShellHalfZ
	buildSidewalkBlock(
		sceneryRoot,
		Vector3.new(
			Constants.World.Origin.X,
			0.15,
			backRowBackZ - backDepth / 2
		),
		Vector3.new(sidewalkLength, 0.3, backDepth)
	)
	buildSidewalkBlock(
		sceneryRoot,
		Vector3.new(
			Constants.World.Origin.X,
			0.15,
			frontRowBackZ + backDepth / 2
		),
		Vector3.new(sidewalkLength, 0.3, backDepth)
	)

	-- Per-plot path from each plot's door to the road sidewalk. The path
	-- runs through what would be the plot's front-edge → road sidewalk
	-- gap, but the sidewalk block already covers it; an extra tile adds
	-- a slightly different concrete colour so plots feel anchored.
	for col = 0, perRow - 1 do
		local plotX = (col - (perRow - 1) / 2) * Constants.World.PlotSpacingX
		for sign = -1, 1, 2 do
			local rowFront = sign * (rowCentreZ - plotShellHalfZ)
			buildSidewalkBlock(
				sceneryRoot,
				Vector3.new(
					plotX,
					0.16,
					(rowFront + sign * roadHalf) / 2
				),
				Vector3.new(8, 0.32, math.abs(rowFront - sign * roadHalf))
			)
		end
	end

	-- Street lamps along both road sidewalks. Spacing roughly one lamp
	-- per plot column plus extras at the ends.
	local lampSpacing = Constants.World.PlotSpacingX
	local lampCount = perRow + 1
	for i = 0, lampCount do
		local x = (i - lampCount / 2) * lampSpacing
		-- Lamps on the back-row side, arms reaching toward the road.
		buildLamp(
			sceneryRoot,
			Vector3.new(x, 0.3, Constants.World.Origin.Z - roadHalf - 1.5),
			1
		)
		-- Lamps on the front-row side, arms reaching the other way.
		buildLamp(
			sceneryRoot,
			Vector3.new(x, 0.3, Constants.World.Origin.Z + roadHalf + 1.5),
			-1
		)
	end

	-- Lamps along the back of each row of plots so they're not pitch
	-- black behind the kiosks.
	for i = 0, lampCount do
		local x = (i - lampCount / 2) * lampSpacing
		buildLamp(
			sceneryRoot,
			Vector3.new(x, 0.3, backRowBackZ - backDepth - 1),
			-1
		)
		buildLamp(
			sceneryRoot,
			Vector3.new(x, 0.3, frontRowBackZ + backDepth + 1),
			1
		)
	end

	-- Scatter trees, bushes, and rocks behind each row of plots and
	-- along the outer edges of the sidewalks. Avoid plot footprints.
	local placed: { { pos: Vector3, radius: number } } = {}
	local function tooClose(p: Vector3, radius: number): boolean
		for _, other in ipairs(placed) do
			if (p - other.pos).Magnitude < radius + other.radius then
				return true
			end
		end
		return false
	end

	local function inPlotFootprint(x: number, z: number): boolean
		for col = 0, perRow - 1 do
			for row = 0, rows - 1 do
				local cx = (col - (perRow - 1) / 2) * Constants.World.PlotSpacingX
				local cz = (row - (rows - 1) / 2) * Constants.World.PlotSpacingZ
				if math.abs(x - cx) < Constants.World.PlotShellSize.X / 2 + 5
					and math.abs(z - cz) < Constants.World.PlotShellSize.Z / 2 + 5
				then
					return true
				end
			end
		end
		return false
	end

	local function inRoadOrSidewalk(z: number): boolean
		local zFromCentre = math.abs(z - Constants.World.Origin.Z)
		-- Road + front sidewalks (between the rows).
		return zFromCentre < frontRowFrontZ + 1
	end

	-- Trees (chunky)
	for _ = 1, 80 do
		local x = rng:NextNumber(-gridWidth / 2 - 50, gridWidth / 2 + 50)
		local z = rng:NextNumber(
			-rowCentreZ - plotShellHalfZ - 60,
			rowCentreZ + plotShellHalfZ + 60
		)
		if not inPlotFootprint(x, z) and not inRoadOrSidewalk(z) then
			local pos = Vector3.new(x, 0.3, z)
			if not tooClose(pos, 12) then
				buildTree(sceneryRoot, pos, rng)
				table.insert(placed, { pos = pos, radius = 12 })
			end
		end
	end

	-- Bushes
	for _ = 1, 40 do
		local x = rng:NextNumber(-gridWidth / 2 - 40, gridWidth / 2 + 40)
		local z = rng:NextNumber(
			-rowCentreZ - plotShellHalfZ - 50,
			rowCentreZ + plotShellHalfZ + 50
		)
		if not inPlotFootprint(x, z) and not inRoadOrSidewalk(z) then
			local pos = Vector3.new(x, 0.3, z)
			if not tooClose(pos, 6) then
				buildBush(sceneryRoot, pos, rng)
				table.insert(placed, { pos = pos, radius = 6 })
			end
		end
	end

	-- Rocks
	for _ = 1, 25 do
		local x = rng:NextNumber(-gridWidth / 2 - 40, gridWidth / 2 + 40)
		local z = rng:NextNumber(
			-rowCentreZ - plotShellHalfZ - 50,
			rowCentreZ + plotShellHalfZ + 50
		)
		if not inPlotFootprint(x, z) and not inRoadOrSidewalk(z) then
			local pos = Vector3.new(x, 0.3, z)
			if not tooClose(pos, 5) then
				buildRockCluster(sceneryRoot, pos, rng)
				table.insert(placed, { pos = pos, radius = 5 })
			end
		end
	end
end

return Environment

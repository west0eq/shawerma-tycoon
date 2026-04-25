--!strict
--[[
	Environment.luau

	Builds the surrounding scenery for the plot grid: an asphalt road that
	runs along the front of every plot, a sidewalk between the road and the
	plot, scattered trees and street lamps in the gaps, and decorative
	patches of grass texture. Pure procedural — no Studio assets.

	The build is keyed off Constants.World so plot grid layout changes
	flow through automatically.
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

local function buildTree(parent: Folder, position: Vector3, rng: Random)
	local tree = Instance.new("Model")
	tree.Name = "Tree"
	tree.Parent = parent

	local trunkH = rng:NextNumber(7, 10)
	local trunk = makePart({
		Name = "Trunk",
		Size = Vector3.new(1.6, trunkH, 1.6),
		Position = position + Vector3.new(0, trunkH / 2, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(85, 55, 35),
	})
	trunk.Parent = tree

	-- Foliage as 3 stacked spheres for a chunky low-poly canopy.
	local foliageColor = Color3.fromRGB(
		60 + rng:NextInteger(-10, 10),
		120 + rng:NextInteger(-10, 20),
		55 + rng:NextInteger(-10, 10)
	)
	local function leafBall(yOffset: number, size: number)
		local b = makePart({
			Name = "Foliage",
			Size = Vector3.new(size, size, size),
			Shape = Enum.PartType.Ball,
			Position = position + Vector3.new(0, trunkH + yOffset, 0),
			Material = Enum.Material.Grass,
			Color = foliageColor,
		})
		b.Parent = tree
	end
	leafBall(0.5, 6)
	leafBall(3.0, 5)
	leafBall(-1.0, 5)
	tree.PrimaryPart = trunk
end

local function buildLamp(parent: Folder, position: Vector3)
	local lamp = Instance.new("Model")
	lamp.Name = "StreetLamp"
	lamp.Parent = parent

	local pole = makePart({
		Name = "Pole",
		Size = Vector3.new(0.5, 12, 0.5),
		Position = position + Vector3.new(0, 6, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(50, 50, 55),
	})
	pole.Parent = lamp

	local arm = makePart({
		Name = "Arm",
		Size = Vector3.new(0.4, 0.4, 2.2),
		Position = position + Vector3.new(0, 11.5, 1.0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(50, 50, 55),
	})
	arm.Parent = lamp

	local bulb = makePart({
		Name = "Bulb",
		Size = Vector3.new(1, 0.5, 1),
		Position = position + Vector3.new(0, 11, 1.8),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 230, 180),
	})
	bulb.Parent = lamp

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Range = 22
	light.Brightness = 1.4
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

-- Build a road segment (asphalt + dashed centre line).
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

-- Origin Z of the row of plots. The grid is centred on Constants.World.Origin.Z.
-- For the 4×2 grid, the front row is at Origin.Z + PlotSpacingZ/2, back row at
-- Origin.Z - PlotSpacingZ/2. The road runs in front of the front row.
function Environment.build(parent: Folder)
	local rng = Random.new(8675309)

	local sceneryRoot = Instance.new("Folder")
	sceneryRoot.Name = "Environment"
	sceneryRoot.Parent = parent

	local perRow = Constants.World.PlotsPerRow
	local rows = math.ceil(Constants.World.NumPlots / perRow)
	local gridWidth = perRow * Constants.World.PlotSpacingX
	local gridDepth = rows * Constants.World.PlotSpacingZ

	local frontZ = Constants.World.Origin.Z + Constants.World.PlotSpacingZ / 2 + Constants.World.PlotShellSize.Z / 2
	local sidewalkDepth = 8
	local roadWidth = 18

	-- Sidewalk strip directly in front of the row of plots.
	buildSidewalkBlock(
		sceneryRoot,
		Vector3.new(Constants.World.Origin.X, 0.15, frontZ + sidewalkDepth / 2),
		Vector3.new(gridWidth + 60, 0.3, sidewalkDepth)
	)

	-- Road in front of the sidewalk.
	buildRoadSegment(
		sceneryRoot,
		Vector3.new(Constants.World.Origin.X, 0, frontZ + sidewalkDepth + roadWidth / 2),
		gridWidth + 80,
		roadWidth
	)

	-- Sidewalk on the far side of the road.
	buildSidewalkBlock(
		sceneryRoot,
		Vector3.new(Constants.World.Origin.X, 0.15, frontZ + sidewalkDepth + roadWidth + sidewalkDepth / 2),
		Vector3.new(gridWidth + 60, 0.3, sidewalkDepth)
	)

	-- Sidewalk along the back of the back row (nice symmetry, gives staff
	-- a place to "go on break").
	local backZ = Constants.World.Origin.Z - Constants.World.PlotSpacingZ / 2 - Constants.World.PlotShellSize.Z / 2
	buildSidewalkBlock(
		sceneryRoot,
		Vector3.new(Constants.World.Origin.X, 0.15, backZ - sidewalkDepth / 2),
		Vector3.new(gridWidth + 60, 0.3, sidewalkDepth)
	)

	-- Per-plot path connecting the plot's front door to the front sidewalk.
	for col = 0, perRow - 1 do
		local plotX = (col - (perRow - 1) / 2) * Constants.World.PlotSpacingX
		local pathLen = Constants.World.SpawnPadOffset + 4
		buildSidewalkBlock(
			sceneryRoot,
			Vector3.new(
				plotX,
				0.15,
				frontZ - Constants.World.PlotShellSize.Z / 2 + pathLen / 2 - 2
			),
			Vector3.new(6, 0.3, pathLen)
		)
	end

	-- Street lamps along the front sidewalk.
	for col = 0, perRow do
		local x = (col - perRow / 2) * Constants.World.PlotSpacingX
		buildLamp(sceneryRoot, Vector3.new(x, 0.3, frontZ + sidewalkDepth - 1.5))
	end

	-- Trees scattered between plots and along the back.
	local placedTrees: { Vector3 } = {}
	local function tooClose(p: Vector3): boolean
		for _, q in ipairs(placedTrees) do
			if (p - q).Magnitude < 14 then
				return true
			end
		end
		return false
	end
	local treeAttempts = 60
	for _ = 1, treeAttempts do
		local x = rng:NextNumber(-gridWidth / 2 - 30, gridWidth / 2 + 30)
		local z = rng:NextNumber(backZ - 30, frontZ - Constants.World.PlotShellSize.Z / 2 - 6)
		local pos = Vector3.new(x, 0.3, z)
		-- Skip trees too close to plot footprints.
		local skip = false
		for col = 0, perRow - 1 do
			for row = 0, rows - 1 do
				local cx = (col - (perRow - 1) / 2) * Constants.World.PlotSpacingX
				local cz = (row - (rows - 1) / 2) * Constants.World.PlotSpacingZ
				if math.abs(x - cx) < Constants.World.PlotShellSize.X / 2 + 6
					and math.abs(z - cz) < Constants.World.PlotShellSize.Z / 2 + 6
				then
					skip = true
					break
				end
			end
			if skip then break end
		end
		if not skip and not tooClose(pos) then
			buildTree(sceneryRoot, pos, rng)
			table.insert(placedTrees, pos)
		end
	end
end

return Environment

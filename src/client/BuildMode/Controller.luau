--!strict
--[[
	BuildMode/Controller.luau

	Build mode is the *client* side of the placement pipeline. The server
	owns world state — this controller only manages the ghost preview and
	the player's intent (mouse + keyboard). Every confirmed action is fired
	through a RemoteEvent and re-validated on the server.

	Modes:
	  • idle    — build mode disabled.
	  • placing — a catalog item is selected, ghost follows the cursor,
	              click to place, R to rotate, Esc/B to cancel.
	  • removing — clicking on a placed item fires `RequestRemove`.

	The controller is a singleton; mount once during client bootstrap.
]]

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))

local Controller = {}

local function getRemote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("ShawermaTycoonRemotes")
	return folder:WaitForChild(name) :: RemoteEvent
end

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local placeRemote = getRemote(Constants.Remotes.RequestPlace)
local removeRemote = getRemote(Constants.Remotes.RequestRemove)

local mode: "idle" | "placing" | "removing" = "idle"
local placingCatalogId: string? = nil
local ghostModel: Model? = nil
local ghostYaw: number = 0

local connections: { RBXScriptConnection } = {}

local function destroyGhost()
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
end

local function makeGhost(catalogId: string)
	destroyGhost()
	local item = BuildCatalog.get(catalogId)
	local cf = CFrame.new(0, -1000, 0)
	local model = item.build(cf)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 0.5
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Anchored = true
		elseif descendant:IsA("PointLight")
			or descendant:IsA("SpotLight")
			or descendant:IsA("SurfaceLight") then
			descendant.Enabled = false
		end
	end
	model.Parent = Workspace
	ghostModel = model
end

local function snapToGrid(value: number): number
	return Util.roundTo(value, Constants.Build.GridSize)
end

local function rayFromMouseToGround(): Vector3?
	local unitRay = Workspace.CurrentCamera:ScreenPointToRay(mouse.X, mouse.Y, 0)
	-- Ground plane y = GroundY (top of floor). Solve t in unitRay.Origin + t*Dir.y = ground.
	local ground = Constants.Build.GroundY
	local dirY = unitRay.Direction.Y
	if math.abs(dirY) < 1e-4 then
		return nil
	end
	local t = (ground - unitRay.Origin.Y) / dirY
	if t <= 0 then
		return nil
	end
	return unitRay.Origin + unitRay.Direction * t
end

local function updateGhost()
	if mode ~= "placing" or not ghostModel or not placingCatalogId then
		return
	end
	local hit = rayFromMouseToGround()
	if not hit then
		return
	end
	local snapX = snapToGrid(hit.X)
	local snapZ = snapToGrid(hit.Z)
	local item = BuildCatalog.get(placingCatalogId)
	-- Position ghost so its base sits on the floor.
	local groundY = Constants.Build.GroundY
	local cf = CFrame.new(snapX, groundY, snapZ) * CFrame.Angles(0, math.rad(ghostYaw), 0)
	if ghostModel.PrimaryPart then
		ghostModel:PivotTo(cf)
	end
end

local function tintGhost(color: Color3)
	if not ghostModel then
		return
	end
	for _, part in ipairs(ghostModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local function exitMode()
	mode = "idle"
	placingCatalogId = nil
	ghostYaw = 0
	destroyGhost()
end

local function startPlacing(catalogId: string)
	if mode == "removing" then
		mode = "idle"
	end
	placingCatalogId = catalogId
	ghostYaw = 0
	makeGhost(catalogId)
	mode = "placing"
end

local function startRemoving()
	exitMode()
	mode = "removing"
end

local function stopRemoving()
	if mode == "removing" then
		mode = "idle"
	end
end

local function getPlacedAtMouse(): Model?
	local target = mouse.Target
	if not target then
		return nil
	end
	local model = target:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChild("PlacedUid") then
			return model
		end
		model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model") :: Model?
	end
	return nil
end

local function handleClick()
	if mode == "placing" and placingCatalogId then
		local hit = rayFromMouseToGround()
		if not hit then
			return
		end
		local snapX = snapToGrid(hit.X)
		local snapZ = snapToGrid(hit.Z)
		placeRemote:FireServer(placingCatalogId, snapX, snapZ, ghostYaw)
	elseif mode == "removing" then
		local model = getPlacedAtMouse()
		if model then
			local uidValue = model:FindFirstChild("PlacedUid") :: StringValue?
			if uidValue then
				removeRemote:FireServer(uidValue.Value)
			end
		end
	end
end

local function rotateLeft()
	if mode == "placing" then
		ghostYaw = (ghostYaw - Constants.Build.RotationStepDegrees) % 360
	end
end

local function rotateRight()
	if mode == "placing" then
		ghostYaw = (ghostYaw + Constants.Build.RotationStepDegrees) % 360
	end
end

function Controller.start(): typeof(setmetatable({}, {}))
	-- Per-frame ghost follow.
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			if mode == "placing" then
				updateGhost()
			end
		end)
	)

	-- Mouse click → place / remove.
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				handleClick()
			elseif input.KeyCode == Enum.KeyCode.R then
				rotateRight()
			elseif input.KeyCode == Enum.KeyCode.Q then
				rotateLeft()
			elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.B then
				exitMode()
			end
		end)
	)

	return {
		startPlacing = startPlacing,
		startRemoving = startRemoving,
		stopRemoving = stopRemoving,
		exitMode = exitMode,
		isActive = function()
			return mode ~= "idle"
		end,
	}
end

return Controller

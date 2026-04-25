--!strict
--[[
	PlotService.luau

	Owns the multi-plot world and assigns plots to players. The first
	free plot in `world.plots` is handed out on join; the plot is freed
	when the player leaves so a refill can happen mid-server.

	Other services query `PlotService.getPlot(player)` to find which
	plot's stations / queue / anchors / placed-item bounds belong to
	the caller.

	Trust model: assignment is server-only. Clients are notified via
	`PlotAssigned` (own plot only) so they can update HUD / camera.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))

local PlotService = {}

PlotService.PlotAssigned = Signal.new()
PlotService.PlotReleased = Signal.new()

local plots: { any } = {}
local playerToIndex: { [Player]: number } = {}
local indexToPlayer: { [number]: Player } = {}
local plotAssignedRemote: RemoteEvent

local function setSignText(plot: any, text: string, color: Color3)
	if plot.signLabel then
		plot.signLabel.Text = text
		plot.signLabel.TextColor3 = color
	end
end

local function setBoardText(plot: any, text: string)
	if plot.boardLabel then
		plot.boardLabel.Text = text
	end
end

local function teleportToPlot(player: Player, plot: any)
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if hrp and hrp:IsA("BasePart") then
		hrp.CFrame = CFrame.new(plot.spawnPad.Position + Vector3.new(0, 4, 0))
	end
end

local function assignNextFreePlot(player: Player)
	for index = 1, #plots do
		if indexToPlayer[index] == nil then
			local plot = plots[index]
			indexToPlayer[index] = player
			playerToIndex[player] = index
			setSignText(
				plot,
				string.format("%s's Shawarma", player.DisplayName),
				Color3.fromRGB(120, 220, 140)
			)
			setBoardText(
				plot,
				string.format("%s's Shawarma\n★ ★ ★ ★ ★\nNow open!", player.DisplayName)
			)
			plotAssignedRemote:FireClient(player, {
				index = index,
				originX = plot.origin.X,
				originY = plot.origin.Y,
				originZ = plot.origin.Z,
			})
			-- Defer teleport one frame to give the character time to load.
			task.defer(function()
				if player.Parent and indexToPlayer[index] == player then
					teleportToPlot(player, plot)
				end
			end)
			PlotService.PlotAssigned:Fire(player, plot)
			return
		end
	end
	-- All plots taken: tell the player so the UI can react gracefully.
	plotAssignedRemote:FireClient(player, { index = 0, full = true })
end

local function releasePlot(player: Player)
	local idx = playerToIndex[player]
	if not idx then
		return
	end
	playerToIndex[player] = nil
	indexToPlayer[idx] = nil
	local plot = plots[idx]
	if plot then
		setSignText(
			plot,
			string.format("Plot %02d  ·  AVAILABLE", idx),
			Color3.fromRGB(255, 230, 170)
		)
		setBoardText(plot, string.format("Plot %02d\n☆ ☆ ☆ ☆ ☆\nAvailable", idx))
		PlotService.PlotReleased:Fire(player, plot)
	end
end

function PlotService.getPlot(player: Player): any?
	local idx = playerToIndex[player]
	if idx then
		return plots[idx]
	end
	return nil
end

function PlotService.getOwner(plot: any): Player?
	return indexToPlayer[plot.index]
end

function PlotService.getOwnerByIndex(index: number): Player?
	return indexToPlayer[index]
end

function PlotService.getOwnedPlots(): { any }
	local out: { any } = {}
	for _, plot in ipairs(plots) do
		if indexToPlayer[plot.index] then
			table.insert(out, plot)
		end
	end
	return out
end

function PlotService.getAllPlots(): { any }
	return plots
end

function PlotService.init(deps: {
	remotes: { [string]: RemoteEvent },
	world: { plots: { any } },
})
	plots = deps.world.plots
	plotAssignedRemote = deps.remotes.PlotAssigned

	for _, player in ipairs(Players:GetPlayers()) do
		assignNextFreePlot(player)
	end

	Players.PlayerAdded:Connect(function(player)
		assignNextFreePlot(player)
		player.CharacterAdded:Connect(function()
			local plot = PlotService.getPlot(player)
			if plot then
				task.defer(function()
					if player.Parent then
						teleportToPlot(player, plot)
					end
				end)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		releasePlot(player)
	end)
end

return PlotService

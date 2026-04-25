--!strict
--[[
	PlotService.luau

	Owns the multi-plot world. Players don't get a plot automatically on
	join — instead the server sends `PlotsAvailable` with the list of free
	plot indices and their world positions, and the client shows a plot
	selection UI. The player picks a plot and a name, and the client fires
	`RequestClaimPlot`. PlotService validates and assigns.

	Other services query `PlotService.getPlot(player)` to find which
	plot's stations / queue / anchors / placed-item bounds belong to the
	caller. Until the player claims, this returns nil and they're a
	spectator.

	Trust model: assignment is server-only. Clients fire `RequestClaimPlot`
	but the server validates name length and plot availability.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Constants = require(Shared:WaitForChild("Constants"))

local World = script.Parent.Parent:WaitForChild("World")
local RealisticRig = require(World:WaitForChild("RealisticRig"))

local PlotService = {}

PlotService.PlotAssigned = Signal.new()
PlotService.PlotReleased = Signal.new()

local plots: { any } = {}
local playerToIndex: { [Player]: number } = {}
local indexToPlayer: { [number]: Player } = {}
local plotAssignedRemote: RemoteEvent
local plotsAvailableRemote: RemoteEvent
local notifyRemote: RemoteEvent

-- Default sign / board colours for unowned plots.
local AVAILABLE_SIGN_COLOR = Color3.fromRGB(255, 230, 170)
local OWNED_SIGN_COLOR = Color3.fromRGB(120, 220, 140)

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

-- Reset a plot's signage to the "available" state.
local function markAvailable(plot: any)
	setSignText(
		plot,
		string.format("Plot %02d  ·  AVAILABLE", plot.index),
		AVAILABLE_SIGN_COLOR
	)
	setBoardText(plot, string.format("Plot %02d\n☆ ☆ ☆ ☆ ☆\nAvailable", plot.index))
end

local function teleportToPlot(player: Player, plot: any)
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if hrp and hrp:IsA("BasePart") then
		hrp.CFrame = CFrame.new(plot.spawnPad.Position + Vector3.new(0, 4, 0))
	end
end

-- Trim a player-supplied plot name. Strict cap on length and a fallback
-- if it's empty after trimming.
local function sanitizeName(raw: string?, fallback: string): string
	local name = raw or fallback
	-- Strip leading / trailing whitespace and control chars.
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	if #name < Constants.PlotName.MinLength then
		return fallback
	end
	if #name > Constants.PlotName.MaxLength then
		name = string.sub(name, 1, Constants.PlotName.MaxLength)
	end
	return name
end

-- Build the payload sent to a client telling them which plots are free
-- (so the selection UI can render them).
local function freePlotsPayload(): { any }
	local list: { any } = {}
	for _, plot in ipairs(plots) do
		if indexToPlayer[plot.index] == nil then
			table.insert(list, {
				index = plot.index,
				originX = plot.origin.X,
				originY = plot.origin.Y,
				originZ = plot.origin.Z,
				facing = plot.facing,
			})
		end
	end
	return list
end

local function broadcastFreePlots()
	-- Only meaningful for players who haven't claimed yet.
	for _, player in ipairs(Players:GetPlayers()) do
		if playerToIndex[player] == nil then
			plotsAvailableRemote:FireClient(player, freePlotsPayload())
		end
	end
end

local function assignSpecificPlot(player: Player, index: number, name: string)
	local plot = plots[index]
	if not plot then
		return false
	end
	if indexToPlayer[index] ~= nil then
		return false
	end

	indexToPlayer[index] = player
	playerToIndex[player] = index

	setSignText(plot, name, OWNED_SIGN_COLOR)
	setBoardText(plot, string.format("%s\n★ ★ ★ ★ ★\nNow open!", name))
	plotAssignedRemote:FireClient(player, {
		index = index,
		originX = plot.origin.X,
		originY = plot.origin.Y,
		originZ = plot.origin.Z,
		facing = plot.facing,
		name = name,
	})

	-- Defer teleport one frame to give the character time to load.
	task.defer(function()
		if player.Parent and indexToPlayer[index] == player then
			teleportToPlot(player, plot)
		end
	end)

	PlotService.PlotAssigned:Fire(player, plot)
	-- Tell remaining unclaimed players that this slot is gone.
	broadcastFreePlots()
	return true
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
		markAvailable(plot)
		PlotService.PlotReleased:Fire(player, plot)
	end
	broadcastFreePlots()
end

local function offerSelection(player: Player)
	-- Don't push selection at a player who already owns a plot.
	if playerToIndex[player] ~= nil then
		return
	end
	plotsAvailableRemote:FireClient(player, freePlotsPayload())
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
	plotsAvailableRemote = deps.remotes.PlotsAvailable
	notifyRemote = deps.remotes.Notify
	local claimRemote = deps.remotes.RequestClaimPlot

	for _, plot in ipairs(plots) do
		markAvailable(plot)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		offerSelection(player)
	end

	Players.PlayerAdded:Connect(function(player)
		offerSelection(player)
		-- Best-effort: pull the player's friends into the customer rig
		-- pool so they see familiar faces wandering through their plot.
		-- Failure (private friend list, API hiccup) is silently ignored.
		if Constants.Customer.UseFriendsAsCustomers then
			RealisticRig.populateFriendsOf(player, 8)
		end
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

	-- Client claim request. Server is the source of truth.
	claimRemote.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local rawIndex = (payload :: any).index
		local rawName = (payload :: any).name
		if typeof(rawIndex) ~= "number" then
			return
		end
		local index = math.floor(rawIndex)
		if index < 1 or index > #plots then
			return
		end
		if playerToIndex[player] ~= nil then
			-- Already owns one — silently ignore.
			return
		end
		if indexToPlayer[index] ~= nil then
			-- Plot was claimed by someone else between offer and request.
			notifyRemote:FireClient(player, "That plot was just taken — pick another.")
			plotsAvailableRemote:FireClient(player, freePlotsPayload())
			return
		end
		local fallback = string.format("%s's Shawarma", player.DisplayName)
		local nameStr: string
		if typeof(rawName) == "string" then
			nameStr = sanitizeName(rawName, fallback)
		else
			nameStr = fallback
		end
		assignSpecificPlot(player, index, nameStr)
	end)
end

return PlotService

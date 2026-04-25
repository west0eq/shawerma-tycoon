--!strict
--[[
	HUD.luau

	Phase 1 HUD. Three readouts:
	  • Top-left: money pill.
	  • Top-right: live queue length + cooking station status.
	  • Bottom-centre: notification stack (handled by Notifications.luau).

	The HUD never mutates game state. It listens to server-fired remotes
	(`MoneyChanged`, `OrderStateChanged`, `StationStateChanged`) and just
	renders.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HUD = {}

local FONT = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.Gotham
local ACCENT = Color3.fromRGB(220, 80, 60)
local PANEL_BG = Color3.fromRGB(22, 22, 28)
local TEXT = Color3.fromRGB(240, 240, 240)
local SUBTEXT = Color3.fromRGB(170, 170, 180)

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function makeLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT_BODY
	label.TextColor3 = TEXT
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do
		(label :: any)[k] = v
	end
	return label
end

function HUD.mount(playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "ShawermaHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	-- ---- money pill ------------------------------------------------------
	local moneyPanel = Instance.new("Frame")
	moneyPanel.Name = "MoneyPanel"
	moneyPanel.Size = UDim2.new(0, 220, 0, 56)
	moneyPanel.Position = UDim2.new(0, 24, 0, 24)
	moneyPanel.BackgroundColor3 = PANEL_BG
	moneyPanel.BorderSizePixel = 0
	moneyPanel.Parent = screen
	corner(moneyPanel, 14)
	stroke(moneyPanel, ACCENT, 2)

	local moneyTitle = makeLabel({
		Name = "Title",
		Text = "CASH",
		Font = FONT,
		TextSize = 12,
		TextColor3 = SUBTEXT,
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -32, 0, 14),
	})
	moneyTitle.Parent = moneyPanel

	local moneyValue = makeLabel({
		Name = "Value",
		Text = "$0",
		Font = FONT,
		TextSize = 26,
		TextColor3 = TEXT,
		Position = UDim2.new(0, 16, 0, 22),
		Size = UDim2.new(1, -32, 0, 28),
	})
	moneyValue.Parent = moneyPanel

	-- ---- queue / station panel -------------------------------------------
	local statusPanel = Instance.new("Frame")
	statusPanel.Name = "StatusPanel"
	statusPanel.Size = UDim2.new(0, 260, 0, 90)
	statusPanel.AnchorPoint = Vector2.new(1, 0)
	statusPanel.Position = UDim2.new(1, -24, 0, 24)
	statusPanel.BackgroundColor3 = PANEL_BG
	statusPanel.BorderSizePixel = 0
	statusPanel.Parent = screen
	corner(statusPanel, 14)
	stroke(statusPanel, ACCENT, 2)

	local statusTitle = makeLabel({
		Name = "Title",
		Text = "RESTAURANT",
		Font = FONT,
		TextSize = 12,
		TextColor3 = SUBTEXT,
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -32, 0, 14),
	})
	statusTitle.Parent = statusPanel

	local queueValue = makeLabel({
		Name = "Queue",
		Text = "Queue: 0",
		Font = FONT,
		TextSize = 18,
		Position = UDim2.new(0, 16, 0, 28),
		Size = UDim2.new(1, -32, 0, 22),
	})
	queueValue.Parent = statusPanel

	local stationValue = makeLabel({
		Name = "Station",
		Text = "Station: Idle",
		TextSize = 16,
		TextColor3 = SUBTEXT,
		Position = UDim2.new(0, 16, 0, 54),
		Size = UDim2.new(1, -32, 0, 22),
	})
	stationValue.Parent = statusPanel

	-- ---- wire remotes ----------------------------------------------------
	Remotes.get(Constants.Remotes.MoneyChanged).OnClientEvent:Connect(function(amount: number)
		moneyValue.Text = Util.formatMoney(amount)
	end)

	Remotes.get(Constants.Remotes.OrderStateChanged).OnClientEvent:Connect(function(snapshot: any)
		queueValue.Text = string.format("Queue: %d", #snapshot)
	end)

	Remotes.get(Constants.Remotes.StationStateChanged).OnClientEvent:Connect(function(payload: any)
		local state: string = payload.state or "Idle"
		stationValue.Text = "Station: " .. state
		if state == "Ready" then
			stationValue.TextColor3 = Color3.fromRGB(120, 220, 140)
		elseif state == "Prepping" then
			stationValue.TextColor3 = Color3.fromRGB(240, 200, 90)
		else
			stationValue.TextColor3 = SUBTEXT
		end
	end)

	return {
		screen = screen,
		mountFrame = screen,
	}
end

return HUD

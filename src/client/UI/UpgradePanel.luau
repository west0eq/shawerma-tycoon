--!strict
--[[
	UpgradePanel.luau

	Lists every restaurant-wide upgrade with its current tier and the cost of
	the next tier. Purchase fires `RequestPurchaseUpgrade`; server validates
	and broadcasts new tiers via `UpgradesChanged`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))
local Util = require(Shared:WaitForChild("Util"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local UpgradePanel = {}

local function getRemote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("ShawermaTycoonRemotes")
	return folder:WaitForChild(name) :: RemoteEvent
end

local function makeRow(parent: Instance, spec: any, currentTier: number, purchase: RemoteEvent): Frame
	local row = Instance.new("Frame")
	row.Name = "Upgrade_" .. spec.id
	row.Size = UDim2.new(1, 0, 0, 70)
	row.BackgroundColor3 = Theme.PanelBgAlt
	row.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = row

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -130, 0, 22)
	title.BackgroundTransparency = 1
	local maxTier = UpgradeCatalog.maxTier(spec.id)
	title.Text = string.format("%s · Tier %d/%d", spec.displayName, currentTier, maxTier)
	title.TextColor3 = Theme.Text
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = row

	local desc = Instance.new("TextLabel")
	desc.AnchorPoint = Vector2.new(0, 1)
	desc.Position = UDim2.new(0, 0, 1, 0)
	desc.Size = UDim2.new(1, -130, 0, 32)
	desc.BackgroundTransparency = 1
	desc.Text = spec.description
	desc.TextColor3 = Theme.SubText
	desc.TextSize = 12
	desc.Font = Enum.Font.Gotham
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextWrapped = true
	desc.Parent = row

	local nextCost = UpgradeCatalog.nextTierCost(spec.id, currentTier)
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, 0, 0.5, 0)
	btn.Size = UDim2.new(0, 110, 0, 38)
	btn.BorderSizePixel = 0
	btn.TextColor3 = Theme.Text
	btn.TextSize = 14
	btn.Font = Enum.Font.GothamBold
	if nextCost then
		btn.Text = "Buy " .. Util.formatMoney(nextCost)
		btn.BackgroundColor3 = Theme.Accent
		btn.AutoButtonColor = true
		btn.Activated:Connect(function()
			purchase:FireServer(spec.id)
		end)
	else
		btn.Text = "MAX"
		btn.BackgroundColor3 = Theme.PanelBg
		btn.AutoButtonColor = false
	end
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = btn
	btn.Parent = row

	row.Parent = parent
	return row
end

export type UpgradePanel = {
	frame: Frame,
	setVisible: (boolean) -> (),
}

function UpgradePanel.mount(screen: ScreenGui): UpgradePanel
	local frame = Instance.new("Frame")
	frame.Name = "UpgradePanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 480, 0, 520)
	frame.BackgroundColor3 = Theme.PanelBg
	frame.BorderSizePixel = 0
	frame.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = Theme.PanelStrokeWidth
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Position = UDim2.new(0, 16, 0, 12)
	title.Size = UDim2.new(1, -64, 0, 32)
	title.BackgroundTransparency = 1
	title.Text = "Upgrades"
	title.TextColor3 = Theme.Text
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.new(0, 32, 0, 32)
	close.BackgroundColor3 = Theme.PanelBgAlt
	close.BorderSizePixel = 0
	close.Text = "×"
	close.TextColor3 = Theme.Text
	close.TextSize = 22
	close.Font = Enum.Font.GothamBold
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 8)
	cc.Parent = close
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	close.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 56)
	list.Size = UDim2.new(1, -24, 1, -68)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local purchase = getRemote(Constants.Remotes.RequestPurchaseUpgrade)
	local upgradesChanged = getRemote(Constants.Remotes.UpgradesChanged)

	local function rebuild(state: { [string]: number })
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local catalog = UpgradeCatalog.all()
		table.sort(catalog, function(a, b)
			return (a.tierCosts[1] or 0) < (b.tierCosts[1] or 0)
		end)
		for _, spec in ipairs(catalog) do
			local tier = state[spec.id] or 0
			makeRow(list, spec, tier, purchase)
		end
	end

	upgradesChanged.OnClientEvent:Connect(function(state)
		rebuild(state or {})
	end)
	rebuild({})

	frame.Parent = screen
	return {
		frame = frame,
		setVisible = function(v: boolean)
			frame.Visible = v
		end,
	}
end

return UpgradePanel

--!strict
--[[
	ShopPanel.luau

	Lists every item in the BuildCatalog with its price and a Buy button.
	Buy fires the `RequestBuy` remote — the server validates funds and
	credits the inventory, no client trust involved.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local ShopPanel = {}

local function getRequestBuyRemote(): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("ShawermaTycoonRemotes")
	return folder:WaitForChild(Constants.Remotes.RequestBuy) :: RemoteEvent
end

local function makeRow(parent: Instance, item: any, requestBuy: RemoteEvent): Frame
	local row = Instance.new("Frame")
	row.Name = item.id
	row.Size = UDim2.new(1, 0, 0, 60)
	row.BackgroundColor3 = Theme.PanelBgAlt
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = row

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.AnchorPoint = Vector2.new(0, 0)
	name.Position = UDim2.new(0, 0, 0, 0)
	name.Size = UDim2.new(1, -120, 0, 22)
	name.BackgroundTransparency = 1
	name.Text = item.displayName
	name.TextColor3 = Theme.Text
	name.TextSize = 16
	name.Font = Enum.Font.GothamMedium
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local category = Instance.new("TextLabel")
	category.Name = "Category"
	category.AnchorPoint = Vector2.new(0, 1)
	category.Position = UDim2.new(0, 0, 1, 0)
	category.Size = UDim2.new(1, -120, 0, 16)
	category.BackgroundTransparency = 1
	category.Text = item.category .. (item.stationType and " · " .. item.stationType or "")
	category.TextColor3 = Theme.SubText
	category.TextSize = 12
	category.Font = Enum.Font.Gotham
	category.TextXAlignment = Enum.TextXAlignment.Left
	category.Parent = row

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, 0, 0.5, 0)
	buy.Size = UDim2.new(0, 100, 0, 36)
	buy.BackgroundColor3 = Theme.Accent
	buy.BorderSizePixel = 0
	buy.Text = Util.formatMoney(item.price)
	buy.TextColor3 = Theme.Text
	buy.TextSize = 16
	buy.Font = Enum.Font.GothamBold
	buy.AutoButtonColor = true

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = buy

	buy.Activated:Connect(function()
		requestBuy:FireServer(item.id)
	end)

	buy.Parent = row
	row.Parent = parent
	return row
end

export type ShopPanel = {
	frame: Frame,
	setVisible: (boolean) -> (),
}

function ShopPanel.mount(screen: ScreenGui): ShopPanel
	local frame = Instance.new("Frame")
	frame.Name = "ShopPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 460, 0, 520)
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
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.new(0, 16, 0, 12)
	title.Size = UDim2.new(1, -64, 0, 32)
	title.BackgroundTransparency = 1
	title.Text = "Shop"
	title.TextColor3 = Theme.Text
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.new(0, 32, 0, 32)
	close.BackgroundColor3 = Theme.PanelBgAlt
	close.BorderSizePixel = 0
	close.Text = "×"
	close.TextColor3 = Theme.Text
	close.TextSize = 22
	close.Font = Enum.Font.GothamBold
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	close.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.AnchorPoint = Vector2.new(0, 0)
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

	local requestBuy = getRequestBuyRemote()
	-- Stable display order: sort by price.
	local items = BuildCatalog.all()
	table.sort(items, function(a, b)
		return a.price < b.price
	end)
	for index, item in ipairs(items) do
		local row = makeRow(list, item, requestBuy)
		row.LayoutOrder = index
	end

	frame.Parent = screen

	return {
		frame = frame,
		setVisible = function(visible: boolean)
			frame.Visible = visible
		end,
	}
end

return ShopPanel

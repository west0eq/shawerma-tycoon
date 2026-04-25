--!strict
--[[
	Sidebar.luau

	Bottom-centre dock (formerly a left sidebar). Each button toggles
	a panel passed in by `mount`. Decoupled from the panels themselves so
	this layer never has to know about ShopPanel/BuildPanel internals.

	The module is still called "Sidebar" so callers don't all have to be
	renamed; we just changed the layout from vertical to horizontal.
]]

local Theme = require(script.Parent:WaitForChild("Theme"))

local Sidebar = {}

local function makeButton(parent: Instance, label: string, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = label .. "Button"
	button.Size = UDim2.new(0, 78, 1, -12)
	button.BackgroundColor3 = Theme.PanelBgAlt
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder
	button.Text = label
	button.TextColor3 = Theme.Text
	button.TextSize = 16
	button.Font = Enum.Font.GothamBold

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1.5
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = Theme.AccentSoft
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Theme.PanelBgAlt
	end)

	button.Parent = parent
	return button
end

export type Sidebar = {
	frame: Frame,
	shopButton: TextButton,
	buildButton: TextButton,
	staffButton: TextButton,
	upgradeButton: TextButton,
}

function Sidebar.mount(screen: ScreenGui): Sidebar
	local frame = Instance.new("Frame")
	frame.Name = "BottomDock"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -12)
	frame.Size = UDim2.new(0, 360, 0, 80)
	frame.BackgroundColor3 = Theme.PanelBg
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = Theme.PanelStrokeWidth
	stroke.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local shopButton = makeButton(frame, "Shop", 1)
	local buildButton = makeButton(frame, "Build", 2)
	local staffButton = makeButton(frame, "Staff", 3)
	local upgradeButton = makeButton(frame, "Upgrades", 4)

	frame.Parent = screen
	return {
		frame = frame,
		shopButton = shopButton,
		buildButton = buildButton,
		staffButton = staffButton,
		upgradeButton = upgradeButton,
	}
end

return Sidebar

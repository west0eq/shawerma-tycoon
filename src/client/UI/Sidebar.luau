--!strict
--[[
	Sidebar.luau

	Vertical button column on the left edge of the screen. Each button toggles
	a panel passed in by `mount`. Decoupled from the panels themselves so the
	sidebar layer never has to know about ShopPanel/BuildPanel internals.
]]

local Theme = require(script.Parent:WaitForChild("Theme"))

local Sidebar = {}

local function makeButton(parent: Instance, text: string, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = text .. "Button"
	button.Size = UDim2.new(1, 0, 0, 50)
	button.BackgroundColor3 = Theme.PanelBgAlt
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Theme.Text
	button.TextSize = 18
	button.Font = Enum.Font.GothamMedium
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
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
	frame.Name = "Sidebar"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 12, 0.5, 0)
	frame.Size = UDim2.new(0, 140, 0, 360)
	frame.BackgroundColor3 = Theme.PanelBg
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = Theme.PanelStrokeWidth
	stroke.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
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

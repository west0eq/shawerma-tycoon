--!strict
--[[
	BuildPanel.luau

	Shows the player's inventory (catalogId → count) and lets them select
	an item to enter placement mode. Communicates with `BuildModeController`
	via two callbacks supplied at mount time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Constants = require(Shared:WaitForChild("Constants"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local BuildPanel = {}

local function getRemote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("ShawermaTycoonRemotes")
	return folder:WaitForChild(name) :: RemoteEvent
end

local function makeRow(parent: Instance, catalogId: string, count: number, onSelect: (string) -> ()): Frame
	local item = BuildCatalog.get(catalogId)
	local row = Instance.new("Frame")
	row.Name = catalogId
	row.Size = UDim2.new(1, 0, 0, 50)
	row.BackgroundColor3 = Theme.PanelBgAlt
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = row

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Size = UDim2.new(1, -180, 1, 0)
	name.BackgroundTransparency = 1
	name.Text = item.displayName
	name.TextColor3 = Theme.Text
	name.TextSize = 16
	name.Font = Enum.Font.GothamMedium
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.AnchorPoint = Vector2.new(1, 0.5)
	countLabel.Position = UDim2.new(1, -110, 0.5, 0)
	countLabel.Size = UDim2.new(0, 60, 0, 24)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "x" .. tostring(count)
	countLabel.TextColor3 = Theme.SubText
	countLabel.TextSize = 14
	countLabel.Font = Enum.Font.Gotham
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.Parent = row

	local place = Instance.new("TextButton")
	place.Name = "Place"
	place.AnchorPoint = Vector2.new(1, 0.5)
	place.Position = UDim2.new(1, 0, 0.5, 0)
	place.Size = UDim2.new(0, 90, 0, 32)
	place.BackgroundColor3 = Theme.Accent
	place.BorderSizePixel = 0
	place.Text = "Place"
	place.TextColor3 = Theme.Text
	place.TextSize = 14
	place.Font = Enum.Font.GothamBold
	local placeCorner = Instance.new("UICorner")
	placeCorner.CornerRadius = UDim.new(0, 8)
	placeCorner.Parent = place
	place.Activated:Connect(function()
		onSelect(catalogId)
	end)
	place.Parent = row

	row.Parent = parent
	return row
end

export type BuildPanel = {
	frame: Frame,
	setVisible: (boolean) -> (),
	setRemoveMode: (boolean) -> (),
}

function BuildPanel.mount(
	screen: ScreenGui,
	onSelectItem: (string) -> (),
	onRemoveModeToggle: (boolean) -> ()
): BuildPanel
	local frame = Instance.new("Frame")
	frame.Name = "BuildPanel"
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
	title.Position = UDim2.new(0, 16, 0, 12)
	title.Size = UDim2.new(1, -64, 0, 32)
	title.BackgroundTransparency = 1
	title.Text = "Inventory"
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

	local removeBtn = Instance.new("TextButton")
	removeBtn.Name = "RemoveMode"
	removeBtn.AnchorPoint = Vector2.new(1, 0)
	removeBtn.Position = UDim2.new(1, -52, 0, 12)
	removeBtn.Size = UDim2.new(0, 100, 0, 32)
	removeBtn.BackgroundColor3 = Theme.PanelBgAlt
	removeBtn.BorderSizePixel = 0
	removeBtn.Text = "Remove"
	removeBtn.TextColor3 = Theme.Text
	removeBtn.TextSize = 14
	removeBtn.Font = Enum.Font.GothamMedium
	local removeCorner = Instance.new("UICorner")
	removeCorner.CornerRadius = UDim.new(0, 8)
	removeCorner.Parent = removeBtn
	local removeMode = false
	removeBtn.Activated:Connect(function()
		removeMode = not removeMode
		onRemoveModeToggle(removeMode)
		removeBtn.BackgroundColor3 = removeMode and Theme.Bad or Theme.PanelBgAlt
	end)
	removeBtn.Parent = frame

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Position = UDim2.new(0, 16, 0, 48)
	hint.Size = UDim2.new(1, -32, 0, 22)
	hint.BackgroundTransparency = 1
	hint.Text = "Pick an item to place. R = rotate · Esc = exit build mode"
	hint.TextColor3 = Theme.SubText
	hint.TextSize = 12
	hint.Font = Enum.Font.Gotham
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.new(0, 12, 0, 80)
	list.Size = UDim2.new(1, -24, 1, -92)
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

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "Empty"
	emptyLabel.Size = UDim2.new(1, 0, 0, 80)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "Inventory is empty.\nBuy items in the Shop to get started."
	emptyLabel.TextColor3 = Theme.SubText
	emptyLabel.TextSize = 14
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.TextWrapped = true
	emptyLabel.Visible = true
	emptyLabel.LayoutOrder = -1
	emptyLabel.Parent = list

	-- Reactive: subscribe to InventoryChanged.
	local inventoryRemote = getRemote(Constants.Remotes.InventoryChanged)
	local function rebuild(inventory: { [string]: number })
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local hasAny = false
		local order = 0
		for catalogId, count in pairs(inventory) do
			if BuildCatalog.exists(catalogId) and count > 0 then
				hasAny = true
				order += 1
				local row = makeRow(list, catalogId, count, onSelectItem)
				row.LayoutOrder = order
			end
		end
		emptyLabel.Visible = not hasAny
	end
	inventoryRemote.OnClientEvent:Connect(rebuild)

	frame.Parent = screen

	return {
		frame = frame,
		setVisible = function(visible: boolean)
			frame.Visible = visible
		end,
		setRemoveMode = function(active: boolean)
			removeMode = active
			removeBtn.BackgroundColor3 = active and Theme.Bad or Theme.PanelBgAlt
		end,
	}
end

return BuildPanel

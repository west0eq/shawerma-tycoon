--!strict
--[[
	StaffPanel.luau

	Hire / fire / upgrade UI for staff. The panel pulls catalog rows
	(Hire <Role>) and currently-hired rows (each with Upgrade and Fire
	buttons) and re-renders whenever the server fires `StaffChanged`.

	All actions go through three RemoteEvents — the server validates costs
	and persists changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local StaffCatalog = require(Shared:WaitForChild("StaffCatalog"))
local Util = require(Shared:WaitForChild("Util"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local StaffPanel = {}

local function getRemote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("ShawermaTycoonRemotes")
	return folder:WaitForChild(name) :: RemoteEvent
end

local function makeButton(text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 90, 0, 28)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Theme.Text
	b.TextSize = 13
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	return b
end

local function makeHireRow(parent: Instance, spec: any, hireRemote: RemoteEvent): Frame
	local row = Instance.new("Frame")
	row.Name = "Hire_" .. spec.role
	row.Size = UDim2.new(1, 0, 0, 60)
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

	local name = Instance.new("TextLabel")
	name.Position = UDim2.new(0, 0, 0, 0)
	name.Size = UDim2.new(1, -110, 0, 22)
	name.BackgroundTransparency = 1
	name.Text = spec.displayName
	name.TextColor3 = Theme.Text
	name.TextSize = 16
	name.Font = Enum.Font.GothamBold
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local desc = Instance.new("TextLabel")
	desc.AnchorPoint = Vector2.new(0, 1)
	desc.Position = UDim2.new(0, 0, 1, 0)
	desc.Size = UDim2.new(1, -110, 0, 18)
	desc.BackgroundTransparency = 1
	desc.Text = spec.description
	desc.TextColor3 = Theme.SubText
	desc.TextSize = 12
	desc.Font = Enum.Font.Gotham
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Parent = row

	local hire = makeButton("Hire " .. Util.formatMoney(spec.hireCost), Theme.Accent)
	hire.AnchorPoint = Vector2.new(1, 0.5)
	hire.Position = UDim2.new(1, 0, 0.5, 0)
	hire.Activated:Connect(function()
		hireRemote:FireServer(spec.role)
	end)
	hire.Parent = row

	row.Parent = parent
	return row
end

local function makeMemberRow(parent: Instance, member: any, fireRemote: RemoteEvent, upgradeRemote: RemoteEvent): Frame
	local spec = StaffCatalog.get(member.role)
	local row = Instance.new("Frame")
	row.Name = "Member_" .. member.uid
	row.Size = UDim2.new(1, 0, 0, 60)
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

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -210, 0, 22)
	name.BackgroundTransparency = 1
	name.Text = string.format("%s · %s · L%d", spec.displayName, member.nickname, member.level)
	name.TextColor3 = Theme.Text
	name.TextSize = 15
	name.Font = Enum.Font.GothamBold
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local effects = StaffCatalog.effects(member.role, member.level)
	local effectStr = ""
	for k, v in pairs(effects) do
		effectStr ..= string.format("%s=%.2f ", k, v)
	end
	local desc = Instance.new("TextLabel")
	desc.AnchorPoint = Vector2.new(0, 1)
	desc.Position = UDim2.new(0, 0, 1, 0)
	desc.Size = UDim2.new(1, -210, 0, 18)
	desc.BackgroundTransparency = 1
	desc.Text = effectStr
	desc.TextColor3 = Theme.SubText
	desc.TextSize = 12
	desc.Font = Enum.Font.Gotham
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Parent = row

	local upgradeCost = StaffCatalog.upgradeCostFor(member.role, member.level)
	local upgradeText = upgradeCost and ("Upg " .. Util.formatMoney(upgradeCost)) or "MAX"
	local upgrade = makeButton(upgradeText, Theme.AccentSoft)
	upgrade.AnchorPoint = Vector2.new(1, 0.5)
	upgrade.Position = UDim2.new(1, -100, 0.5, 0)
	if upgradeCost then
		upgrade.Activated:Connect(function()
			upgradeRemote:FireServer(member.uid)
		end)
	else
		upgrade.AutoButtonColor = false
		upgrade.BackgroundColor3 = Theme.PanelBg
	end
	upgrade.Parent = row

	local fire = makeButton("Fire", Theme.Bad)
	fire.AnchorPoint = Vector2.new(1, 0.5)
	fire.Position = UDim2.new(1, 0, 0.5, 0)
	fire.Activated:Connect(function()
		fireRemote:FireServer(member.uid)
	end)
	fire.Parent = row

	row.Parent = parent
	return row
end

export type StaffPanel = {
	frame: Frame,
	setVisible: (boolean) -> (),
}

function StaffPanel.mount(screen: ScreenGui): StaffPanel
	local frame = Instance.new("Frame")
	frame.Name = "StaffPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 520, 0, 560)
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
	title.Text = "Staff"
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

	local hireRemote = getRemote(Constants.Remotes.RequestHireStaff)
	local fireRemote = getRemote(Constants.Remotes.RequestFireStaff)
	local upgradeRemote = getRemote(Constants.Remotes.RequestUpgradeStaff)
	local staffChanged = getRemote(Constants.Remotes.StaffChanged)

	local function rebuild(staffList: { any })
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		-- Section header: hire.
		local hireHdr = Instance.new("TextLabel")
		hireHdr.Size = UDim2.new(1, 0, 0, 22)
		hireHdr.BackgroundTransparency = 1
		hireHdr.Text = "Hire"
		hireHdr.TextColor3 = Theme.SubText
		hireHdr.TextSize = 14
		hireHdr.Font = Enum.Font.GothamBold
		hireHdr.TextXAlignment = Enum.TextXAlignment.Left
		hireHdr.Parent = list
		local hireFrame = Instance.new("Frame")
		hireFrame.Size = UDim2.new(1, 0, 0, 0)
		hireFrame.AutomaticSize = Enum.AutomaticSize.Y
		hireFrame.BackgroundTransparency = 1
		hireFrame.Parent = list
		local hireLayout = Instance.new("UIListLayout")
		hireLayout.Padding = UDim.new(0, 8)
		hireLayout.Parent = hireFrame
		local catalog = StaffCatalog.all()
		table.sort(catalog, function(a, b) return a.hireCost < b.hireCost end)
		for _, spec in ipairs(catalog) do
			makeHireRow(hireFrame, spec, hireRemote)
		end

		-- Section header: hired.
		local hiredHdr = Instance.new("TextLabel")
		hiredHdr.Size = UDim2.new(1, 0, 0, 22)
		hiredHdr.BackgroundTransparency = 1
		hiredHdr.Text = string.format("Your Crew (%d)", #staffList)
		hiredHdr.TextColor3 = Theme.SubText
		hiredHdr.TextSize = 14
		hiredHdr.Font = Enum.Font.GothamBold
		hiredHdr.TextXAlignment = Enum.TextXAlignment.Left
		hiredHdr.Parent = list
		for _, member in ipairs(staffList) do
			makeMemberRow(list, member, fireRemote, upgradeRemote)
		end
	end

	staffChanged.OnClientEvent:Connect(function(staffList)
		rebuild(staffList or {})
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

return StaffPanel

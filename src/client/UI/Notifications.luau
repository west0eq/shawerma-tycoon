--!strict
--[[
	Notifications.luau

	Tiny toast stack. Server fires `Notify` with a string; we slide it in,
	hold for ~3s, and slide it out. Phase 4 will replace this with a richer
	notification feed (icons, colors per category).
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Notifications = {}

local TOAST_LIFETIME = 3
local SLIDE_TIME = 0.25

function Notifications.mount(parent: ScreenGui)
	local container = Instance.new("Frame")
	container.Name = "Notifications"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -32)
	container.Size = UDim2.new(0, 360, 0, 200)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	local function pushToast(message: string)
		local toast = Instance.new("Frame")
		toast.Size = UDim2.new(0, 0, 0, 36)
		toast.AutomaticSize = Enum.AutomaticSize.X
		toast.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
		toast.BackgroundTransparency = 0.05
		toast.Parent = container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = toast

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(220, 80, 60)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.4
		stroke.Parent = toast

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 14)
		padding.PaddingRight = UDim.new(0, 14)
		padding.Parent = toast

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 16
		label.TextColor3 = Color3.fromRGB(240, 240, 240)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.Text = message
		label.Parent = toast

		toast.BackgroundTransparency = 1
		stroke.Transparency = 1
		label.TextTransparency = 1
		TweenService:Create(toast, TweenInfo.new(SLIDE_TIME), { BackgroundTransparency = 0.05 }):Play()
		TweenService:Create(stroke, TweenInfo.new(SLIDE_TIME), { Transparency = 0.4 }):Play()
		TweenService:Create(label, TweenInfo.new(SLIDE_TIME), { TextTransparency = 0 }):Play()

		task.delay(TOAST_LIFETIME, function()
			TweenService:Create(toast, TweenInfo.new(SLIDE_TIME), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(SLIDE_TIME), { Transparency = 1 }):Play()
			TweenService:Create(label, TweenInfo.new(SLIDE_TIME), { TextTransparency = 1 }):Play()
			task.wait(SLIDE_TIME + 0.05)
			toast:Destroy()
		end)
	end

	Remotes.get(Constants.Remotes.Notify).OnClientEvent:Connect(pushToast)
end

return Notifications

--!strict
--[[
	PlotSelector.luau

	Fullscreen plot picker shown to a player who hasn't claimed a plot
	yet. Receives the list of free plots from the server (`PlotsAvailable`
	remote), aims a scriptable camera at the currently highlighted plot,
	lets the player cycle with ◄ / ► buttons or arrow keys, type a name,
	and fire `RequestClaimPlot` to claim.

	On `PlotAssigned` (own plot) the UI hides and the camera is restored.

	The panel sits on its own ScreenGui at high DisplayOrder so it draws
	above the regular HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local PlotSelector = {}

type PlotInfo = {
	index: number,
	originX: number,
	originY: number,
	originZ: number,
	facing: number,
}

local function makeButton(parent: Instance, text: string, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = Theme.AccentSoft
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Theme.Text
	b.TextSize = 22
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	b.Parent = parent
	return b
end

function PlotSelector.mount(playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "PlotSelector"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 50
	screen.Enabled = false
	screen.Parent = playerGui

	-- Dimming background panel.
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Parent = screen

	-- Bottom card containing controls.
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 720, 0, 240)
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -40)
	card.BackgroundColor3 = Theme.PanelBg
	card.BorderSizePixel = 0
	card.Parent = frame
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 16)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Theme.Border
	cardStroke.Thickness = 2
	cardStroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 40)
	title.Position = UDim2.new(0, 20, 0, 16)
	title.BackgroundTransparency = 1
	title.Text = "Choose your shawarma plot"
	title.TextColor3 = Theme.Text
	title.TextSize = 24
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -40, 0, 22)
	subtitle.Position = UDim2.new(0, 20, 0, 56)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Use ◄ / ► or arrow keys to preview. Type a name and click Claim."
	subtitle.TextColor3 = Theme.SubText
	subtitle.TextSize = 14
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = card

	-- Plot index display in the middle.
	local plotLabel = Instance.new("TextLabel")
	plotLabel.Size = UDim2.new(0, 280, 0, 60)
	plotLabel.Position = UDim2.new(0.5, -140, 0, 90)
	plotLabel.BackgroundColor3 = Theme.PanelBgAlt
	plotLabel.BorderSizePixel = 0
	plotLabel.Text = "Plot —"
	plotLabel.TextColor3 = Theme.Text
	plotLabel.TextSize = 26
	plotLabel.Font = Enum.Font.GothamBold
	plotLabel.Parent = card
	local plotLabelCorner = Instance.new("UICorner")
	plotLabelCorner.CornerRadius = UDim.new(0, 10)
	plotLabelCorner.Parent = plotLabel

	-- Prev / Next arrow buttons either side.
	local prevBtn = makeButton(card, "◄", UDim2.new(0, 60, 0, 60))
	prevBtn.Position = UDim2.new(0.5, -210, 0, 90)
	local nextBtn = makeButton(card, "►", UDim2.new(0, 60, 0, 60))
	nextBtn.Position = UDim2.new(0.5, 150, 0, 90)

	-- Name TextBox.
	local nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(0, 360, 0, 40)
	nameBox.Position = UDim2.new(0, 20, 1, -60)
	nameBox.BackgroundColor3 = Theme.PanelBgAlt
	nameBox.BorderSizePixel = 0
	nameBox.Text = ""
	nameBox.PlaceholderText = "Restaurant name…"
	nameBox.TextColor3 = Theme.Text
	nameBox.PlaceholderColor3 = Theme.SubText
	nameBox.TextSize = 16
	nameBox.Font = Enum.Font.Gotham
	nameBox.ClearTextOnFocus = false
	nameBox.TextXAlignment = Enum.TextXAlignment.Left
	nameBox.Parent = card
	local nameCorner = Instance.new("UICorner")
	nameCorner.CornerRadius = UDim.new(0, 10)
	nameCorner.Parent = nameBox
	local namePadding = Instance.new("UIPadding")
	namePadding.PaddingLeft = UDim.new(0, 10)
	namePadding.PaddingRight = UDim.new(0, 10)
	namePadding.Parent = nameBox

	-- Claim button.
	local claimBtn = makeButton(card, "Claim", UDim2.new(0, 280, 0, 40))
	claimBtn.Position = UDim2.new(1, -300, 1, -60)
	claimBtn.BackgroundColor3 = Theme.Accent

	-- Big "ALL PLOTS TAKEN" label (shown when no free plots).
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Size = UDim2.new(0, 600, 0, 50)
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "All 8 plots are taken right now. Hang tight."
	emptyLabel.TextColor3 = Theme.SubText
	emptyLabel.TextSize = 22
	emptyLabel.Font = Enum.Font.GothamBold
	emptyLabel.Visible = false
	emptyLabel.Parent = frame

	-- ----- state ---------------------------------------------------------
	local freePlots: { PlotInfo } = {}
	local selectedIdx = 1
	local active = false
	local cameraConnection: RBXScriptConnection? = nil
	local player = Players.LocalPlayer
	local localCamera = workspace.CurrentCamera
	local savedCameraType: Enum.CameraType = localCamera.CameraType

	-- Default name derived from player's display name.
	local function defaultName(): string
		return player.DisplayName .. "'s Shawarma"
	end
	nameBox.Text = defaultName()

	local function applyCamera()
		if not active or #freePlots == 0 then
			return
		end
		local plot = freePlots[selectedIdx]
		if not plot then
			return
		end
		-- Camera placed in front of the plot (toward the road, opposite
		-- the door direction so we look toward the door + sign).
		local camOffset = Vector3.new(0, 28, plot.facing * 80)
		local camPos = Vector3.new(plot.originX, plot.originY, plot.originZ) + camOffset
		local lookAt = Vector3.new(plot.originX, plot.originY + 8, plot.originZ)
		localCamera.CFrame = CFrame.lookAt(camPos, lookAt)
	end

	local function updateLabel()
		if #freePlots == 0 then
			plotLabel.Text = "—"
			emptyLabel.Visible = true
			card.Visible = false
		else
			emptyLabel.Visible = false
			card.Visible = true
			local plot = freePlots[selectedIdx]
			plotLabel.Text = string.format("Plot %02d  (%d/%d)", plot.index, selectedIdx, #freePlots)
		end
	end

	local function show(plots: { PlotInfo })
		freePlots = plots
		selectedIdx = 1
		active = true
		screen.Enabled = true
		savedCameraType = localCamera.CameraType
		localCamera.CameraType = Enum.CameraType.Scriptable
		updateLabel()
		applyCamera()

		-- Hold the camera in place every frame so other systems (e.g.
		-- character spawn at 0,0,0) don't yank it.
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		cameraConnection = RunService.RenderStepped:Connect(applyCamera)
	end

	local function hide()
		active = false
		screen.Enabled = false
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		localCamera.CameraType = savedCameraType
	end

	local function step(delta: number)
		if #freePlots == 0 then
			return
		end
		selectedIdx = ((selectedIdx - 1 + delta) % #freePlots) + 1
		updateLabel()
		applyCamera()
	end

	prevBtn.Activated:Connect(function() step(-1) end)
	nextBtn.Activated:Connect(function() step(1) end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if not active or gpe then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
			step(-1)
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
			step(1)
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			-- Same as clicking Claim.
			claimBtn:Activate()
		end
	end)

	-- Wire remotes.
	local plotsAvailable = Remotes.get(Constants.Remotes.PlotsAvailable)
	local plotAssigned = Remotes.get(Constants.Remotes.PlotAssigned)
	local requestClaim = Remotes.get(Constants.Remotes.RequestClaimPlot)

	plotsAvailable.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		show(payload :: { PlotInfo })
	end)

	plotAssigned.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and (payload :: any).index ~= nil then
			hide()
		end
	end)

	claimBtn.Activated:Connect(function()
		if not active or #freePlots == 0 then
			return
		end
		local plot = freePlots[selectedIdx]
		if not plot then
			return
		end
		local nm = nameBox.Text
		if nm == "" then
			nm = defaultName()
		end
		requestClaim:FireServer({ index = plot.index, name = nm })
	end)

	return {
		show = show,
		hide = hide,
	}
end

return PlotSelector

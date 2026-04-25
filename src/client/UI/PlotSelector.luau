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

	-- Compact card pinned to the bottom of the screen.
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 360, 0, 150)
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -24)
	card.BackgroundColor3 = Theme.PanelBg
	card.BorderSizePixel = 0
	card.Parent = frame
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Theme.Border
	cardStroke.Thickness = 1.5
	cardStroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 18)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Choose your plot"
	title.TextColor3 = Theme.Text
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 14)
	subtitle.Position = UDim2.new(0, 10, 0, 26)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "◄ ► to preview · Enter to claim"
	subtitle.TextColor3 = Theme.SubText
	subtitle.TextSize = 11
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = card

	-- Plot index display in the middle row.
	local plotLabel = Instance.new("TextLabel")
	plotLabel.Size = UDim2.new(0, 150, 0, 32)
	plotLabel.Position = UDim2.new(0.5, -75, 0, 50)
	plotLabel.BackgroundColor3 = Theme.PanelBgAlt
	plotLabel.BorderSizePixel = 0
	plotLabel.Text = "Plot —"
	plotLabel.TextColor3 = Theme.Text
	plotLabel.TextSize = 14
	plotLabel.Font = Enum.Font.GothamBold
	plotLabel.Parent = card
	local plotLabelCorner = Instance.new("UICorner")
	plotLabelCorner.CornerRadius = UDim.new(0, 6)
	plotLabelCorner.Parent = plotLabel

	-- Prev / Next arrow buttons either side.
	local prevBtn = makeButton(card, "◄", UDim2.new(0, 32, 0, 32))
	prevBtn.Position = UDim2.new(0.5, -118, 0, 50)
	prevBtn.TextSize = 16
	local nextBtn = makeButton(card, "►", UDim2.new(0, 32, 0, 32))
	nextBtn.Position = UDim2.new(0.5, 86, 0, 50)
	nextBtn.TextSize = 16

	-- Name TextBox.
	local nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(0, 200, 0, 28)
	nameBox.Position = UDim2.new(0, 10, 1, -38)
	nameBox.BackgroundColor3 = Theme.PanelBgAlt
	nameBox.BorderSizePixel = 0
	nameBox.Text = ""
	nameBox.PlaceholderText = "Restaurant name…"
	nameBox.TextColor3 = Theme.Text
	nameBox.PlaceholderColor3 = Theme.SubText
	nameBox.TextSize = 12
	nameBox.Font = Enum.Font.Gotham
	nameBox.ClearTextOnFocus = false
	nameBox.TextXAlignment = Enum.TextXAlignment.Left
	nameBox.Parent = card
	local nameCorner = Instance.new("UICorner")
	nameCorner.CornerRadius = UDim.new(0, 6)
	nameCorner.Parent = nameBox
	local namePadding = Instance.new("UIPadding")
	namePadding.PaddingLeft = UDim.new(0, 8)
	namePadding.PaddingRight = UDim.new(0, 8)
	namePadding.Parent = nameBox

	-- Claim button.
	local claimBtn = makeButton(card, "Claim", UDim2.new(0, 130, 0, 28))
	claimBtn.Position = UDim2.new(1, -140, 1, -38)
	claimBtn.TextSize = 14
	claimBtn.BackgroundColor3 = Theme.Accent

	-- Compact "ALL PLOTS TAKEN" label (shown when no free plots).
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Size = UDim2.new(0, 360, 0, 32)
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "All 8 plots are taken. Hang tight."
	emptyLabel.TextColor3 = Theme.SubText
	emptyLabel.TextSize = 16
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

	-- Default name derived from player's display name.
	local function defaultName(): string
		return player.DisplayName .. "'s Shawarma"
	end
	nameBox.Text = defaultName()

	-- While the picker is up we zero the local character's WalkSpeed +
	-- JumpPower so they can't wander. We do NOT anchor the
	-- HumanoidRootPart — anchoring fights the server-side teleport that
	-- runs right after Claim. Track the character we modified so a
	-- respawn (e.g. fell while picking) gets re-frozen.
	local frozenCharacter: Model? = nil

	local function freezeCharacter(character: Model?)
		if not character then
			return
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
		end
		frozenCharacter = character
	end

	local function unfreezeCharacter()
		local character = frozenCharacter
		frozenCharacter = nil
		if not character then
			return
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 16
			hum.JumpPower = 50
		end
	end

	-- Re-freeze on respawn so the player can't escape the picker by dying.
	player.CharacterAdded:Connect(function(character)
		if active then
			task.wait(0.2)
			freezeCharacter(character)
		end
	end)

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
		localCamera.CameraType = Enum.CameraType.Scriptable
		updateLabel()
		applyCamera()
		freezeCharacter(player.Character)

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
		unfreezeCharacter()
		-- Restore the default follow camera. We always force Custom (the
		-- default in Roblox) and re-aim it at the player's Humanoid;
		-- saving / restoring the previous CameraType would risk leaving
		-- it on Scriptable if the picker showed up before the default
		-- camera scripts initialised.
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		localCamera.CameraSubject = humanoid
		localCamera.CameraType = Enum.CameraType.Custom
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

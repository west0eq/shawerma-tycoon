--!strict
--[[
	main.client.luau

	Mounts every UI module and wires the build-mode controller. The order
	matters: HUD/Notifications first so visual feedback is up before the
	input layer starts firing remotes.
]]

local Players = game:GetService("Players")

local pkg = script.Parent
local UI = pkg:WaitForChild("UI")
local BuildMode = pkg:WaitForChild("BuildMode")

local HUD = require(UI:WaitForChild("HUD"))
local Notifications = require(UI:WaitForChild("Notifications"))
local Sidebar = require(UI:WaitForChild("Sidebar"))
local ShopPanel = require(UI:WaitForChild("ShopPanel"))
local BuildPanel = require(UI:WaitForChild("BuildPanel"))
local StaffPanel = require(UI:WaitForChild("StaffPanel"))
local UpgradePanel = require(UI:WaitForChild("UpgradePanel"))
local BuildController = require(BuildMode:WaitForChild("Controller"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hud = HUD.mount(playerGui)
Notifications.mount(hud.screen)

local sidebar = Sidebar.mount(hud.screen)
local shopPanel = ShopPanel.mount(hud.screen)
local staffPanel = StaffPanel.mount(hud.screen)
local upgradePanel = UpgradePanel.mount(hud.screen)
local buildPanel: any
local controller = BuildController.start()

local function hideAllPanels()
	shopPanel.setVisible(false)
	if buildPanel then
		buildPanel.setVisible(false)
	end
	staffPanel.setVisible(false)
	upgradePanel.setVisible(false)
end

buildPanel = BuildPanel.mount(hud.screen, function(catalogId: string)
	-- Selecting an item in the build panel begins placement and hides the
	-- panel so the player can see the world.
	buildPanel.setVisible(false)
	controller.startPlacing(catalogId)
end, function(active: boolean)
	if active then
		buildPanel.setVisible(false)
		controller.startRemoving()
	else
		controller.stopRemoving()
	end
end)

sidebar.shopButton.Activated:Connect(function()
	local target = not shopPanel.frame.Visible
	hideAllPanels()
	shopPanel.setVisible(target)
	if target then
		controller.exitMode()
	end
end)
sidebar.buildButton.Activated:Connect(function()
	local target = not buildPanel.frame.Visible
	hideAllPanels()
	buildPanel.setVisible(target)
	if not target then
		controller.exitMode()
	end
end)
sidebar.staffButton.Activated:Connect(function()
	local target = not staffPanel.frame.Visible
	hideAllPanels()
	staffPanel.setVisible(target)
	if target then
		controller.exitMode()
	end
end)
sidebar.upgradeButton.Activated:Connect(function()
	local target = not upgradePanel.frame.Visible
	hideAllPanels()
	upgradePanel.setVisible(target)
	if target then
		controller.exitMode()
	end
end)

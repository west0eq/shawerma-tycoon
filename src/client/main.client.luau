--!strict
--[[
	main.client.luau

	Client bootstrap. Mounts the HUD + notifications. Phase 2 will add the
	build-mode controller, shop / staff panels, and proximity hint overlays.
]]

local Players = game:GetService("Players")

local pkg = script.Parent
local UI = pkg:WaitForChild("UI")
local HUD = require(UI:WaitForChild("HUD"))
local Notifications = require(UI:WaitForChild("Notifications"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local hud = HUD.mount(playerGui)
Notifications.mount(hud.screen)

print("[ShawermaTycoon] Client ready.")

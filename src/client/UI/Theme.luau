--!strict
--[[
	Theme.luau

	Visual tokens shared across UI modules. Centralising here means a
	restyle is a one-file edit later.
]]

local Theme = {}

Theme.PanelBg = Color3.fromRGB(22, 22, 28)
Theme.PanelBgAlt = Color3.fromRGB(32, 32, 42)
Theme.Accent = Color3.fromRGB(220, 80, 60)
Theme.AccentSoft = Color3.fromRGB(180, 60, 40)
Theme.Text = Color3.fromRGB(240, 240, 240)
Theme.SubText = Color3.fromRGB(170, 170, 180)
Theme.Good = Color3.fromRGB(120, 200, 120)
Theme.Bad = Color3.fromRGB(220, 80, 80)
Theme.Border = Color3.fromRGB(60, 60, 70)

Theme.CornerRadius = UDim.new(0, 12)
Theme.PanelStrokeWidth = 2

return Theme

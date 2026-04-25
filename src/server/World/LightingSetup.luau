--!strict
--[[
	LightingSetup.luau

	Configures Lighting for an early-evening / dusk look. The scene is
	deliberately dimmed so the warm interior ceiling lamps and exterior
	street lamps actually read on screen. All values are conservative —
	the game still renders fine on low-end devices.
]]

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

function LightingSetup.apply()
	-- Cool, dim base ambient so warm point lights pop. Not pitch black —
	-- daytime gameplay still needs to read at a glance.
	Lighting.Ambient = Color3.fromRGB(55, 60, 75)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 78, 95)
	Lighting.Brightness = 1.0
	-- Dusk: sun low on the horizon, long warm shadows.
	Lighting.ClockTime = 18.4
	Lighting.GeographicLatitude = 41
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.5
	Lighting.FogColor = Color3.fromRGB(70, 80, 95)
	Lighting.FogStart = 220
	Lighting.FogEnd = 520
	Lighting.ExposureCompensation = -0.35

	-- Replace any existing post-process effects so a re-apply is idempotent.
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.42
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(180, 165, 165)
	atmosphere.Decay = Color3.fromRGB(80, 90, 110)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 20
	sky.MoonAngularSize = 11
	sky.StarCount = 1500
	sky.SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex"
	sky.SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex"
	sky.SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex"
	sky.SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex"
	sky.SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex"
	sky.SkyboxUp = "rbxasset://textures/sky/sky512_up.tex"
	sky.Parent = Lighting

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Brightness = -0.08
	correction.Contrast = 0.18
	correction.Saturation = 0.22
	-- Slight warm tint without going orange; balances the cool ambient.
	correction.TintColor = Color3.fromRGB(255, 240, 220)
	correction.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 22
	bloom.Threshold = 0.85
	bloom.Parent = Lighting
end

return LightingSetup

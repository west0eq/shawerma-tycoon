--!strict
--[[
	LightingSetup.luau

	Configures Lighting so the procedural world doesn't render blown-out
	white. Defaults the post-processing stack to a warm, slightly dimmed
	street-food look. All values are conservative — the game renders fine
	on low-end devices.
]]

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

function LightingSetup.apply()
	Lighting.Ambient = Color3.fromRGB(95, 95, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 125)
	Lighting.Brightness = 1.4
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 45
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.4
	Lighting.FogColor = Color3.fromRGB(170, 175, 185)
	Lighting.FogStart = 250
	Lighting.FogEnd = 600
	Lighting.ExposureCompensation = -0.2

	-- Replace any existing post-process effects so a re-apply is idempotent.
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(220, 225, 230)
	atmosphere.Decay = Color3.fromRGB(95, 110, 130)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.0
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 18
	sky.MoonAngularSize = 11
	sky.StarCount = 0
	sky.SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex"
	sky.SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex"
	sky.SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex"
	sky.SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex"
	sky.SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex"
	sky.SkyboxUp = "rbxasset://textures/sky/sky512_up.tex"
	sky.Parent = Lighting

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Brightness = -0.05
	correction.Contrast = 0.12
	correction.Saturation = 0.15
	correction.TintColor = Color3.fromRGB(255, 248, 235)
	correction.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 18
	bloom.Threshold = 0.95
	bloom.Parent = Lighting
end

return LightingSetup

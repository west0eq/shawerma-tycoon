--!strict
--[[
	CharacterRig.luau

	Procedural humanoid rig used for both customers and staff. The torso is
	anchored and acts as the model's PrimaryPart, every other body part is
	welded to the torso so `Model:PivotTo(cf)` (or tweening the torso CFrame)
	moves the whole rig as one unit.

	Output Model layout:
	    Torso (anchored, primary)
	      ├─ Head (welded)
	      ├─ HeadHair (welded to head, optional)
	      ├─ Hat (welded to head, optional)
	      ├─ ArmL, ArmR (welded)
	      ├─ LegL, LegR (welded)
	      └─ Nameplate BillboardGui (parented to head, optional)

	The rig is intentionally flat-shaded SmoothPlastic — Roblox's default
	NPC look. It tries to match a basic R15 silhouette without depending on
	any Studio assets so the game runs from a pure Rojo flow.
]]

local CharacterRig = {}

export type RigSpec = {
	name: string?,
	skinTone: Color3?,
	shirtColor: Color3?,
	pantsColor: Color3?,
	hairColor: Color3?,
	hatColor: Color3?,
	-- Optional text shown on a billboard above the head.
	nameplate: string?,
	-- Optional secondary line under the nameplate (e.g. role).
	subtitle: string?,
}

local DEFAULT_SKIN = Color3.fromRGB(243, 207, 169)
local DEFAULT_SHIRT = Color3.fromRGB(80, 90, 140)
local DEFAULT_PANTS = Color3.fromRGB(60, 60, 70)
local DEFAULT_HAIR = Color3.fromRGB(40, 30, 25)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

local function weld(a: BasePart, b: BasePart, c0: CFrame): Weld
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = c0
	w.Parent = a
	return w
end

-- Total rig height ≈ 5.4 studs (legs 1.8 + torso 2.0 + head 1.2 + hair 0.4).
function CharacterRig.build(spec: RigSpec): Model
	local skin = spec.skinTone or DEFAULT_SKIN
	local shirt = spec.shirtColor or DEFAULT_SHIRT
	local pants = spec.pantsColor or DEFAULT_PANTS
	local hairColor = spec.hairColor or DEFAULT_HAIR

	local model = Instance.new("Model")
	model.Name = spec.name or "Rig"

	-- Torso (the anchored root). Position it so its centre is ~3 studs
	-- above ground when the model is dropped at y=0.
	local torso = part({
		Name = "Torso",
		Size = Vector3.new(2, 2, 1),
		Color = shirt,
		Anchored = true,
	})
	torso.CFrame = CFrame.new(0, 2.8, 0)
	torso.Parent = model
	model.PrimaryPart = torso

	-- Head
	local head = part({
		Name = "Head",
		Size = Vector3.new(1.2, 1.2, 1.2),
		Shape = Enum.PartType.Ball,
		Color = skin,
	})
	head.CFrame = torso.CFrame * CFrame.new(0, 1.6, 0)
	head.Parent = model
	weld(torso, head, CFrame.new(0, 1.6, 0))

	-- Hair cap (rounded slab on top of head). Skipped if hatColor provided.
	if not spec.hatColor then
		local hair = part({
			Name = "Hair",
			Size = Vector3.new(1.3, 0.5, 1.3),
			Color = hairColor,
		})
		hair.CFrame = head.CFrame * CFrame.new(0, 0.5, 0)
		hair.Parent = model
		weld(head, hair, CFrame.new(0, 0.5, 0))
	else
		local hat = part({
			Name = "Hat",
			Size = Vector3.new(1.4, 0.45, 1.4),
			Color = spec.hatColor :: Color3,
		})
		hat.CFrame = head.CFrame * CFrame.new(0, 0.55, 0)
		hat.Parent = model
		weld(head, hat, CFrame.new(0, 0.55, 0))
	end

	-- Arms (slimmer than torso so the silhouette reads).
	local function arm(name: string, xOffset: number)
		local a = part({
			Name = name,
			Size = Vector3.new(0.7, 2, 0.9),
			Color = shirt,
		})
		a.CFrame = torso.CFrame * CFrame.new(xOffset, 0, 0)
		a.Parent = model
		weld(torso, a, CFrame.new(xOffset, 0, 0))
	end
	arm("ArmL", -1.35)
	arm("ArmR", 1.35)

	-- Legs.
	local function leg(name: string, xOffset: number)
		local l = part({
			Name = name,
			Size = Vector3.new(0.9, 1.8, 0.9),
			Color = pants,
		})
		l.CFrame = torso.CFrame * CFrame.new(xOffset, -1.9, 0)
		l.Parent = model
		weld(torso, l, CFrame.new(xOffset, -1.9, 0))
	end
	leg("LegL", -0.55)
	leg("LegR", 0.55)

	-- Optional nameplate.
	if spec.nameplate then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Nameplate"
		gui.Size = UDim2.new(0, 160, 0, 36)
		gui.AlwaysOnTop = true
		gui.StudsOffset = Vector3.new(0, 1.8, 0)
		gui.Parent = head

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, 0, spec.subtitle and 0.55 or 1, 0)
		txt.BackgroundTransparency = 1
		txt.Text = spec.nameplate
		txt.TextColor3 = Color3.new(1, 1, 1)
		txt.TextStrokeTransparency = 0.2
		txt.Font = Enum.Font.GothamBold
		txt.TextSize = 14
		txt.Parent = gui

		if spec.subtitle then
			local sub = Instance.new("TextLabel")
			sub.Size = UDim2.new(1, 0, 0.45, 0)
			sub.Position = UDim2.new(0, 0, 0.55, 0)
			sub.BackgroundTransparency = 1
			sub.Text = spec.subtitle
			sub.TextColor3 = Color3.fromRGB(220, 220, 220)
			sub.TextStrokeTransparency = 0.4
			sub.Font = Enum.Font.Gotham
			sub.TextSize = 12
			sub.Parent = gui
		end
	end

	return model
end

-- Pre-mixed palettes for variety. CustomerService picks one per spawn.
CharacterRig.CUSTOMER_PALETTES = {
	{
		skinTone = Color3.fromRGB(243, 207, 169),
		shirtColor = Color3.fromRGB(220, 80, 80),
		pantsColor = Color3.fromRGB(45, 50, 70),
		hairColor = Color3.fromRGB(40, 25, 20),
	},
	{
		skinTone = Color3.fromRGB(225, 175, 140),
		shirtColor = Color3.fromRGB(80, 140, 220),
		pantsColor = Color3.fromRGB(80, 70, 60),
		hairColor = Color3.fromRGB(95, 65, 35),
	},
	{
		skinTone = Color3.fromRGB(190, 130, 90),
		shirtColor = Color3.fromRGB(60, 180, 110),
		pantsColor = Color3.fromRGB(35, 40, 50),
		hairColor = Color3.fromRGB(30, 25, 25),
	},
	{
		skinTone = Color3.fromRGB(243, 207, 169),
		shirtColor = Color3.fromRGB(255, 195, 70),
		pantsColor = Color3.fromRGB(50, 50, 60),
		hairColor = Color3.fromRGB(220, 180, 120),
	},
	{
		skinTone = Color3.fromRGB(135, 90, 60),
		shirtColor = Color3.fromRGB(170, 90, 200),
		pantsColor = Color3.fromRGB(55, 40, 35),
		hairColor = Color3.fromRGB(20, 20, 20),
	},
	{
		skinTone = Color3.fromRGB(225, 175, 140),
		shirtColor = Color3.fromRGB(240, 140, 70),
		pantsColor = Color3.fromRGB(40, 60, 90),
		hairColor = Color3.fromRGB(220, 100, 60),
	},
}

return CharacterRig

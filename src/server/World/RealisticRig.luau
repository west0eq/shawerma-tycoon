--!strict
--[[
	RealisticRig.luau

	Builds R15 NPC characters that look like real Roblox players. We pull
	a `HumanoidDescription` from a curated list of public Roblox userIds
	via `Players:GetHumanoidDescriptionFromUserId(userId)` and feed it to
	`Players:CreateHumanoidModelFromDescription` to get a fully-clothed,
	properly-haired avatar, then we re-parent / re-anchor it so existing
	movement code (which tweens the torso CFrame) still works.

	Why anchor instead of using `Humanoid:MoveTo()`?  CustomerService and
	StaffService were originally built around tweened torsos so the
	walking is fully deterministic and not subject to Roblox's stuck-
	pathfinding edge cases. We keep that invariant. Animations still
	play (Motor6D-driven, independent of physics) so the rig still looks
	alive even with an anchored HRP.

	Fallback: if `GetHumanoidDescriptionFromUserId` errors out (network
	rate-limit, Studio not signed in, deleted account, etc.) we transparently
	fall back to the procedural `CharacterRig` so the game still runs.

	Output Model layout:
	    HumanoidRootPart  (anchored, primary, network-disabled)
	      ├─ Humanoid (Health=Inf so it never dies)
	      ├─ all R15 limb parts welded via Motor6D
	      ├─ Accessory[]  (hair, hats, etc.)
	      └─ Animator child of Humanoid
	    + Optional BillboardGui above the head with a nameplate.

	Caching: descriptions are cached forever per-userId; rig clones are
	produced from the cached description (one fetch per unique avatar).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local RealisticRig = {}

-- A handful of well-known public userIds with diverse Roblox avatars.
-- Sticking to a small curated list keeps requests cacheable and avoids
-- hammering `GetHumanoidDescriptionFromUserId` with random IDs that
-- might 404. None of these accounts are required for the game to run —
-- if any fetch fails the rig falls back to the procedural builder.
local DEFAULT_USER_IDS: { number } = {
	1, -- Roblox (the staff account; avatar is a guarantee).
	261, -- Shedletsky / Telamon — extremely well-known account.
	16, -- erik.cassel
	118271815, -- Builderman variant
	2231221, -- Stickmasterluke
	48103520, -- DenisDaily-era classic avatar
	1019432, -- Loleris
	138096841, -- KreekCraft
	7977612, -- Linkmon99
	131963900, -- Tofuu
	93961128, -- Flamingo's older avatar
	48395067, -- BiGGames-era avatar
}

-- Cached per-userId HumanoidDescription. nil means "not fetched", false
-- means "tried and failed; do not retry".
local descCache: { [number]: any } = {}

-- Names assigned to nameplates when the customer is anonymous.
local FALLBACK_NAMES = {
	"Liam", "Noah", "Sofia", "Mia", "Elena", "Yusuf", "Leyla", "Omar",
	"Aria", "Ezra", "Maya", "Jonas", "Ines", "Idris", "Zara", "Sami",
}

export type RigSpec = {
	name: string?,
	nameplate: string?,
	subtitle: string?,
	-- Optional override; if nil we pick from the default pool.
	userId: number?,
}

local function tryFetchDescription(userId: number): HumanoidDescription?
	if descCache[userId] ~= nil then
		if descCache[userId] == false then
			return nil
		end
		return descCache[userId]
	end
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if ok and desc then
		descCache[userId] = desc
		return desc
	else
		warn(string.format("[RealisticRig] GetHumanoidDescriptionFromUserId(%d) failed: %s", userId, tostring(desc)))
		descCache[userId] = false
		return nil
	end
end

local function buildModelFromDescription(desc: HumanoidDescription): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn(string.format("[RealisticRig] CreateHumanoidModelFromDescription failed: %s", tostring(model)))
		return nil
	end
	return model
end

local function preparePart(part: BasePart)
	-- Anchor HRP so the rig stops at our requested CFrame and never
	-- ragdolls. All other body parts are unanchored so Motor6D
	-- animations can still drive them.
	if part.Name == "HumanoidRootPart" then
		part.Anchored = true
		part.CanCollide = false
	else
		part.Anchored = false
		part.CanCollide = false
	end
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function attachNameplate(model: Model, nameplate: string?, subtitle: string?)
	if not nameplate then
		return
	end
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.new(0, 110, 0, subtitle and 36 or 22)
	gui.StudsOffset = Vector3.new(0, 1.7, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(245, 245, 240)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = nameplate
	label.Parent = gui

	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, 0, 0, 14)
		sub.Position = UDim2.new(0, 0, 0, 18)
		sub.BackgroundTransparency = 1
		sub.TextColor3 = Color3.fromRGB(200, 200, 200)
		sub.TextStrokeTransparency = 0.4
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 11
		sub.Text = subtitle
		sub.Parent = gui
	end
end

-- Default Roblox walk + idle animations. AssetIds are stable Roblox-
-- internal animations, available at runtime without uploading.
local DEFAULT_ANIM_WALK = "rbxassetid://180426354"
local DEFAULT_ANIM_IDLE = "rbxassetid://180435571"

-- Per-model AnimationTrack registry. Indexed by Model so playWalk /
-- stopWalk can reach the tracks without poking at descendants every
-- frame. Cleared automatically when the model is destroyed.
local trackRegistry: { [Model]: { idle: AnimationTrack?, walk: AnimationTrack? } } = {}

local function attachAnimations(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local idleAnim = Instance.new("Animation")
	idleAnim.AnimationId = DEFAULT_ANIM_IDLE
	idleAnim.Name = "IdleAnimation"
	idleAnim.Parent = humanoid
	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = DEFAULT_ANIM_WALK
	walkAnim.Name = "WalkAnimation"
	walkAnim.Parent = humanoid

	local idleTrack: AnimationTrack? = nil
	local walkTrack: AnimationTrack? = nil
	if RunService:IsServer() then
		local okI, t = pcall(function()
			return animator:LoadAnimation(idleAnim)
		end)
		if okI and t then
			idleTrack = t
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Idle
			t:Play()
		end
		local okW, w = pcall(function()
			return animator:LoadAnimation(walkAnim)
		end)
		if okW and w then
			walkTrack = w
			w.Looped = true
			w.Priority = Enum.AnimationPriority.Movement
		end
	end
	trackRegistry[model] = { idle = idleTrack, walk = walkTrack }
	model.Destroying:Connect(function()
		trackRegistry[model] = nil
	end)
end

-- Public: switch a realistic rig into the walk loop. No-op for
-- procedural rigs (the registry won't have an entry for them).
function RealisticRig.playWalk(model: Model)
	local entry = trackRegistry[model]
	if not entry then
		return
	end
	if entry.walk and not entry.walk.IsPlaying then
		entry.walk:Play(0.15)
	end
	if entry.idle and entry.idle.IsPlaying then
		entry.idle:Stop(0.15)
	end
end

-- Public: stop the walk loop and let idle resume.
function RealisticRig.stopWalk(model: Model)
	local entry = trackRegistry[model]
	if not entry then
		return
	end
	if entry.walk and entry.walk.IsPlaying then
		entry.walk:Stop(0.15)
	end
	if entry.idle and not entry.idle.IsPlaying then
		entry.idle:Play(0.15)
	end
end

-- Public: query whether the given model is a RealisticRig (so callers
-- can decide whether to drive walk/idle or fall back).
function RealisticRig.isRealistic(model: Model): boolean
	return trackRegistry[model] ~= nil
end

-- Pick a userId for the next rig. We rotate through DEFAULT_USER_IDS so
-- there's variety but caching still works after the first ~8 customers.
local nextUserIndex = 0
local function pickUserId(): number
	nextUserIndex = (nextUserIndex % #DEFAULT_USER_IDS) + 1
	return DEFAULT_USER_IDS[nextUserIndex]
end

-- Public: try to build a realistic R15 rig. Returns the Model on
-- success, or nil if every attempt failed (caller should fall back to
-- the procedural rig).
function RealisticRig.tryBuild(spec: RigSpec): Model?
	local userId = spec.userId or pickUserId()
	local desc = tryFetchDescription(userId)
	if not desc then
		-- One more attempt with a guaranteed-to-exist userId before giving up.
		desc = tryFetchDescription(1)
	end
	if not desc then
		return nil
	end
	local model = buildModelFromDescription(desc)
	if not model then
		return nil
	end
	model.Name = spec.name or "RealisticNPC"
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			preparePart(descendant)
		end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		model.PrimaryPart = hrp
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HealthDisplayDistance = 0
		humanoid.NameDisplayDistance = 0
		humanoid.Health = math.huge
		humanoid.MaxHealth = math.huge
		humanoid.AutomaticScalingEnabled = false
	end
	attachAnimations(model)
	attachNameplate(model, spec.nameplate, spec.subtitle)
	return model
end

function RealisticRig.randomFallbackName(): string
	return FALLBACK_NAMES[math.random(1, #FALLBACK_NAMES)]
end

-- Optional: tell the rig system to also pull in the local owner's
-- friend list so customers occasionally look like the player's friends.
-- This is a convenience helper — callers can also pass userIds directly.
function RealisticRig.populateFriendsOf(player: Player, maxFriends: number?)
	if Constants.Customer.UseRealisticRigs == false then
		return
	end
	local cap = maxFriends or 8
	task.spawn(function()
		local ok, pages = pcall(function()
			return Players:GetFriendsAsync(player.UserId)
		end)
		if not ok or not pages then
			return
		end
		local added = 0
		while added < cap do
			local page = pages:GetCurrentPage()
			for _, info in ipairs(page) do
				if added >= cap then
					break
				end
				if info.Id then
					table.insert(DEFAULT_USER_IDS, info.Id)
					added += 1
				end
			end
			if pages.IsFinished then
				break
			end
			local okNext = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			if not okNext then
				break
			end
		end
	end)
end

return RealisticRig

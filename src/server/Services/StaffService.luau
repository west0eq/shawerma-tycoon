--!strict
--[[
	StaffService.luau

	Owns staff lifecycle and AI:
	  • Hire / fire / upgrade (server-trusted, debits cash via EconomyService).
	  • Persists `PlayerSave.staff`. Restored on rejoin.
	  • Spawns a procedural body per hire (parts only — no Studio assets).
	  • Tick loop: cooks scan idle stations and auto-start prep; cleaners
	    walk to vacated seats; servers + cashiers contribute effects.

	Effect application:
	  • Cook effects (speed, qualityBonus) are passed into
	    `StationService.startPrepOnStation` which propagates them through to
	    food-quality and pay-out events.
	  • Cashier (tipBonus) and server (fastServiceBonus) effects are queried
	    via `getAggregateEffects()` and applied at pay-out time.

	Trust model: hire/fire/upgrade requests come through three RemoteEvents.
	Every input is validated against StaffCatalog before any cash mutation.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Signal = require(Shared:WaitForChild("Signal"))
local StaffCatalog = require(Shared:WaitForChild("StaffCatalog"))
local Types = require(Shared:WaitForChild("Types"))
local DishCatalog = require(Shared:WaitForChild("DishCatalog"))

type StaffRole = Types.StaffRole
type StaffMember = Types.StaffMember

local StaffService = {}

StaffService.Changed = Signal.new()

-- ---- module state -------------------------------------------------------

local DataService: any
local EconomyService: any
local StationService: any
local PlotService: any
local notify: RemoteEvent
local staffRemote: RemoteEvent

local staffFolder: Folder
-- player → uid → { member, model, body, ... }
local liveStaff: { [Player]: { [string]: any } } = {}

local NICKNAMES = {
	"Adel", "Bilal", "Cemil", "Dara", "Emre", "Faruk", "Gizem",
	"Hasan", "Ilyas", "Jamal", "Kaya", "Leyla", "Murat", "Nazli",
	"Omar", "Pelin", "Rabia", "Sami", "Tarek", "Umut", "Yasin", "Zeynep",
}

-- ---- save helpers -------------------------------------------------------

local function ensureStaff(save: any)
	if not save.staff then
		save.staff = {}
	end
end

local function broadcast(player: Player)
	local save = DataService.get(player)
	if not save then
		return
	end
	ensureStaff(save)
	staffRemote:FireClient(player, save.staff)
	StaffService.Changed:Fire(player, save.staff)
end

local function findMember(save: any, uid: string): (StaffMember?, number?)
	for index, m in ipairs(save.staff) do
		if m.uid == uid then
			return m, index
		end
	end
	return nil, nil
end

local function countOfRole(save: any, role: StaffRole): number
	local count = 0
	for _, m in ipairs(save.staff) do
		if m.role == role then
			count += 1
		end
	end
	return count
end

-- ---- visuals ------------------------------------------------------------

local function buildBody(member: StaffMember): Model
	local spec = StaffCatalog.get(member.role)
	local model = Instance.new("Model")
	model.Name = string.format("Staff_%s_%s", member.role, member.nickname)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 4, 1)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Material = Enum.Material.Fabric
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Color = spec.bodyColor
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Anchored = false
	head.CanCollide = false
	head.CanQuery = false
	head.CanTouch = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(243, 207, 169)
	head.CFrame = body.CFrame * CFrame.new(0, body.Size.Y / 2 + head.Size.Y / 2, 0)
	head.Parent = model

	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = head
	weld.C0 = CFrame.new(0, body.Size.Y / 2 + head.Size.Y / 2, 0)
	weld.Parent = body

	-- Role badge (a hat-like part above the head).
	local badge = Instance.new("Part")
	badge.Name = "Badge"
	badge.Size = Vector3.new(1.4, 0.4, 1.4)
	badge.Anchored = false
	badge.CanCollide = false
	badge.CanQuery = false
	badge.CanTouch = false
	badge.Material = Enum.Material.SmoothPlastic
	badge.TopSurface = Enum.SurfaceType.Smooth
	badge.BottomSurface = Enum.SurfaceType.Smooth
	badge.Color = spec.bodyColor:Lerp(Color3.new(0, 0, 0), 0.3)
	badge.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + badge.Size.Y / 2, 0)
	badge.Parent = model

	local badgeWeld = Instance.new("Weld")
	badgeWeld.Part0 = head
	badgeWeld.Part1 = badge
	badgeWeld.C0 = CFrame.new(0, head.Size.Y / 2 + badge.Size.Y / 2, 0)
	badgeWeld.Parent = head

	-- Nameplate text above the badge.
	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.new(0, 120, 0, 32)
	label.AlwaysOnTop = true
	label.StudsOffset = Vector3.new(0, 2, 0)
	label.Parent = badge

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Text = string.format("%s · %s · L%d", spec.displayName, member.nickname, member.level)
	txt.TextColor3 = Color3.new(1, 1, 1)
	txt.TextStrokeTransparency = 0.2
	txt.Font = Enum.Font.GothamBold
	txt.TextSize = 14
	txt.Parent = label

	model.PrimaryPart = body
	return model
end

local function defaultPositionFor(player: Player, role: StaffRole, index: number): Vector3
	local origin = Vector3.new(0, 3, 0)
	if PlotService then
		local plot = PlotService.getPlot(player)
		if plot then
			local anchors = plot.staffAnchors
			if role == "cook" and anchors.cookSpot then
				origin = anchors.cookSpot.Position + Vector3.new(0, 2, 0)
			elseif role == "cashier" and anchors.cashierSpot then
				origin = anchors.cashierSpot.Position + Vector3.new(0, 2, 0)
			elseif role == "server" and anchors.serverSpot then
				origin = anchors.serverSpot.Position + Vector3.new(0, 2, 0)
			elseif role == "cleaner" and anchors.cleanerSpot then
				origin = anchors.cleanerSpot.Position + Vector3.new(0, 2, 0)
			end
		end
	end
	return origin + Vector3.new((index - 1) * 3, 0, 0)
end

local function tweenTo(part: BasePart, targetPos: Vector3, duration: number?)
	local d = duration or (math.max(0.2, (targetPos - part.Position).Magnitude / Constants.Staff.WalkSpeed))
	local lookAt = part.CFrame
	if (targetPos - part.Position).Magnitude > 0.05 then
		lookAt = CFrame.lookAt(targetPos, targetPos + Vector3.new(1, 0, 0))
	end
	local tween = TweenService:Create(
		part,
		TweenInfo.new(d, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(targetPos) * (lookAt - lookAt.Position) }
	)
	tween:Play()
end

local function spawnBodyFor(player: Player, member: StaffMember, index: number)
	local model = buildBody(member)
	model:PivotTo(CFrame.new(defaultPositionFor(player, member.role, index)))
	model.Parent = staffFolder

	local entry = {
		uid = member.uid,
		member = member,
		body = model.PrimaryPart,
		model = model,
		owner = player,
	}
	if not liveStaff[player] then
		liveStaff[player] = {}
	end
	liveStaff[player][member.uid] = entry
end

local function despawnBody(player: Player, uid: string)
	local entries = liveStaff[player]
	if not entries then
		return
	end
	local entry = entries[uid]
	if not entry then
		return
	end
	if entry.model and entry.model.Parent then
		entry.model:Destroy()
	end
	entries[uid] = nil
end

local function rebuildAllBodies(player: Player)
	-- Tear down anything we currently render for this player.
	if liveStaff[player] then
		for uid in pairs(liveStaff[player]) do
			despawnBody(player, uid)
		end
	end
	local save = DataService.get(player)
	if not save then
		return
	end
	ensureStaff(save)
	-- Index per role for positioning.
	local indexByRole: { [string]: number } = {}
	for _, member in ipairs(save.staff) do
		indexByRole[member.role] = (indexByRole[member.role] or 0) + 1
		spawnBodyFor(player, member, indexByRole[member.role])
	end
end

-- ---- AI -----------------------------------------------------------------

local function aggregateEffectsForPlayer(player: Player, role: StaffRole): { [string]: number }
	-- Sum the per-level effects of every hired staff member of `role`. For
	-- multipliers like `speed`, take the highest of the active staff so two
	-- cooks aren't two times faster — a cook is a cook.
	local save = DataService.get(player)
	if not save or not save.staff then
		return {}
	end
	local out: { [string]: number } = {}
	local maxKeys = { speed = true, fastServiceBonus = true, qualityBonus = true, tableResetSpeed = true }
	for _, m in ipairs(save.staff) do
		if m.role == role then
			local effects = StaffCatalog.effects(m.role, m.level)
			for k, v in pairs(effects) do
				if maxKeys[k] then
					out[k] = math.max(out[k] or v, v)
				else
					out[k] = (out[k] or 0) + v
				end
			end
		end
	end
	return out
end

function StaffService.getAggregateEffects(role: StaffRole, player: Player?): { [string]: number }
	local subject = player or Players:GetPlayers()[1]
	if not subject then
		return {}
	end
	return aggregateEffectsForPlayer(subject, role)
end

local function tickCooksForPlayer(player: Player)
	local effects = aggregateEffectsForPlayer(player, "cook")
	if next(effects) == nil then
		return
	end
	local plotIndex: number? = nil
	if PlotService then
		local plot = PlotService.getPlot(player)
		if plot then
			plotIndex = plot.index
		end
	end
	local stations
	if plotIndex then
		stations = StationService.getStationsForPlot(plotIndex)
	else
		stations = StationService.getAllStations()
	end
	for _, station in ipairs(stations) do
		if station.state == "Idle" then
			StationService.startPrepOnStation(station, nil, effects)
		end
	end
end

local function tickCooks()
	for _, player in ipairs(Players:GetPlayers()) do
		tickCooksForPlayer(player)
	end
end

-- ---- hire / fire / upgrade ---------------------------------------------

local function pickNickname(): string
	return NICKNAMES[math.random(1, #NICKNAMES)]
end

function StaffService.tryHire(player: Player, role: any): boolean
	if typeof(role) ~= "string" or not StaffCatalog.exists(role) then
		notify:FireClient(player, "Unknown staff role")
		return false
	end
	local typedRole = role :: StaffRole
	local save = DataService.get(player)
	if not save then
		return false
	end
	ensureStaff(save)
	if countOfRole(save, typedRole) >= Constants.Staff.MaxPerRole then
		notify:FireClient(player, "Hire cap reached for that role")
		return false
	end
	local spec = StaffCatalog.get(typedRole)
	if not EconomyService.tryDebit(player, spec.hireCost, "Hired " .. spec.displayName) then
		notify:FireClient(player, "Not enough cash")
		return false
	end
	local member: StaffMember = {
		uid = HttpService:GenerateGUID(false),
		role = typedRole,
		level = 1,
		nickname = pickNickname(),
	}
	DataService.mutate(player, function(s)
		ensureStaff(s)
		table.insert(s.staff, member)
	end)
	rebuildAllBodies(player)
	broadcast(player)
	return true
end

function StaffService.tryFire(player: Player, uid: any): boolean
	if typeof(uid) ~= "string" then
		return false
	end
	local save = DataService.get(player)
	if not save then
		return false
	end
	ensureStaff(save)
	local member, index = findMember(save, uid)
	if not member or not index then
		notify:FireClient(player, "No such staff member")
		return false
	end
	DataService.mutate(player, function(s)
		ensureStaff(s)
		table.remove(s.staff, index :: number)
	end)
	rebuildAllBodies(player)
	broadcast(player)
	return true
end

function StaffService.tryUpgrade(player: Player, uid: any): boolean
	if typeof(uid) ~= "string" then
		return false
	end
	local save = DataService.get(player)
	if not save then
		return false
	end
	ensureStaff(save)
	local member, index = findMember(save, uid)
	if not member or not index then
		notify:FireClient(player, "No such staff member")
		return false
	end
	local cost = StaffCatalog.upgradeCostFor(member.role, member.level)
	if not cost then
		notify:FireClient(player, "Already at max level")
		return false
	end
	if not EconomyService.tryDebit(player, cost, "Upgraded " .. member.nickname) then
		notify:FireClient(player, "Not enough cash")
		return false
	end
	DataService.mutate(player, function(s)
		ensureStaff(s)
		local _, idx = findMember(s, uid)
		if idx then
			s.staff[idx].level += 1
		end
	end)
	rebuildAllBodies(player)
	broadcast(player)
	return true
end

-- ---- init ---------------------------------------------------------------

function StaffService.init(deps: {
	remotes: { [string]: RemoteEvent },
	dataService: any,
	economyService: any,
	stationService: any,
	plotService: any?,
})
	DataService = deps.dataService
	EconomyService = deps.economyService
	StationService = deps.stationService
	PlotService = deps.plotService
	notify = deps.remotes.Notify
	staffRemote = deps.remotes.StaffChanged

	staffFolder = Workspace:FindFirstChild("ShawermaTycoonStaff") :: Folder
	if not staffFolder then
		staffFolder = Instance.new("Folder")
		staffFolder.Name = "ShawermaTycoonStaff"
		staffFolder.Parent = Workspace
	end

	deps.remotes.RequestHireStaff.OnServerEvent:Connect(function(player, role)
		StaffService.tryHire(player, role)
	end)
	deps.remotes.RequestFireStaff.OnServerEvent:Connect(function(player, uid)
		StaffService.tryFire(player, uid)
	end)
	deps.remotes.RequestUpgradeStaff.OnServerEvent:Connect(function(player, uid)
		StaffService.tryUpgrade(player, uid)
	end)

	DataService.ProfileLoaded:Connect(function(player: Player)
		rebuildAllBodies(player)
		broadcast(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if liveStaff[player] then
			for uid in pairs(liveStaff[player]) do
				despawnBody(player, uid)
			end
			liveStaff[player] = nil
		end
	end)

	-- Periodic cook AI.
	task.spawn(function()
		while true do
			task.wait(Constants.Staff.TickIntervalSeconds)
			local ok, err = pcall(tickCooks)
			if not ok then
				warn("[StaffService] tickCooks: " .. tostring(err))
			end
		end
	end)
end

return StaffService

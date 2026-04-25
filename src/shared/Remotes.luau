--!strict
--[[
	Remotes.luau

	Lazily fetches (or, on the server, creates) the central Remotes folder used
	by every gameplay service. Keeping all remotes named in `Constants.Remotes`
	means there is exactly one place to audit the network surface.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Constants)

local FOLDER_NAME = "ShawermaTycoonRemotes"

local function ensureRemote(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function build(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	-- Only the server should create the folder. Clients wait for it.
	if not RunService:IsServer() then
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
		assert(folder, "Remotes folder did not replicate within 30s")
		assert(folder:IsA("Folder"), "Remotes is not a Folder")
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local Remotes = {}

function Remotes.init(): { [string]: Instance }
	assert(RunService:IsServer(), "Remotes.init must run on the server")
	local folder = build()
	local registry = {}

	for key, name in pairs(Constants.Remotes) do
		-- All P1 remotes are events; we'll add RemoteFunctions in P2 if needed.
		registry[key] = ensureRemote(folder, name, "RemoteEvent")
	end

	return registry
end

function Remotes.get(name: string): RemoteEvent
	local folder = build()
	local remote = folder:WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteEvent"), "Remote '" .. name .. "' missing")
	return remote
end

return Remotes

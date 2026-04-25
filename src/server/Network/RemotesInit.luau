--!strict
--[[
	RemotesInit.luau

	Thin wrapper that boots the shared Remotes folder. Lives on the server side
	so we can grow server-only network helpers (rate limiting, validation
	wrappers) without poking the shared module.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local RemotesInit = {}

function RemotesInit.start(): { [string]: RemoteEvent }
	local registry = Remotes.init()
	-- Cast the loose `Instance` map to RemoteEvent for downstream callers.
	local typed: { [string]: RemoteEvent } = {}
	for key, instance in pairs(registry) do
		assert(instance:IsA("RemoteEvent"), "Expected RemoteEvent for " .. key)
		typed[key] = instance
	end
	return typed
end

return RemotesInit

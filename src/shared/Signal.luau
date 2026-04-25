--!strict
--[[
	Signal.luau

	Minimal BindableEvent-backed signal with deterministic ordering. Used by
	server services to communicate without depending on each other directly.

	API mirrors RBXScriptSignal closely:
		local sig = Signal.new()
		local conn = sig:Connect(function(...) end)
		sig:Fire(...)
		conn:Disconnect()
		sig:Destroy()
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (Connection) -> (),
}

export type Signal = typeof(setmetatable(
	{} :: {
		_bindable: BindableEvent,
		_connections: { RBXScriptConnection },
	},
	Signal
))

function Signal.new(): Signal
	local self = setmetatable({
		_bindable = Instance.new("BindableEvent"),
		_connections = {},
	}, Signal)
	return self :: any
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local rbxConnection = self._bindable.Event:Connect(handler)
	table.insert(self._connections, rbxConnection)

	local connection = {
		Connected = true,
	} :: any
	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		rbxConnection:Disconnect()
	end
	return connection
end

function Signal:Fire(...: any)
	self._bindable:Fire(...)
end

function Signal:Destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	table.clear(self._connections)
	self._bindable:Destroy()
end

return Signal

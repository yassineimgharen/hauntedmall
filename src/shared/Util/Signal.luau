-- Minimal signal for module-to-module events. Handlers run via task.spawn, so a handler
-- that does not yield finishes before Fire returns.

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: () -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local handlers = self._handlers
	table.insert(handlers, handler)
	return {
		Disconnect = function()
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...: any)
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

return Signal

-- Client-only event bus for UI feedback that never needs the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

return {
	Notify = Signal.new(), -- (text, kind) → toast, same as a server Notify
}

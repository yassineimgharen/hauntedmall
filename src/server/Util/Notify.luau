-- Server → client feedback helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type Kind = "info" | "success" | "warning" | "danger" | "levelup"

local Notify = {}

function Notify.player(player: Player, text: string, kind: Kind?)
	Net.get("Notify"):FireClient(player, text, kind or "info")
end

function Notify.all(text: string, kind: Kind?)
	Net.get("Notify"):FireAllClients(text, kind or "info")
end

-- Visual/audio cue for one client, e.g. ("Sale", {Position=..., Amount=...}).
function Notify.effect(player: Player, kind: string, payload: { [string]: any }?)
	Net.get("Effect"):FireClient(player, kind, payload or {})
end

function Notify.effectAll(kind: string, payload: { [string]: any }?)
	Net.get("Effect"):FireAllClients(kind, payload or {})
end

return Notify

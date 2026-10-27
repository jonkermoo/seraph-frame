--!strict
-- The ONLY place client/server message names are defined.
-- Add a name here, then use Net.remote(name) on both sides.

local Net = {}

Net.Messages = table.freeze({
	Ping = "Ping",
	FrameBoard = "FrameBoard", -- client -> server, no payload: board the Frame you stand next to
	FrameExit = "FrameExit", -- client -> server (x, z, yaw radians): leave the Frame, final hull position
	FrameAction = "FrameAction", -- client -> server (action: "dash" | "leap"): stamped on the hull for watchers
})

export type MessageName = "Ping" | "FrameBoard" | "FrameExit" | "FrameAction"

-- Roblox services are fetched lazily so the name table above stays testable in Lune.
-- The server creates remotes; the client waits for them to replicate.
function Net.remote(name: MessageName): RemoteEvent
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	if RunService:IsClient() then
		local folder = ReplicatedStorage:WaitForChild("Remotes")
		return folder:WaitForChild(name) :: RemoteEvent
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		created.Parent = ReplicatedStorage
		folder = created
	end
	local remote = folder:FindFirstChild(name)
	if not remote then
		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = folder
		remote = created
	end
	return remote :: RemoteEvent
end

return Net

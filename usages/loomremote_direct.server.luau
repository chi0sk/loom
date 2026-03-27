--// @chi0sk / sam

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomRemote = require(ReplicatedStorage:WaitForChild("LoomRemote"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local pingRemoteEvent = remotesFolder:WaitForChild("Ping")

local PingCodec = Loom.struct({
	{"sentAtMs", Loom.uint53},
	{"text", Loom.bounded_str(64)},
})

local pingRemote = LoomRemote.new(pingRemoteEvent, PingCodec)

pingRemote:Connect(function(player, payload)
	print("ping from", player.Name, payload.text, payload.sentAtMs)
end)

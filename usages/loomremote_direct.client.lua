--// @chi0sk / sam

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomRemote = require(ReplicatedStorage:WaitForChild("LoomRemote"))
local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local pingRemoteEvent = remotesFolder:WaitForChild("Ping")

local PingCodec = Loom.struct({
	{"sentAtMs", Loom.uint53},
	{"text", Loom.bounded_str(64)},
})

local pingRemote = LoomRemote.new(pingRemoteEvent, PingCodec)

local sentKey = "loomremote_direct_example_sent"
if not localPlayer:GetAttribute(sentKey) then
	localPlayer:SetAttribute(sentKey, true)

	pingRemote:FireServer({
		sentAtMs = DateTime.now().UnixTimestampMillis,
		text = "yo",
	})
end

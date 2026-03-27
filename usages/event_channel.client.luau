--// @chi0sk / sam

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomChannels = require(ReplicatedStorage:WaitForChild("LoomChannels"))
local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local chatRemoteEvent = remotesFolder:WaitForChild("ChatMessage")

local ChatMessage = Loom.struct({
	{"channel", Loom.bounded_str(16)},
	{"text", Loom.bounded_str(120)},
	{"sentAtMs", Loom.uint53},
})

local chatChannel = LoomChannels.event(chatRemoteEvent, ChatMessage)

chatChannel:Connect(function(message)
	print("server said", message.channel, message.text)
end)

local sentKey = "loom_event_channel_example_sent"
if not localPlayer:GetAttribute(sentKey) then
	localPlayer:SetAttribute(sentKey, true)

	chatChannel:FireServer({
		channel = "global",
		text = "yo from the client",
		sentAtMs = DateTime.now().UnixTimestampMillis,
	})
end

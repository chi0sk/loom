--// @chi0sk / sam

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomChannels = require(ReplicatedStorage:WaitForChild("LoomChannels"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local chatRemoteEvent = remotesFolder:WaitForChild("ChatMessage")

local ChatMessage = Loom.struct({
	{"channel", Loom.bounded_str(16)},
	{"text", Loom.bounded_str(120)},
	{"sentAtMs", Loom.uint53},
})

local chatChannel = LoomChannels.event(chatRemoteEvent, ChatMessage)
local lastMessageByPlayer = setmetatable({}, {__mode = "k"})

chatChannel:Connect(function(player, message)
	local signature = string.format("%s|%s|%s", message.channel, message.text, tostring(message.sentAtMs))
	if lastMessageByPlayer[player] == signature then
		return
	end
	lastMessageByPlayer[player] = signature

	print(("[%s] %s: %s"):format(message.channel, player.Name, message.text))
end)

Players.PlayerAdded:Connect(function(player)
	chatChannel:FireClient(player, {
		channel = "system",
		text = "welcome in",
		sentAtMs = DateTime.now().UnixTimestampMillis,
	})
end)

Players.PlayerRemoving:Connect(function(player)
	lastMessageByPlayer[player] = nil
end)

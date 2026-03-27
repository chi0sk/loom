--// @chi0sk / sam

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomChannels = require(ReplicatedStorage:WaitForChild("LoomChannels"))
local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local getProfileRemote = remotesFolder:WaitForChild("GetProfile")

local ProfileRequest = Loom.struct({
	{"targetUserId", Loom.u32},
})

local ProfileResponse = Loom.struct({
	{"userId", Loom.u32},
	{"displayName", Loom.bounded_str(16)},
	{"coins", Loom.int53},
})

local profileChannel = LoomChannels.request(getProfileRemote, ProfileRequest, ProfileResponse)

local requestKey = "loom_request_channel_example_sent"
if localPlayer:GetAttribute(requestKey) then
	return
end
localPlayer:SetAttribute(requestKey, true)

local response, err = profileChannel:InvokeServer({
	targetUserId = 71234,
})

if response then
	print("profile", response.userId, response.displayName, response.coins)
else
	warn("request failed", err)
end

--// @chi0sk / sam

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomChannels = require(ReplicatedStorage:WaitForChild("LoomChannels"))

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

profileChannel:Handle(function(_player, request)
	return {
		userId = request.targetUserId,
		displayName = "sam",
		coins = 25000,
	}
end)

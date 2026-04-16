-- LoomChannels.request server example
-- the handler returns the response value directly.
-- if something goes wrong internally, the caller gets nil, err.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomChannels = require(ReplicatedStorage:WaitForChild("LoomChannels"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getCoinsRemote = remotes:WaitForChild("GetCoins")

local RequestCodec = Loom.struct({
    {"includeLastRewardTime", Loom.bool},
})

local ResponseCodec = Loom.struct({
    {"coins", Loom.u32},
    {"lastRewardUnix", Loom.optional(Loom.uint53)},
})

local getCoins = LoomChannels.request(getCoinsRemote, RequestCodec, ResponseCodec)

local playerCoins = {}
local playerLastReward = {}

getCoins:Handle(function(player, request)
    local coins = playerCoins[player] or 0
    local lastRewardUnix = nil

    if request.includeLastRewardTime then
        lastRewardUnix = playerLastReward[player]
    end

    return {
        coins = coins,
        lastRewardUnix = lastRewardUnix,
    }
end)

-- LoomChannels.request client example
-- where this fits:
-- use a request when the client needs to ask a question and wait for one answer back.
-- think: get shop data, fetch profile info, ask the server to price an upgrade.

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

local response, err = getCoins:InvokeServer({
    includeLastRewardTime = true,
})

if err then
    warn("GetCoins failed:", err)
    return
end

print("coins:", response.coins)
print("last reward:", response.lastRewardUnix)

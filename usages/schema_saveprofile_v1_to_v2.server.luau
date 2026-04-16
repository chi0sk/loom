-- schema migration example
-- where this fits:
-- use Loom.schema when the payload may live a long time,
-- like datastore data, saved files, cache blobs, or anything versioned.
-- the point is that old data can still be read after the format changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loom = require(ReplicatedStorage:WaitForChild("Loom"))

local ProfileV1 = Loom.schema({
    name = "PlayerProfile",
    version = 1,
    codec = Loom.struct({
        {"coins", Loom.u32},
        {"xp", Loom.u32},
    }),
})

local ProfileV2 = Loom.schema({
    name = "PlayerProfile",
    version = 2,
    codec = Loom.struct({
        {"coins", Loom.u32},
        {"xp", Loom.u32},
        {"title", Loom.bounded_str(20), "Rookie"},
    }),
    migrations = {
        [1] = function(data)
            data.title = "Rookie"
            return data
        end,
    },
})

-- imagine this is old data already saved somewhere
local oldBlob = ProfileV1:encodeBase64({
    coins = 120,
    xp = 35,
})

-- now the game has upgraded to version 2
local upgradedProfile = ProfileV2:decodeBase64(oldBlob)

print(upgradedProfile.coins)
print(upgradedProfile.xp)
print(upgradedProfile.title)

-- raw codec example
-- where this fits:
-- use this when you just want to turn a Lua table into a compact buffer,
-- then turn it back into a Lua table later.
-- good for save payloads, memory caches, or testing a codec before you put it on a remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loom = require(ReplicatedStorage:WaitForChild("Loom"))

local ItemCodec = Loom.struct({
    {"id", Loom.u16},
    {"name", Loom.bounded_str(24)},
    {"amount", Loom.u16},
    {"equipped", Loom.bool, false},
})

local InventoryCodec = Loom.struct({
    {"coins", Loom.u32},
    {"items", Loom.array(ItemCodec, 50)},
})

local inventory = {
    coins = 275,
    items = {
        {id = 1, name = "Wood Sword", amount = 1, equipped = true},
        {id = 2, name = "Apple", amount = 8},
        {id = 3, name = "Potion", amount = 2},
    },
}

local packet = Loom.encodeRaw(InventoryCodec, inventory)
local decoded = Loom.decodeRaw(InventoryCodec, packet)

print("encoded bytes:", buffer.len(packet))
print("coins:", decoded.coins)
print("first item:", decoded.items[1].name)

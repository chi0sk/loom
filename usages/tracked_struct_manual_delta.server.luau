-- tracked_struct example
-- where this fits:
-- use this when you already have an old state and a new state,
-- and you want Loom to only encode the changed fields.
-- this is the lower level version of what LoomChannels.state does for you.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loom = require(ReplicatedStorage:WaitForChild("Loom"))

local Tracker = Loom.tracked_struct({
    {"health", Loom.u16},
    {"stamina", Loom.u16},
    {"zone", Loom.bounded_str(24)},
    {"position", Loom.vec3},
})

local previous = {
    health = 100,
    stamina = 50,
    zone = "Village",
    position = Vector3.new(0, 5, 0),
}

local current = {
    health = 82,
    stamina = 47,
    zone = nil,
    position = Vector3.new(8, 5, 3),
}

local packet = Loom.encodeRaw(Tracker, previous, current)
local delta = Loom.decodeRaw(Tracker, packet)

local clientCache = table.clone(previous)
Loom.applyDelta(clientCache, delta)

print("delta has health:", delta.health)
print("zone removed:", clientCache.zone == nil)
print("new position:", clientCache.position)

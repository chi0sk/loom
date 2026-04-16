-- LoomChannels.state client example
-- where this fits:
-- use a state channel when the server owns a piece of state,
-- and you want the client to keep a local cache that updates over time.
-- great for HUD state, match state, objective state, and scoreboard data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomChannels = require(ReplicatedStorage:WaitForChild("LoomChannels"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local hudRemote = remotes:WaitForChild("PlayerHudState")

local hudState = LoomChannels.state(hudRemote, {
    {"health", Loom.u16},
    {"stamina", Loom.u16},
    {"alive", Loom.bool},
    {"zone", Loom.bounded_str(24)},
    {"questTitle", Loom.bounded_str(40)},
    {"position", Loom.vec3},
})

hudState:Connect(function(state, delta)
    print("full state now:", state.health, state.stamina, state.zone)

    if delta.questTitle ~= nil then
        print("quest title changed to:", state.questTitle)
    end

    if delta.zone ~= nil and state.zone == nil then
        print("zone was removed from the cache")
    end
end)

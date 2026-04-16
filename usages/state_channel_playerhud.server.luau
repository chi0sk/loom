-- LoomChannels.state server example
-- the server pushes full logical state,
-- LoomChannels only sends what changed for each player.

local Players = game:GetService("Players")
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

local function pushHudForPlayer(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then
        return
    end

    hudState:Push(player, {
        health = math.floor(humanoid.Health),
        stamina = 80,
        alive = humanoid.Health > 0,
        zone = "Village",
        questTitle = "Talk to the blacksmith",
        position = root.Position,
    })
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(1)
        pushHudForPlayer(player)
    end)
end)

-- later, if you want to remove a field from the client cache:
local function clearQuest(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end

    hudState:Push(player, {
        health = 100,
        stamina = 100,
        alive = true,
        zone = "Village",
        questTitle = nil,
        position = root.Position,
    })
end

return clearQuest

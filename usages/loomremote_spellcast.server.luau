-- LoomRemote server example
-- this receives the typed payload sent by the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomRemote = require(ReplicatedStorage:WaitForChild("LoomRemote"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spellRemoteEvent = remotes:WaitForChild("CastSpell")

local SpellCastCodec = Loom.struct({
    {"spell", Loom.enum({"Fireball", "Dash", "Heal"})},
    {"origin", Loom.vec3},
    {"direction", Loom.vec3},
    {"chargePercent", Loom.u8},
})

local spellRemote = LoomRemote.new(spellRemoteEvent, SpellCastCodec)

spellRemote:Connect(function(player, cast)
    -- validate before trusting the client
    if cast.chargePercent > 100 then
        return
    end

    print(player.Name, "cast", cast.spell)
    print("from", cast.origin, "toward", cast.direction)

    -- do your game logic here
end)

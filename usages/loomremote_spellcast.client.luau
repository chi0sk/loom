-- LoomRemote client example
-- where this fits:
-- use LoomRemote when you still want a normal RemoteEvent flow,
-- but you do not want to manually pack and unpack the payload yourself.

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

spellRemote:FireServer({
    spell = "Fireball",
    origin = Vector3.new(0, 5, 0),
    direction = Vector3.new(1, 0, 0),
    chargePercent = 80,
})

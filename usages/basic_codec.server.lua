--// @chi0sk / sam

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))

local PlayerProfile = Loom.schema({
	name = "PlayerProfile",
	version = 1,
	codec = Loom.struct({
		{"userId", Loom.u32},
		{"displayName", Loom.bounded_str(16)},
		{"coins", Loom.int53, 0},
		{"alive", Loom.bool, true},
		{"spawn", Loom.vec3},
	}),
})

local payload = {
	userId = 71234,
	displayName = "sam",
	spawn = Vector3.new(0, 6, 0),
}

local packet = PlayerProfile:encode(payload)
local decoded = PlayerProfile:decode(packet)

print("encoded bytes", buffer.len(packet))
print(decoded.userId, decoded.displayName, decoded.coins, decoded.alive, decoded.spawn)

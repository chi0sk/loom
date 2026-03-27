--// @chi0sk / sam

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loom = require(ReplicatedStorage:WaitForChild("Loom"))
local LoomChannels = require(ReplicatedStorage:WaitForChild("LoomChannels"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local playerStateRemote = remotesFolder:WaitForChild("PlayerState")

local playerStateChannel = LoomChannels.state(playerStateRemote, {
	{"health", Loom.u16},
	{"stamina", Loom.u16},
	{"nickname", Loom.bounded_str(16)},
	{"alive", Loom.bool},
	{"position", Loom.vec3},
})

playerStateChannel:Connect(function(state, delta)
	print("state bytes landed")
	print("health", state.health)
	print("stamina", state.stamina)
	print("nickname", state.nickname)
	print("alive", state.alive)
	print("position", state.position)
	print("delta keys", next(delta) ~= nil and "changed" or "none")
end)

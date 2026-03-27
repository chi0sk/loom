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

game.Players.PlayerAdded:Connect(function(player)
	local state = {
		health = 100,
		stamina = 50,
		nickname = player.Name,
		alive = true,
		position = Vector3.new(0, 0, 0),
	}

	playerStateChannel:Push(player, state)

	task.delay(2, function()
		if not player.Parent then
			return
		end

		state.health = 82
		state.stamina = 45
		state.nickname = nil
		state.alive = false
		state.position = Vector3.new(8, 0, -3)

		playerStateChannel:Push(player, state)
	end)
end)

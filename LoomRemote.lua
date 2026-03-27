--// @chi0sk / sam
-- tiny wrapper over remoteevent so i can send loom packets without boilerplate.

local RunService = game:GetService("RunService")

local Loom = require(script.Parent:WaitForChild("Loom"))

local LoomRemote = {}
local RemoteMeta = {}
RemoteMeta.__index = RemoteMeta

local function defaultOnError(stage: string, remoteName: string, err: string)
	warn(string.format("loomremote %s failed for '%s': %s", stage, remoteName, err))
end

local function buildCodecIo(schemaOrCodec: any, useSchemaHeader: boolean)
	if type(schemaOrCodec) ~= "table" then
		error("loomremote: schemaOrCodec must be a table", 3)
	end

	if type(schemaOrCodec.encodePayload) == "function" and type(schemaOrCodec.decodePayload) == "function" then
		if useSchemaHeader then
			return function(...: any): buffer
				return schemaOrCodec:encode(...)
			end, function(packet: buffer): any
				return schemaOrCodec:decode(packet)
			end
		end

		return function(...: any): buffer
			return schemaOrCodec:encodePayload(...)
		end, function(packet: buffer): any
			return schemaOrCodec:decodePayload(packet)
		end
	end

	if type(schemaOrCodec.encode) == "function" and type(schemaOrCodec.decode) == "function" then
		return function(...: any): buffer
			return Loom.encodeRaw(schemaOrCodec, ...)
		end, function(packet: buffer): any
			return Loom.decodeRaw(schemaOrCodec, packet)
		end
	end

	error("loomremote: object must be a loom codec or schema", 3)
end

function RemoteMeta:_encode(...: any): buffer?
	local ok, packet = pcall(self._encodeFn, ...)
	if not ok then
		self._onError("encode", self._remote.Name, tostring(packet))
		return nil
	end
	return packet
end

function RemoteMeta:_decode(packet: buffer): (boolean, any)
	local ok, value = pcall(self._decodeFn, packet)
	if not ok then
		self._onError("decode", self._remote.Name, tostring(value))
		return false, nil
	end
	return true, value
end

function RemoteMeta:Encode(...: any): buffer?
	return self:_encode(...)
end

function RemoteMeta:Decode(packet: buffer): any
	local ok, value = self:_decode(packet)
	if not ok then
		return nil
	end
	return value
end

function RemoteMeta:Connect(handler)
	if RunService:IsServer() then
		return self._remote.OnServerEvent:Connect(function(player: Player, packet: buffer)
			local ok, value = self:_decode(packet)
			if ok then
				handler(player, value, packet)
			end
		end)
	end

	return self._remote.OnClientEvent:Connect(function(packet: buffer)
		local ok, value = self:_decode(packet)
		if ok then
			handler(value, packet)
		end
	end)
end

function RemoteMeta:FireServer(...: any)
	assert(not RunService:IsServer(), "loomremote: FireServer can only be used on the client")
	local packet = self:_encode(...)
	if packet ~= nil then
		self._remote:FireServer(packet)
	end
end

function RemoteMeta:FireClient(player: Player, ...: any)
	assert(RunService:IsServer(), "loomremote: FireClient can only be used on the server")
	local packet = self:_encode(...)
	if packet ~= nil then
		self._remote:FireClient(player, packet)
	end
end

function RemoteMeta:FireAllClients(...: any)
	assert(RunService:IsServer(), "loomremote: FireAllClients can only be used on the server")
	local packet = self:_encode(...)
	if packet ~= nil then
		self._remote:FireAllClients(packet)
	end
end

function RemoteMeta:FireClients(players: {Player}, ...: any)
	assert(RunService:IsServer(), "loomremote: FireClients can only be used on the server")
	local packet = self:_encode(...)
	if packet == nil then
		return
	end

	for _, player in ipairs(players) do
		self._remote:FireClient(player, packet)
	end
end

function RemoteMeta:FireExcept(excluded: Player, ...: any)
	assert(RunService:IsServer(), "loomremote: FireExcept can only be used on the server")
	local packet = self:_encode(...)
	if packet == nil then
		return
	end

	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		if player ~= excluded then
			self._remote:FireClient(player, packet)
		end
	end
end

function LoomRemote.new(remote: RemoteEvent, schemaOrCodec: any, options)
	assert(typeof(remote) == "Instance" and remote:IsA("RemoteEvent"), "loomremote: remote must be a RemoteEvent")

	local encodeFn, decodeFn = buildCodecIo(schemaOrCodec, options and options.useSchemaHeader == true)

	return setmetatable({
		_remote = remote,
		_encodeFn = encodeFn,
		_decodeFn = decodeFn,
		_onError = options and options.onError or defaultOnError,
	}, RemoteMeta)
end

return LoomRemote

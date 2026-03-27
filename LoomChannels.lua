--// @chi0sk / sam
-- higher level helpers on top of loomremote.
-- this is the stuff i'd actually reach for in a game most of the time.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Loom = require(script.Parent:WaitForChild("Loom"))
local LoomRemote = require(script.Parent:WaitForChild("LoomRemote"))

local LoomChannels = {}

local b_create = buffer.create
local b_copy = buffer.copy
local b_len = buffer.len
local b_readstring = buffer.readstring

local function defaultOnError(stage: string, channelName: string, err: string)
	warn(string.format("loomchannels %s failed for '%s': %s", stage, channelName, err))
end

local function buildCodecIo(schemaOrCodec: any, useSchemaHeader: boolean)
	if type(schemaOrCodec) ~= "table" then
		error("loomchannels: schemaOrCodec must be a table", 3)
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

	error("loomchannels: object must be a loom codec or schema", 3)
end

local function cloneBuffer(buf: buffer): buffer
	local len = b_len(buf)
	local out = b_create(len)
	if len > 0 then
		b_copy(out, 0, buf, 0, len)
	end
	return out
end

local function valuesEqual(a: any, b: any, seenA: {[table]: table}?, seenB: {[table]: table}?): boolean
	if a == b then
		return true
	end

	local ta = typeof(a)
	local tb = typeof(b)
	if ta ~= tb then
		return false
	end

	if ta == "buffer" then
		return b_len(a) == b_len(b) and b_readstring(a, 0, b_len(a)) == b_readstring(b, 0, b_len(b))
	end

	if ta ~= "table" then
		return false
	end

	seenA = seenA or {}
	seenB = seenB or {}

	local mappedA = seenA[a]
	local mappedB = seenB[b]
	if mappedA ~= nil or mappedB ~= nil then
		return mappedA == b and mappedB == a
	end

	seenA[a] = b
	seenB[b] = a

	for key, value in pairs(a) do
		if not valuesEqual(value, b[key], seenA, seenB) then
			return false
		end
	end

	for key in pairs(b) do
		if a[key] == nil and b[key] ~= nil then
			return false
		end
	end

	return true
end

local function cloneValue(value: any, seen: {[table]: table}?): any
	local kind = typeof(value)
	if kind == "buffer" then
		return cloneBuffer(value)
	end

	if kind ~= "table" then
		return value
	end

	seen = seen or {}
	local mapped = seen[value]
	if mapped then
		return mapped
	end

	local out = table.clone(value)
	seen[value] = out
	for key, nested in pairs(value) do
		out[key] = cloneValue(nested, seen)
	end
	return out
end

local function buildDelta(fieldNames: {string}, prevState: {[string]: any}, currState: {[string]: any}): ({[string]: any}, boolean)
	local delta = {}
	local changed = false

	for i = 1, #fieldNames do
		local name = fieldNames[i]
		local prevValue = prevState[name]
		local currValue = currState[name]
		if not valuesEqual(prevValue, currValue) then
			delta[name] = currValue == nil and Loom.none or currValue
			changed = true
		end
	end

	return delta, changed
end

function LoomChannels.event(remote: RemoteEvent, schemaOrCodec: any, options)
	return LoomRemote.new(remote, schemaOrCodec, options)
end

function LoomChannels.request(remote: RemoteFunction, requestCodec: any, responseCodec: any, options)
	assert(typeof(remote) == "Instance" and remote:IsA("RemoteFunction"), "loomchannels.request: remote must be a RemoteFunction")

	local encodeRequest, decodeRequest = buildCodecIo(requestCodec, options and options.requestHeader == true)
	local encodeResponse, decodeResponse = buildCodecIo(responseCodec, options and options.responseHeader == true)
	local errorCodec = Loom.bounded_str(options and options.maxErrorLength or 240)
	-- this wrapper codec keeps the request path small and gives us an error lane back.
	-- tag 0 = success payload, tag 1 = error string.
	local responseEnvelopeCodec = {
		encode = function(w, value)
			if value.tag == 0 then
				w:writeU8(0)
				local packet = encodeResponse(value.value)
				w:copyFrom(packet, 0, b_len(packet))
			else
				w:writeU8(1)
				errorCodec.encode(w, value.value)
			end
		end,
		decode = function(r)
			local tag = r:readU8()
			if tag == 0 then
				local packet = r._buf
				local start = r._pos
				local len = r:remaining()
				local payload = b_create(len)
				if len > 0 then
					b_copy(payload, 0, packet, start, len)
				end
				r._pos += len
				return {tag = 0, value = decodeResponse(payload)}
			end
			if tag == 1 then
				return {tag = 1, value = errorCodec.decode(r)}
			end
			error(string.format("loomchannels: request response tag %d is invalid", tag), 2)
		end,
	}
	local onError = options and options.onError or defaultOnError

	local channel = {
		_remote = remote,
	}

	function channel:Handle(handler)
		if RunService:IsServer() then
			remote.OnServerInvoke = function(player: Player, requestPacket: buffer)
				local okDecode, requestValue = pcall(decodeRequest, requestPacket)
				if not okDecode then
					onError("decode_request", remote.Name, tostring(requestValue))
					return Loom.encodeRaw(responseEnvelopeCodec, {tag = 1, value = "bad request packet"})
				end

				local okHandle, responseValue = pcall(handler, player, requestValue)
				if not okHandle then
					onError("handle_request", remote.Name, tostring(responseValue))
					return Loom.encodeRaw(responseEnvelopeCodec, {tag = 1, value = "handler error"})
				end

				local okEncode, responsePacket = pcall(Loom.encodeRaw, responseEnvelopeCodec, {tag = 0, value = responseValue})
				if not okEncode then
					onError("encode_response", remote.Name, tostring(responsePacket))
					return Loom.encodeRaw(responseEnvelopeCodec, {tag = 1, value = "bad response payload"})
				end

				return responsePacket
			end
			return
		end

		remote.OnClientInvoke = function(requestPacket: buffer)
			local okDecode, requestValue = pcall(decodeRequest, requestPacket)
			if not okDecode then
				onError("decode_request", remote.Name, tostring(requestValue))
				return Loom.encodeRaw(responseEnvelopeCodec, {tag = 1, value = "bad request packet"})
			end

			local okHandle, responseValue = pcall(handler, requestValue)
			if not okHandle then
				onError("handle_request", remote.Name, tostring(responseValue))
				return Loom.encodeRaw(responseEnvelopeCodec, {tag = 1, value = "handler error"})
			end

			local okEncode, responsePacket = pcall(Loom.encodeRaw, responseEnvelopeCodec, {tag = 0, value = responseValue})
			if not okEncode then
				onError("encode_response", remote.Name, tostring(responsePacket))
				return Loom.encodeRaw(responseEnvelopeCodec, {tag = 1, value = "bad response payload"})
			end

			return responsePacket
		end
	end

	function channel:InvokeServer(requestValue)
		assert(not RunService:IsServer(), "loomchannels.request: InvokeServer can only be used on the client")
		local okPacket, requestPacket = pcall(encodeRequest, requestValue)
		if not okPacket then
			onError("encode_request", remote.Name, tostring(requestPacket))
			return nil, "bad request payload"
		end

		local okInvoke, responsePacket = pcall(remote.InvokeServer, remote, requestPacket)
		if not okInvoke then
			onError("invoke_server", remote.Name, tostring(responsePacket))
			return nil, tostring(responsePacket)
		end

		local okDecode, responseValue = pcall(Loom.decodeRaw, responseEnvelopeCodec, responsePacket)
		if not okDecode then
			onError("decode_response", remote.Name, tostring(responseValue))
			return nil, "bad response packet"
		end

		if responseValue.tag == 1 then
			onError("response_error", remote.Name, responseValue.value)
			return nil, responseValue.value
		end

		return responseValue.value, nil
	end

	function channel:InvokeClient(player: Player, requestValue)
		assert(RunService:IsServer(), "loomchannels.request: InvokeClient can only be used on the server")
		local okPacket, requestPacket = pcall(encodeRequest, requestValue)
		if not okPacket then
			onError("encode_request", remote.Name, tostring(requestPacket))
			return nil, "bad request payload"
		end

		local okInvoke, responsePacket = pcall(remote.InvokeClient, remote, player, requestPacket)
		if not okInvoke then
			onError("invoke_client", remote.Name, tostring(responsePacket))
			return nil, tostring(responsePacket)
		end

		local okDecode, responseValue = pcall(Loom.decodeRaw, responseEnvelopeCodec, responsePacket)
		if not okDecode then
			onError("decode_response", remote.Name, tostring(responseValue))
			return nil, "bad response packet"
		end

		if responseValue.tag == 1 then
			onError("response_error", remote.Name, responseValue.value)
			return nil, responseValue.value
		end

		return responseValue.value, nil
	end

	function channel:Destroy()
		if RunService:IsServer() then
			if self._remote.OnServerInvoke ~= nil then
				self._remote.OnServerInvoke = nil
			end
			return
		end

		if self._remote.OnClientInvoke ~= nil then
			self._remote.OnClientInvoke = nil
		end
	end

	return channel
end

function LoomChannels.state(remote: RemoteEvent, fields: {{any}}, options)
	assert(typeof(remote) == "Instance" and remote:IsA("RemoteEvent"), "loomchannels.state: remote must be a RemoteEvent")

	local deltaCodec = Loom.delta_struct(fields)
	local channelRemote = LoomRemote.new(remote, deltaCodec, options)
	local fieldNames = table.create(#fields)
	for i = 1, #fields do
		fieldNames[i] = fields[i][1]
	end

	local channel = {
		_remote = channelRemote,
		_lastByPlayer = setmetatable({}, {__mode = "k"}),
		_clientState = {},
	}

	if RunService:IsServer() then
		channel._cleanupConnection = Players.PlayerRemoving:Connect(function(player)
			channel._lastByPlayer[player] = nil
		end)
	end

	function channel:Push(player: Player, state: {[string]: any}): boolean
		assert(RunService:IsServer(), "loomchannels.state: Push can only be used on the server")
		local prevState = self._lastByPlayer[player] or {}
		local delta, changed = buildDelta(fieldNames, prevState, state)
		if not changed then
			return false
		end

		self._remote:FireClient(player, delta)
		self._lastByPlayer[player] = cloneValue(state)
		return true
	end

	function channel:PushAll(state: {[string]: any})
		assert(RunService:IsServer(), "loomchannels.state: PushAll can only be used on the server")
		local players = Players:GetPlayers()
		for i = 1, #players do
			self:Push(players[i], state)
		end
	end

	function channel:Reset(player: Player?)
		if RunService:IsServer() then
			if player ~= nil then
				self._lastByPlayer[player] = nil
				return
			end

			for key in pairs(self._lastByPlayer) do
				self._lastByPlayer[key] = nil
			end
			return
		end

		table.clear(self._clientState)
	end

	function channel:GetState(): {[string]: any}
		return self._clientState
	end

	function channel:Connect(handler)
		assert(not RunService:IsServer(), "loomchannels.state: Connect should be used on the client")
		return self._remote:Connect(function(delta)
			Loom.applyDelta(self._clientState, delta)
			handler(self._clientState, delta)
		end)
	end

	function channel:Destroy()
		if self._cleanupConnection then
			self._cleanupConnection:Disconnect()
			self._cleanupConnection = nil
		end

		if RunService:IsServer() then
			for key in pairs(self._lastByPlayer) do
				self._lastByPlayer[key] = nil
			end
		else
			table.clear(self._clientState)
		end
	end

	return channel
end

return LoomChannels

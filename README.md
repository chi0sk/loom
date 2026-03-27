# loom

typed binary serialization for roblox. includes direct remote wrappers and higher level channels for events, requests, and state sync.

bad explaination

```lua
-- server
local playerState = LoomChannels.state(remotes.PlayerState, {
    {"health", Loom.u16},
    {"stamina", Loom.u16},
    {"alive", Loom.bool},
    {"position", Loom.vec3},
})

playerState:Push(player, {
    health = 100,
    stamina = 50,
    alive = true,
    position = Vector3.new(0, 0, 0),
})

-- client
local playerState = LoomChannels.state(remotes.PlayerState, {
    {"health", Loom.u16},
    {"stamina", Loom.u16},
    {"alive", Loom.bool},
    {"position", Loom.vec3},
})

playerState:Connect(function(state, delta)
    print(state.health, state.position)
end)
```

---

## install

drop these into `ReplicatedStorage`:

- `Loom`
- `LoomRemote`
- `LoomChannels`

`LoomRemote` expects a sibling module named `Loom`.

`LoomChannels` expects sibling modules named `Loom` and `LoomRemote`.

---

## what you use

### `Loom`

the serializer itself.

use it for:
- codecs like `Loom.struct(...)`, `Loom.array(...)`, `Loom.map(...)`
- schemas with versioning via `Loom.schema(...)`
- tracked deltas via `Loom.tracked_struct(...)`

### `LoomRemote`

thin wrapper for `RemoteEvent`.

use it when you just want:
- `:FireServer(...)`
- `:FireClient(...)`
- `:FireAllClients(...)`
- `:Connect(...)`

### `LoomChannels`

higher level helpers.

use it when you want:
- `LoomChannels.event(...)`
- `LoomChannels.request(...)`
- `LoomChannels.state(...)`

---

## examples

look in `/usages`.

- `basic_codec.server.luau`
- `loomremote_direct.server.luau`
- `loomremote_direct.client.luau`
- `event_channel.server.luau`
- `event_channel.client.luau`
- `request_channel.server.luau`
- `request_channel.client.luau`
- `state_channel.server.luau`
- `state_channel.client.luau`

---

## features

- typed codecs for numbers, strings, buffers, roblox types, structs, unions, maps, tuples, and more
- schema versioning with migrations
- direct remote wrappers through `LoomRemote`
- higher level event, request, and state channels through `LoomChannels`
- tracked deltas with delete support through `Loom.none`
- payload encode/decode helpers for raw buffers, strings, and base64

---

## quick api

### `Loom`

| method | description |
|---|---|
| `Loom.struct(fields)` | build an ordered named payload |
| `Loom.schema(config)` | build a versioned schema |
| `Loom.encodeRaw(codec, value, ...)` | encode without schema headers |
| `Loom.decodeRaw(codec, packet)` | decode without schema headers |
| `Loom.tracked_struct(fields)` | build a delta codec from full states |
| `Loom.applyDelta(state, delta)` | apply decoded tracked changes |

### `LoomRemote`

| method | description |
|---|---|
| `LoomRemote.new(remoteEvent, codecOrSchema, options?)` | create a wrapped remote |
| `remote:FireServer(...)` | encode and send to server |
| `remote:FireClient(player, ...)` | encode and send to one client |
| `remote:FireAllClients(...)` | encode and send to everyone |
| `remote:Connect(handler)` | decode and handle packets |

### `LoomChannels`

| method | description |
|---|---|
| `LoomChannels.event(remoteEvent, codecOrSchema, options?)` | simple event channel |
| `LoomChannels.request(remoteFunction, requestCodec, responseCodec, options?)` | typed request/response |
| `LoomChannels.state(remoteEvent, fields, options?)` | server push + client cached state sync |

---

## notes

- use schemas if you care about versioning or persistence
- use raw codecs if both ends already agree on the payload
- use `Loom.none` when a tracked delta needs to delete a key
- use `Loom.applyDelta(...)` on the client side for tracked state updates

---

## license

MIT license. do whatever you want with it, just keep the attribution.

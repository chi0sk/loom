--// @chi0sk / sam
-- binary serializer for roblox

local Loom = {}
local NONE = table.freeze({})

local b_create      = buffer.create
local b_copy        = buffer.copy
local b_len         = buffer.len
local b_readstring  = buffer.readstring
local b_reads8      = buffer.readi8
local b_reads16     = buffer.readi16
local b_reads32     = buffer.readi32
local b_readu8      = buffer.readu8
local b_readu16     = buffer.readu16
local b_readu32     = buffer.readu32
local b_readf32     = buffer.readf32
local b_readf64     = buffer.readf64
local b_writestring = buffer.writestring
local b_writei8     = buffer.writei8
local b_writei16    = buffer.writei16
local b_writei32    = buffer.writei32
local b_writeu8     = buffer.writeu8
local b_writeu16    = buffer.writeu16
local b_writeu32    = buffer.writeu32
local b_writef32    = buffer.writef32
local b_writef64    = buffer.writef64

local str_byte = string.byte
local str_char = string.char

local MAGIC_0           = 0x42
local MAGIC_1           = 0x53
local WRITER_INIT_CAP   = 256
local VARINT_MAX_BYTES  = 5
local VARINT_MAX_VALUE  = 0xFFFFFFFF
local MAX_SAFE_INTEGER  = 9007199254740991
local MIN_SAFE_INTEGER  = -MAX_SAFE_INTEGER
-- floor(32767 * sqrt(2)), fills i16 range for smallest-3 components
local QUAT_SCALE        = 46340
local DEFAULT_MAX_COUNT = 65536

-- base64 (messagingservice needs it since it json-encodes everything)

local B64_STR = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_PAD = str_byte("=")

local B64_BYTES: {number} = table.create(64)
local B64_INV: {[number]: number} = {}
for i = 1, 64 do
	local code = str_byte(B64_STR, i)
	B64_BYTES[i] = code
	B64_INV[code] = i - 1
end

local function base64Encode(s: string): string
	local n = #s
	if n == 0 then return "" end

	local outLen = math.ceil(n / 3) * 4
	local out = b_create(outLen)
	local si = 1
	local oi = 0

	while si <= n do
		local b0 = str_byte(s, si)
		local b1 = str_byte(s, si + 1)
		local b2 = str_byte(s, si + 2)
		local v  = b0 * 65536 + (b1 or 0) * 256 + (b2 or 0)

		b_writeu8(out, oi,     B64_BYTES[math.floor(v / 262144) % 64 + 1])
		b_writeu8(out, oi + 1, B64_BYTES[math.floor(v / 4096)   % 64 + 1])
		b_writeu8(out, oi + 2, b1 and B64_BYTES[math.floor(v / 64) % 64 + 1] or B64_PAD)
		b_writeu8(out, oi + 3, b2 and B64_BYTES[v % 64 + 1] or B64_PAD)

		si += 3
		oi += 4
	end

	return b_readstring(out, 0, outLen)
end

local function base64Decode(s: string): string
	local n = #s
	if n == 0 then return "" end

	if n % 4 ~= 0 then
		error(string.format("loom: base64 length %d is not a multiple of 4", n), 2)
	end

	local padCount = 0
	if str_byte(s, n) == B64_PAD then padCount = 1 end
	if n > 1 and str_byte(s, n - 1) == B64_PAD then padCount = 2 end

	for i = 1, n - padCount do
		local ch = str_byte(s, i)
		if ch == B64_PAD then
			error(string.format("loom: '=' at position %d is not valid padding", i), 2)
		elseif B64_INV[ch] == nil then
			error(string.format("loom: invalid base64 character '%s' at position %d", str_char(ch), i), 2)
		end
	end

	local outLen = n / 4 * 3 - padCount
	local out = b_create(outLen)
	local si = 1
	local oi = 0

	while si <= n do
		local c0 = B64_INV[str_byte(s, si)] or 0
		local c1 = B64_INV[str_byte(s, si + 1)] or 0
		local c2 = B64_INV[str_byte(s, si + 2)] or 0
		local c3 = B64_INV[str_byte(s, si + 3)] or 0
		local v  = c0 * 262144 + c1 * 4096 + c2 * 64 + c3

		b_writeu8(out, oi, math.floor(v / 65536) % 256)
		oi += 1
		if oi < outLen then
			b_writeu8(out, oi, math.floor(v / 256) % 256)
			oi += 1
		end
		if oi < outLen then
			b_writeu8(out, oi, v % 256)
			oi += 1
		end
		si += 4
	end

	return b_readstring(out, 0, outLen)
end

local function bufToStr(buf: buffer): string
	return b_readstring(buf, 0, b_len(buf))
end

local function strToBuf(s: string): buffer
	local buf = b_create(#s)
	b_writestring(buf, 0, s)
	return buf
end

-- writer (doubles on overflow)

local WriterMeta = {}
WriterMeta.__index = WriterMeta

export type Writer = typeof(setmetatable({} :: {
	_buf: buffer,
	_pos: number,
	_cap: number,
}, WriterMeta))

local function newWriter(): Writer
	return setmetatable({
		_buf = b_create(WRITER_INIT_CAP),
		_pos = 0,
		_cap = WRITER_INIT_CAP,
	}, WriterMeta)
end

function WriterMeta:_grow(needed: number)
	local cap = self._cap
	repeat cap *= 2 until cap >= self._pos + needed
	local nb = b_create(cap)
	b_copy(nb, 0, self._buf, 0, self._pos)
	self._buf = nb
	self._cap = cap
end

function WriterMeta:_reserve(n: number)
	if self._pos + n > self._cap then self:_grow(n) end
end

function WriterMeta:writeU8(v: number)
	assert(v >= 0 and v <= 255 and math.floor(v) == v,
		string.format("loom: writeU8 value %s out of range [0, 255]", tostring(v)))
	self:_reserve(1)
	b_writeu8(self._buf, self._pos, v)
	self._pos += 1
end

function WriterMeta:writeU16(v: number)
	assert(v >= 0 and v <= 65535 and math.floor(v) == v,
		string.format("loom: writeU16 value %s out of range [0, 65535]", tostring(v)))
	self:_reserve(2)
	b_writeu16(self._buf, self._pos, v)
	self._pos += 2
end

function WriterMeta:writeU32(v: number)
	assert(v >= 0 and v <= 4294967295 and math.floor(v) == v,
		string.format("loom: writeU32 value %s out of range [0, 4294967295]", tostring(v)))
	self:_reserve(4)
	b_writeu32(self._buf, self._pos, v)
	self._pos += 4
end

function WriterMeta:writeI8(v: number)
	assert(v >= -128 and v <= 127 and math.floor(v) == v,
		string.format("loom: writeI8 value %s out of range [-128, 127]", tostring(v)))
	self:_reserve(1)
	b_writei8(self._buf, self._pos, v)
	self._pos += 1
end

function WriterMeta:writeI16(v: number)
	assert(v >= -32768 and v <= 32767 and math.floor(v) == v,
		string.format("loom: writeI16 value %s out of range [-32768, 32767]", tostring(v)))
	self:_reserve(2)
	b_writei16(self._buf, self._pos, v)
	self._pos += 2
end

function WriterMeta:writeI32(v: number)
	assert(v >= -2147483648 and v <= 2147483647 and math.floor(v) == v,
		string.format("loom: writeI32 value %s out of range [-2147483648, 2147483647]", tostring(v)))
	self:_reserve(4)
	b_writei32(self._buf, self._pos, v)
	self._pos += 4
end

function WriterMeta:writeF32(v: number)
	self:_reserve(4)
	b_writef32(self._buf, self._pos, v)
	self._pos += 4
end

function WriterMeta:writeF64(v: number)
	self:_reserve(8)
	b_writef64(self._buf, self._pos, v)
	self._pos += 8
end

-- leb128 unsigned varint. values < 128 cost 1 byte.
function WriterMeta:writeVarint(v: number)
	v = math.floor(v)
	assert(v >= 0 and v <= VARINT_MAX_VALUE,
		string.format("loom: writeVarint value %s out of range [0, %d]", tostring(v), VARINT_MAX_VALUE))
	while v >= 128 do
		self:_reserve(1)
		b_writeu8(self._buf, self._pos, v % 128 + 128)
		self._pos += 1
		v = math.floor(v / 128)
	end
	self:_reserve(1)
	b_writeu8(self._buf, self._pos, v)
	self._pos += 1
end

-- zigzag encode then leb128
function WriterMeta:writeSVarint(v: number)
	local z = v >= 0 and v * 2 or (-v * 2) - 1
	self:writeVarint(z)
end

function WriterMeta:writeBool(v: boolean)
	self:_reserve(1)
	b_writeu8(self._buf, self._pos, v and 1 or 0)
	self._pos += 1
end

function WriterMeta:writeStr(v: string)
	local len = #v
	self:writeVarint(len)
	if len > 0 then
		self:_reserve(len)
		b_writestring(self._buf, self._pos, v)
		self._pos += len
	end
end

function WriterMeta:copyFrom(src: buffer, srcOffset: number, count: number)
	self:_reserve(count)
	b_copy(self._buf, self._pos, src, srcOffset, count)
	self._pos += count
end

function WriterMeta:flush(): buffer
	local out = b_create(self._pos)
	b_copy(out, 0, self._buf, 0, self._pos)
	return out
end

function WriterMeta:pos(): number
	return self._pos
end

-- reader

local ReaderMeta = {}
ReaderMeta.__index = ReaderMeta

export type Reader = typeof(setmetatable({} :: {
	_buf: buffer,
	_pos: number,
	_len: number,
}, ReaderMeta))

local function newReader(buf: buffer): Reader
	return setmetatable({
		_buf = buf,
		_pos = 0,
		_len = b_len(buf),
	}, ReaderMeta)
end

function ReaderMeta:_check(n: number)
	if self._pos + n > self._len then
		error(string.format(
			"loom: buffer underrun at byte %d -- need %d, have %d",
			self._pos, n, self._len - self._pos
		), 3)
	end
end

function ReaderMeta:readU8(): number
	self:_check(1)
	local v = b_readu8(self._buf, self._pos)
	self._pos += 1
	return v
end

function ReaderMeta:readU16(): number
	self:_check(2)
	local v = b_readu16(self._buf, self._pos)
	self._pos += 2
	return v
end

function ReaderMeta:readU32(): number
	self:_check(4)
	local v = b_readu32(self._buf, self._pos)
	self._pos += 4
	return v
end

function ReaderMeta:readI8(): number
	self:_check(1)
	local v = b_reads8(self._buf, self._pos)
	self._pos += 1
	return v
end

function ReaderMeta:readI16(): number
	self:_check(2)
	local v = b_reads16(self._buf, self._pos)
	self._pos += 2
	return v
end

function ReaderMeta:readI32(): number
	self:_check(4)
	local v = b_reads32(self._buf, self._pos)
	self._pos += 4
	return v
end

function ReaderMeta:readF32(): number
	self:_check(4)
	local v = b_readf32(self._buf, self._pos)
	self._pos += 4
	return v
end

function ReaderMeta:readF64(): number
	self:_check(8)
	local v = b_readf64(self._buf, self._pos)
	self._pos += 8
	return v
end

function ReaderMeta:readVarint(): number
	local result = 0
	local mul    = 1
	for _ = 1, VARINT_MAX_BYTES do
		local byte = self:readU8()
		result += (byte % 128) * mul
		mul    *= 128
		if byte < 128 then
			if result > VARINT_MAX_VALUE then
				error(string.format(
					"loom: varint value %d exceeds u32 max -- corrupt buffer?", result
				), 2)
			end
			return result
		end
	end
	error("loom: varint exceeded 5 bytes -- corrupt buffer?", 2)
end

function ReaderMeta:readSVarint(): number
	local z = self:readVarint()
	return z % 2 == 0 and z / 2 or -(z + 1) / 2
end

function ReaderMeta:readBool(): boolean
	return self:readU8() ~= 0
end

function ReaderMeta:readStr(): string
	local len = self:readVarint()
	if len == 0 then return "" end
	self:_check(len)
	local s = b_readstring(self._buf, self._pos, len)
	self._pos += len
	return s
end

function ReaderMeta:skip(n: number)
	self:_check(n)
	self._pos += n
end

function ReaderMeta:pos(): number
	return self._pos
end

function ReaderMeta:remaining(): number
	return self._len - self._pos
end

export type Codec<T> = {
	encode: (writer: Writer, value: T) -> (),
	decode: (reader: Reader) -> T,
}

-- primitive codecs

Loom.u8 = {
	encode = function(w: Writer, v: number) w:writeU8(v) end,
	decode = function(r: Reader) return r:readU8() end,
} :: Codec<number>

Loom.u16 = {
	encode = function(w: Writer, v: number) w:writeU16(v) end,
	decode = function(r: Reader) return r:readU16() end,
} :: Codec<number>

Loom.u32 = {
	encode = function(w: Writer, v: number) w:writeU32(v) end,
	decode = function(r: Reader) return r:readU32() end,
} :: Codec<number>

Loom.i8 = {
	encode = function(w: Writer, v: number) w:writeI8(v) end,
	decode = function(r: Reader) return r:readI8() end,
} :: Codec<number>

Loom.i16 = {
	encode = function(w: Writer, v: number) w:writeI16(v) end,
	decode = function(r: Reader) return r:readI16() end,
} :: Codec<number>

Loom.i32 = {
	encode = function(w: Writer, v: number) w:writeI32(v) end,
	decode = function(r: Reader) return r:readI32() end,
} :: Codec<number>

Loom.f32 = {
	encode = function(w: Writer, v: number) w:writeF32(v) end,
	decode = function(r: Reader) return r:readF32() end,
} :: Codec<number>

Loom.f64 = {
	encode = function(w: Writer, v: number) w:writeF64(v) end,
	decode = function(r: Reader) return r:readF64() end,
} :: Codec<number>

Loom.number = Loom.f64

local function assertSafeInteger(v: number, minValue: number, maxValue: number, label: string)
	assert(v == v and v ~= math.huge and v ~= -math.huge,
		string.format("loom: %s must be a finite number, got %s", label, tostring(v)))
	assert(math.floor(v) == v,
		string.format("loom: %s must be an integer, got %s", label, tostring(v)))
	assert(v >= minValue and v <= maxValue,
		string.format("loom: %s %s out of range [%d, %d]", label, tostring(v), minValue, maxValue))
end

Loom.int53 = {
	encode = function(w: Writer, v: number)
		assertSafeInteger(v, MIN_SAFE_INTEGER, MAX_SAFE_INTEGER, "int53")
		w:writeF64(v)
	end,
	decode = function(r: Reader): number
		local v = r:readF64()
		assertSafeInteger(v, MIN_SAFE_INTEGER, MAX_SAFE_INTEGER, "decoded int53")
		return v
	end,
} :: Codec<number>

Loom.uint53 = {
	encode = function(w: Writer, v: number)
		assertSafeInteger(v, 0, MAX_SAFE_INTEGER, "uint53")
		w:writeF64(v)
	end,
	decode = function(r: Reader): number
		local v = r:readF64()
		assertSafeInteger(v, 0, MAX_SAFE_INTEGER, "decoded uint53")
		return v
	end,
} :: Codec<number>

Loom.f64_int = Loom.int53

Loom.varint = {
	encode = function(w: Writer, v: number) w:writeVarint(v) end,
	decode = function(r: Reader) return r:readVarint() end,
} :: Codec<number>

Loom.svarint = {
	encode = function(w: Writer, v: number) w:writeSVarint(v) end,
	decode = function(r: Reader) return r:readSVarint() end,
} :: Codec<number>

Loom.bool = {
	encode = function(w: Writer, v: boolean) w:writeBool(v) end,
	decode = function(r: Reader) return r:readBool() end,
} :: Codec<boolean>

Loom.str = {
	encode = function(w: Writer, v: string) w:writeStr(v) end,
	decode = function(r: Reader) return r:readStr() end,
} :: Codec<string>

Loom.bytes = Loom.str

Loom.buffer = {
	encode = function(w: Writer, v: buffer)
		local len = b_len(v)
		w:writeVarint(len)
		if len > 0 then
			w:copyFrom(v, 0, len)
		end
	end,
	decode = function(r: Reader): buffer
		local len = r:readVarint()
		if len == 0 then return b_create(0) end
		r:_check(len)
		local out = b_create(len)
		b_copy(out, 0, r._buf, r._pos, len)
		r._pos += len
		return out
	end,
} :: Codec<buffer>

-- bounded_str: rejects strings over maxLen on both ends
-- example: Loom.bounded_str(256)
function Loom.bounded_str(maxLen: number): Codec<string>
	assert(maxLen >= 1, "bounded_str: maxLen must be >= 1")
	return {
		encode = function(w: Writer, v: string)
			assert(#v <= maxLen,
				string.format("loom: string length %d exceeds bound %d", #v, maxLen))
			w:writeStr(v)
		end,
		decode = function(r: Reader): string
			local len = r:readVarint()
			if len > maxLen then
				error(string.format(
					"loom: string length %d exceeds bound %d -- possible attack?", len, maxLen
				), 2)
			end
			if len == 0 then return "" end
			r:_check(len)
			local s = b_readstring(r._buf, r._pos, len)
			r._pos += len
			return s
		end,
	}
end

-- roblox types

Loom.vec2 = {
	encode = function(w: Writer, v: Vector2)
		w:_reserve(8)
		b_writef32(w._buf, w._pos, v.X)
		b_writef32(w._buf, w._pos + 4, v.Y)
		w._pos += 8
	end,
	decode = function(r: Reader): Vector2
		return Vector2.new(r:readF32(), r:readF32())
	end,
} :: Codec<Vector2>

Loom.vec3 = {
	encode = function(w: Writer, v: Vector3)
		w:_reserve(12)
		b_writef32(w._buf, w._pos, v.X)
		b_writef32(w._buf, w._pos + 4, v.Y)
		b_writef32(w._buf, w._pos + 8, v.Z)
		w._pos += 12
	end,
	decode = function(r: Reader): Vector3
		return Vector3.new(r:readF32(), r:readF32(), r:readF32())
	end,
} :: Codec<Vector3>

-- color3: quantizes to 3 bytes, don't use for HDR
Loom.color3 = {
	encode = function(w: Writer, v: Color3)
		local r8 = math.clamp(math.round(v.R * 255), 0, 255)
		local g8 = math.clamp(math.round(v.G * 255), 0, 255)
		local b8 = math.clamp(math.round(v.B * 255), 0, 255)
		w:_reserve(3)
		b_writeu8(w._buf, w._pos, r8)
		b_writeu8(w._buf, w._pos + 1, g8)
		b_writeu8(w._buf, w._pos + 2, b8)
		w._pos += 3
	end,
	decode = function(r: Reader): Color3
		return Color3.new(r:readU8() / 255, r:readU8() / 255, r:readU8() / 255)
	end,
} :: Codec<Color3>

Loom.udim = {
	encode = function(w: Writer, v: UDim)
		w:_reserve(6)
		b_writef32(w._buf, w._pos, v.Scale)
		local off = math.clamp(v.Offset, -32768, 32767)
		b_writei16(w._buf, w._pos + 4, off)
		w._pos += 6
	end,
	decode = function(r: Reader): UDim
		return UDim.new(r:readF32(), r:readI16())
	end,
} :: Codec<UDim>

Loom.udim2 = {
	encode = function(w: Writer, v: UDim2)
		w:_reserve(12)
		b_writef32(w._buf, w._pos, v.X.Scale)
		local xoff = math.clamp(v.X.Offset, -32768, 32767)
		b_writei16(w._buf, w._pos + 4, xoff)
		b_writef32(w._buf, w._pos + 6, v.Y.Scale)
		local yoff = math.clamp(v.Y.Offset, -32768, 32767)
		b_writei16(w._buf, w._pos + 10, yoff)
		w._pos += 12
	end,
	decode = function(r: Reader): UDim2
		return UDim2.new(r:readF32(), r:readI16(), r:readF32(), r:readI16())
	end,
} :: Codec<UDim2>

Loom.vec3int16 = {
	encode = function(w: Writer, v: Vector3int16)
		w:_reserve(6)
		b_writei16(w._buf, w._pos, v.X)
		b_writei16(w._buf, w._pos + 2, v.Y)
		b_writei16(w._buf, w._pos + 4, v.Z)
		w._pos += 6
	end,
	decode = function(r: Reader): Vector3int16
		return Vector3int16.new(r:readI16(), r:readI16(), r:readI16())
	end,
} :: Codec<Vector3int16>

-- quaternion helpers (smallest-3)
-- drop the largest component, store the other 3 scaled to i16.
-- negate everything if the dropped component is negative so decode can always sqrt.

local function cfToQuat(cf: CFrame): (number, number, number, number)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local trace = r00 + r11 + r22
	local qw, qx, qy, qz
	if trace > 0 then
		local s = 0.5 / math.sqrt(trace + 1)
		qw = 0.25 / s
		qx = (r21 - r12) * s
		qy = (r02 - r20) * s
		qz = (r10 - r01) * s
	elseif r00 > r11 and r00 > r22 then
		local s = 2 * math.sqrt(1 + r00 - r11 - r22)
		qw = (r21 - r12) / s
		qx = 0.25 * s
		qy = (r01 + r10) / s
		qz = (r02 + r20) / s
	elseif r11 > r22 then
		local s = 2 * math.sqrt(1 + r11 - r00 - r22)
		qw = (r02 - r20) / s
		qx = (r01 + r10) / s
		qy = 0.25 * s
		qz = (r12 + r21) / s
	else
		local s = 2 * math.sqrt(1 + r22 - r00 - r11)
		qw = (r10 - r01) / s
		qx = (r02 + r20) / s
		qy = (r12 + r21) / s
		qz = 0.25 * s
	end
	return qw, qx, qy, qz
end

local function encodeSmallest3(w: Writer, qw: number, qx: number, qy: number, qz: number)
	local drop   = 0
	local maxAbs = math.abs(qw)
	local aX, aY, aZ = math.abs(qx), math.abs(qy), math.abs(qz)
	if aX > maxAbs then maxAbs = aX; drop = 1 end
	if aY > maxAbs then maxAbs = aY; drop = 2 end
	if aZ > maxAbs then               drop = 3 end

	local sign = 1
	if (drop == 0 and qw < 0) or (drop == 1 and qx < 0)
	or (drop == 2 and qy < 0) or (drop == 3 and qz < 0) then
		sign = -1
	end
	local sw, sx, sy, sz = qw * sign, qx * sign, qy * sign, qz * sign

	local buf, pos = w._buf, w._pos
	w:_reserve(7)
	b_writeu8(buf, pos, drop)
	pos += 1
	if drop ~= 0 then
		b_writei16(buf, pos, math.clamp(math.round(sw * QUAT_SCALE), -32767, 32767)); pos += 2
	end
	if drop ~= 1 then
		b_writei16(buf, pos, math.clamp(math.round(sx * QUAT_SCALE), -32767, 32767)); pos += 2
	end
	if drop ~= 2 then
		b_writei16(buf, pos, math.clamp(math.round(sy * QUAT_SCALE), -32767, 32767)); pos += 2
	end
	if drop ~= 3 then
		b_writei16(buf, pos, math.clamp(math.round(sz * QUAT_SCALE), -32767, 32767)); pos += 2
	end
	w._pos = pos
end

local function decodeSmallest3(r: Reader): (number, number, number, number)
	local drop = r:readU8()
	if drop > 3 then
		error(string.format("loom: quaternion drop index %d invalid -- corrupt buffer?", drop), 3)
	end
	local a = r:readI16() / QUAT_SCALE
	local b = r:readI16() / QUAT_SCALE
	local c = r:readI16() / QUAT_SCALE
	local d = math.sqrt(math.max(0, 1 - a*a - b*b - c*c))
	if     drop == 0 then return  d, a, b, c
	elseif drop == 1 then return  a, d, b, c
	elseif drop == 2 then return  a, b, d, c
	else                   return  a, b, c, d
	end
end

-- cframe: f32 position + full f32 quaternion
Loom.cframe = {
	encode = function(w: Writer, cf: CFrame)
		local p = cf.Position
		w:_reserve(28)
		b_writef32(w._buf, w._pos, p.X)
		b_writef32(w._buf, w._pos + 4, p.Y)
		b_writef32(w._buf, w._pos + 8, p.Z)
		local qw, qx, qy, qz = cfToQuat(cf)
		b_writef32(w._buf, w._pos + 12, qx)
		b_writef32(w._buf, w._pos + 16, qy)
		b_writef32(w._buf, w._pos + 20, qz)
		b_writef32(w._buf, w._pos + 24, qw)
		w._pos += 28
	end,
	decode = function(r: Reader): CFrame
		local px, py, pz = r:readF32(), r:readF32(), r:readF32()
		local qx, qy, qz, qw = r:readF32(), r:readF32(), r:readF32(), r:readF32()
		return CFrame.new(px, py, pz, qx, qy, qz, qw)
	end,
} :: Codec<CFrame>

-- cframe_compressed: f32 position + smallest-3 rotation
Loom.cframe_compressed = {
	encode = function(w: Writer, cf: CFrame)
		local p = cf.Position
		w:_reserve(12)
		b_writef32(w._buf, w._pos, p.X)
		b_writef32(w._buf, w._pos + 4, p.Y)
		b_writef32(w._buf, w._pos + 8, p.Z)
		w._pos += 12
		local qw, qx, qy, qz = cfToQuat(cf)
		encodeSmallest3(w, qw, qx, qy, qz)
	end,
	decode = function(r: Reader): CFrame
		local px, py, pz = r:readF32(), r:readF32(), r:readF32()
		local qw, qx, qy, qz = decodeSmallest3(r)
		return CFrame.new(px, py, pz, qx, qy, qz, qw)
	end,
} :: Codec<CFrame>

-- cframe_net: quantized u16 position + smallest-3 rotation
-- example: Loom.cframe_net()           -- +-4096 studs
--          Loom.cframe_net(-1024, 1024)
function Loom.cframe_net(posMin: number?, posMax: number?): Codec<CFrame>
	local pMin   = posMin or -4096
	local pMax   = posMax or  4096
	assert(pMin < pMax, "cframe_net: posMin must be less than posMax")
	local range  = pMax - pMin
	local maxInt = 65535

	local function qPos(v: number): number
		return math.clamp(math.round((v - pMin) / range * maxInt), 0, maxInt)
	end
	local function dqPos(v: number): number
		return pMin + (v / maxInt) * range
	end

	return {
		encode = function(w: Writer, cf: CFrame)
			local p = cf.Position
			w:_reserve(6)
			b_writeu16(w._buf, w._pos,     qPos(p.X))
			b_writeu16(w._buf, w._pos + 2, qPos(p.Y))
			b_writeu16(w._buf, w._pos + 4, qPos(p.Z))
			w._pos += 6
			local qw, qx, qy, qz = cfToQuat(cf)
			encodeSmallest3(w, qw, qx, qy, qz)
		end,
		decode = function(r: Reader): CFrame
			local px = dqPos(r:readU16())
			local py = dqPos(r:readU16())
			local pz = dqPos(r:readU16())
			local qw, qx, qy, qz = decodeSmallest3(r)
			return CFrame.new(px, py, pz, qx, qy, qz, qw)
		end,
	}
end

-- stored as u32 value, not name string
-- example: Loom.roblox_enum(Enum.HumanoidRigType)
function Loom.roblox_enum(enumType: Enum): Codec<EnumItem>
	local byValue: {[number]: EnumItem} = {}
	for _, item in ipairs(enumType:GetEnumItems()) do
		byValue[item.Value] = item
	end
	return {
		encode = function(w: Writer, v: EnumItem)
			w:writeU32(v.Value)
		end,
		decode = function(r: Reader): EnumItem
			local val  = r:readU32()
			local item = byValue[val]
			if not item then
				error(string.format("loom: unknown enum value %d", val), 2)
			end
			return item
		end,
	}
end

-- quantized vec3
-- bits=8 -> 3 bytes, bits=16 -> 6 bytes
-- example: Loom.vec3_quantized(-4096, 4096, 16)
function Loom.vec3_quantized(minVal: number, maxVal: number, bits: number): Codec<Vector3>
	assert(bits == 8 or bits == 16, "vec3_quantized: bits must be 8 or 16")
	assert(minVal < maxVal, "vec3_quantized: minVal must be less than maxVal")
	local range  = maxVal - minVal
	local maxInt = (2 ^ bits) - 1

	local function quantize(v: number): number
		return math.clamp(math.round((v - minVal) / range * maxInt), 0, maxInt)
	end
	local function dequantize(v: number): number
		return minVal + (v / maxInt) * range
	end

	if bits == 8 then
		return {
			encode = function(w: Writer, v: Vector3)
				w:_reserve(3)
				b_writeu8(w._buf, w._pos,     quantize(v.X))
				b_writeu8(w._buf, w._pos + 1, quantize(v.Y))
				b_writeu8(w._buf, w._pos + 2, quantize(v.Z))
				w._pos += 3
			end,
			decode = function(r: Reader): Vector3
				return Vector3.new(dequantize(r:readU8()), dequantize(r:readU8()), dequantize(r:readU8()))
			end,
		}
	else
		return {
			encode = function(w: Writer, v: Vector3)
				w:_reserve(6)
				b_writeu16(w._buf, w._pos,     quantize(v.X))
				b_writeu16(w._buf, w._pos + 2, quantize(v.Y))
				b_writeu16(w._buf, w._pos + 4, quantize(v.Z))
				w._pos += 6
			end,
			decode = function(r: Reader): Vector3
				return Vector3.new(dequantize(r:readU16()), dequantize(r:readU16()), dequantize(r:readU16()))
			end,
		}
	end
end

-- composite codecs

-- array: varint count + elements
-- example: Loom.array(Loom.u32)
-- example: Loom.array(Loom.str, 1000)
function Loom.array<T>(elementCodec: Codec<T>, maxCount: number?): Codec<{T}>
	local limit = maxCount or DEFAULT_MAX_COUNT
	return {
		encode = function(w: Writer, arr: {T})
			assert(#arr <= limit,
				string.format("loom: array count %d exceeds limit %d", #arr, limit))
			w:writeVarint(#arr)
			for _, v in ipairs(arr) do
				elementCodec.encode(w, v)
			end
		end,
		decode = function(r: Reader): {T}
			local count = r:readVarint()
			if count > limit then
				error(string.format(
					"loom: array count %d exceeds limit %d -- corrupt or malicious buffer?",
					count, limit
				), 2)
			end
			local out: {T} = count <= r:remaining() and table.create(count) or {}
			for i = 1, count do
				out[i] = elementCodec.decode(r)
			end
			return out
		end,
	}
end

-- map: sorted keys for deterministic wire order
-- note: sorting adds O(n log n) overhead, use array(struct) if you need max throughput
function Loom.map<K, V>(keyCodec: Codec<K>, valCodec: Codec<V>, maxCount: number?): Codec<{[K]: V}>
	local limit = maxCount or DEFAULT_MAX_COUNT
	return {
		encode = function(w: Writer, m: {[K]: V})
			local keys: {K} = {}
			for k in pairs(m) do
				keys[#keys + 1] = k
			end
			assert(#keys <= limit,
				string.format("loom: map count %d exceeds limit %d", #keys, limit))
			local sortFn = nil
			if #keys > 1 then
				local kt = type(keys[1])
				for i = 2, #keys do
					if type(keys[i]) ~= kt then
						error(string.format(
							"loom: map keys must all be the same type for sorting, got '%s' and '%s'",
							kt, type(keys[i])
						), 2)
					end
				end
				if kt == "string" or kt == "number" then
					sortFn = function(a, b) return a < b end
				elseif kt == "boolean" then
					sortFn = function(a, b) return a == false and b == true end
				else
					error(string.format(
						"loom: map keys of type '%s' can't be sorted deterministically; use string, number, or boolean keys",
						kt
					), 2)
				end
			end
			table.sort(keys, sortFn)
			w:writeVarint(#keys)
			for _, k in ipairs(keys) do
				keyCodec.encode(w, k)
				valCodec.encode(w, m[k])
			end
		end,
		decode = function(r: Reader): {[K]: V}
			local count = r:readVarint()
			if count > limit then
				error(string.format(
					"loom: map count %d exceeds limit %d -- corrupt or malicious buffer?",
					count, limit
				), 2)
			end
			local out: {[K]: V} = {}
			for _ = 1, count do
				local k = keyCodec.decode(r)
				out[k] = valCodec.decode(r)
			end
			return out
		end,
	}
end

-- struct unroll helpers
-- for n <= 8 we skip the loop entirely, direct upvalue calls

local function buildUnrolledEncode(
	encFns: {any},
	names: {string},
	hasDefaults: {boolean},
	defaults: {any},
	n: number
): (Writer, {[string]: any}) -> ()
	if n == 1 then
		local e1,n1,h1,d1 = encFns[1],names[1],hasDefaults[1],defaults[1]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then
				if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end
			end
			e1(w,x1)
		end
	elseif n == 2 then
		local e1,n1,h1,d1,e2,n2,h2,d2 = encFns[1],names[1],hasDefaults[1],defaults[1],encFns[2],names[2],hasDefaults[2],defaults[2]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end end
			local x2 = v[n2]
			if x2 == nil then if h2 then x2 = d2 else error(string.format("loom: missing struct field '%s'", n2), 2) end end
			e1(w,x1); e2(w,x2)
		end
	elseif n == 3 then
		local e1,n1,h1,d1,e2,n2,h2,d2,e3,n3,h3,d3 = encFns[1],names[1],hasDefaults[1],defaults[1],encFns[2],names[2],hasDefaults[2],defaults[2],encFns[3],names[3],hasDefaults[3],defaults[3]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end end
			local x2 = v[n2]
			if x2 == nil then if h2 then x2 = d2 else error(string.format("loom: missing struct field '%s'", n2), 2) end end
			local x3 = v[n3]
			if x3 == nil then if h3 then x3 = d3 else error(string.format("loom: missing struct field '%s'", n3), 2) end end
			e1(w,x1); e2(w,x2); e3(w,x3)
		end
	elseif n == 4 then
		local e1,n1,h1,d1,e2,n2,h2,d2,e3,n3,h3,d3,e4,n4,h4,d4 = encFns[1],names[1],hasDefaults[1],defaults[1],encFns[2],names[2],hasDefaults[2],defaults[2],encFns[3],names[3],hasDefaults[3],defaults[3],encFns[4],names[4],hasDefaults[4],defaults[4]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end end
			local x2 = v[n2]
			if x2 == nil then if h2 then x2 = d2 else error(string.format("loom: missing struct field '%s'", n2), 2) end end
			local x3 = v[n3]
			if x3 == nil then if h3 then x3 = d3 else error(string.format("loom: missing struct field '%s'", n3), 2) end end
			local x4 = v[n4]
			if x4 == nil then if h4 then x4 = d4 else error(string.format("loom: missing struct field '%s'", n4), 2) end end
			e1(w,x1); e2(w,x2); e3(w,x3); e4(w,x4)
		end
	elseif n == 5 then
		local e1,n1,h1,d1,e2,n2,h2,d2,e3,n3,h3,d3,e4,n4,h4,d4,e5,n5,h5,d5 = encFns[1],names[1],hasDefaults[1],defaults[1],encFns[2],names[2],hasDefaults[2],defaults[2],encFns[3],names[3],hasDefaults[3],defaults[3],encFns[4],names[4],hasDefaults[4],defaults[4],encFns[5],names[5],hasDefaults[5],defaults[5]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end end
			local x2 = v[n2]
			if x2 == nil then if h2 then x2 = d2 else error(string.format("loom: missing struct field '%s'", n2), 2) end end
			local x3 = v[n3]
			if x3 == nil then if h3 then x3 = d3 else error(string.format("loom: missing struct field '%s'", n3), 2) end end
			local x4 = v[n4]
			if x4 == nil then if h4 then x4 = d4 else error(string.format("loom: missing struct field '%s'", n4), 2) end end
			local x5 = v[n5]
			if x5 == nil then if h5 then x5 = d5 else error(string.format("loom: missing struct field '%s'", n5), 2) end end
			e1(w,x1); e2(w,x2); e3(w,x3); e4(w,x4); e5(w,x5)
		end
	elseif n == 6 then
		local e1,n1,h1,d1,e2,n2,h2,d2,e3,n3,h3,d3,e4,n4,h4,d4,e5,n5,h5,d5,e6,n6,h6,d6 = encFns[1],names[1],hasDefaults[1],defaults[1],encFns[2],names[2],hasDefaults[2],defaults[2],encFns[3],names[3],hasDefaults[3],defaults[3],encFns[4],names[4],hasDefaults[4],defaults[4],encFns[5],names[5],hasDefaults[5],defaults[5],encFns[6],names[6],hasDefaults[6],defaults[6]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end end
			local x2 = v[n2]
			if x2 == nil then if h2 then x2 = d2 else error(string.format("loom: missing struct field '%s'", n2), 2) end end
			local x3 = v[n3]
			if x3 == nil then if h3 then x3 = d3 else error(string.format("loom: missing struct field '%s'", n3), 2) end end
			local x4 = v[n4]
			if x4 == nil then if h4 then x4 = d4 else error(string.format("loom: missing struct field '%s'", n4), 2) end end
			local x5 = v[n5]
			if x5 == nil then if h5 then x5 = d5 else error(string.format("loom: missing struct field '%s'", n5), 2) end end
			local x6 = v[n6]
			if x6 == nil then if h6 then x6 = d6 else error(string.format("loom: missing struct field '%s'", n6), 2) end end
			e1(w,x1); e2(w,x2); e3(w,x3); e4(w,x4); e5(w,x5); e6(w,x6)
		end
	elseif n == 7 then
		local e1,n1,h1,d1,e2,n2,h2,d2,e3,n3,h3,d3,e4,n4,h4,d4,e5,n5,h5,d5,e6,n6,h6,d6,e7,n7,h7,d7 = encFns[1],names[1],hasDefaults[1],defaults[1],encFns[2],names[2],hasDefaults[2],defaults[2],encFns[3],names[3],hasDefaults[3],defaults[3],encFns[4],names[4],hasDefaults[4],defaults[4],encFns[5],names[5],hasDefaults[5],defaults[5],encFns[6],names[6],hasDefaults[6],defaults[6],encFns[7],names[7],hasDefaults[7],defaults[7]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end end
			local x2 = v[n2]
			if x2 == nil then if h2 then x2 = d2 else error(string.format("loom: missing struct field '%s'", n2), 2) end end
			local x3 = v[n3]
			if x3 == nil then if h3 then x3 = d3 else error(string.format("loom: missing struct field '%s'", n3), 2) end end
			local x4 = v[n4]
			if x4 == nil then if h4 then x4 = d4 else error(string.format("loom: missing struct field '%s'", n4), 2) end end
			local x5 = v[n5]
			if x5 == nil then if h5 then x5 = d5 else error(string.format("loom: missing struct field '%s'", n5), 2) end end
			local x6 = v[n6]
			if x6 == nil then if h6 then x6 = d6 else error(string.format("loom: missing struct field '%s'", n6), 2) end end
			local x7 = v[n7]
			if x7 == nil then if h7 then x7 = d7 else error(string.format("loom: missing struct field '%s'", n7), 2) end end
			e1(w,x1); e2(w,x2); e3(w,x3); e4(w,x4); e5(w,x5); e6(w,x6); e7(w,x7)
		end
	elseif n == 8 then
		local e1,n1,h1,d1,e2,n2,h2,d2,e3,n3,h3,d3,e4,n4,h4,d4,e5,n5,h5,d5,e6,n6,h6,d6,e7,n7,h7,d7,e8,n8,h8,d8 = encFns[1],names[1],hasDefaults[1],defaults[1],encFns[2],names[2],hasDefaults[2],defaults[2],encFns[3],names[3],hasDefaults[3],defaults[3],encFns[4],names[4],hasDefaults[4],defaults[4],encFns[5],names[5],hasDefaults[5],defaults[5],encFns[6],names[6],hasDefaults[6],defaults[6],encFns[7],names[7],hasDefaults[7],defaults[7],encFns[8],names[8],hasDefaults[8],defaults[8]
		return function(w,v)
			local x1 = v[n1]
			if x1 == nil then if h1 then x1 = d1 else error(string.format("loom: missing struct field '%s'", n1), 2) end end
			local x2 = v[n2]
			if x2 == nil then if h2 then x2 = d2 else error(string.format("loom: missing struct field '%s'", n2), 2) end end
			local x3 = v[n3]
			if x3 == nil then if h3 then x3 = d3 else error(string.format("loom: missing struct field '%s'", n3), 2) end end
			local x4 = v[n4]
			if x4 == nil then if h4 then x4 = d4 else error(string.format("loom: missing struct field '%s'", n4), 2) end end
			local x5 = v[n5]
			if x5 == nil then if h5 then x5 = d5 else error(string.format("loom: missing struct field '%s'", n5), 2) end end
			local x6 = v[n6]
			if x6 == nil then if h6 then x6 = d6 else error(string.format("loom: missing struct field '%s'", n6), 2) end end
			local x7 = v[n7]
			if x7 == nil then if h7 then x7 = d7 else error(string.format("loom: missing struct field '%s'", n7), 2) end end
			local x8 = v[n8]
			if x8 == nil then if h8 then x8 = d8 else error(string.format("loom: missing struct field '%s'", n8), 2) end end
			e1(w,x1); e2(w,x2); e3(w,x3); e4(w,x4); e5(w,x5); e6(w,x6); e7(w,x7); e8(w,x8)
		end
	else
		return function(w, v)
			for i = 1, n do
				local value = v[names[i]]
				if value == nil then
					if hasDefaults[i] then
						value = defaults[i]
					else
						error(string.format("loom: missing struct field '%s'", names[i]), 2)
					end
				end
				encFns[i](w, value)
			end
		end
	end
end

local function buildUnrolledDecode(decFns: {any}, names: {string}, n: number): (Reader) -> {[string]: any}
	if n == 1 then
		local d1,n1 = decFns[1],names[1]
		return function(r) local o={};o[n1]=d1(r);return o end
	elseif n == 2 then
		local d1,n1,d2,n2 = decFns[1],names[1],decFns[2],names[2]
		return function(r) local o={};o[n1]=d1(r);o[n2]=d2(r);return o end
	elseif n == 3 then
		local d1,n1,d2,n2,d3,n3 = decFns[1],names[1],decFns[2],names[2],decFns[3],names[3]
		return function(r) local o={};o[n1]=d1(r);o[n2]=d2(r);o[n3]=d3(r);return o end
	elseif n == 4 then
		local d1,n1,d2,n2,d3,n3,d4,n4 = decFns[1],names[1],decFns[2],names[2],decFns[3],names[3],decFns[4],names[4]
		return function(r) local o={};o[n1]=d1(r);o[n2]=d2(r);o[n3]=d3(r);o[n4]=d4(r);return o end
	elseif n == 5 then
		local d1,n1,d2,n2,d3,n3,d4,n4,d5,n5 = decFns[1],names[1],decFns[2],names[2],decFns[3],names[3],decFns[4],names[4],decFns[5],names[5]
		return function(r) local o={};o[n1]=d1(r);o[n2]=d2(r);o[n3]=d3(r);o[n4]=d4(r);o[n5]=d5(r);return o end
	elseif n == 6 then
		local d1,n1,d2,n2,d3,n3,d4,n4,d5,n5,d6,n6 = decFns[1],names[1],decFns[2],names[2],decFns[3],names[3],decFns[4],names[4],decFns[5],names[5],decFns[6],names[6]
		return function(r) local o={};o[n1]=d1(r);o[n2]=d2(r);o[n3]=d3(r);o[n4]=d4(r);o[n5]=d5(r);o[n6]=d6(r);return o end
	elseif n == 7 then
		local d1,n1,d2,n2,d3,n3,d4,n4,d5,n5,d6,n6,d7,n7 = decFns[1],names[1],decFns[2],names[2],decFns[3],names[3],decFns[4],names[4],decFns[5],names[5],decFns[6],names[6],decFns[7],names[7]
		return function(r) local o={};o[n1]=d1(r);o[n2]=d2(r);o[n3]=d3(r);o[n4]=d4(r);o[n5]=d5(r);o[n6]=d6(r);o[n7]=d7(r);return o end
	elseif n == 8 then
		local d1,n1,d2,n2,d3,n3,d4,n4,d5,n5,d6,n6,d7,n7,d8,n8 = decFns[1],names[1],decFns[2],names[2],decFns[3],names[3],decFns[4],names[4],decFns[5],names[5],decFns[6],names[6],decFns[7],names[7],decFns[8],names[8]
		return function(r) local o={};o[n1]=d1(r);o[n2]=d2(r);o[n3]=d3(r);o[n4]=d4(r);o[n5]=d5(r);o[n6]=d6(r);o[n7]=d7(r);o[n8]=d8(r);return o end
	else
		return function(r)
			local out: {[string]: any} = {}
			for i = 1, n do out[names[i]] = decFns[i](r) end
			return out
		end
	end
end

-- struct: field order is wire format, never reorder/remove fields
-- append new fields at the end only
-- example:
--   Loom.struct({
--     {"id",     Loom.u32},
--     {"name",   Loom.str},
--     {"health", Loom.f32},
--   })
function Loom.struct(fields: {{any}}): Codec<{[string]: any}>
	local n = #fields

	local encFns:   {any}    = table.create(n)
	local decFns:   {any}    = table.create(n)
	local names:    {string} = table.create(n)
	local defaults: {any}    = table.create(n)
	local hasDefaults: {boolean} = table.create(n)
	local indexMap: {[string]: number} = {}

	for i, pair in ipairs(fields) do
		assert(type(pair[1]) == "string", string.format("struct field %d: name must be a string", i))
		assert(type(pair[2]) == "table",  string.format("struct field %d ('%s'): codec must be a table", i, pair[1]))
		local nm    = pair[1] :: string
		local codec = pair[2] :: Codec<any>
		encFns[i]      = codec.encode
		decFns[i]      = codec.decode
		names[i]       = nm
		hasDefaults[i] = pair[3] ~= nil
		defaults[i]    = pair[3]
		indexMap[nm]   = i
	end

	local encFn = buildUnrolledEncode(encFns, names, hasDefaults, defaults, n)
	local decFn = buildUnrolledDecode(decFns, names, n)

	return {
		encode = encFn,
		decode = decFn,
		fieldIndex = function(name: string): number?
			return indexMap[name]
		end,
		fieldCount = n,
	}
end

-- delta_struct: sparse updates with delete support
-- wire format: 1 byte mode + ceil(n/8) presence bytes + optional delete bytes + values
-- fields absent from v are skipped. Loom.none marks a delete.
-- decode returns only changed fields; deletes come back as Loom.none.
-- apply with Loom.applyDelta so deletes are handled correctly.
function Loom.delta_struct(fields: {{any}}): Codec<{[string]: any}>
	local n = #fields
	assert(n >= 1, "delta_struct: needs at least one field")
	local byteCount = math.ceil(n / 8)
	local MODE_HAS_DELETES = 1

	type CompiledField = {name: string, codec: Codec<any>, bi: number, bit: number}
	local compiled: {CompiledField} = table.create(n)
	for i, pair in ipairs(fields) do
		assert(type(pair[1]) == "string", string.format("delta_struct field %d: name must be a string", i))
		assert(type(pair[2]) == "table",  string.format("delta_struct field %d ('%s'): codec must be a table", i, pair[1]))
		compiled[i] = {
			name  = pair[1] :: string,
			codec = pair[2] :: Codec<any>,
			bi    = math.ceil(i / 8),
			bit   = bit32.lshift(1, (i - 1) % 8),
		}
	end

	return {
		encode = function(w: Writer, v: {[string]: any})
			local presentMask: {number} = table.create(byteCount, 0)
			local deleteMask: {number} = table.create(byteCount, 0)
			local hasDeletes = false
			for i = 1, n do
				local cf = compiled[i]
				local value = v[cf.name]
				if value == NONE then
					deleteMask[cf.bi] = bit32.bor(deleteMask[cf.bi], cf.bit)
					hasDeletes = true
				elseif value ~= nil then
					presentMask[cf.bi] = bit32.bor(presentMask[cf.bi], cf.bit)
				end
			end
			w:_reserve(1 + byteCount + (hasDeletes and byteCount or 0))
			b_writeu8(w._buf, w._pos, hasDeletes and MODE_HAS_DELETES or 0)
			w._pos += 1
			for i = 1, byteCount do
				b_writeu8(w._buf, w._pos, presentMask[i])
				w._pos += 1
			end
			if hasDeletes then
				for i = 1, byteCount do
					b_writeu8(w._buf, w._pos, deleteMask[i])
					w._pos += 1
				end
			end
			for i = 1, n do
				local cf  = compiled[i]
				local val = v[cf.name]
				if val ~= nil and val ~= NONE then
					cf.codec.encode(w, val)
				end
			end
		end,
		decode = function(r: Reader): {[string]: any}
			local mode = r:readU8()
			if bit32.band(mode, bit32.bnot(MODE_HAS_DELETES)) ~= 0 then
				error(string.format("loom: delta_struct mode %d is invalid -- corrupt buffer?", mode), 2)
			end
			local presentMask: {number} = table.create(byteCount)
			local deleteMask: {number} = table.create(byteCount, 0)
			for i = 1, byteCount do
				presentMask[i] = r:readU8()
			end
			if bit32.band(mode, MODE_HAS_DELETES) ~= 0 then
				for i = 1, byteCount do
					deleteMask[i] = r:readU8()
				end
			end
			local out: {[string]: any} = {}
			for i = 1, n do
				local cf = compiled[i]
				local hasValue  = bit32.band(presentMask[cf.bi], cf.bit) ~= 0
				local hasDelete = bit32.band(deleteMask[cf.bi], cf.bit) ~= 0
				if hasValue and hasDelete then
					error(string.format(
						"loom: field '%s' is marked as both present and deleted -- corrupt buffer?",
						cf.name
					), 2)
				end
				if hasValue then
					out[cf.name] = cf.codec.decode(r)
				elseif hasDelete then
					out[cf.name] = NONE
				end
			end
			return out
		end,
	}
end

-- tracked_struct: diffs prev/curr for you, encodes only what changed
-- uses the same wire format as delta_struct
-- nested table fields use reference equality, so replace the table to trigger detection
-- example:
--   local Tracker = Loom.tracked_struct({
--     {"position", Loom.vec3},
--     {"health",   Loom.f32},
--   })
--   local buf   = Loom.encodeRaw(Tracker, prevState, currState)
--   local delta = Loom.decodeRaw(Tracker, buf)
--   Loom.applyDelta(clientState, delta)
function Loom.tracked_struct(fields: {{any}}): {
	encode: (writer: Writer, prev: {[string]: any}, curr: {[string]: any}) -> (),
	decode: (reader: Reader) -> {[string]: any},
}
	local inner = Loom.delta_struct(fields)
	local n     = #fields
	local names: {string} = table.create(n)
	for i, pair in ipairs(fields) do
		names[i] = pair[1] :: string
	end

	return {
		encode = function(w: Writer, prev: {[string]: any}, curr: {[string]: any})
			local delta: {[string]: any} = {}
			for i = 1, n do
				local nm = names[i]
				local currValue = curr[nm]
				if currValue ~= prev[nm] then
					delta[nm] = currValue == nil and NONE or currValue
				end
			end
			inner.encode(w, delta)
		end,
		decode = inner.decode,
	}
end

function Loom.applyDelta(state: {[string]: any}, delta: {[string]: any}): {[string]: any}
	for key, value in pairs(delta) do
		if value == NONE then
			state[key] = nil
		else
			state[key] = value
		end
	end
	return state
end

function Loom.isNone(value: any): boolean
	return value == NONE
end

-- optional: 1 byte presence + value if set
function Loom.optional<T>(inner: Codec<T>): Codec<T?>
	return {
		encode = function(w: Writer, v: T?)
			if v == nil then
				w:_reserve(1)
				b_writeu8(w._buf, w._pos, 0)
				w._pos += 1
			else
				w:_reserve(1)
				b_writeu8(w._buf, w._pos, 1)
				w._pos += 1
				inner.encode(w, v)
			end
		end,
		decode = function(r: Reader): T?
			if r:readU8() == 0 then return nil end
			return inner.decode(r)
		end,
	}
end

-- union: u8 tag + variant value
-- example: local Reward = Loom.union({Loom.str, Loom.u32})
--          encode(w, {tag=0, value="sword"})
function Loom.union(codecs: {Codec<any>}): Codec<{tag: number, value: any}>
	assert(#codecs >= 1,   "union: needs at least one codec")
	assert(#codecs <= 255, "union: max 255 variants (u8 tag)")
	local count = #codecs
	return {
		encode = function(w: Writer, v: {tag: number, value: any})
			local tag = v.tag
			assert(tag >= 0 and tag < count,
				string.format("union: tag %d out of range [0, %d)", tag, count))
			w:_reserve(1)
			b_writeu8(w._buf, w._pos, tag)
			w._pos += 1
			codecs[tag + 1].encode(w, v.value)
		end,
		decode = function(r: Reader): {tag: number, value: any}
			local tag = r:readU8()
			if tag >= count then
				error(string.format("loom: union tag %d out of range -- corrupt buffer?", tag), 2)
			end
			return {tag = tag, value = codecs[tag + 1].decode(r)}
		end,
	}
end

-- tuple: fixed-length heterogeneous sequence, integer-keyed
-- example: Loom.tuple({Loom.u32, Loom.str, Loom.f32})
function Loom.tuple(codecs: {Codec<any>}): Codec<{any}>
	local count = #codecs
	return {
		encode = function(w: Writer, v: {any})
			for i = 1, count do
				codecs[i].encode(w, v[i])
			end
		end,
		decode = function(r: Reader): {any}
			local out: {any} = table.create(count)
			for i = 1, count do
				out[i] = codecs[i].decode(r)
			end
			return out
		end,
	}
end

-- bitfield: packs named booleans into ceil(n/8) bytes
-- example: Loom.bitfield({"isAdmin", "isPremium", "isBanned"})
function Loom.bitfield(fields: {string}): Codec<{[string]: boolean}>
	local n = #fields
	assert(n >= 1, "bitfield: needs at least one field")
	local byteCount = math.ceil(n / 8)
	return {
		encode = function(w: Writer, v: {[string]: boolean})
			local bytes: {number} = table.create(byteCount, 0)
			for i, name in ipairs(fields) do
				if v[name] then
					local byteIdx = math.ceil(i / 8)
					bytes[byteIdx] = bit32.bor(bytes[byteIdx], bit32.lshift(1, (i - 1) % 8))
				end
			end
			w:_reserve(byteCount)
			for i = 1, byteCount do
				b_writeu8(w._buf, w._pos, bytes[i])
				w._pos += 1
			end
		end,
		decode = function(r: Reader): {[string]: boolean}
			local bytes: {number} = table.create(byteCount)
			r:_check(byteCount)
			for i = 1, byteCount do
				bytes[i] = b_readu8(r._buf, r._pos)
				r._pos += 1
			end
			local out: {[string]: boolean} = {}
			for i, name in ipairs(fields) do
				local byteIdx = math.ceil(i / 8)
				out[name] = bit32.band(bit32.rshift(bytes[byteIdx], (i - 1) % 8), 1) == 1
			end
			return out
		end,
	}
end

-- enum: string -> varint index. values < 128 = 1 byte.
-- example: Loom.enum({"sword", "shield", "bow"})
function Loom.enum(values: {string}): Codec<string>
	assert(#values >= 1, "enum: needs at least one value")
	local toIdx: {[string]: number} = {}
	for i, v in ipairs(values) do
		toIdx[v] = i - 1
	end
	return {
		encode = function(w: Writer, v: string)
			local idx = toIdx[v]
			if idx == nil then
				error(string.format("loom: enum value '%s' not in schema", tostring(v)), 2)
			end
			w:writeVarint(idx)
		end,
		decode = function(r: Reader): string
			local idx = r:readVarint()
			local v   = values[idx + 1]
			if not v then
				error(string.format("loom: enum index %d out of range [0, %d)", idx, #values), 2)
			end
			return v
		end,
	}
end

-- literal: zero bytes on wire, always returns the same constant
-- use for default fields added in a new schema version
function Loom.literal<T>(value: T): Codec<T>
	return {
		encode = function(_w: Writer, _v: T) end,
		decode = function(_r: Reader): T return value end,
	}
end

-- schema versioning
-- header: magic (2) + name hash (2) + version (2) = 6 bytes

local function nameHash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + str_byte(s, i)) % 65536
	end
	return h
end

export type MigrationFn = (data: {[string]: any}) -> {[string]: any}

export type SchemaConfig<T> = {
	name: string,
	version: number,
	codec: Codec<T>,
	-- migrations[v] upgrades data from version v to v+1
	-- missing entries = no-op (purely additive change)
	migrations: {[number]: MigrationFn}?,
}

local SchemaMT = {}
SchemaMT.__index = SchemaMT

function SchemaMT:_writeHeader(w: Writer)
	w:_reserve(6)
	b_writeu8( w._buf, w._pos,     MAGIC_0)
	b_writeu8( w._buf, w._pos + 1, MAGIC_1)
	b_writeu16(w._buf, w._pos + 2, self._hash)
	b_writeu16(w._buf, w._pos + 4, self._version)
	w._pos += 6
end

function SchemaMT:_readHeader(r: Reader): number
	local m0 = r:readU8()
	local m1 = r:readU8()
	if m0 ~= MAGIC_0 or m1 ~= MAGIC_1 then
		error(string.format(
			"loom: bad magic 0x%02X%02X -- not a loom buffer or it's corrupt",
			m0, m1
		), 3)
	end
	local hash = r:readU16()
	if hash ~= self._hash then
		error(string.format(
			"loom: schema hash mismatch (0x%04X != 0x%04X for '%s') -- wrong schema",
			hash, self._hash, self._name
		), 3)
	end
	return r:readU16()
end

function SchemaMT:_migrate(data: {[string]: any}, from: number): {[string]: any}
	if from == self._version then return data end
	if from > self._version then
		error(string.format(
			"loom: buffer is version %d, schema is version %d -- can't downgrade",
			from, self._version
		), 3)
	end
	for v = from, self._version - 1 do
		local fn = self._migrations[v]
		if fn then data = fn(data) end
	end
	return data
end

function SchemaMT:encode(...: any): buffer
	local w = newWriter()
	self:_writeHeader(w)
	local codecAny = self._codec :: any
	codecAny.encode(w, ...)
	return w:flush()
end

function SchemaMT:encodeString(...: any): string
	return bufToStr(self:encode(...))
end

function SchemaMT:encodeBase64(...: any): string
	return base64Encode(self:encodeString(...))
end

-- encodePayload: skips the 6-byte header, use inside a known channel
function SchemaMT:encodePayload(...: any): buffer
	local w = newWriter()
	local codecAny = self._codec :: any
	codecAny.encode(w, ...)
	return w:flush()
end

function SchemaMT:encodePayloadString(...: any): string
	return bufToStr(self:encodePayload(...))
end

function SchemaMT:decode(buf: buffer): any
	local r              = newReader(buf)
	local encodedVersion = self:_readHeader(r)
	local data           = self._codec.decode(r)
	local remaining = r:remaining()
	if remaining ~= 0 then
		error(string.format(
			"loom: %d unconsumed byte(s) after decode for schema '%s' -- truncated schema or codec mismatch?",
			remaining, self._name
		), 2)
	end
	return self:_migrate(data, encodedVersion)
end

function SchemaMT:decodeString(s: string): any
	return self:decode(strToBuf(s))
end

function SchemaMT:decodeBase64(s: string): any
	return self:decodeString(base64Decode(s))
end

-- decodePayload: no header check, no migration
function SchemaMT:decodePayload(buf: buffer): any
	local r = newReader(buf)
	return self._codec.decode(r)
end

function SchemaMT:decodePayloadString(s: string): any
	return self:decodePayload(strToBuf(s))
end

-- example:
--   local ItemSchema = Loom.schema({
--     name    = "Item",
--     version = 2,
--     codec   = Loom.struct({
--       {"id",     Loom.u16},
--       {"name",   Loom.str},
--       {"damage", Loom.f32},
--       {"flags",  Loom.bitfield({"isFoil", "isLocked"})},
--     }),
--     migrations = {
--       [1] = function(data)
--         data.flags = {isFoil = false, isLocked = false}
--         return data
--       end,
--     },
--   })
function Loom.schema<T>(config: SchemaConfig<T>): any
	assert(type(config.name) == "string" and #config.name > 0,
		"schema name must be a non-empty string")
	assert(type(config.version) == "number" and config.version >= 1 and math.floor(config.version) == config.version,
		"schema version must be a positive integer")
	assert(type(config.codec) == "table",
		"schema codec must be a codec table")

	return setmetatable({
		_name       = config.name,
		_version    = config.version,
		_hash       = nameHash(config.name),
		_codec      = config.codec,
		_migrations = config.migrations or {},
	}, SchemaMT)
end

function Loom.encodeRaw<T>(codec: Codec<T>, value: T, ...: any): buffer
	local w = newWriter()
	local codecAny = codec :: any
	codecAny.encode(w, value, ...)
	return w:flush()
end

function Loom.decodeRaw<T>(codec: Codec<T>, buf: buffer): T
	local r = newReader(buf)
	return codec.decode(r)
end

Loom.newWriter    = newWriter
Loom.newReader    = newReader
Loom.base64Encode = base64Encode
Loom.base64Decode = base64Decode
Loom.bufToStr     = bufToStr
Loom.strToBuf     = strToBuf
Loom.none         = NONE
Loom.None         = NONE

return Loom

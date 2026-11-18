-- The hitmarker sound. The game plays only the sounds of the game's own sound banks, and a new sound there
-- means a new list of every sound in the game, which one other mod at a time can have. So this one
-- plays through Windows (winmm PlaySound, through LuaJIT's FFI, as Obsidian API takes screenshots):
-- the WAV of src/hitsound.lua, kept in memory at the volume set, played from the start on every mark.
-- A new mark cuts the one before short, as a hitmarker should. It goes past the game's volume
-- settings, so it has a volume setting of the mod.
local M = {}

M.FLAGS = 0x0001 + 0x0002 + 0x0004  -- SND_ASYNC, SND_NODEFAULT, SND_MEMORY
M.HEAD = 44                         -- bytes before the samples of a plain WAV
M.GAP = 0.03                        -- seconds between two plays at the least

-- The samples of `wav` (a string) at `volume` (0 to 1) as a string, the header kept. Pure, for tests.
function M.scaled(wav, volume)
	volume = math.max(0, math.min(1, volume or 1))
	if volume >= 1 then return wav end
	local out = { wav:sub(1, M.HEAD) }
	local bytes = {}
	for i = M.HEAD + 1, #wav - 1, 2 do
		local lo, hi = wav:byte(i, i + 1)
		local v = lo + hi * 256
		if v >= 32768 then v = v - 65536 end
		v = math.floor(v * volume + 0.5)
		if v < 0 then v = v + 65536 end
		bytes[#bytes + 1] = string.char(v % 256, math.floor(v / 256))
		if #bytes >= 512 then
			out[#out + 1] = table.concat(bytes)
			bytes = {}
		end
	end
	out[#out + 1] = table.concat(bytes)
	if #wav % 2 == 1 and #wav > M.HEAD then out[#out + 1] = wav:sub(-1) end
	return table.concat(out)
end

local function find_ffi()
	local ok, ffi = pcall(require, "ffi")
	if ok and type(ffi) == "table" then return ffi end
	local loaded = type(package) == "table" and package.loaded
	if type(loaded) == "table" and type(loaded.ffi) == "table" then return loaded.ffi end
	return nil
end

-- A player for `wav` at `volume`, or nil and why not. player.play() plays it.
function M.new(wav, volume)
	local ffi = find_ffi()
	if not ffi then return nil, "no FFI" end
	if ffi.os ~= "Windows" then return nil, "not Windows" end
	-- Declared already by another mod is as good.
	pcall(ffi.cdef, "int PlaySoundA(const char *sound, void *module, unsigned int flags);")
	local ok, winmm = pcall(ffi.load, "winmm")
	if not ok then return nil, "no winmm" end
	local data = M.scaled(wav, volume)
	-- The bytes stay in a buffer of this player's for as long as it lives: Windows reads them while
	-- the sound plays.
	local buffer = ffi.new("char[?]", #data)
	ffi.copy(buffer, data, #data)
	local last = -math.huge
	local player = { buffer = buffer }
	function player.play(now)
		if now and now - last < M.GAP then return false end
		last = now or last
		return winmm.PlaySoundA(buffer, nil, M.FLAGS) ~= 0
	end
	return player
end

return M

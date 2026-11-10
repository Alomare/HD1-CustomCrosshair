-- A small JSON reader for the tests: obsidian.json into Lua tables. Objects and arrays become tables,
-- null becomes nil.
local M = {}

local function fail(s, i, what)
	error(string.format("json: %s at %d near %q", what, i, s:sub(i, i + 20)), 0)
end

local function skip(s, i)
	local _, e = s:find("^[ \t\r\n]*", i)
	return e + 1
end

local value

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8(code)
	if code < 0x80 then return string.char(code) end
	if code < 0x800 then return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64) end
	return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

local function str(s, i)
	local out, j = {}, i + 1
	while true do
		local c = s:sub(j, j)
		if c == "" then fail(s, i, "unclosed string") end
		if c == '"' then return table.concat(out), j + 1 end
		if c == "\\" then
			local e = s:sub(j + 1, j + 1)
			if e == "u" then
				out[#out + 1] = utf8(tonumber(s:sub(j + 2, j + 5), 16))
				j = j + 6
			else
				out[#out + 1] = ESCAPES[e] or fail(s, j, "bad escape")
				j = j + 2
			end
		else
			out[#out + 1] = c
			j = j + 1
		end
	end
end

value = function(s, i)
	i = skip(s, i)
	local c = s:sub(i, i)
	if c == "{" then
		local t = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "}" then return t, i + 1 end
		while true do
			i = skip(s, i)
			if s:sub(i, i) ~= '"' then fail(s, i, "expected a key") end
			local k
			k, i = str(s, i)
			i = skip(s, i)
			if s:sub(i, i) ~= ":" then fail(s, i, "expected :") end
			t[k], i = value(s, i + 1)
			i = skip(s, i)
			local d = s:sub(i, i)
			if d == "}" then return t, i + 1 end
			if d ~= "," then fail(s, i, "expected , or }") end
			i = i + 1
		end
	elseif c == "[" then
		local t = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "]" then return t, i + 1 end
		while true do
			t[#t + 1], i = value(s, i)
			i = skip(s, i)
			local d = s:sub(i, i)
			if d == "]" then return t, i + 1 end
			if d ~= "," then fail(s, i, "expected , or ]") end
			i = i + 1
		end
	elseif c == '"' then
		return str(s, i)
	elseif s:find("^true", i) then
		return true, i + 4
	elseif s:find("^false", i) then
		return false, i + 5
	elseif s:find("^null", i) then
		return nil, i + 4
	end
	local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
	if num and num ~= "" then return tonumber(num), i + #num end
	fail(s, i, "unexpected character")
end

function M.decode(s)
	local v, i = value(s, 1)
	i = skip(s, i)
	if i <= #s then fail(s, i, "text after the value") end
	return v
end

function M.read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return M.decode(s)
end

return M

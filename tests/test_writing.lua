-- The writing rules: no contraction or possessive of "it" in any file, and in the words players read
-- (obsidian.json, README.md, the preview captions) no first person, no possessives and no dashes as
-- punctuation.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local json = dofile("tests/json.lua")

local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- Spelled in pieces, so this file passes the same check.
local IT_WORDS = { "%f[%a]i" .. "ts%f[%A]", "%f[%a]it'" .. "s%f[%A]" }
local FIRST_PERSON = { "i", "me", "my", "mine", "we", "us", "our", "ours" }

local function check_it(text, where)
	local lower = text:lower()
	for _, p in ipairs(IT_WORDS) do
		local at = lower:find(p)
		if at then error(where .. ": \"" .. text:sub(math.max(1, at - 30), at + 30) .. "\"", 2) end
	end
end

local function check_player(text, where)
	check_it(text, where)
	local lower = text:lower()
	for _, w in ipairs(FIRST_PERSON) do
		if lower:find("%f[%a]" .. w .. "%f[%A]") then error(where .. ": first person \"" .. w .. "\" in: " .. text, 2) end
	end
	if text:find("%a'" .. "s%f[%A]") then error(where .. ": possessive in: " .. text, 2) end
	if text:find("\226\128\148", 1, true) or text:find("\226\128\147", 1, true) then error(where .. ": dash in: " .. text, 2) end
	if text:find("[^%s] %- ") then error(where .. ": dash in: " .. text, 2) end
end

local FILES = { "obsidian.json", "README.md", "main.lua", "src/shapes.lua", "src/hitmarker.lua", "tools/build_previews.lua",
	"tests/run.lua", "tests/json.lua", "tests/svg.lua", "tests/test_shapes.lua", "tests/test_preview.lua",
	"tests/test_manifest.lua", "tests/test_main.lua", "tests/test_hitmarker.lua", "tests/test_writing.lua",
	"preview/idle.svg", "preview/aim.svg", "preview/hitmarker.svg" }

test("no_file_says_it_is_or_belonging_to_it", function()
	for _, path in ipairs(FILES) do
		local n = 0
		for line in read(path):gmatch("[^\n]+") do
			n = n + 1
			check_it(line, path .. ":" .. n)
		end
	end
end)

test("manifest_text_keeps_the_rules", function()
	local count = 0
	local function walk(v, where)
		if type(v) == "table" then
			for k, x in pairs(v) do
				if k == "en" and type(x) == "string" then
					check_player(x, where)
					count = count + 1
				else
					walk(x, where .. "." .. tostring(k))
				end
			end
		end
	end
	walk(json.read("obsidian.json"), "obsidian.json")
	eq(count > 50, true, "texts checked: " .. count)
end)

test("readme_keeps_the_rules", function()
	local text = read("README.md"):gsub("```.-```", ""):gsub("`[^`]*`", "")
	for line in text:gmatch("[^\n]+") do check_player(line, "README.md") end
end)

test("preview_captions_keep_the_rules", function()
	for _, path in ipairs({ "preview/idle.svg", "preview/aim.svg", "preview/hitmarker.svg" }) do
		for caption in read(path):gmatch(">([^<{]+)<") do
			if caption:find("%a") then check_player(caption, path) end
		end
	end
end)

return T

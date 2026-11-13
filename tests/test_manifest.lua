-- obsidian.json: the options main.lua reads, with the defaults src/shapes.lua falls back to, in the
-- groups and with the previews Obsidian shows.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local json = dofile("tests/json.lua")
local shapes = dofile("src/shapes.lua")
local hitmarker = dofile("src/hitmarker.lua")

local function manifest() return json.read("obsidian.json") end

local function by_id(m)
	local out = {}
	for _, o in ipairs(m.options) do out[o.id] = o end
	return out
end

local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() end
	return f ~= nil
end

test("identity_and_files", function()
	local m = manifest()
	eq(m.id, "alomare.customcrosshair", "id")
	eq(m.version, "0.4.0", "version")
	eq(m.scope, "client", "scope")
	eq(m.entry, "main.lua", "entry")
	eq(m.authors[1], "Alomare", "author")
	eq(m.source, "https://github.com/Alomare/HD1-CustomCrosshair", "source")
	eq(exists(m.entry), true, "entry exists")
	for _, path in ipairs(m.modules) do eq(exists(path), true, path) end
	eq(#m.modules, 2, "shapes and hitmarker")
	-- The hitmarker hears hits through Obsidian API; nothing else is needed.
	eq(#m.requires, 1, "one other mod")
	eq(m.requires[1], "obsidian.api", "Obsidian API")
end)

test("main_lua_has_the_manifest_version", function()
	local f = assert(io.open("main.lua", "rb"))
	local text = f:read("*a")
	f:close()
	eq(text:match('local VERSION = "([^"]+)"'), manifest().version, "VERSION in main.lua")
end)

test("every_hitmarker_setting_is_an_option_with_the_module_default", function()
	local options = by_id(manifest())
	local count = 0
	for _, key in ipairs(hitmarker.KEYS) do
		local id = hitmarker.IDS[key]
		local o = options[id]
		assert(o, id .. " is declared")
		eq(o.default, hitmarker.DEFAULTS[key], id .. " default")
		eq(o.group, "hitmarker", id .. " group")
		if id ~= "hitmarker" then eq(o.visible_when and o.visible_when.hitmarker, true, id .. " shows while the hitmarker is on") end
		count = count + 1
	end
	local grouped = 0
	for _, o in pairs(options) do
		if o.group == "hitmarker" then grouped = grouped + 1 end
	end
	eq(grouped, count, "no other options in the group")
	local from = options.hitmarker_from.choices
	eq(#from, #hitmarker.FROM, "hits from: choices")
	for i, c in ipairs(from) do eq(c.id, hitmarker.FROM[i], "hits from: choice " .. i) end
	eq(options.hitmarker_color.visible_when.hitmarker_hits, true, "hit color with hits on")
	eq(options.hitmarker_kill_color.visible_when.hitmarker_kills, true, "kill color with kills on")
end)

test("new_shadow_settings_keep_the_old_look_by_default", function()
	local options = by_id(manifest())
	for _, prefix in ipairs({ "idle", "aim" }) do
		eq(options[prefix .. "_shadow_size"].default, 1, prefix .. " size")
		eq(options[prefix .. "_shadow_spread"].default, 0, prefix .. " spread")
		eq(options[prefix .. "_shadow_blur"].default, 0, prefix .. " blur")
		eq(options[prefix .. "_shadow_blur"].max, shapes.MAX_BLUR, prefix .. " blur rings")
		eq(options[prefix .. "_shadow_blur"].step, 1, prefix .. " whole pixels of blur")
		for _, key in ipairs({ "size", "spread", "blur" }) do
			eq(options[prefix .. "_shadow_" .. key].visible_when[prefix .. "_shadow"], true, prefix .. " " .. key .. " with the shadow on")
		end
	end
end)

test("every_state_setting_is_an_option_with_the_shapes_default", function()
	local options = by_id(manifest())
	for _, prefix in ipairs({ "idle", "aim" }) do
		for _, key in ipairs(shapes.KEYS) do
			local id = prefix .. "_" .. key
			local o = options[id]
			assert(o, id .. " is declared")
			eq(o.default, shapes.DEFAULTS[prefix][key], id .. " default")
			eq(o.group, prefix, id .. " group")
		end
	end
end)

test("shape_choices_are_the_shapes_in_order", function()
	local options = by_id(manifest())
	for _, id in ipairs({ "idle_shape", "aim_shape" }) do
		local choices = options[id].choices
		eq(#choices, #shapes.SHAPES, id .. " count")
		for i, c in ipairs(choices) do eq(c.id, shapes.SHAPES[i], id .. " choice " .. i) end
	end
end)

test("groups_previews_and_conditions_point_at_real_things", function()
	local m = manifest()
	local groups = {}
	for _, g in ipairs(m.option_groups) do groups[g.id] = true end
	eq(m.option_groups[1].id, "general", "general first")
	eq(m.option_groups[2].id, "idle", "idle second")
	eq(m.option_groups[3].id, "aim", "aiming third")
	eq(m.option_groups[4].id, "hitmarker", "hitmarker last")
	local options = by_id(m)
	for _, o in ipairs(m.options) do
		eq(groups[o.group], true, o.id .. " group")
		eq(o.id:match("^[a-z0-9_]+$") ~= nil, true, o.id .. " id")
		eq(type(o.label) == "table" and type(o.label.en) == "string", true, o.id .. " label")
		if o.type == "number" then
			eq(o.default >= o.min and o.default <= o.max, true, o.id .. " default in range")
		end
		for other, value in pairs(o.visible_when or {}) do
			eq(options[other] ~= nil and options[other].type == "toggle", true, o.id .. " visible_when " .. other)
			eq(type(value), "boolean", o.id .. " visible_when value")
		end
	end
	eq(#m.option_previews, 3, "previews")
	for _, p in ipairs(m.option_previews) do
		eq(groups[p.group], true, p.id .. " group")
		eq(exists(p.template), true, p.template)
		eq(p.width, 240, p.id .. " width")
		eq(p.height, 140, p.id .. " height")
	end
	eq(options.enabled.type, "toggle", "on and off")
	eq(options.third_person.type, "toggle", "third person")
end)

test("arms_inside_a_circle_stay_longer_than_the_line", function()
	-- Circle with cross: the arms are ARM minus the thickness long.
	local options = by_id(manifest())
	for _, prefix in ipairs({ "idle", "aim" }) do
		eq(options[prefix .. "_thickness"].max < shapes.ARM, true, prefix .. " thickest line")
	end
end)

return T

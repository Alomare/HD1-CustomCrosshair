-- obsidian.json: the options main.lua reads, with the defaults src/shapes.lua falls back to, in the
-- groups and with the previews Obsidian shows.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local json = dofile("tests/json.lua")
local shapes = dofile("src/shapes.lua")

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
	eq(m.version, "0.1.1", "version")
	eq(m.scope, "client", "scope")
	eq(m.entry, "main.lua", "entry")
	eq(m.authors[1], "Alomare", "author")
	eq(m.source, "https://github.com/Alomare/HD1-CustomCrosshair", "source")
	eq(exists(m.entry), true, "entry exists")
	for _, path in ipairs(m.modules) do eq(exists(path), true, path) end
	eq(m.requires, nil, "needs no other mod")
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
	eq(#m.option_previews, 2, "previews")
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

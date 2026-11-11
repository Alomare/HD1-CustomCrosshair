-- preview/*.svg: filled in as Obsidian fills them, they show the same pixels src/shapes.lua and
-- src/hitmarker.lua draw in the game, in the same colors, for every shape and a spread of settings.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local shapes = dofile("src/shapes.lua")
local hitmarker = dofile("src/hitmarker.lua")
local svg = dofile("tests/svg.lua")
local json = dofile("tests/json.lua")
local builder = dofile("tools/build_previews.lua")

local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local STATES = { "idle", "aim" }

local VARIANTS = {
	{ thickness = 1, gap = 4, scale = 1, outline = true, outline_thickness = 1, shadow = false },
	{ thickness = 2, gap = 0, scale = 1.5, outline = true, outline_thickness = 2, shadow = true, shadow_offset = 2,
		shadow_size = 1.25, shadow_spread = 1, shadow_blur = 2 },
	{ thickness = 3, gap = 7, scale = 0.5, outline = false, shadow = true, shadow_offset = 1.5, shadow_size = 0.5, shadow_blur = 1 },
	{ thickness = 1.5, gap = 3, scale = 2.3, outline = true, outline_thickness = 1.5, shadow = true, shadow_offset = 3,
		shadow_size = 1.05, shadow_spread = 0.5, shadow_blur = 3 },
	{ thickness = 6, gap = 0, scale = 1, outline = true, outline_thickness = 4, shadow = false },
	-- Serifs of brackets round to nothing here and come back as a pixel, in the game and the preview.
	{ thickness = 1, gap = 2, scale = 0.6, outline = false, shadow = false },
	{ thickness = 1, gap = 5, scale = 0.7, outline = true, outline_thickness = 1, shadow = true, shadow_offset = 1 },
	{ thickness = 2, gap = 24, scale = 4, outline = true, outline_thickness = 1, shadow = true, shadow_offset = 6,
		color = "#ff2040", opacity = 0.35, outline_color = "#203040", shadow_color = "#00ff00", shadow_opacity = 0.8,
		shadow_size = 2, shadow_spread = 6, shadow_blur = 3 },
	{ thickness = 2.5, gap = 1, scale = 1.1, outline = false, shadow = true, shadow_offset = 1, shadow_size = 0.75,
		shadow_spread = 2.5, shadow_blur = 2, shadow_opacity = 0.1, opacity = 0.1 },
}

-- Option values for one state, from the defaults and a variant.
local function values_for(prefix, shape, variant)
	local s = {}
	for k, v in pairs(shapes.DEFAULTS[prefix]) do s[k] = v end
	for k, v in pairs(variant) do s[k] = v end
	s.shape = shape
	local values = {}
	for k, v in pairs(s) do values[prefix .. "_" .. k] = v end
	return values, s
end

-- Every option at the default of obsidian.json, then `over`.
local function all_values(over)
	local values = {}
	for _, o in ipairs(json.read("obsidian.json").options) do values[o.id] = o.default end
	for k, v in pairs(over or {}) do values[k] = v end
	return values
end

local function num(v) return tonumber(v) or error("not a number: " .. tostring(v)) end

local TOLERANCE = 1e-4

-- Two lists of number lists, the same within TOLERANCE.
local function same_lists(got, want, what)
	eq(#got, #want, what .. " count")
	for i = 1, #want do
		eq(#got[i], #want[i], what .. " " .. i .. " length")
		for j = 1, #want[i] do near(got[i][j], want[i][j], what .. " " .. i .. "." .. j, TOLERANCE) end
	end
end

-- What a layer of shapes.lua draws: rects as sorted text, circles as { kind, numbers } in order of
-- kind, polygons as point lists in order.
local function expected(items)
	local rects, circles, polys, seen = {}, {}, {}, {}
	for _, it in ipairs(items) do
		if it.kind == "rect" then
			rects[#rects + 1] = string.format("%d,%d,%d,%d", it.x, it.y, it.w, it.h)
		elseif it.of then
			if not seen[it.of] then
				seen[it.of] = true
				local o = it.of
				if o.kind == "ring" then
					circles[#circles + 1] = { "ring", o.cx, o.cy, o.r_in, o.r_out }
				else
					circles[#circles + 1] = { "disc", o.cx, o.cy, o.r }
				end
			end
		else
			polys[#polys + 1] = it.pts
		end
	end
	table.sort(rects)
	table.sort(circles, function(a, b) return a[1] > b[1] end)
	return table.concat(rects, " "), circles, polys
end

-- The same read back from a filled-in layer of the SVG, turned to game coordinates (y up, the aim pixel
-- from 0 to 1).
local function drawn(group)
	local rects, circles, polys = {}, {}, {}
	local found = svg.find_all(group, function(n) return n.tag == "rect" or n.tag == "circle" or n.tag == "polygon" end)
	for _, el in ipairs(found) do
		local a = el.attrs
		if el.tag == "rect" then
			local x, y, w, h = num(a.x), num(a.y), num(a.width), num(a.height)
			rects[#rects + 1] = string.format("%d,%d,%d,%d", x, 1 - y - h, w, h)
		elseif el.tag == "circle" then
			local cx, cy, r = num(a.cx), 1 - num(a.cy), num(a.r)
			if a.fill == "none" then
				local sw = num(a["stroke-width"])
				local r_in, r_out = r - sw / 2, r + sw / 2
				if r_in <= 1e-9 then
					circles[#circles + 1] = { "disc", cx, cy, r_out }
				else
					circles[#circles + 1] = { "ring", cx, cy, r_in, r_out }
				end
			else
				circles[#circles + 1] = { "disc", cx, cy, r }
			end
		else
			local p = {}
			for x, y in a.points:gmatch("([-%d.e]+),([-%d.e]+)") do
				p[#p + 1] = num(x)
				p[#p + 1] = 1 - num(y)
			end
			polys[#polys + 1] = p
		end
	end
	table.sort(rects)
	table.sort(circles, function(a, b) return a[1] > b[1] end)
	return table.concat(rects, " "), circles, polys
end

local function compare_layer(g, items, what)
	local er, ec, ep = expected(items)
	local dr, dc, dp = drawn(g)
	eq(dr, er, what .. " rects")
	eq(#dc, #ec, what .. " circles")
	for i = 1, #ec do
		eq(dc[i][1], ec[i][1], what .. " circle kind")
		for j = 2, #ec[i] do near(dc[i][j], ec[i][j], what .. " " .. ec[i][1] .. " " .. j, TOLERANCE) end
	end
	same_lists(dp, ep, what .. " polygons")
end

local function by_role(node)
	local out = {}
	for _, g in ipairs(svg.find_all(node, function(n) return n.tag == "g" and n.attrs["data-role"] end)) do
		out[g.attrs["data-role"]] = g
	end
	return out
end

local function hex(color) return string.format("#%02x%02x%02x", color[1], color[2], color[3]) end

-- The blur copies of a filled-in blur group: { dx, dy, alpha from 0 to 255 } in game coordinates,
-- sorted. Each ring group gives the opacity; each copy points at the shadow.
local function copies_drawn(g, prefix, what)
	local out = {}
	for _, ring in ipairs(svg.find_all(g, function(n) return n.tag == "g" and n.attrs["data-ring"] end)) do
		eq(ring.attrs["stroke-opacity"], ring.attrs["fill-opacity"], what .. " ring stroke opacity")
		local alpha = num(ring.attrs["fill-opacity"]) * 255
		for _, use in ipairs(svg.find_all(ring, function(n) return n.tag == "use" end)) do
			eq(use.attrs.href, "#" .. prefix .. "_shadow_shape", what .. " copy of the shadow")
			local dx, dy = use.attrs.transform:match("^translate%(([-%d.]+) ([-%d.]+)%)$")
			out[#out + 1] = { num(dx), 0 - num(dy), alpha }
		end
	end
	return out
end

local function copies_expected(layers, s)
	local out = {}
	for _, l in ipairs(layers) do
		if l.role == "blur" then out[#out + 1] = { l.dx, l.dy, shapes.color_of(s, "blur", l.weight)[4] } end
	end
	return out
end

local function sort_copies(list)
	table.sort(list, function(a, b)
		if a[1] ~= b[1] then return a[1] < b[1] end
		if a[2] ~= b[2] then return a[2] < b[2] end
		return a[3] < b[3]
	end)
	return list
end

test("the_files_match_the_builder", function()
	for name, path in pairs(builder.FILES) do
		eq(read(path) == builder.template(name), true, path .. " is what tools/build_previews.lua writes (run it again)")
	end
end)

test("templates_are_valid_xml_within_the_limits", function()
	for name, path in pairs(builder.FILES) do
		local text = read(path)
		eq(#text <= 64 * 1024, true, path .. " size " .. #text)
		eq(text:find("&", 1, true), nil, path .. " has no &")
		local root = svg.parse(text)
		eq(root.children[1].tag, "svg", name .. " root")
		eq(text:find("<script", 1, true) == nil and text:find("foreignObject", 1, true) == nil, true, "nothing the sanitizer removes")
		eq(text:find('href="http', 1, true), nil, "no outside links")
		-- Every expression and condition, kept or not, within the limits of the Launcher.
		local values = all_values()
		local count = 0
		for expr in text:gmatch("{{(.-)}}") do
			eq(#expr <= svg.MAX_EXPR, true, path .. " expression of " .. #expr .. " characters")
			local ok, err = pcall(svg.eval, expr, values)
			eq(ok, true, path .. ": " .. tostring(err))
			count = count + 1
		end
		for cond in text:gmatch('data%-if="([^"]*)"') do
			local ok, err = pcall(svg.eval, cond, values)
			eq(ok, true, path .. ": " .. tostring(err))
			count = count + 1
		end
		eq(count > 100, true, path .. " expressions read: " .. count)
	end
end)

test("previews_draw_what_the_game_draws", function()
	local checked, copies = 0, 0
	for _, prefix in ipairs(STATES) do
		local tree = svg.parse(read(builder.FILES[prefix]))
		for _, shape in ipairs(shapes.SHAPES) do
			for vi, variant in ipairs(VARIANTS) do
				local values, s = values_for(prefix, shape, variant)
				local out = svg.render(tree, values)
				local what = prefix .. " " .. shape .. " variant " .. vi
				local group = svg.find_all(out, function(n) return n.attrs.id == prefix .. "_crosshair" end)[1]
				if not shapes.drawn(shape) then
					eq(group, nil, what .. ": nothing drawn")
					local texts = svg.find_all(out, function(n) return n.tag == "text" end)
					eq(#texts, 1, what .. ": one caption")
					eq(svg.text_of(texts[1]), shape == "game" and "Game cursor" or "No crosshair", what .. " caption")
				else
					assert(group, what .. ": crosshair group")
					local roles = by_role(group)
					local layers = shapes.layers(s)
					local want_roles, count = {}, 0
					for _, l in ipairs(layers) do want_roles[l.role] = true end
					for role in pairs(roles) do
						eq(want_roles[role], true, what .. ": layer " .. role .. " in the game")
						count = count + 1
					end
					for role in pairs(want_roles) do eq(roles[role] ~= nil, true, what .. ": layer " .. role .. " in the preview") end
					for _, l in ipairs(layers) do
						local g = roles[l.role]
						local color = shapes.color_of(s, l.role, l.weight)
						eq(g.attrs.fill, hex(color), what .. " " .. l.role .. " color")
						if l.role ~= "blur" then
							compare_layer(g, l.items, what .. " " .. l.role)
							near(num(g.attrs["fill-opacity"]) * 255, color[4], what .. " " .. l.role .. " opacity", 0.51)
							eq(g.attrs["stroke-opacity"], g.attrs["fill-opacity"], what .. " " .. l.role .. " ring opacity")
							for _, el in ipairs(svg.find_all(g, function(x) return x.tag == "circle" end)) do
								if el.attrs.stroke then eq(el.attrs.stroke, g.attrs.fill, what .. " ring color") end
							end
							checked = checked + 1
						end
					end
					if roles.blur then
						local got = sort_copies(copies_drawn(roles.blur, prefix, what))
						local want = sort_copies(copies_expected(layers, s))
						eq(#got, #want, what .. " blur copies")
						for i = 1, #want do
							eq(got[i][1] .. "," .. got[i][2], want[i][1] .. "," .. want[i][2], what .. " blur copy " .. i)
							near(got[i][3], want[i][3], what .. " blur copy " .. i .. " opacity", 0.51)
						end
						copies = copies + #want
					end
					local use = svg.find_all(out, function(n) return n.tag == "use" and n.attrs.href == "#" .. prefix .. "_crosshair" end)[1]
					assert(use, what .. ": magnified copy")
					local zoom = num(use.attrs.transform:match("scale%(([%d.]+)%)"))
					eq(zoom >= 1 and zoom <= 4 and zoom == math.floor(zoom), true, what .. " zoom " .. zoom)
				end
			end
		end
	end
	eq(checked > 100, true, "layers checked: " .. checked)
	eq(copies > 100, true, "blur copies checked: " .. copies)
end)

-- The shadow rects as 0.1 worked them out: round(c + k * (sum - grow + shift)), no size, no spread.
local function rects_0_1(shape, thickness, gap, k, c, grow, shift)
	local sizes = { H = thickness / 2, G = gap, T = thickness, ["1"] = 1 }
	local function total(list)
		local s = 0
		for _, t in ipairs(list) do s = s + t[1] * sizes[t[2]] end
		return s
	end
	local out = {}
	for _, r in ipairs(shapes.RECTS) do
		local listed = false
		for _, s in ipairs(r.shapes) do listed = listed or s == shape end
		if listed then
			local l = shapes.round(c + k * (total(r.x0) - grow + shift))
			local rr = shapes.round(c + k * (total(r.x1) + grow + shift))
			local b = shapes.round(c + k * (total(r.y0) - grow - shift))
			local t = shapes.round(c + k * (total(r.y1) + grow - shift))
			if rr <= l then rr = l + 1 end
			if t <= b then t = b + 1 end
			out[#out + 1] = { kind = "rect", x = l, y = b, w = rr - l, h = t - b }
		end
	end
	return out
end

test("default_shadow_settings_draw_what_0_1_drew", function()
	-- Size 1, spread 0 and blur 0 leave the shadow of every shape as it was: the same rects to the
	-- pixel, the same circles, no copies.
	local checked = 0
	for _, prefix in ipairs(STATES) do
		for _, shape in ipairs(shapes.SHAPES) do
			for _, variant in ipairs(VARIANTS) do
				local _, s = values_for(prefix, shape, variant)
				s.shadow, s.shadow_size, s.shadow_spread, s.shadow_blur = true, 1, 0, 0
				local layers = shapes.layers(s)
				for _, l in ipairs(layers) do eq(l.role ~= "blur", true, shape .. " no blur") end
				if shapes.drawn(shape) then
					local k = s.scale
					local edge = s.outline and s.outline_thickness or 0
					local c = shapes.centre(s.thickness * k)
					local got, circles = expected(layers[1].items)
					eq(got, (expected(rects_0_1(shape, s.thickness, s.gap, k, c, edge, s.shadow_offset))), shape .. " shadow rects")
					local parts = shapes.parts(shape, shapes.ARM * k, s.gap * k, s.thickness * k)
					local _, old_circles = expected(shapes.items(parts, edge * k, s.shadow_offset * k, c))
					eq(#circles, #old_circles, shape .. " shadow circles")
					for i = 1, #old_circles do
						for j = 2, #old_circles[i] do eq(circles[i][j], old_circles[i][j], shape .. " shadow circle " .. j) end
					end
					checked = checked + 1
				end
			end
		end
	end
	eq(checked > 100, true, "shapes checked: " .. checked)
end)

test("the_magnified_copy_stays_on_the_right_half", function()
	for _, prefix in ipairs(STATES) do
		local tree = svg.parse(builder.build(prefix))
		for _, variant in ipairs(VARIANTS) do
			local values, s = values_for(prefix, "brackets", variant)
			local out = svg.render(tree, values)
			local use = svg.find_all(out, function(n) return n.tag == "use" and n.attrs.href == "#" .. prefix .. "_crosshair" end)[1]
			local zoom = num(use.attrs.transform:match("scale%(([%d.]+)%)"))
			local reach = 0
			for _, l in ipairs(shapes.layers(s)) do
				for _, it in ipairs(l.items) do
					if it.kind == "rect" then
						reach = math.max(reach, math.abs(it.x), math.abs(it.x + it.w), math.abs(it.y), math.abs(it.y + it.h))
					end
				end
			end
			eq(reach * zoom <= 60 or zoom == 1, true, prefix .. " zoom " .. zoom .. " reach " .. reach)
		end
	end
end)

local MARKERS = {
	{},
	{ hitmarker_size = 20, hitmarker_gap = 30, hitmarker_thickness = 6, aim_thickness = 1 },
	{ hitmarker_size = 2, hitmarker_gap = 0, hitmarker_thickness = 1, hitmarker_outline = false, aim_thickness = 3, aim_scale = 1.5 },
	{ hitmarker_size = 9, hitmarker_gap = 4, hitmarker_thickness = 2.5, hitmarker_color = "#00ffcc", hitmarker_kill_color = "#3050ff" },
	{ hitmarker_hits = false },
	{ hitmarker_kills = false, hitmarker_size = 14 },
	{ hitmarker = false },
}

test("hitmarker_preview_draws_what_the_game_draws", function()
	local tree = svg.parse(read(builder.FILES.hitmarker))
	local checked = 0
	for vi, over in ipairs(MARKERS) do
		local values = all_values(over)
		local s = hitmarker.settings(function(id) return values[id] end)
		local c = shapes.centre(values.aim_thickness * values.aim_scale)
		local out = svg.render(tree, values)
		local what = "hitmarker variant " .. vi
		local texts = {}
		for _, t in ipairs(svg.find_all(out, function(n) return n.tag == "text" end)) do texts[#texts + 1] = svg.text_of(t) end
		local captions = table.concat(texts, " | ")
		local roles = by_role(out)
		if not s.on then
			eq(next(roles), nil, what .. ": no marks")
			eq(captions, "No hitmarker", what .. " caption")
		else
			for _, kind in ipairs({ "hit", "kill" }) do
				local wanted = s.kills
				if kind == "hit" then wanted = s.hits end
				local g = roles[kind]
				eq(g ~= nil, wanted, what .. " " .. kind .. " shown")
				eq(captions:find(kind == "hit" and "Hits off" or "Kills off", 1, true) == nil, wanted, what .. " " .. kind .. " caption")
				if g then
					local zoom = num(g.attrs.transform:match("scale%(([%d.]+)%)"))
					eq(zoom >= 1 and zoom <= 4 and zoom == math.floor(zoom), true, what .. " zoom " .. zoom)
					local layers = hitmarker.layers(s, kind, c)
					local found = svg.find_all(g, function(n) return n.tag == "g" and n.attrs["data-layer"] end)
					eq(#found, #layers, what .. " " .. kind .. " layers")
					local reach = 0
					for i, l in ipairs(layers) do
						local lg = found[i]
						eq(lg.attrs["data-layer"], l.role, what .. " " .. kind .. " layer order")
						eq(lg.attrs.fill, l.hex, what .. " " .. kind .. " " .. l.role .. " color")
						local _, _, polys = drawn(lg)
						local want = {}
						for _, it in ipairs(l.items) do
							want[#want + 1] = it.pts
							for j = 1, #it.pts do reach = math.max(reach, math.abs(it.pts[j] - c)) end
						end
						same_lists(polys, want, what .. " " .. kind .. " " .. l.role)
						checked = checked + 1
					end
					eq(reach * zoom <= 58 or zoom == 1, true, what .. " fits half the picture at zoom " .. zoom)
				end
			end
		end
	end
	eq(checked >= 15, true, "layers checked: " .. checked)
end)

test("the_expression_reader_keeps_to_the_language", function()
	eq(svg.eval("1+2*3", {}), 7, "precedence")
	eq(svg.eval("a=='x'?2:3", { a = "x" }), 2, "ternary")
	eq(svg.eval("clamp(9,1,4)", {}), 4, "clamp")
	eq(svg.eval("round(2.5)", {}), 3, "round")
	eq(svg.eval("!b||c", { b = true, c = 0 }), 0, "or")
	eq(pcall(svg.eval, "-1", {}), false, "no unary minus")
	eq(pcall(svg.eval, "missing+1", {}), false, "unknown id")
	eq(pcall(svg.parse, '<svg a="1 &amp;&amp; 2"/>'), false, "an & in an attribute is refused")
	eq(pcall(svg.eval, "1" .. string.rep("+1", 200), {}), false, "longer than 400 characters")
	eq(pcall(svg.eval, string.rep("(", 20) .. "1" .. string.rep(")", 20), {}), false, "deeper than 40")
	eq(svg.eval(string.rep("(", 19) .. "1" .. string.rep(")", 19), {}), 1, "40 deep")
end)

return T

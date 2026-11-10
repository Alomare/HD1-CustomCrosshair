-- preview/*.svg: filled in as Obsidian fills them, they show the same pixels src/shapes.lua draws in
-- the game, in the same colors, for every shape and a spread of settings.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local shapes = dofile("src/shapes.lua")
local svg = dofile("tests/svg.lua")
local builder = dofile("tools/build_previews.lua")

local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local VARIANTS = {
	{ thickness = 1, gap = 4, scale = 1, outline = true, outline_thickness = 1, shadow = false },
	{ thickness = 2, gap = 0, scale = 1.5, outline = true, outline_thickness = 2, shadow = true, shadow_offset = 2 },
	{ thickness = 3, gap = 7, scale = 0.5, outline = false, shadow = true, shadow_offset = 1.5 },
	{ thickness = 1.5, gap = 3, scale = 2.3, outline = true, outline_thickness = 1.5, shadow = true, shadow_offset = 3 },
	{ thickness = 6, gap = 0, scale = 1, outline = true, outline_thickness = 4, shadow = false },
	-- Serifs of brackets round to nothing here and come back as a pixel, in the game and the preview.
	{ thickness = 1, gap = 2, scale = 0.6, outline = false, shadow = false },
	{ thickness = 1, gap = 5, scale = 0.7, outline = true, outline_thickness = 1, shadow = true, shadow_offset = 1 },
	{ thickness = 2, gap = 24, scale = 4, outline = true, outline_thickness = 1, shadow = true, shadow_offset = 6,
		color = "#ff2040", opacity = 0.35, outline_color = "#203040", shadow_color = "#00ff00", shadow_opacity = 0.8 },
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

local function num(v) return tonumber(v) or error("not a number: " .. tostring(v)) end

local function key(n) return string.format("%.4f", n + 0) end

-- What shapes.lua draws in one layer, as sorted text: rects, circles, polygons.
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
					circles[#circles + 1] = "ring " .. key(o.cx) .. " " .. key(o.cy) .. " " .. key(o.r_in) .. " " .. key(o.r_out)
				else
					circles[#circles + 1] = "disc " .. key(o.cx) .. " " .. key(o.cy) .. " " .. key(o.r)
				end
			end
		else
			local p = {}
			for i = 1, #it.pts do p[i] = key(it.pts[i]) end
			polys[#polys + 1] = table.concat(p, ",")
		end
	end
	table.sort(rects)
	table.sort(circles)
	return table.concat(rects, " "), table.concat(circles, " | "), table.concat(polys, " | ")
end

-- The same read back from a filled-in layer of the SVG, turned to game coordinates (y up, the aim pixel
-- from 0 to 1).
local function drawn(group)
	local rects, circles, polys = {}, {}, {}
	local shapes_drawn = svg.find_all(group, function(n) return n.tag == "rect" or n.tag == "circle" or n.tag == "polygon" end)
	for _, el in ipairs(shapes_drawn) do
		do
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
						circles[#circles + 1] = "disc " .. key(cx) .. " " .. key(cy) .. " " .. key(r_out)
					else
						circles[#circles + 1] = "ring " .. key(cx) .. " " .. key(cy) .. " " .. key(r_in) .. " " .. key(r_out)
					end
				else
					circles[#circles + 1] = "disc " .. key(cx) .. " " .. key(cy) .. " " .. key(r)
				end
			elseif el.tag == "polygon" then
				local p = {}
				for x, y in a.points:gmatch("([-%d.e]+),([-%d.e]+)") do
					p[#p + 1] = key(num(x))
					p[#p + 1] = key(1 - num(y))
				end
				polys[#polys + 1] = table.concat(p, ",")
			end
		end
	end
	table.sort(rects)
	table.sort(circles)
	return table.concat(rects, " "), table.concat(circles, " | "), table.concat(polys, " | ")
end

local function by_role(node)
	local out = {}
	for _, g in ipairs(svg.find_all(node, function(n) return n.tag == "g" and n.attrs["data-role"] end)) do
		out[g.attrs["data-role"]] = g
	end
	return out
end

test("the_files_match_the_builder", function()
	for prefix, path in pairs(builder.FILES) do
		eq(read(path) == builder.build(prefix), true, path .. " is what tools/build_previews.lua writes (run it again)")
	end
end)

test("templates_are_valid_xml_within_the_size_limit", function()
	for prefix, path in pairs(builder.FILES) do
		local text = read(path)
		eq(#text <= 64 * 1024, true, path .. " size " .. #text)
		eq(text:find("&", 1, true), nil, path .. " has no &")
		local root = svg.parse(text)
		eq(root.children[1].tag, "svg", prefix .. " root")
		eq(text:find("<script", 1, true) == nil and text:find("foreignObject", 1, true) == nil, true, "nothing the sanitizer removes")
		eq(text:find('href="http', 1, true), nil, "no outside links")
	end
end)

test("previews_draw_what_the_game_draws", function()
	local checked = 0
	for prefix, path in pairs(builder.FILES) do
		local tree = svg.parse(read(path))
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
					local count = 0
					for _ in pairs(roles) do count = count + 1 end
					eq(count, #layers, what .. ": layers")
					for _, l in ipairs(layers) do
						local g = roles[l.role]
						assert(g, what .. ": layer " .. l.role)
						local er, ec, ep = expected(l.items)
						local dr, dc, dp = drawn(g)
						eq(dr, er, what .. " " .. l.role .. " rects")
						eq(dc, ec, what .. " " .. l.role .. " circles")
						eq(dp, ep, what .. " " .. l.role .. " polygons")
						local color = shapes.color_of(s, l.role)
						eq(g.attrs.fill, string.format("#%02x%02x%02x", color[1], color[2], color[3]), what .. " " .. l.role .. " color")
						near(num(g.attrs["fill-opacity"]) * 255, color[4], what .. " " .. l.role .. " opacity", 0.51)
						for _, el in ipairs(svg.find_all(g, function(x) return x.tag == "circle" end)) do
							if el.attrs.stroke then
								eq(el.attrs.stroke, g.attrs.fill, what .. " ring color")
								eq(el.attrs["stroke-opacity"], g.attrs["fill-opacity"], what .. " ring opacity")
							end
						end
						checked = checked + 1
					end
					local use = svg.find_all(out, function(n) return n.tag == "use" end)[1]
					assert(use, what .. ": magnified copy")
					local zoom = num(use.attrs.transform:match("scale%(([%d.]+)%)"))
					eq(zoom >= 1 and zoom <= 4 and zoom == math.floor(zoom), true, what .. " zoom " .. zoom)
				end
			end
		end
	end
	eq(checked > 100, true, "layers checked: " .. checked)
end)

test("the_magnified_copy_stays_on_the_right_half", function()
	for prefix in pairs(builder.FILES) do
		local tree = svg.parse(builder.build(prefix))
		for _, variant in ipairs(VARIANTS) do
			local values, s = values_for(prefix, "brackets", variant)
			local out = svg.render(tree, values)
			local use = svg.find_all(out, function(n) return n.tag == "use" end)[1]
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

test("the_expression_reader_keeps_to_the_language", function()
	eq(svg.eval("1+2*3", {}), 7, "precedence")
	eq(svg.eval("a=='x'?2:3", { a = "x" }), 2, "ternary")
	eq(svg.eval("clamp(9,1,4)", {}), 4, "clamp")
	eq(svg.eval("round(2.5)", {}), 3, "round")
	eq(svg.eval("!b||c", { b = true, c = 0 }), 0, "or")
	eq(pcall(svg.eval, "-1", {}), false, "no unary minus")
	eq(pcall(svg.eval, "missing+1", {}), false, "unknown id")
	eq(pcall(svg.parse, '<svg a="1 &amp;&amp; 2"/>'), false, "an & in an attribute is refused")
end)

return T

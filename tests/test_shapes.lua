-- src/shapes.lua: the pixels each shape covers, outlines, shadows and colors.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local shapes = dofile("src/shapes.lua")

local function settings(over)
	local s = {}
	for k, v in pairs(shapes.DEFAULTS.aim) do s[k] = v end
	-- A plain look the tests below change one setting at a time: no outline, no shadow, and a shadow
	-- that is sharp at half strength once one is switched on.
	s.outline, s.shadow, s.opacity = false, false, 1
	s.shadow_opacity, s.shadow_offset, s.shadow_blur = 0.5, 2, 0
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function layer(layers, role)
	for _, l in ipairs(layers) do
		if l.role == role then return l end
	end
	return nil
end

local function rects(items)
	local out = {}
	for _, it in ipairs(items) do
		if it.kind == "rect" then out[#out + 1] = string.format("%d,%d,%d,%d", it.x, it.y, it.w, it.h) end
	end
	table.sort(out)
	return table.concat(out, " ")
end

local function rect_list(list)
	local out = {}
	for _, r in ipairs(list) do out[#out + 1] = table.concat(r, ",") end
	table.sort(out)
	return table.concat(out, " ")
end

-- The rects mirrored left to right (and top to bottom) about the centre c.
local function mirrored(items, c, axis)
	local out = {}
	for _, it in ipairs(items) do
		if it.kind == "rect" then
			if axis == "x" then
				out[#out + 1] = { 2 * c - it.x - it.w, it.y, it.w, it.h }
			else
				out[#out + 1] = { it.x, 2 * c - it.y - it.h, it.w, it.h }
			end
		end
	end
	return rect_list(out)
end

local function convex(pts)
	local n, sign = #pts / 2, 0
	for i = 1, n do
		local j, k = i % n + 1, (i + 1) % n + 1
		local ax, ay = pts[j * 2 - 1] - pts[i * 2 - 1], pts[j * 2] - pts[i * 2]
		local bx, by = pts[k * 2 - 1] - pts[j * 2 - 1], pts[k * 2] - pts[j * 2]
		local cross = ax * by - ay * bx
		if math.abs(cross) > 1e-9 then
			local s = cross > 0 and 1 or -1
			if sign ~= 0 and s ~= sign then return false end
			sign = s
		end
	end
	return true
end

test("an_even_cross_is_centred_on_the_pixel_corner", function()
	local fill = layer(shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4 })), "fill")
	eq(rects(fill.items), rect_list({ { 5, -1, 8, 2 }, { -13, -1, 8, 2 }, { -1, 5, 2, 8 }, { -1, -13, 2, 8 } }), "rects")
end)

test("an_odd_cross_is_centred_on_the_aim_pixel", function()
	local fill = layer(shapes.layers(settings({ shape = "cross", thickness = 1, gap = 4 })), "fill")
	-- Pixels 1 to 4 and -4 to -1 stay clear on each side of the aim pixel 0.
	eq(rects(fill.items), rect_list({ { 5, 0, 8, 1 }, { -12, 0, 8, 1 }, { 0, 5, 1, 8 }, { 0, -12, 1, 8 } }), "rects")
	local three = layer(shapes.layers(settings({ shape = "cross", thickness = 3, gap = 0 })), "fill")
	eq(rects(three.items), rect_list({ { 2, -1, 8, 3 }, { -9, -1, 8, 3 }, { -1, 2, 3, 8 }, { -1, -9, 3, 8 } }), "thick rects")
end)

test("whole_pixel_settings_give_matching_sides", function()
	for _, shape in ipairs({ "cross", "cross_dot", "circle_cross", "brackets", "t" }) do
		for _, th in ipairs({ 1, 2, 3, 4 }) do
			for _, gap in ipairs({ 0, 3, 4, 7 }) do
				for _, outline in ipairs({ false, true }) do
					local s = settings({ shape = shape, thickness = th, gap = gap, outline = outline, outline_thickness = 1 })
					local c = shapes.centre(th)
					for _, l in ipairs(shapes.layers(s)) do
						local what = shape .. " " .. th .. " " .. gap .. " " .. l.role
						eq(mirrored(l.items, c, "x"), rects(l.items), what .. " left and right")
						if shape ~= "t" then eq(mirrored(l.items, c, "y"), rects(l.items), what .. " up and down") end
					end
				end
			end
		end
	end
end)

test("t_has_no_top_arm", function()
	local fill = layer(shapes.layers(settings({ shape = "t", thickness = 2, gap = 4 })), "fill")
	eq(rects(fill.items), rect_list({ { 5, -1, 8, 2 }, { -13, -1, 8, 2 }, { -1, -13, 2, 8 } }), "rects")
end)

test("the_outline_grows_every_line_and_sits_behind", function()
	local layers = shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4, outline = true, outline_thickness = 1 }))
	eq(#layers, 2, "layers")
	eq(layers[1].role, "outline", "back")
	eq(layers[2].role, "fill", "front")
	eq(rects(layers[1].items), rect_list({ { 4, -2, 10, 4 }, { -14, -2, 10, 4 }, { -2, 4, 4, 10 }, { -2, -14, 4, 10 } }), "outline rects")
end)

test("the_shadow_moves_down_and_right_and_takes_the_outline_size", function()
	local layers = shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4, outline = true, outline_thickness = 1, shadow = true, shadow_offset = 2 }))
	eq(layers[1].role, "shadow", "first")
	eq(rects(layers[1].items), rect_list({ { 6, -4, 10, 4 }, { -12, -4, 10, 4 }, { 0, 2, 4, 10 }, { 0, -16, 4, 10 } }), "shadow rects")
	local plain = shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4, shadow = true, shadow_offset = 1 }))
	eq(#plain, 2, "shadow and lines without an outline")
	eq(rects(plain[1].items), rect_list({ { 6, -2, 8, 2 }, { -12, -2, 8, 2 }, { 0, 4, 2, 8 }, { 0, -14, 2, 8 } }), "shadow of the lines")
end)

test("spread_widens_the_shadow_on_every_side", function()
	local base = settings({ shape = "cross", thickness = 2, gap = 4, outline = true, outline_thickness = 1, shadow = true, shadow_offset = 2 })
	local wide = settings({ shape = "cross", thickness = 2, gap = 4, outline = true, outline_thickness = 1, shadow = true, shadow_offset = 2, shadow_spread = 2 })
	local grown = {}
	for _, it in ipairs(layer(shapes.layers(base), "shadow").items) do grown[#grown + 1] = { it.x - 2, it.y - 2, it.w + 4, it.h + 4 } end
	eq(rects(layer(shapes.layers(wide), "shadow").items), rect_list(grown), "two pixels past the outline size")
	eq(rects(layer(shapes.layers(wide), "outline").items), rects(layer(shapes.layers(base), "outline").items), "outline untouched")
end)

test("size_scales_the_shadow_round_the_centre_of_the_crosshair", function()
	local big = settings({ shape = "cross", thickness = 2, gap = 4, shadow = true, shadow_offset = 1, shadow_size = 2 })
	-- The crosshair at scale 2, moved down and to the right by the offset at scale 1.
	local twice = layer(shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4, scale = 2 })), "fill")
	local moved = {}
	for _, it in ipairs(twice.items) do moved[#moved + 1] = { it.x + 1, it.y - 1, it.w, it.h } end
	eq(rects(layer(shapes.layers(big), "shadow").items), rect_list(moved), "shadow at twice the size")
	eq(rects(layer(shapes.layers(big), "fill").items), rects(layer(shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4 })), "fill").items), "lines untouched")
	local ring = layer(shapes.layers(settings({ shape = "circle", thickness = 2, gap = 4, shadow = true, shadow_size = 0.5 })), "shadow")
	near(ring.items[1].of.r_out, (1 + 4 + 8) * 0.5, "a ring at half the radius")
	local dot = layer(shapes.layers(settings({ shape = "dot", thickness = 2, shadow = true, shadow_size = 1.5 })), "shadow")
	near(dot.items[1].of.r, 3, "a dot at one and a half times")
end)

test("blur_adds_rings_of_fainter_copies_of_the_shadow", function()
	local s = settings({ shape = "cross_dot", thickness = 2, gap = 4, shadow = true, shadow_offset = 2, shadow_blur = 2 })
	local layers = shapes.layers(s)
	local shadow = layer(layers, "shadow")
	local copies = {}
	for i, l in ipairs(layers) do
		if l.role == "blur" then
			copies[#copies + 1] = l
			eq(i < 17 + 1, true, "copies come first, behind everything")
		end
	end
	eq(#copies, 16, "two rings of eight")
	local weights = {}
	for _, l in ipairs(copies) do
		local r = math.max(math.abs(l.dx), math.abs(l.dy))
		eq(r == 1 or r == 2, true, "a pixel or two out")
		weights[r] = l.weight
		eq(#l.items, #shadow.items, "the whole shadow")
		for i, it in ipairs(l.items) do
			local base = shadow.items[i]
			if it.kind == "rect" then
				eq(it.x .. "," .. it.y .. "," .. it.w .. "," .. it.h, (base.x + l.dx) .. "," .. (base.y + l.dy) .. "," .. base.w .. "," .. base.h, "moved rect")
			else
				for j = 1, #it.pts, 2 do
					near(it.pts[j], base.pts[j] + l.dx, "moved x")
					near(it.pts[j + 1], base.pts[j + 1] + l.dy, "moved y")
				end
			end
		end
	end
	near(weights[1], 2 / 9, "inner ring")
	near(weights[2], 1 / 9, "outer ring, fainter")
	local c = shapes.color_of(s, "blur", weights[1])
	eq(c[4], shapes.round(0.5 * 2 / 9 * 255), "a share of the shadow opacity")
end)

test("blur_rings_follow_the_scale_and_stop_at_three", function()
	local copies = shapes.blur_copies(3, 2)
	eq(#copies, 24, "three rings")
	eq(copies[#copies].dx ~= 0 and math.abs(copies[#copies].dx), 6, "third ring six pixels out at scale 2")
	eq(#shapes.blur_copies(9, 1), 8 * shapes.MAX_BLUR, "no more than three rings")
	eq(#shapes.blur_copies(0, 1), 0, "none")
	eq(#shapes.blur_copies(1.5, 1), 8, "whole pixels only")
	local s = settings({ shape = "cross", shadow = false, shadow_blur = 3 })
	for _, l in ipairs(shapes.layers(s)) do eq(l.role ~= "blur", true, "no blur without the shadow") end
end)

test("circles_are_rings_of_quads_round_the_centre", function()
	local fill = layer(shapes.layers(settings({ shape = "circle", thickness = 1, gap = 4 })), "fill")
	local n = shapes.sides(12.5)
	eq(#fill.items, n, "one quad per side")
	eq(n % 4, 0, "sides come in fours")
	local of = fill.items[1].of
	eq(of.kind, "ring", "kind")
	near(of.r_out, 12.5, "outer radius: half the line, the gap and an arm")
	near(of.r_in, 11.5, "inner radius")
	near(of.cx, 0.5, "centre x")
	for _, it in ipairs(fill.items) do
		eq(it.of, of, "shared")
		eq(convex(it.pts), true, "convex quad")
		for i = 1, 8, 2 do
			local r = math.sqrt((it.pts[i] - 0.5) ^ 2 + (it.pts[i + 1] - 0.5) ^ 2)
			eq(math.abs(r - 12.5) < 1e-9 or math.abs(r - 11.5) < 1e-9, true, "point on a radius")
		end
	end
end)

test("circle_with_cross_stops_the_arms_at_the_line", function()
	local fill = layer(shapes.layers(settings({ shape = "circle_cross", thickness = 2, gap = 4 })), "fill")
	local ring, arms = nil, {}
	for _, it in ipairs(fill.items) do
		if it.of then ring = it.of else arms[#arms + 1] = it end
	end
	eq(#arms, 4, "arms")
	near(ring.r_in, 1 + 4 + 8 - 2, "inner edge")
	eq(rects(arms), rect_list({ { 5, -1, 6, 2 }, { -11, -1, 6, 2 }, { -1, 5, 2, 6 }, { -1, -11, 2, 6 } }), "arms end at the inner edge")
end)

test("the_dot_is_twice_the_thickness_across", function()
	for _, shape in ipairs({ "dot", "cross_dot", "circle_dot" }) do
		local fill = layer(shapes.layers(settings({ shape = shape, thickness = 3 })), "fill")
		local disc
		for _, it in ipairs(fill.items) do
			if it.of and it.of.kind == "disc" then disc = it.of end
		end
		near(disc.r, 3, shape .. " dot radius")
		near(disc.cx, 0.5, shape .. " centre")
	end
	local grown = layer(shapes.layers(settings({ shape = "dot", thickness = 2, outline = true, outline_thickness = 1 })), "outline")
	near(grown.items[1].of.r, 3, "outline round the dot")
end)

test("the_chevron_is_two_convex_halves_under_the_centre", function()
	local fill = layer(shapes.layers(settings({ shape = "chevron", thickness = 2, gap = 4 })), "fill")
	eq(#fill.items, 2, "halves")
	local left, right = fill.items[1].pts, fill.items[2].pts
	eq(convex(left) and convex(right), true, "convex")
	-- The top of the outer edge: the gap below the edge of a line through the centre.
	near(left[1], 0, "tip x")
	near(left[2], -5, "tip y")
	for i = 1, 8, 2 do
		-- Mirror images: the right half runs the other way round.
		local j = 8 - i
		near(right[j], -left[i], "mirror x " .. i)
		near(right[j + 1], left[i + 1], "mirror y " .. i)
	end
	local outline = layer(shapes.layers(settings({ shape = "chevron", thickness = 2, gap = 4, outline = true, outline_thickness = 1 })), "outline")
	-- Grown by 1 all round: the tip rises by 1 / sin(45 degrees).
	near(outline.items[1].pts[2], -5 + math.sqrt(2), "outline tip")
end)

test("brackets_open_toward_the_centre", function()
	local fill = layer(shapes.layers(settings({ shape = "brackets", thickness = 2, gap = 4 })), "fill")
	eq(rects(fill.items), rect_list({
		{ 9, -7, 2, 14 }, { 5, 5, 4, 2 }, { 5, -7, 4, 2 },
		{ -11, -7, 2, 14 }, { -9, 5, 4, 2 }, { -9, -7, 4, 2 },
	}), "bars and serifs")
end)

test("game_and_none_draw_nothing", function()
	eq(#shapes.layers(settings({ shape = "game" })), 0, "game")
	eq(#shapes.layers(settings({ shape = "none" })), 0, "none")
	eq(shapes.drawn("game"), false, "game drawn")
	eq(shapes.drawn("cross"), true, "cross drawn")
end)

test("every_listed_shape_draws_convex_polygons_and_real_rects", function()
	for _, shape in ipairs(shapes.SHAPES) do
		for _, scale in ipairs({ 0.5, 1, 1.3, 4 }) do
			for _, th in ipairs({ 1, 1.5, 6 }) do
				local s = settings({ shape = shape, scale = scale, thickness = th, gap = 3, outline = true, outline_thickness = 2, shadow = true, shadow_offset = 1.5 })
				for _, l in ipairs(shapes.layers(s)) do
					for _, it in ipairs(l.items) do
						if it.kind == "rect" then
							eq(it.w >= 1 and it.h >= 1, true, shape .. " rect size")
							eq(it.x == math.floor(it.x) and it.y == math.floor(it.y), true, shape .. " whole pixels")
						else
							eq(#it.pts >= 6, true, shape .. " polygon points")
							eq(convex(it.pts), true, shape .. " convex")
						end
					end
				end
			end
		end
	end
end)

test("scale_and_factor_multiply_every_size", function()
	local big = layer(shapes.layers(settings({ shape = "cross", thickness = 1, gap = 2, scale = 2 })), "fill")
	eq(rects(big.items), rect_list({ { 5, -1, 16, 2 }, { -21, -1, 16, 2 }, { -1, 5, 2, 16 }, { -1, -21, 2, 16 } }), "scale 2")
	local same = layer(shapes.layers(settings({ shape = "cross", thickness = 1, gap = 2, scale = 4 }), 0.5), "fill")
	eq(rects(same.items), rects(big.items), "scale 4 at half size")
end)

test("rects_are_never_thinner_than_a_pixel", function()
	local items = shapes.rect_items("cross", 0.1, 0, 1, 0, 0, 0)
	eq(#items, 4, "arms")
	for _, it in ipairs(items) do
		eq(it.w >= 1 and it.h >= 1, true, "at least a pixel")
	end
	eq(items[1].h, 1, "a hair line still covers a row")
end)

test("length_sets_the_arms_the_circle_and_the_brackets", function()
	eq(shapes.DEFAULTS.idle.length, shapes.ARM, "idle default keeps the old arms")
	eq(shapes.DEFAULTS.aim.length, shapes.ARM, "aiming default keeps the old arms")
	-- Cross, 2 thick, gap 4: the right arm starts 5 out and runs `length`.
	local cross = rects(layer(shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4, length = 12 })), "fill").items)
	eq(cross, rect_list({ { 5, -1, 12, 2 }, { -17, -1, 12, 2 }, { -1, 5, 2, 12 }, { -1, -17, 2, 12 } }), "arms 12 long")
	local none = rects(layer(shapes.layers(settings({ shape = "cross", thickness = 2, gap = 4, length = 0 })), "fill").items)
	eq(none, rect_list({ { 5, -1, 1, 2 }, { -5, -1, 1, 2 }, { -1, 5, 2, 1 }, { -1, -5, 2, 1 } }), "length 0 leaves a pixel")
	local ring = layer(shapes.layers(settings({ shape = "circle", thickness = 2, gap = 4, length = 12 })), "fill")
	near(ring.items[1].of.r_out, 1 + 4 + 12, "the circle runs through the tips of the arms")
	-- Brackets, 1 thick: the bar reaches 0.75 of the length above and below the centre line, the serifs
	-- are half the length.
	local function sizes(length)
		local out = {}
		for _, it in ipairs(layer(shapes.layers(settings({ shape = "brackets", thickness = 1, gap = 2, length = length })), "fill").items) do
			out[#out + 1] = it.w .. "x" .. it.h
		end
		table.sort(out)
		return table.concat(out, " ")
	end
	eq(sizes(8), "1x13 1x13 4x1 4x1 4x1 4x1", "6 and 4 pixels at the default length, as before the option")
	eq(sizes(16), "1x25 1x25 8x1 8x1 8x1 8x1", "twice the length, twice the size")
	local missing = settings({ shape = "brackets", thickness = 1, gap = 2 })
	missing.length = nil
	local eight = shapes.layers(settings({ shape = "brackets", thickness = 1, gap = 2, length = 8 }))
	eq(rects(shapes.layers(missing)[1].items), rects(eight[1].items), "no length is the default length")
end)

test("rect_edges_are_sums_of_known_sizes", function()
	local known = { H = true, G = true, T = true, L = true, ["1"] = true }
	for i, r in ipairs(shapes.RECTS) do
		for _, edge in ipairs({ "x0", "x1", "y0", "y1" }) do
			eq(#r[edge] > 0, true, i .. " " .. edge .. " terms")
			for _, t in ipairs(r[edge]) do
				eq(type(t[1]), "number", i .. " coefficient")
				eq(known[t[2]], true, i .. " size " .. tostring(t[2]))
			end
		end
		for _, shape in ipairs(r.shapes) do eq(shapes.drawn(shape), true, i .. " shape " .. shape) end
	end
end)

test("sides_follow_the_radius_within_bounds", function()
	eq(shapes.sides(0.5), shapes.MIN_SIDES, "small")
	eq(shapes.sides(1000), shapes.MAX_SIDES, "large")
	eq(shapes.sides(20) > shapes.sides(10), true, "grows")
end)

test("the_spread_fraction_and_the_extra_gap", function()
	eq(shapes.spread_fraction({ spread = 1, spread_min = 1, spread_max = 5 }), 0)
	eq(shapes.spread_fraction({ spread = 3, spread_min = 1, spread_max = 5 }), 0.5)
	eq(shapes.spread_fraction({ spread = 9, spread_min = 1, spread_max = 5 }), 1, "held to the most")
	eq(shapes.spread_fraction({ spread = 3, spread_min = 1, spread_max = 5, fixed_spread = true }), 0, "a fixed spread")
	eq(shapes.spread_fraction({ spread = 3, spread_min = 2, spread_max = 2 }), 0)
	eq(shapes.spread_fraction(nil), 0)
	eq(shapes.spread_extra(0), 0)
	eq(shapes.spread_extra(1), shapes.SPREAD_GAP)
	local s = { gap = 4, thickness = 2 }
	local wide = shapes.with_gap(s, 6)
	eq(wide.gap, 10)
	eq(wide.thickness, 2)
	eq(s.gap, 4, "the settings stay")
end)

test("colors_take_the_opacity", function()
	local c = shapes.rgba("#ff8000", 0.5)
	eq(c[1], 255, "r")
	eq(c[2], 128, "g")
	eq(c[3], 0, "b")
	eq(c[4], 128, "a")
	eq(shapes.rgba("red", 1)[1], 255, "bad color is white")
	local s = settings({ opacity = 0.5, shadow_opacity = 0.5, shadow_color = "#102030", outline_color = "#000000", color = "#ffffff" })
	eq(shapes.color_of(s, "shadow")[4], 64, "shadow times the opacity")
	eq(shapes.color_of(s, "shadow")[2], 32, "shadow color")
	eq(shapes.color_of(s, "outline")[4], 128, "outline fades with the lines")
	eq(shapes.color_of(s, "fill")[4], 128, "lines")
end)

test("settings_fill_in_defaults_and_refuse_wrong_types", function()
	local values = { aim_shape = "dot", aim_gap = "wide", aim_outline = false }
	local s = shapes.settings("aim", function(id) return values[id] end)
	eq(s.shape, "dot", "given")
	eq(s.gap, shapes.DEFAULTS.aim.gap, "wrong type")
	eq(s.outline, false, "false is a value")
	eq(s.color, shapes.DEFAULTS.aim.color, "missing")
	local idle = shapes.settings("idle", nil)
	eq(idle.shape, shapes.DEFAULTS.idle.shape, "no values")
end)

return T

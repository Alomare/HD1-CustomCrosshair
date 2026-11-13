-- Crosshair geometry: a shape and the settings in, the pieces to draw out. No game calls, so the tests
-- run it offline and preview/*.svg (tools/build_previews.lua) draws the same pixels.
--
-- Coordinates are pixels with y up, as obsidian.ui.canvas draws, relative to the pixel under the aim
-- point, which spans 0 to 1 on both axes. Every distance out from the centre is counted from the edge
-- of the centre line (half the thickness), and the centre sits in the middle of that pixel for an odd
-- thickness and on the corner of the pixel for an even one. With whole-pixel settings every edge then
-- falls on a pixel boundary: lines stay sharp and both sides of the crosshair match. Rectangles are
-- rounded to whole pixels; circles and the chevron are polygons.
local M = {}

-- Every shape, in the order the options list them. "game" keeps the game cursor and "none" draws
-- nothing; both come out empty here.
M.SHAPES = { "cross", "cross_dot", "dot", "circle", "circle_dot", "circle_cross", "t", "chevron", "brackets", "game", "none" }

-- Default arm length at scale 1, in pixels (option length). A circle runs through the tips of the arms
-- of a cross with the same settings.
M.ARM = 8

-- Circles are polygons with sides of about this many pixels, from MIN_SIDES to MAX_SIDES sides.
M.SIDE = 2.5
M.MIN_SIDES, M.MAX_SIDES = 12, 96

-- Settings of each state as obsidian.json declares them. main.lua fills a missing value from here, and
-- tests/test_manifest.lua keeps the two the same.
M.DEFAULTS = {
	idle = {
		shape = "circle", scale = 1, gap = 0, length = 8, thickness = 3, color = "#ffffff", opacity = 0.4,
		outline = false, outline_color = "#000000", outline_thickness = 1,
		shadow = false, shadow_color = "#000000", shadow_opacity = 0.5, shadow_offset = 2,
		shadow_size = 1, shadow_spread = 0, shadow_blur = 0,
	},
	aim = {
		shape = "cross", scale = 1, gap = 2, length = 8, thickness = 3, color = "#ffffff", opacity = 0.95,
		outline = true, outline_color = "#000000", outline_thickness = 0.51,
		shadow = true, shadow_color = "#000000", shadow_opacity = 0.2, shadow_offset = 0,
		shadow_size = 1, shadow_spread = 0, shadow_blur = 3,
	},
}

-- The settings of one state, without the prefix.
M.KEYS = { "shape", "scale", "gap", "length", "thickness", "color", "opacity", "outline", "outline_color", "outline_thickness",
	"shadow", "shadow_color", "shadow_opacity", "shadow_offset", "shadow_size", "shadow_spread", "shadow_blur" }

-- Shadow blur: rings of copies of the shadow, eight copies to a ring, one ring per pixel of blur.
M.MAX_BLUR = 3
M.BLUR_DIRECTIONS = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }

local SQRT_HALF = math.sqrt(0.5)

local function round(v)
	return math.floor(v + 0.5)
end
M.round = round

-- Whether a shape draws anything.
function M.drawn(shape)
	return shape ~= nil and shape ~= "game" and shape ~= "none"
end

-- Where the centre sits in the aim pixel, on both axes: 0.5 for an odd thickness, 0 for an even one.
function M.centre(T)
	return round(T) % 2 == 1 and 0.5 or 0
end

-- The rectangles of every shape. Each edge (left x0, right x1, bottom y0, top y1) is a sum of terms
-- { coefficient, size } taken in order, before the scale: H is half the thickness, G the gap, T the
-- thickness, L the length and "1" a plain number of pixels. tools/build_previews.lua writes the same
-- sums into the previews in the same order, so the game and the preview round every edge alike. The
-- arms are L long; brackets grow with L too, at the default length of 8 the same 4 and 6 pixels as
-- before the option (0.5 and 0.75 times 8 are exact).
local H, G, T, L = "H", "G", "T", "L"
local function terms(...) return { ... } end
M.RECTS = {
	-- Cross, and the T without a top arm: right, left, bottom, then top.
	{ shapes = { "cross", "cross_dot", "t" }, x0 = terms({ 1, H }, { 1, G }), x1 = terms({ 1, H }, { 1, G }, { 1, L }), y0 = terms({ -1, H }), y1 = terms({ 1, H }) },
	{ shapes = { "cross", "cross_dot", "t" }, x0 = terms({ -1, H }, { -1, G }, { -1, L }), x1 = terms({ -1, H }, { -1, G }), y0 = terms({ -1, H }), y1 = terms({ 1, H }) },
	{ shapes = { "cross", "cross_dot", "t" }, x0 = terms({ -1, H }), x1 = terms({ 1, H }), y0 = terms({ -1, H }, { -1, G }, { -1, L }), y1 = terms({ -1, H }, { -1, G }) },
	{ shapes = { "cross", "cross_dot" }, x0 = terms({ -1, H }), x1 = terms({ 1, H }), y0 = terms({ 1, H }, { 1, G }), y1 = terms({ 1, H }, { 1, G }, { 1, L }) },
	-- Inside the circle, up to the inner edge of the line (H less T comes to 0.5 T).
	{ shapes = { "circle_cross" }, x0 = terms({ 1, H }, { 1, G }), x1 = terms({ 1, G }, { 1, L }, { -0.5, T }), y0 = terms({ -1, H }), y1 = terms({ 1, H }) },
	{ shapes = { "circle_cross" }, x0 = terms({ 0.5, T }, { -1, G }, { -1, L }), x1 = terms({ -1, H }, { -1, G }), y0 = terms({ -1, H }), y1 = terms({ 1, H }) },
	{ shapes = { "circle_cross" }, x0 = terms({ -1, H }), x1 = terms({ 1, H }), y0 = terms({ 0.5, T }, { -1, G }, { -1, L }), y1 = terms({ -1, H }, { -1, G }) },
	{ shapes = { "circle_cross" }, x0 = terms({ -1, H }), x1 = terms({ 1, H }), y0 = terms({ 1, H }, { 1, G }), y1 = terms({ 1, G }, { 1, L }, { -0.5, T }) },
	-- "[ ]": a bar each side, 0.75 L (6 at the default) above and below the edge of the centre line, and
	-- serifs 0.5 L (4) long reaching back to the gap. Right bar, top and bottom serif, then the same on
	-- the left. H and T come together as 1.5 T or 0.5 T where they meet, which keeps the expressions of
	-- the preview within the 400 characters of the Launcher.
	{ shapes = { "brackets" }, x0 = terms({ 1, H }, { 1, G }, { 0.5, L }), x1 = terms({ 1.5, T }, { 1, G }, { 0.5, L }), y0 = terms({ -1, H }, { -0.75, L }), y1 = terms({ 1, H }, { 0.75, L }) },
	{ shapes = { "brackets" }, x0 = terms({ 1, H }, { 1, G }), x1 = terms({ 1, H }, { 1, G }, { 0.5, L }), y0 = terms({ 0.75, L }, { -0.5, T }), y1 = terms({ 1, H }, { 0.75, L }) },
	{ shapes = { "brackets" }, x0 = terms({ 1, H }, { 1, G }), x1 = terms({ 1, H }, { 1, G }, { 0.5, L }), y0 = terms({ -1, H }, { -0.75, L }), y1 = terms({ 0.5, T }, { -0.75, L }) },
	{ shapes = { "brackets" }, x0 = terms({ -1.5, T }, { -1, G }, { -0.5, L }), x1 = terms({ -1, H }, { -1, G }, { -0.5, L }), y0 = terms({ -1, H }, { -0.75, L }), y1 = terms({ 1, H }, { 0.75, L }) },
	{ shapes = { "brackets" }, x0 = terms({ -1, H }, { -1, G }, { -0.5, L }), x1 = terms({ -1, H }, { -1, G }), y0 = terms({ 0.75, L }, { -0.5, T }), y1 = terms({ 1, H }, { 0.75, L }) },
	{ shapes = { "brackets" }, x0 = terms({ -1, H }, { -1, G }, { -0.5, L }), x1 = terms({ -1, H }, { -1, G }), y0 = terms({ -1, H }, { -0.75, L }), y1 = terms({ 0.5, T }, { -0.75, L }) },
}

local function has(list, shape)
	for _, s in ipairs(list) do
		if s == shape then return true end
	end
	return false
end

-- A sum of terms, in order. sizes: { H, G, T, L, ["1"] = 1 }.
local function sum(list, sizes)
	local s = 0
	for _, t in ipairs(list) do s = s + t[1] * sizes[t[2]] end
	return s
end

-- The rectangles of a shape as whole pixels { kind = "rect", x, y, w, h } around the centre (c, c)
-- of the aim pixel: sized by z, then grown by `grow` and moved by `shift` down and to the right, all
-- before the scale k. z is 1 when left out (1 times a sum is the same sum, to the last bit), and the
-- length is ARM when left out. `spread` grows the rectangles once more after `grow`, added apart
-- from it as the preview adds it (0 when left out, which changes nothing).
function M.rect_items(shape, thickness, gap, k, c, grow, shift, out, z, length, spread)
	out = out or {}
	z = z or 1
	spread = spread or 0
	local sizes = { H = thickness / 2, G = gap, T = thickness, L = length or M.ARM, ["1"] = 1 }
	for _, r in ipairs(M.RECTS) do
		if has(r.shapes, shape) then
			local x0 = z * sum(r.x0, sizes) - grow - spread + shift
			local x1 = z * sum(r.x1, sizes) + grow + spread + shift
			local y0 = z * sum(r.y0, sizes) - grow - spread - shift
			local y1 = z * sum(r.y1, sizes) + grow + spread - shift
			local l, rr = round(c + k * x0), round(c + k * x1)
			local b, t = round(c + k * y0), round(c + k * y1)
			if rr <= l then rr = l + 1 end
			if t <= b then t = b + 1 end
			out[#out + 1] = { kind = "rect", x = l, y = b, w = rr - l, h = t - b }
		end
	end
	return out
end

-- The other parts of a shape around the centre (0, 0), in pixels:
--   { kind = "ring", r_in, r_out }              a circle line
--   { kind = "disc", r }                        a filled circle
--   { kind = "chevron", apex, length, width }   a "^" whose centre line starts at (0, apex) and runs
--                                               `length` down to each side at 45 degrees
-- A, G and T are the arm length, gap and thickness in pixels, the scale already applied.
function M.parts(shape, A, G, T)
	local out = {}
	local H = T / 2
	if shape == "circle" or shape == "circle_dot" or shape == "circle_cross" then
		out[#out + 1] = { kind = "ring", r_in = math.max(H + G + A - T, 0), r_out = H + G + A }
	end
	if shape == "cross_dot" or shape == "dot" or shape == "circle_dot" then
		out[#out + 1] = { kind = "disc", r = T }
	end
	if shape == "chevron" then
		-- The tip of the outer edge sits at the gap below the centre.
		out[#out + 1] = { kind = "chevron", apex = -H - G - T * SQRT_HALF, length = A, width = T }
	end
	return out
end

-- A part grown outward by `by` pixels on every side, for the outline.
function M.grow(part, by)
	if by == 0 then return part end
	local k = part.kind
	if k == "ring" then
		return { kind = "ring", r_in = math.max(part.r_in - by, 0), r_out = part.r_out + by }
	elseif k == "disc" then
		return { kind = "disc", r = part.r + by }
	elseif k == "chevron" then
		-- The same centre line: wider, and longer at the open ends.
		return { kind = "chevron", apex = part.apex, length = part.length + by, width = part.width + 2 * by }
	end
	return part
end

-- Sides of a circle of radius r.
function M.sides(r)
	local n = math.ceil(2 * math.pi * r / M.SIDE)
	n = math.max(M.MIN_SIDES, math.min(M.MAX_SIDES, n))
	return math.ceil(n / 4) * 4
end

-- The two quads of a chevron, as point lists around the centre { x1, y1, ... }: they meet on the
-- vertical line through the centre, so the halves never overlap.
function M.chevron_quads(apex, length, width)
	local k, a = width * SQRT_HALF, length * SQRT_HALF
	local h = k / 2
	local left = { 0, apex + k, -a - h, apex - a + h, -a + h, apex - a - h, 0, apex - k }
	local right = { 0, apex - k, a - h, apex - a - h, a + h, apex - a + h, 0, apex + k }
	return left, right
end

-- Polygons for parts grown by `grow` pixels and moved by `shift` down and to the right, with the
-- centre at (c, c) in the aim pixel: { kind = "poly", pts }, convex. A ring is a run of quads, a
-- disc one polygon, a chevron two quads. The polygons of one circle share
-- `of` = { kind, cx, cy, r_in, r_out } or { kind, cx, cy, r }, which the preview test compares with
-- the SVG circles.
function M.items(parts, grow, shift, c, out)
	out = out or {}
	local dx, dy = c + shift, c - shift
	for _, base in ipairs(parts) do
		local p = M.grow(base, grow)
		if p.kind == "disc" or (p.kind == "ring" and p.r_in <= 0) then
			local r = p.kind == "disc" and p.r or p.r_out
			local n = M.sides(r)
			local pts = {}
			for i = 0, n - 1 do
				local t = 2 * math.pi * i / n
				pts[#pts + 1] = dx + r * math.cos(t)
				pts[#pts + 1] = dy + r * math.sin(t)
			end
			out[#out + 1] = { kind = "poly", pts = pts, of = { kind = "disc", cx = dx, cy = dy, r = r } }
		elseif p.kind == "ring" then
			local n = M.sides(p.r_out)
			local of = { kind = "ring", cx = dx, cy = dy, r_in = p.r_in, r_out = p.r_out }
			for i = 0, n - 1 do
				local t0, t1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
				local c0, s0, c1, s1 = math.cos(t0), math.sin(t0), math.cos(t1), math.sin(t1)
				out[#out + 1] = { kind = "poly", of = of, pts = {
					dx + p.r_out * c0, dy + p.r_out * s0,
					dx + p.r_out * c1, dy + p.r_out * s1,
					dx + p.r_in * c1, dy + p.r_in * s1,
					dx + p.r_in * c0, dy + p.r_in * s0,
				} }
			end
		elseif p.kind == "chevron" then
			for _, q in ipairs({ M.chevron_quads(p.apex, p.length, p.width) }) do
				for i = 1, #q, 2 do
					q[i], q[i + 1] = q[i] + dx, q[i + 1] + dy
				end
				out[#out + 1] = { kind = "poly", pts = q }
			end
		end
	end
	return out
end

-- Rings of blur at scale k: { { dx, dy, weight }, ... }, whole pixels with y up. Ring j sits round(j * k)
-- pixels out, and each copy in it takes `weight` of the shadow opacity: less the further out, and a
-- third at most, since about three copies of a ring overlap just past a straight edge.
function M.blur_copies(blur, k)
	local n = math.max(0, math.min(M.MAX_BLUR, math.floor(blur or 0)))
	local out = {}
	for j = 1, n do
		local r = round(j * k)
		local weight = (n + 1 - j) / (3 * (n + 1))
		for _, d in ipairs(M.BLUR_DIRECTIONS) do
			out[#out + 1] = { dx = d[1] * r, dy = d[2] * r, weight = weight }
		end
	end
	return out
end

-- Items moved by whole pixels (dx, dy), y up: new items, new point lists.
function M.moved(items, dx, dy)
	local out = {}
	for i, it in ipairs(items) do
		if it.kind == "rect" then
			out[i] = { kind = "rect", x = it.x + dx, y = it.y + dy, w = it.w, h = it.h }
		else
			local pts = {}
			for j = 1, #it.pts, 2 do
				pts[j], pts[j + 1] = it.pts[j] + dx, it.pts[j + 1] + dy
			end
			out[i] = { kind = "poly", pts = pts }
		end
	end
	return out
end

-- Everything one state draws, back to front:
--   { { role = "blur" | "shadow" | "outline" | "fill", items }, ... }
-- `s` holds the settings of the state without the prefix. `factor` scales the whole crosshair once
-- more (the cursor flying back to the Helldiver shrinks); 1 when left out. Empty for "game" and "none".
-- The shadow is the crosshair at shadow_size times the size, around the same centre, grown by the
-- outline and the spread and moved by the offset. Each blur layer is that shadow moved by dx, dy and
-- drawn at `weight` of the shadow opacity.
function M.layers(s, factor)
	if not M.drawn(s.shape) then return {} end
	local k = (s.scale or 1) * (factor or 1)
	local thickness, gap, length = s.thickness or 1, s.gap or 0, s.length or M.ARM
	local c = M.centre(thickness * k)
	-- Outline, spread and offset before the scale.
	local edge = s.outline and (s.outline_thickness or 0) or 0
	local offset = s.shadow_offset or 0
	local function items(grow, shift, z, spread)
		spread = spread or 0
		local parts = M.parts(s.shape, length * k * z, gap * k * z, thickness * k * z)
		local out = M.rect_items(s.shape, thickness, gap, k, c, grow, shift, nil, z, length, spread)
		return M.items(parts, (grow + spread) * k, shift * k, c, out)
	end
	local out = {}
	if s.shadow then
		local shadow = items(edge, offset, s.shadow_size or 1, s.shadow_spread or 0)
		for _, copy in ipairs(M.blur_copies(s.shadow_blur, k)) do
			out[#out + 1] = { role = "blur", dx = copy.dx, dy = copy.dy, weight = copy.weight, items = M.moved(shadow, copy.dx, copy.dy) }
		end
		out[#out + 1] = { role = "shadow", items = shadow }
	end
	if s.outline and edge > 0 then out[#out + 1] = { role = "outline", items = items(edge, 0, 1) } end
	out[#out + 1] = { role = "fill", items = items(0, 0, 1) }
	return out
end

-- "#rrggbb" and an opacity from 0 to 1 as { r, g, b, a } from 0 to 255. White for anything else.
function M.rgba(hex, opacity)
	local r, g, b = 255, 255, 255
	if type(hex) == "string" then
		local rr, gg, bb = hex:match("^#(%x%x)(%x%x)(%x%x)$")
		if rr then r, g, b = tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16) end
	end
	local a = math.max(0, math.min(1, tonumber(opacity) or 1))
	return { r, g, b, round(a * 255) }
end

-- The color of a layer of a state. weight: the share of the shadow opacity a blur layer takes.
function M.color_of(s, role, weight)
	local opacity = s.opacity or 1
	if role == "shadow" then return M.rgba(s.shadow_color, (s.shadow_opacity or 0) * opacity) end
	if role == "blur" then return M.rgba(s.shadow_color, (s.shadow_opacity or 0) * opacity * (weight or 0)) end
	if role == "outline" then return M.rgba(s.outline_color, opacity) end
	return M.rgba(s.color, opacity)
end

-- The settings of a state from get(id), the option values, with the defaults filling in what is
-- missing or of the wrong type. prefix: "idle" or "aim".
function M.settings(prefix, get)
	local d = M.DEFAULTS[prefix]
	local s = {}
	for _, key in ipairs(M.KEYS) do
		local v = get and get(prefix .. "_" .. key)
		if v == nil or type(v) ~= type(d[key]) then v = d[key] end
		s[key] = v
	end
	return s
end

-- Aiming gap scales with spread: the gap of the aiming crosshair opens by up to SPREAD_GAP pixels
-- (before the scale) as the spread of the weapon grows from least to most. The firearm of the game keeps
-- the spread it fires with now in the firearm state (FirearmComponent: spread, from spread_min to spread_max as
-- shots are fired, and back as they decay).
M.SPREAD_GAP = 12

-- How far the spread is between least and most, from 0 to 1, from the state of a firearm.
function M.spread_fraction(st)
	if type(st) ~= "table" or st.fixed_spread then return 0 end
	local now, low, high = tonumber(st.spread), tonumber(st.spread_min), tonumber(st.spread_max)
	if not (now and low and high) or high <= low then return 0 end
	return math.max(0, math.min(1, (now - low) / (high - low)))
end

-- The extra gap in whole pixels for a fraction, so a few looks cover every spread.
function M.spread_extra(fraction)
	return math.floor((fraction or 0) * M.SPREAD_GAP + 0.5)
end

-- A copy of settings s with `extra` pixels on the gap.
function M.with_gap(s, extra)
	local out = {}
	for k, v in pairs(s) do out[k] = v end
	out.gap = (s.gap or 0) + (extra or 0)
	return out
end

return M

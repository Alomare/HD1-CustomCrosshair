-- Writes preview/idle.svg, preview/aim.svg and preview/hitmarker.svg, the live previews Obsidian shows
-- above each group of options (option_previews in obsidian.json). From the repository root:
--   luajit tools/build_previews.lua
-- Each template draws what src/shapes.lua or src/hitmarker.lua draws, in the same pixels: the
-- crosshair at actual size on the left and magnified on the right, the marks of a hit and of a kill
-- side by side, over a mid grey so light and dark colors both show. The values come from {{expr}} and
-- data-if, in the expression language Obsidian reads (numbers, 'strings', option ids, + - * / %,
-- comparisons, && || !, a ? b : c, min max abs round floor ceil clamp), each expression at most 400
-- characters. "a ? b : 0" stands in for a && b and "0-x" for -x: an & or < inside an attribute isn't
-- valid XML, and the test reader refuses unary minus. Rectangles come from shapes.RECTS, summed in the
-- same order as the game sums them, so both round every edge alike. Blur copies of the shadow are
-- <use> elements, moved by whole pixels as the game moves them. tests/test_preview.lua fills the
-- templates in and compares every rectangle, circle, polygon and copy with the game.
local shapes = dofile("src/shapes.lua")
local hitmarker = dofile("src/hitmarker.lua")

local M = {}

-- sqrt(1/2), short enough to keep the chevron points of the shadow within 400 characters. Polygons
-- and circles are compared to 0.0001 of a pixel, so the missing digits never show.
local SQ = "0.70710678"

local function E(expr) return "{{" .. expr .. "}}" end

local function number(v)
	if v == math.floor(v) then return string.format("%d", v) end
	return tostring(v)
end

-- The option ids of one state as expressions.
local function names(p)
	local o = function(k) return p .. "_" .. k end
	return {
		p = p,
		o = o,
		shape = o("shape"),
		S = o("scale"),
		-- Sizes of shapes.RECTS, before the scale.
		H = o("thickness") .. "/2",
		G = o("gap"),
		T = o("thickness"),
		-- Where the centre sits in the aim pixel (shapes.centre): 0.5 for an odd thickness, 0 for an even one.
		C = "round(" .. o("thickness") .. "*" .. o("scale") .. ")%2/2",
	}
end

local function shape_in(n, list)
	local parts = {}
	for _, s in ipairs(list) do parts[#parts + 1] = n.shape .. "=='" .. s .. "'" end
	return table.concat(parts, "||")
end

-- A sum of shapes.RECTS terms in order, times z when there is one, then the growth and the shift, as
-- an expression.
local function sum(n, list, g_sign, g, d_sign, d, z)
	local out = {}
	for i, t in ipairs(list) do
		local coef, size = t[1], t[2]
		local mag = math.abs(coef)
		local body = size == "1" and number(mag) or (mag == 1 and n[size] or number(mag) .. "*" .. n[size])
		if coef < 0 then
			out[#out + 1] = (i == 1 and "0-" or "-") .. body
		else
			out[#out + 1] = (i == 1 and "" or "+") .. body
		end
	end
	local s = table.concat(out)
	if z then s = z .. "*(" .. s .. ")" end
	if g ~= "0" then s = s .. (g_sign < 0 and "-" or "+") .. g end
	if d ~= "0" then s = s .. (d_sign < 0 and "-" or "+") .. d end
	return s
end

-- One rectangle of shapes.RECTS sized by z, grown by g and moved by d down and to the right, rounded
-- as shapes.rect_items rounds it, at least a pixel each way, in SVG coordinates (y down) where the aim
-- pixel spans 0 to 1.
local function rect(n, r, g, d, z)
	local function edge(list, g_sign, d_sign)
		return "round(" .. n.C .. "+" .. n.S .. "*(" .. sum(n, list, g_sign, g, d_sign, d, z) .. "))"
	end
	local L, R = edge(r.x0, -1, 1), edge(r.x1, 1, 1)
	local B, T = edge(r.y0, -1, -1), edge(r.y1, 1, -1)
	return string.format('<rect x="%s" y="%s" width="%s" height="%s"/>',
		E(L), E("min(1-" .. T .. ",0-" .. B .. ")"), E("max(" .. R .. "-" .. L .. ",1)"), E("max(" .. T .. "-" .. B .. ",1)"))
end

-- Every part of every shape, as SVG elements of one layer. g: growth (outline and spread), d: shadow
-- shift, both before the scale, and z the shadow size (nil for 1).
local function parts(n, g, d, z, color)
	local out = {}
	local S, H, G, T = n.S, n.H, n.G, n.T
	-- Rectangles, a group for each run with the same shapes.
	local i = 1
	while i <= #shapes.RECTS do
		local set = table.concat(shapes.RECTS[i].shapes, " ")
		out[#out + 1] = string.format('<g data-if="%s">', shape_in(n, shapes.RECTS[i].shapes))
		while i <= #shapes.RECTS and table.concat(shapes.RECTS[i].shapes, " ") == set do
			out[#out + 1] = "  " .. rect(n, shapes.RECTS[i], g, d, z)
			i = i + 1
		end
		out[#out + 1] = "</g>"
	end

	local plus_g = g ~= "0" and ("+" .. g) or ""
	local minus_g = g ~= "0" and ("-" .. g) or ""
	local zs = z and (z .. "*") or ""
	-- Circle centre in SVG coordinates: (c + d, 1 - c + d), d scaled.
	local shift = d ~= "0" and ("+" .. S .. "*" .. d) or ""
	local cx = n.C .. shift
	local cy = "1-" .. n.C .. shift
	-- Sizes of shapes.parts times z.
	local function sized(expr) return z and (z .. "*(" .. expr .. ")") or expr end

	-- The circle line, a stroked circle between the inner and outer radius (shapes.parts). The
	-- opacity of the stroke comes from the layer.
	local r_out = S .. "*(" .. sized(H .. "+" .. G .. "+8") .. plus_g .. ")"
	local r_in = "max(" .. S .. "*(" .. sized(H .. "+" .. G .. "+8-" .. T) .. minus_g .. "),0)"
	out[#out + 1] = string.format('<circle data-if="%s" cx="%s" cy="%s" r="%s" stroke-width="%s" fill="none" stroke="%s"/>',
		shape_in(n, { "circle", "circle_dot", "circle_cross" }), E(cx), E(cy),
		E("(" .. r_in .. "+" .. r_out .. ")/2"), E(r_out .. "-" .. r_in), E(color))

	-- The dot.
	out[#out + 1] = string.format('<circle data-if="%s" cx="%s" cy="%s" r="%s"/>',
		shape_in(n, { "cross_dot", "dot", "circle_dot" }), E(cx), E(cy), E(S .. "*(" .. zs .. T .. plus_g .. ")"))

	-- The chevron: two quads meeting on the vertical line through the centre (shapes.chevron_quads).
	local apex = "(0-" .. S .. "*" .. zs .. "(" .. H .. "+" .. G .. "+" .. T .. "*" .. SQ .. "))"
	local k = "(" .. S .. "*(" .. zs .. T .. (g ~= "0" and ("+2*" .. g) or "") .. ")*" .. SQ .. ")"
	local a = "(" .. S .. "*(" .. zs .. "8" .. plus_g .. ")*" .. SQ .. ")"
	local h = "(" .. k .. "/2)"
	local function pt(x, y)
		-- Around the centre (x, y up) to SVG: c + d + x, 1 - c + d - y.
		return E(cx .. "+" .. x) .. "," .. E(cy .. "-(" .. y .. ")")
	end
	local chevron = shape_in(n, { "chevron" })
	out[#out + 1] = string.format('<polygon data-if="%s" points="%s"/>', chevron, table.concat({
		pt("0", apex .. "+" .. k),
		pt("(0-" .. a .. "-" .. h .. ")", apex .. "-" .. a .. "+" .. h),
		pt("(0-" .. a .. "+" .. h .. ")", apex .. "-" .. a .. "-" .. h),
		pt("0", apex .. "-" .. k),
	}, " "))
	out[#out + 1] = string.format('<polygon data-if="%s" points="%s"/>', chevron, table.concat({
		pt("0", apex .. "-" .. k),
		pt("(" .. a .. "-" .. h .. ")", apex .. "-" .. a .. "-" .. h),
		pt("(" .. a .. "+" .. h .. ")", apex .. "-" .. a .. "+" .. h),
		pt("0", apex .. "+" .. k),
	}, " "))
	return out
end

-- One layer: a group with the color and opacity of the layer, for the fill and for circle lines.
-- `id` wraps the elements in a group the blur copies point at.
local function layer(n, role, cond, g, d, z, color, opacity, id)
	local lines = {}
	lines[#lines + 1] = string.format('    <g data-role="%s"%s fill="%s" fill-opacity="%s" stroke-opacity="%s">', role,
		cond and string.format(' data-if="%s"', cond) or "", E(color), E(opacity), E(opacity))
	local indent = "      "
	if id then
		lines[#lines + 1] = string.format('      <g id="%s">', id)
		indent = "        "
	end
	for _, el in ipairs(parts(n, g, d, z, color)) do lines[#lines + 1] = indent .. el end
	if id then lines[#lines + 1] = "      </g>" end
	lines[#lines + 1] = "    </g>"
	return table.concat(lines, "\n")
end

-- The blur: copies of the shadow, eight to a ring, ring j round(j * scale) pixels out, at a share of
-- the shadow opacity that falls ring by ring (shapes.blur_copies). Each ring is a group with that
-- opacity, which the copies inside take on.
local function blur(n, color, opacity, id)
	local o, S = n.o, n.S
	local B = "min(floor(" .. o("shadow_blur") .. ")," .. shapes.MAX_BLUR .. ")"
	local lines = {
		string.format('    <g data-role="blur" data-if="%s?%s>=1:0" fill="%s">', o("shadow"), o("shadow_blur"), E(color)),
	}
	for j = 1, shapes.MAX_BLUR do
		local r = "round(" .. j .. "*" .. S .. ")"
		local w = E(opacity .. "*(" .. B .. "+1-" .. j .. ")/(3*(" .. B .. "+1))")
		lines[#lines + 1] = string.format('      <g data-ring="%d" data-if="%s>=%d" fill-opacity="%s" stroke-opacity="%s">', j, o("shadow_blur"), j, w, w)
		for _, dir in ipairs(shapes.BLUR_DIRECTIONS) do
			-- y up in the game, down in SVG.
			local dx = dir[1] == 0 and "0" or E(dir[1] > 0 and r or ("0-" .. r))
			local dy = dir[2] == 0 and "0" or E(dir[2] > 0 and ("0-" .. r) or r)
			lines[#lines + 1] = string.format('        <use href="#%s" transform="translate(%s %s)"/>', id, dx, dy)
		end
		lines[#lines + 1] = "      </g>"
	end
	lines[#lines + 1] = "    </g>"
	return table.concat(lines, "\n")
end

-- The whole template of one state: "idle" or "aim".
function M.build(p)
	local n = names(p)
	local o = n.o
	local edge = "(" .. o("outline") .. "?" .. o("outline_thickness") .. ":0)"
	local grow = "(" .. edge .. "+" .. o("shadow_spread") .. ")"
	local drawn = n.shape .. "!='game'?" .. n.shape .. "!='none':0"
	local shadow_id = p .. "_shadow_shape"
	local shadow_opacity = o("shadow_opacity") .. "*" .. o("opacity")
	-- About how far the crosshair reaches from the centre, for the magnification.
	local reach = "(" .. o("gap") .. "+8+" .. o("thickness") .. ")"
	local extent = "(max(" .. reach .. "+" .. edge .. "," .. o("shadow") .. "?" .. o("shadow_size") .. "*" .. reach .. "+" .. edge ..
		"+" .. o("shadow_spread") .. "+" .. o("shadow_offset") .. "+" .. o("shadow_blur") .. ":0)*" .. n.S .. "+1)"
	local zoom = "clamp(floor(54/" .. extent .. "),1,4)"
	local lines = {
		'<svg xmlns="http://www.w3.org/2000/svg" width="240" height="140" viewBox="0 0 240 140">',
		'  <rect x="0" y="0" width="240" height="140" fill="#808080"/>',
		string.format('  <g id="%s_crosshair" transform="translate(60 70)" shape-rendering="crispEdges" data-if="%s">', p, drawn),
		blur(n, o("shadow_color"), shadow_opacity, shadow_id),
		layer(n, "shadow", o("shadow"), grow, o("shadow_offset"), o("shadow_size"), o("shadow_color"), shadow_opacity, shadow_id),
		layer(n, "outline", o("outline"), o("outline_thickness"), "0", nil, o("outline_color"), o("opacity")),
		layer(n, "fill", nil, "0", "0", nil, o("color"), o("opacity")),
		'  </g>',
		string.format('  <use href="#%s_crosshair" data-if="%s" transform="translate(%s %s) scale(%s)"/>', p, drawn,
			E("180-60.5*" .. zoom), E("70-70.5*" .. zoom), E(zoom)),
		string.format('  <line data-if="%s" x1="120" y1="10" x2="120" y2="116" stroke="#6c6c6c" stroke-width="1"/>', drawn),
		'  <g font-family="Segoe UI, Arial, sans-serif" font-size="11" fill="#ffffff" text-anchor="middle">',
		string.format('    <text data-if="%s" x="60" y="132">Actual size</text>', drawn),
		string.format('    <text data-if="%s" x="180" y="132">Zoom %sx</text>', drawn, E(zoom)),
		string.format('    <text data-if="%s==\'game\'" x="120" y="74">Game cursor</text>', n.shape),
		string.format('    <text data-if="%s==\'none\'" x="120" y="74">No crosshair</text>', n.shape),
		'  </g>',
		'</svg>',
		'',
	}
	return table.concat(lines, "\n")
end

-- Hitmarker --------------------------------------------------------------------------------------

local HM = hitmarker.IDS
-- The marks sit on the centre of the aiming crosshair (shapes.centre), as they mostly show while aiming.
local HM_C = "round(aim_thickness*aim_scale)%2/2"

-- "+x" or "-x", or "x" / "0-x" first in a sum.
local function signed(sign, x, first)
	if sign > 0 then return (first and "" or "+") .. x end
	return (first and "0-" or "-") .. x
end

-- The four quads of hitmarker.quads, grown by `grow` pixels, as SVG polygons (y down).
local function marker_quads(grow)
	local g = grow ~= 0 and number(grow) or nil
	local r0 = g and ("(" .. HM.gap .. "-" .. g .. ")") or HM.gap
	local r1 = "(" .. HM.gap .. "+" .. HM.size .. (g and ("+" .. g) or "") .. ")"
	local h = "(" .. HM.thickness .. "/2" .. (g and ("+" .. g) or "") .. ")"
	local out = {}
	for _, d in ipairs(hitmarker.ARMS) do
		local sx, sy = d[1], d[2]
		local pts = {}
		-- The corners in the order of hitmarker.quads: (r0, -h), (r1, -h), (r1, h), (r0, h).
		for _, corner in ipairs({ { r0, -1 }, { r1, -1 }, { r1, 1 }, { r0, 1 } }) do
			local r, ts = corner[1], corner[2]
			-- x = c + q (sx r - sy t), y = c + q (sy r + sx t), with t = ts h; SVG y is 1 - y.
			local x = HM_C .. "+" .. SQ .. "*(" .. signed(sx, r, true) .. signed(-sy * ts, h) .. ")"
			local y = "1-" .. HM_C .. "-" .. SQ .. "*(" .. signed(sy, r, true) .. signed(sx * ts, h) .. ")"
			pts[#pts + 1] = E(x) .. "," .. E(y)
		end
		out[#out + 1] = string.format('<polygon points="%s"/>', table.concat(pts, " "))
	end
	return out
end

-- One mark, magnified about the middle of the aim pixel and moved to (x, y).
local function mark(kind, x, y, zoom, color)
	local lines = {
		string.format('  <g data-role="%s" data-if="%s" transform="translate(%s %s) scale(%s)" shape-rendering="crispEdges">',
			kind, kind == "kill" and HM.kills or HM.hits, E(x .. "-0.5*" .. zoom), E(y .. "-0.5*" .. zoom), E(zoom)),
		string.format('    <g data-layer="outline" data-if="%s" fill="%s">', HM.outline, hitmarker.OUTLINE_COLOR),
	}
	for _, el in ipairs(marker_quads(hitmarker.OUTLINE)) do lines[#lines + 1] = "      " .. el end
	lines[#lines + 1] = "    </g>"
	lines[#lines + 1] = string.format('    <g data-layer="fill" fill="%s">', E(color))
	for _, el in ipairs(marker_quads(0)) do lines[#lines + 1] = "      " .. el end
	lines[#lines + 1] = "    </g>"
	lines[#lines + 1] = "  </g>"
	return table.concat(lines, "\n")
end

-- The hitmarker template: the mark of a hit on the left and of a kill on the right, at the same zoom.
function M.build_hitmarker()
	-- About how far a mark reaches from the centre, outline included.
	local extent = "((" .. HM.gap .. "+" .. HM.size .. "+" .. HM.thickness .. "/2+2)*" .. SQ .. "+1)"
	local zoom = "clamp(floor(50/" .. extent .. "),1,4)"
	local on = HM.on
	local lines = {
		'<svg xmlns="http://www.w3.org/2000/svg" width="240" height="140" viewBox="0 0 240 140">',
		'  <rect x="0" y="0" width="240" height="140" fill="#808080"/>',
		string.format('  <g data-if="%s">', on),
		mark("hit", "60", "64", zoom, HM.color),
		mark("kill", "180", "64", zoom, HM.kill_color),
		'  <line x1="120" y1="10" x2="120" y2="116" stroke="#6c6c6c" stroke-width="1"/>',
		'  </g>',
		'  <g font-family="Segoe UI, Arial, sans-serif" font-size="11" fill="#ffffff" text-anchor="middle">',
		string.format('    <text data-if="%s?%s:0" x="60" y="132">Hit</text>', on, HM.hits),
		string.format('    <text data-if="%s?!%s:0" x="60" y="132">Hits off</text>', on, HM.hits),
		string.format('    <text data-if="%s?%s:0" x="180" y="132">Kill</text>', on, HM.kills),
		string.format('    <text data-if="%s?!%s:0" x="180" y="132">Kills off</text>', on, HM.kills),
		string.format('    <text data-if="%s" x="120" y="132">Zoom %sx</text>', on, E(zoom)),
		string.format('    <text data-if="!%s" x="120" y="74">No hitmarker</text>', on),
		'  </g>',
		'</svg>',
		'',
	}
	return table.concat(lines, "\n")
end

M.FILES = { idle = "preview/idle.svg", aim = "preview/aim.svg", hitmarker = "preview/hitmarker.svg" }

-- The template written to M.FILES[name].
function M.template(name)
	if name == "hitmarker" then return M.build_hitmarker() end
	return M.build(name)
end

-- Run as a script: write every file.
if arg and arg[0] and arg[0]:find("build_previews", 1, true) then
	for _, name in ipairs({ "idle", "aim", "hitmarker" }) do
		local f = assert(io.open(M.FILES[name], "wb"))
		f:write(M.template(name))
		f:close()
		print("wrote " .. M.FILES[name])
	end
end

return M

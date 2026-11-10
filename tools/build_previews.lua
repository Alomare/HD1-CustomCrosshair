-- Writes preview/idle.svg and preview/aim.svg, the live previews Obsidian shows above each group of
-- options (option_previews in obsidian.json). From the repository root:
--   luajit tools/build_previews.lua
-- Each template draws what src/shapes.lua draws, in the same pixels: the crosshair at actual size on
-- the left and magnified on the right, over a mid grey so light and dark colors both show. The values
-- come from {{expr}} and data-if, in the expression language Obsidian reads (numbers, 'strings',
-- option ids, + - * / %, comparisons, && || !, a ? b : c, min max abs round floor ceil clamp).
-- "a ? b : 0" stands in for a && b and "0-x" for -x: an & or < inside an attribute isn't valid XML,
-- and unary minus isn't in the language. Rectangles come from shapes.RECTS, summed in the same order
-- as the game sums them, so both round every edge alike. tests/test_preview.lua fills the templates
-- in and compares every rectangle, circle and polygon with src/shapes.lua.
local shapes = dofile("src/shapes.lua")

local M = {}

local SQ = "0.7071067811865476" -- sqrt(1/2)

local function E(expr) return "{{" .. expr .. "}}" end

local function number(v)
	if v == math.floor(v) then return string.format("%d", v) end
	return tostring(v)
end

-- The option ids of one state as expressions.
local function names(p)
	local o = function(k) return p .. "_" .. k end
	return {
		o = o,
		shape = o("shape"),
		S = o("scale"),
		-- Sizes of shapes.RECTS, before the scale.
		H = o("thickness") .. "/2",
		G = o("gap"),
		T = o("thickness"),
		-- Where the centre sits in the aim pixel (shapes.centre).
		C = "(round(" .. o("thickness") .. "*" .. o("scale") .. ")%2==1?0.5:0)",
	}
end

local function shape_in(n, list)
	local parts = {}
	for _, s in ipairs(list) do parts[#parts + 1] = n.shape .. "=='" .. s .. "'" end
	return table.concat(parts, "||")
end

-- A sum of shapes.RECTS terms in order, then the growth and the shift, as an expression.
local function sum(n, list, g_sign, g, d_sign, d)
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
	if g ~= "0" then out[#out + 1] = (g_sign < 0 and "-" or "+") .. g end
	if d ~= "0" then out[#out + 1] = (d_sign < 0 and "-" or "+") .. d end
	return table.concat(out)
end

-- One rectangle of shapes.RECTS grown by g and moved by d down and to the right, rounded as
-- shapes.rect_items rounds it, at least a pixel each way, in SVG coordinates (y down) where the aim
-- pixel spans 0 to 1.
local function rect(n, r, g, d)
	local function edge(list, g_sign, d_sign)
		return "round(" .. n.C .. "+" .. n.S .. "*(" .. sum(n, list, g_sign, g, d_sign, d) .. "))"
	end
	local L, R = edge(r.x0, -1, 1), edge(r.x1, 1, 1)
	local B, T = edge(r.y0, -1, -1), edge(r.y1, 1, -1)
	return string.format('<rect x="%s" y="%s" width="%s" height="%s"/>',
		E(L), E("min(1-" .. T .. ",0-" .. B .. ")"), E("max(" .. R .. "-" .. L .. ",1)"), E("max(" .. T .. "-" .. B .. ",1)"))
end

-- Every part of every shape, as SVG elements of one layer. g: growth (outline) and d: shadow shift,
-- both before the scale.
local function parts(n, g, d, color, opacity)
	local out = {}
	local S, H, G, T = n.S, n.H, n.G, n.T
	-- Rectangles, a group for each run with the same shapes.
	local i = 1
	while i <= #shapes.RECTS do
		local set = table.concat(shapes.RECTS[i].shapes, " ")
		out[#out + 1] = string.format('<g data-if="%s">', shape_in(n, shapes.RECTS[i].shapes))
		while i <= #shapes.RECTS and table.concat(shapes.RECTS[i].shapes, " ") == set do
			out[#out + 1] = "  " .. rect(n, shapes.RECTS[i], g, d)
			i = i + 1
		end
		out[#out + 1] = "</g>"
	end

	local plus_g = g ~= "0" and ("+" .. g) or ""
	local minus_g = g ~= "0" and ("-" .. g) or ""
	-- Circle centre in SVG coordinates: (c + d, 1 - c + d), d scaled.
	local shift = d ~= "0" and ("+" .. S .. "*" .. d) or ""
	local cx = n.C .. shift
	local cy = "1-" .. n.C .. shift

	-- The circle line, a stroked circle between the inner and outer radius (shapes.parts).
	local r_out = S .. "*(" .. H .. "+" .. G .. "+8" .. plus_g .. ")"
	local r_in = "max(" .. S .. "*(" .. H .. "+" .. G .. "+8-" .. T .. minus_g .. "),0)"
	out[#out + 1] = string.format('<circle data-if="%s" cx="%s" cy="%s" r="%s" stroke-width="%s" fill="none" stroke="%s" stroke-opacity="%s"/>',
		shape_in(n, { "circle", "circle_dot", "circle_cross" }), E(cx), E(cy),
		E("(" .. r_in .. "+" .. r_out .. ")/2"), E(r_out .. "-" .. r_in), E(color), E(opacity))

	-- The dot.
	out[#out + 1] = string.format('<circle data-if="%s" cx="%s" cy="%s" r="%s"/>',
		shape_in(n, { "cross_dot", "dot", "circle_dot" }), E(cx), E(cy), E(S .. "*(" .. T .. plus_g .. ")"))

	-- The chevron: two quads meeting on the vertical line through the centre (shapes.chevron_quads).
	local apex = "(0-" .. S .. "*(" .. H .. "+" .. G .. "+" .. T .. "*" .. SQ .. "))"
	local k = "(" .. S .. "*(" .. T .. (g ~= "0" and ("+2*" .. g) or "") .. ")*" .. SQ .. ")"
	local a = "(" .. S .. "*(8" .. plus_g .. ")*" .. SQ .. ")"
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

local function layer(n, role, cond, g, d, color, opacity)
	local lines = {}
	lines[#lines + 1] = string.format('    <g data-role="%s"%s fill="%s" fill-opacity="%s">', role,
		cond and string.format(' data-if="%s"', cond) or "", E(color), E(opacity))
	for _, el in ipairs(parts(n, g, d, color, opacity)) do lines[#lines + 1] = "      " .. el end
	lines[#lines + 1] = "    </g>"
	return table.concat(lines, "\n")
end

-- The whole template of one state: "idle" or "aim".
function M.build(p)
	local n = names(p)
	local o = n.o
	local edge = "(" .. o("outline") .. "?" .. o("outline_thickness") .. ":0)"
	local drawn = n.shape .. "!='game'?" .. n.shape .. "!='none':0"
	-- About how far the crosshair reaches from the centre, for the magnification.
	local extent = "((" .. o("gap") .. "+8+" .. o("thickness") .. "+" .. edge .. "+(" .. o("shadow") .. "?" .. o("shadow_offset") .. ":0))*" .. n.S .. "+1)"
	local zoom = "clamp(floor(54/" .. extent .. "),1,4)"
	local lines = {
		'<svg xmlns="http://www.w3.org/2000/svg" width="240" height="140" viewBox="0 0 240 140">',
		'  <rect x="0" y="0" width="240" height="140" fill="#808080"/>',
		string.format('  <g id="%s_crosshair" transform="translate(60 70)" shape-rendering="crispEdges" data-if="%s">', p, drawn),
		layer(n, "shadow", o("shadow"), edge, o("shadow_offset"), o("shadow_color"), o("shadow_opacity") .. "*" .. o("opacity")),
		layer(n, "outline", o("outline"), o("outline_thickness"), "0", o("outline_color"), o("opacity")),
		layer(n, "fill", nil, "0", "0", o("color"), o("opacity")),
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

M.FILES = { idle = "preview/idle.svg", aim = "preview/aim.svg" }

-- Run as a script: write both files.
if arg and arg[0] and arg[0]:find("build_previews", 1, true) then
	for _, p in ipairs({ "idle", "aim" }) do
		local f = assert(io.open(M.FILES[p], "wb"))
		f:write(M.build(p))
		f:close()
		print("wrote " .. M.FILES[p])
	end
end

return M

-- src/hitmarker.lua: the settings, the four lines around the centre, the outline and the fade.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local hitmarker = dofile("src/hitmarker.lua")

local function settings(over)
	local s = {}
	for k, v in pairs(hitmarker.DEFAULTS) do s[k] = v end
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function dist(x0, y0, x1, y1) return math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) end

local function centroid(pts)
	local x, y = 0, 0
	for i = 1, #pts, 2 do x, y = x + pts[i], y + pts[i + 1] end
	return x / (#pts / 2), y / (#pts / 2)
end

test("settings_fill_in_defaults_and_refuse_wrong_types", function()
	local values = { hitmarker_size = 12, hitmarker_gap = "wide", hitmarker_kills = false, hitmarker_from = "all" }
	local s = hitmarker.settings(function(id) return values[id] end)
	eq(s.size, 12, "given")
	eq(s.gap, hitmarker.DEFAULTS.gap, "wrong type")
	eq(s.kills, false, "false is a value")
	eq(s.from, "all", "choice")
	eq(s.color, hitmarker.DEFAULTS.color, "missing")
	eq(hitmarker.settings(nil).time, hitmarker.DEFAULTS.time, "no values")
end)

test("shown_needs_the_toggle_and_hits_or_kills", function()
	eq(hitmarker.shown(settings()), true, "defaults")
	eq(hitmarker.shown(settings({ on = false })), false, "off")
	eq(hitmarker.shown(settings({ hits = false })), true, "kills only")
	eq(hitmarker.shown(settings({ kills = false })), true, "hits only")
	eq(hitmarker.shown(settings({ hits = false, kills = false })), false, "neither")
end)

test("four_lines_on_the_diagonals_from_the_gap_out", function()
	local s = settings({ gap = 6, size = 8, thickness = 2 })
	local quads = hitmarker.quads(s, 0.5, 0)
	eq(#quads, 4, "lines")
	for i, q in ipairs(quads) do
		eq(#q, 8, i .. " corners")
		-- A rectangle: size long, thickness wide.
		near(dist(q[1], q[2], q[3], q[4]), 8, i .. " length")
		near(dist(q[3], q[4], q[5], q[6]), 2, i .. " width")
		near(dist(q[5], q[6], q[7], q[8]), 8, i .. " length, far side")
		near(dist(q[7], q[8], q[1], q[2]), 2, i .. " width, inner end")
		-- The middle of the inner end sits `gap` out from the centre, on the diagonal.
		local mx, my = (q[1] + q[7]) / 2, (q[2] + q[8]) / 2
		near(dist(0.5, 0.5, mx, my), 6, i .. " gap")
		near(math.abs(mx - 0.5), math.abs(my - 0.5), i .. " on the diagonal")
		local cx, cy = centroid(q)
		near(dist(0.5, 0.5, cx, cy), 6 + 8 / 2, i .. " middle of the line")
		local d = hitmarker.ARMS[i]
		eq((cx - 0.5) * d[1] > 0 and (cy - 0.5) * d[2] > 0, true, i .. " in the right corner")
	end
end)

test("the_lines_turn_by_a_quarter_round_the_centre", function()
	local quads = hitmarker.quads(settings({ gap = 3, size = 5, thickness = 1.5 }), 0, 0)
	for i = 1, 4 do
		local a, b = quads[i], quads[i % 4 + 1]
		for j = 1, 8, 2 do
			-- (x, y) turned a quarter counterclockwise is (-y, x).
			near(b[j], -a[j + 1], "line " .. i .. " x " .. j)
			near(b[j + 1], a[j], "line " .. i .. " y " .. j)
		end
	end
end)

test("the_outline_grows_each_line_by_a_pixel_all_round", function()
	local s = settings({ gap = 6, size = 6, thickness = 2 })
	local plain, grown = hitmarker.quads(s, 0, 0), hitmarker.quads(s, 0, hitmarker.OUTLINE)
	for i = 1, 4 do
		local p, g = plain[i], grown[i]
		near(dist(g[1], g[2], g[3], g[4]), 6 + 2, i .. " longer by a pixel each end")
		near(dist(g[3], g[4], g[5], g[6]), 2 + 2, i .. " wider by a pixel each side")
		local px, py = centroid(p)
		local gx, gy = centroid(g)
		near(gx, px, i .. " same middle x")
		near(gy, py, i .. " same middle y")
	end
end)

test("layers_put_the_outline_behind_in_black", function()
	local layers = hitmarker.layers(settings(), "hit", 0)
	eq(#layers, 2, "outline and lines")
	eq(layers[1].role, "outline", "back")
	eq(layers[1].hex, "#000000", "black")
	eq(layers[2].role, "fill", "front")
	eq(layers[2].hex, hitmarker.DEFAULTS.color, "hit color")
	eq(#layers[2].items, 4, "four lines")
	eq(layers[2].items[1].kind, "poly", "polygons")
	eq(hitmarker.layers(settings(), "kill", 0)[2].hex, hitmarker.DEFAULTS.kill_color, "kill color")
	local plain = hitmarker.layers(settings({ outline = false }), "hit", 0)
	eq(#plain, 1, "no outline")
	eq(plain[1].role, "fill", "lines only")
end)

test("a_mark_fades_in_a_straight_line", function()
	eq(hitmarker.fade(0, 0.4), 1, "full at once")
	near(hitmarker.fade(0.1, 0.4), 0.75, "a quarter in")
	near(hitmarker.fade(0.3, 0.4), 0.25, "three quarters in")
	eq(hitmarker.fade(0.4, 0.4), 0, "gone at the end")
	eq(hitmarker.fade(1, 0.4), 0, "gone after")
	eq(hitmarker.fade(-0.1, 0.4), 0, "nothing before")
end)

test("tpc_red_is_the_default_kill_color", function()
	-- The kill marker of Third Person Camera: Color(alpha, 255, 45, 35).
	eq(hitmarker.DEFAULTS.kill_color, "#ff2d23", "kill color")
	eq(hitmarker.DEFAULTS.time, 0.35, "fade time")
end)

return T

-- Hitmarker: four diagonal lines around the crosshair that flash when a shot from this player hurts or
-- kills an enemy, then fade out. Settings and geometry only, with no game calls, so the tests run it
-- offline and preview/hitmarker.svg (tools/build_previews.lua) draws the same polygons. main.lua
-- listens for the hits and draws.
--
-- Coordinates are pixels with y up, as obsidian.ui.canvas draws, relative to the pixel under the aim
-- point, which spans 0 to 1 on both axes. The lines are polygons, so they are not rounded to pixels.
local M = {}

M.SQRT_HALF = math.sqrt(0.5)

-- The outline: a border of this many pixels, in this color.
M.OUTLINE = 1
M.OUTLINE_COLOR = "#000000"

-- Where hits count from, in the order the options list them.
M.FROM = { "weapons", "all" }

-- Settings as obsidian.json declares them, and the option id of each. main.lua fills a missing value
-- from here, and tests/test_manifest.lua keeps the two the same.
M.DEFAULTS = {
	on = true, hits = true, kills = true, from = "weapons", color = "#ffffff", kill_color = "#ff2d23",
	size = 6, gap = 6, thickness = 2, time = 0.35, outline = true,
}
M.KEYS = { "on", "hits", "kills", "from", "color", "kill_color", "size", "gap", "thickness", "time", "outline" }
M.IDS = {
	on = "hitmarker", hits = "hitmarker_hits", kills = "hitmarker_kills", from = "hitmarker_from",
	color = "hitmarker_color", kill_color = "hitmarker_kill_color", size = "hitmarker_size", gap = "hitmarker_gap",
	thickness = "hitmarker_thickness", time = "hitmarker_time", outline = "hitmarker_outline",
}

-- The settings from get(id), the option values, with the defaults filling in what is missing or of the
-- wrong type.
function M.settings(get)
	local s = {}
	for _, key in ipairs(M.KEYS) do
		local d = M.DEFAULTS[key]
		local v = get and get(M.IDS[key])
		if v == nil or type(v) ~= type(d) then v = d end
		s[key] = v
	end
	return s
end

-- Whether anything shows: the hitmarker on, with hits or kills or both.
function M.shown(s)
	return s.on == true and (s.hits == true or s.kills == true)
end

-- The four lines from up and right round to down and right: x and y along each diagonal.
M.ARMS = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }

-- The four lines around the centre (c, c) of the aim pixel, each grown by `grow` pixels on every side:
-- quads { x1, y1, ..., x4, y4 }. A line runs along a diagonal from `gap` to `gap + size` pixels out
-- from the centre and is `thickness` wide.
function M.quads(s, c, grow)
	local q = M.SQRT_HALF
	local r0, r1 = s.gap - grow, s.gap + s.size + grow
	local h = s.thickness / 2 + grow
	local out = {}
	for i, d in ipairs(M.ARMS) do
		local sx, sy = d[1], d[2]
		local function x(r, t) return c + q * (sx * r - sy * t) end
		local function y(r, t) return c + q * (sy * r + sx * t) end
		out[i] = { x(r0, -h), y(r0, -h), x(r1, -h), y(r1, -h), x(r1, h), y(r1, h), x(r0, h), y(r0, h) }
	end
	return out
end

-- What one kind of mark ("hit" or "kill") draws, back to front:
--   { { role = "outline" | "fill", hex = "#rrggbb", items = { { kind = "poly", pts }, ... } }, ... }
function M.layers(s, kind, c)
	local out = {}
	local function layer(role, grow, hex)
		local items = {}
		for i, pts in ipairs(M.quads(s, c, grow)) do items[i] = { kind = "poly", pts = pts } end
		out[#out + 1] = { role = role, hex = hex, items = items }
	end
	if s.outline then layer("outline", M.OUTLINE, M.OUTLINE_COLOR) end
	layer("fill", 0, kind == "kill" and s.kill_color or s.color)
	return out
end

-- How strong a mark `age` seconds old shows: 1 at once, falling in a straight line to 0 at `time`.
function M.fade(age, time)
	if age < 0 or age >= time then return 0 end
	return 1 - age / time
end

return M

-- src/spin.lua: the laser spin, and the spread read from the shots counted.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local spin = dofile("src/spin.lua")
local shapes = dofile("src/shapes.lua")

test("the_spin_reaches_a_turn_a_second_within_0.05_seconds", function()
	local s = spin.new()
	spin.step(s, true, 0.025)
	near(s.speed, 180, "half way up")
	spin.step(s, true, 0.025)
	near(s.speed, 360, "full spin")
	spin.step(s, true, 1)
	near(s.speed, 360, "no faster")
end)

test("the_spin_winds_down_in_about_half_a_second_and_rests_square", function()
	local s = spin.new()
	for _ = 1, 20 do spin.step(s, true, 0.0137) end
	local t = 0
	while s.speed > 0 and t < 2 do
		spin.step(s, false, 0.01)
		t = t + 0.01
	end
	eq(s.speed, 0, "stopped")
	assert(t > 0.2 and t < 0.8, "about half a second: " .. t)
	eq(s.angle, 0, "upright")
	local before = s.angle
	spin.step(s, false, 0.1)
	eq(s.angle, before, "stays at rest")
end)

test("a_t_rests_only_after_a_whole_turn", function()
	eq(spin.square_for("dot", "cross"), 90)
	eq(spin.square_for("dot", "t"), 360)
	local s = spin.new(360)
	for _ = 1, 20 do spin.step(s, true, 0.0137) end
	local start, gone = s.angle, 0
	while s.speed > 0 do
		local before = s.angle
		spin.step(s, false, 0.01)
		if s.speed > 0 then gone = gone + (s.angle - before) end
	end
	assert((start + gone) % 360 > 300 or (start + gone) % 360 < 60, "ends near a whole turn")
	eq(s.angle, 0)
end)

test("firing_again_while_winding_down_spins_up_again", function()
	local s = spin.new()
	for _ = 1, 10 do spin.step(s, true, 0.01) end
	spin.step(s, false, 0.1)
	assert(s.speed < 360 and s.speed > 0, "winding down")
	spin.step(s, true, 0.05)
	near(s.speed, 360, "back to full")
	eq(s.stop_at, nil, "no rest point while firing")
end)

test("turn_rotates_points_about_a_centre", function()
	local out = spin.turn({ 1, 0, 0, 1 }, 0, 0, 0, 1, {})
	near(out[1], 0) near(out[2], 1) near(out[3], -1) near(out[4], 0)
end)

test("spread_follows_the_shots_counted_as_they_decay", function()
	-- The game leaves spread at the last shot's value; the shots counted go down every frame.
	local st = { spread = 5, spread_min = 1, spread_max = 5, spread_shots_fired = 10, spread_shots_max = 10 }
	eq(shapes.spread_angle(st), 5, "right after a burst")
	st.spread_shots_fired = 5
	eq(shapes.spread_angle(st), 3, "half recovered, spread untouched")
	st.spread_shots_fired = -3
	eq(shapes.spread_angle(st), 1, "the game lets the count go below 0")
end)

return T

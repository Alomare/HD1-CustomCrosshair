-- The laser spin: while a laser weapon fires, the crosshair spins up to RATE degrees a second within
-- UP seconds; once firing stops it winds down over about DOWN seconds and comes to rest upright: on a
-- multiple of `square`, the turn that leaves the look the same (a quarter turn for a cross, a dot or a
-- circle, a whole turn for a T). At rest the angle counts as 0 again. Plain numbers only, so tests can
-- run it.
local M = {}

M.RATE = 360    -- degrees a second at full spin
M.UP = 0.05     -- seconds from rest to full spin
M.DOWN = 0.5    -- seconds from full spin to rest
M.SQUARE = 90   -- the default rest step

-- The shapes a quarter turn leaves the same.
M.QUARTER = { cross = true, cross_dot = true, dot = true, circle = true, circle_dot = true, circle_cross = true,
	none = true, game = true }

-- The rest step for the two looks: a quarter turn when both stay the same under it, else a whole turn.
function M.square_for(idle_shape, aim_shape)
	return (M.QUARTER[idle_shape] and M.QUARTER[aim_shape]) and 90 or 360
end

function M.new(square) return { angle = 0, speed = 0, stop_at = nil, brake = nil, square = square or M.SQUARE } end

-- Moves the spin on by dt seconds. firing: a laser weapon fires now. Answers the angle in degrees.
function M.step(s, firing, dt)
	dt = math.max(0, dt or 0)
	if firing then
		s.stop_at, s.brake = nil, nil
		s.speed = math.min(M.RATE, s.speed + M.RATE / M.UP * dt)
		s.angle = (s.angle + s.speed * dt) % 360
		return s.angle
	end
	if s.speed <= 0 then return s.angle end
	if not s.stop_at then
		-- The rest point nearest where the plain wind-down would end, never less than half of that way
		-- ahead, and the braking that ends there.
		local natural = M.RATE / M.DOWN
		local travel = s.speed * s.speed / (2 * natural)
		local sq = s.square
		local target = math.floor((s.angle + travel) / sq + 0.5) * sq
		if target - s.angle < travel * 0.5 then target = target + sq end
		local d = target - s.angle
		s.stop_at, s.brake = target, s.speed * s.speed / (2 * d)
	end
	local before = s.speed
	s.speed = math.max(0, s.speed - s.brake * dt)
	s.angle = s.angle + (before + s.speed) / 2 * dt
	if s.speed <= 0 or s.angle >= s.stop_at then
		-- Upright: the look at the rest point is the look at 0.
		s.speed, s.angle = 0, 0
		s.stop_at, s.brake = nil, nil
	end
	return s.angle
end

-- Turns the points of buf (x1, y1, x2, y2, ...) about (cx, cy) by c = cos, s = sin, into out.
function M.turn(pts, cx, cy, c, s, out)
	for j = 1, #pts, 2 do
		local dx, dy = pts[j] - cx, pts[j + 1] - cy
		out[j], out[j + 1] = cx + dx * c - dy * s, cy + dx * s + dy * c
	end
	return out
end

return M

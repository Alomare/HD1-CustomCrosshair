-- main.lua against stand-ins for the engine: which cursors go, where and how the crosshair is drawn,
-- Integrated Third Person, and the cursor flying back to the Helldiver.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local ITP = "alomare.integratedthirdperson"
local MOUSE = { x = 500, y = 300 }

local function setup(options)
	SET, BITMAPS = {}, {}
	MOUSE.x, MOUSE.y = 500, 300
	-- A long frame finishes every fade at once; one test below covers the fade.
	rawset(_G, "ENGINE_DT", 1)
	rawset(_G, "Window", { set_cursor = function(p) SET[#SET + 1] = p end })
	rawset(_G, "CursorManager", { shown = true, current_cursor = "hud/cursors/game", next_cursor = nil })
	rawset(_G, "Mouse", { axis_index = function(name) return name == "cursor" and 7 or nil end, axis = function(i) return i == 7 and MOUSE or nil end })
	rawset(_G, "Gui", { bitmap_uv = function(gui, material) BITMAPS[#BITMAPS + 1] = material end })
	rawset(_G, "InputComponent", {
		update_masters = function(self, fail)
			Gui.bitmap_uv("hud gui", "icon")
			Gui.bitmap_uv(self.cursor_gui, "cursor_game", { x = 0, y = 0 }, { x = 1, y = 1 }, { x = 84, y = 184 }, { x = 16, y = 16 }, "color")
			if fail then error("game error") end
			return "done"
		end,
	})
	for k, v in pairs(options or {}) do OPTIONS[k] = v end
	return dofile("main.lua")
end

local function hook(target, method)
	for _, h in ipairs(HOOKS) do
		if h.target == target and h.method == method then return h end
	end
	return nil
end

-- The game function, called through the hook the mod put on it.
local function through(target, method, ...)
	local h = assert(hook(target, method), target .. "." .. method .. " is hooked")
	return h.fn(rawget(_G, target)[method], ...)
end

local function frame()
	for _, f in ipairs(FRAMES) do f() end
end

local function startup()
	for _, f in ipairs(STARTUP) do f() end
end

local function kit() return KITS[1] end

local function rects_at(z)
	local out = {}
	for _, c in ipairs(kit().calls) do
		if c[1] == "rect" and (z == nil or c.z == z) then out[#out + 1] = c end
	end
	return out
end

local function has_rect(z, x, y, w, h)
	for _, c in ipairs(rects_at(z)) do
		if c[2] == x and c[3] == y and c[4] == w and c[5] == h then return c end
	end
	return nil
end

test("game_cursors_go_and_every_other_cursor_stays", function()
	setup()
	through("Window", "set_cursor", "hud/cursors/game")
	through("Window", "set_cursor", "hud/cursors/game_inactive_large")
	through("Window", "set_cursor", "hud/cursors/game_transition_03")
	through("Window", "set_cursor", "hud/cursors/menu")
	through("Window", "set_cursor", "hud/cursors/invisible")
	through("Window", "set_cursor", "")
	eq(table.concat(SET, " | "), "hud/cursors/invisible | hud/cursors/invisible_large | hud/cursors/invisible | hud/cursors/menu | hud/cursors/invisible | ", "cursors set")
end)

test("a_state_on_game_keeps_that_game_cursor", function()
	setup({ idle_shape = "game" })
	through("Window", "set_cursor", "hud/cursors/game_inactive")
	through("Window", "set_cursor", "hud/cursors/game")
	through("Window", "set_cursor", "hud/cursors/game_transition_01_large")
	eq(table.concat(SET, " | "), "hud/cursors/game_inactive | hud/cursors/invisible | hud/cursors/invisible_large", "cursors set")
	CursorManager.current_cursor = "hud/cursors/game_inactive"
	frame()
	eq(#kit().calls, 0, "nothing drawn over the game cursor")
end)

test("both_states_on_game_leave_the_game_alone", function()
	setup({ idle_shape = "game", aim_shape = "game" })
	eq(#HOOKS, 0, "hooks")
	eq(#FRAMES, 0, "frame functions")
	eq(#STARTUP, 0, "no claim on the third person crosshair")
end)

test("switched_off_does_nothing", function()
	setup({ enabled = false })
	eq(#HOOKS, 0, "hooks")
	eq(#FRAMES, 0, "frame functions")
	eq(#KITS, 0, "canvas")
end)

test("an_older_loader_without_a_canvas_leaves_the_cursor", function()
	obsidian.ui = nil
	setup()
	eq(#HOOKS, 0, "hooks")
	eq(LOGS[#LOGS]:find("no obsidian.ui canvas", 1, true) ~= nil, true, "logged")
end)

test("aiming_draws_the_aiming_look_at_the_mouse", function()
	setup()
	frame()
	-- Cross with dot, 2 thick, gap 4: the right arm runs from 5 to 13 past the pixel corner.
	local arm = has_rect(862, 505, 299, 8, 2)
	assert(arm, "right arm on the front layer")
	eq(arm.c[1] .. "," .. arm.c[4], "255,255", "white and solid")
	assert(has_rect(862, 487, 299, 8, 2), "left arm")
	assert(has_rect(862, 499, 305, 2, 8), "top arm")
	local edge = has_rect(861, 504, 298, 10, 4)
	assert(edge, "outline behind")
	eq(edge.c[1] .. "," .. edge.c[4], "0,255", "black outline")
	local dots = 0
	for _, c in ipairs(kit().calls) do
		if c[1] == "poly" then dots = dots + 1 end
	end
	eq(dots, 2, "dot and dot outline")
end)

test("between_shots_draws_the_idle_look", function()
	setup({ idle_shape = "cross", idle_thickness = 1, idle_gap = 4, idle_outline = false, idle_opacity = 0.6 })
	CursorManager.current_cursor = "hud/cursors/game_inactive"
	frame()
	local arm = has_rect(862, 505, 300, 8, 1)
	assert(arm, "idle right arm, 1 thick on the aim row")
	eq(arm.c[4], 153, "idle opacity")
	eq(#rects_at(), 4, "four arms, no outline")
end)

test("a_transition_draws_the_look_it_heads_for", function()
	setup({ idle_shape = "cross", idle_outline = false })
	CursorManager.next_cursor = "hud/cursors/game_inactive"
	frame()
	eq(#rects_at(861), 0, "no aiming outline")
	eq(#rects_at(862), 4, "idle arms")
end)

test("idle_and_aiming_fade_into_each_other", function()
	setup({ idle_shape = "cross", idle_thickness = 1, idle_outline = false })
	rawset(_G, "ENGINE_DT", 0.02)
	frame()
	local aim = has_rect(862, 505, 299, 8, 2)
	assert(aim, "aiming look at once on the first frame")
	eq(aim.alpha, 1, "full strength")
	CursorManager.current_cursor = "hud/cursors/game_inactive"
	kit().calls = {}
	frame()
	-- 0.02 of 0.08 seconds: a quarter of the way to idle.
	local idle = has_rect(862, 505, 300, 8, 1)
	aim = has_rect(862, 505, 299, 8, 2)
	assert(idle and aim, "both looks while they cross")
	near(idle.alpha, 0.25, "idle fading in")
	near(aim.alpha, 0.75, "aiming fading out")
	eq(kit().alpha, 1, "opacity back")
	for _ = 1, 3 do frame() end
	kit().calls = {}
	frame()
	eq(has_rect(862, 505, 299, 8, 2), nil, "aiming look gone")
	eq(has_rect(862, 505, 300, 8, 1).alpha, 1, "idle at full strength")
	CursorManager.current_cursor = "hud/cursors/menu"
	frame()
	CursorManager.current_cursor = "hud/cursors/game"
	kit().calls = {}
	frame()
	eq(has_rect(862, 505, 299, 8, 2).alpha, 1, "after a menu the look comes back at once")
end)

test("menus_the_map_and_a_hidden_cursor_draw_nothing", function()
	setup()
	CursorManager.current_cursor = "hud/cursors/menu"
	frame()
	CursorManager.current_cursor = "hud/cursors/game"
	CursorManager.shown = false
	frame()
	eq(#kit().calls, 0, "nothing drawn")
end)

test("third_person_claims_the_crosshair_and_draws_at_the_aim_point", function()
	local claimed
	local spot = { x = 960.7, y = 540.2, aiming = true }
	IMPORTS[ITP] = { claim_crosshair = function(id) claimed = id return true end, crosshair = function() return spot end }
	setup()
	eq(claimed, nil, "not before every mod has started")
	startup()
	eq(claimed, "alomare.customcrosshair", "claimed by id")
	CursorManager.shown = false
	frame()
	assert(has_rect(862, 965, 539, 8, 2), "right arm at the aim point")
	spot.aiming = false
	kit().calls = {}
	frame()
	eq(#rects_at(862), 0, "the idle circle has no rects")
	eq(#kit().calls > 0, true, "idle look drawn")
	CursorManager.shown, CursorManager.current_cursor = true, "hud/cursors/menu"
	kit().calls = {}
	frame()
	eq(#kit().calls, 0, "hidden while the menu cursor shows")
end)

test("third_person_falls_back_to_the_mouse_when_the_view_is_top_down", function()
	IMPORTS[ITP] = { claim_crosshair = function() end, crosshair = function() return nil end }
	setup()
	startup()
	frame()
	assert(has_rect(862, 505, 299, 8, 2), "at the mouse")
end)

test("third_person_off_leaves_that_mod_alone", function()
	local claimed = false
	IMPORTS[ITP] = { claim_crosshair = function() claimed = true end, crosshair = function() return { x = 10, y = 10, aiming = true } end }
	setup({ third_person = false })
	startup()
	frame()
	eq(claimed, false, "no claim")
	assert(has_rect(862, 505, 299, 8, 2), "at the mouse")
end)

test("a_state_on_game_takes_the_default_look_in_third_person", function()
	IMPORTS[ITP] = { claim_crosshair = function() end, crosshair = function() return { x = 100, y = 100, aiming = true } end }
	setup({ aim_shape = "game", idle_shape = "dot" })
	startup()
	frame()
	assert(has_rect(862, 105, 99, 8, 2), "default cross with dot")
end)

test("the_cursor_flying_back_is_caught_and_drawn_shrinking", function()
	setup()
	local real = Gui.bitmap_uv
	local self = { cursor_gui = "cursor gui" }
	eq(through("InputComponent", "update_masters", self), "done", "the game function answers")
	eq(table.concat(BITMAPS, " "), "icon", "only the game cursor image is held back")
	eq(Gui.bitmap_uv, real, "Gui.bitmap_uv put back")
	CursorManager.shown = false
	frame()
	-- Half size (16 of 32 pixels), centred on (92, 192), at a quarter strength.
	local arm = has_rect(862, 95, 192, 4, 1)
	assert(arm, "half-size right arm")
	eq(arm.alpha, 0.25, "faded by the square of the size")
	eq(kit().alpha, 1, "opacity back")
	kit().calls = {}
	frame()
	eq(#kit().calls, 0, "once per catch")
end)

test("a_failing_input_update_still_puts_gui_back", function()
	setup()
	local real = Gui.bitmap_uv
	local ok, err = pcall(through, "InputComponent", "update_masters", { cursor_gui = "g" }, true)
	eq(ok, false, "the error goes on")
	eq(tostring(err):find("game error", 1, true) ~= nil, true, "same error")
	eq(Gui.bitmap_uv, real, "Gui.bitmap_uv put back")
end)

test("the_game_cursor_image_stays_when_aiming_keeps_the_game_cursor", function()
	setup({ aim_shape = "game" })
	eq(hook("InputComponent", "update_masters"), nil, "input code left alone")
end)

test("drawing_a_frame_makes_no_tables", function()
	setup({ aim_shape = "circle_cross", aim_shadow = true })
	local k = kit()
	k.rect, k.poly, k.layer, k.opacity = function() end, function() end, function() end, function() end
	frame()
	jit.off()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 500 do frame() end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	jit.on()
	eq(grew < 1, true, "KB allocated over 500 frames: " .. grew)
end)

return T

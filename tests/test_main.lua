-- main.lua against stand-ins for the engine: which cursors go, where and how the crosshair is drawn,
-- Integrated Third Person, and the cursor flying back to the Helldiver.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local ITP = "alomare.integratedthirdperson"
local MOUSE = { x = 500, y = 300 }

-- The look of 0.4.0, which the tests below measure against: the defaults since 0.5.0 differ.
local LOOK = {
	idle_shape = "circle", idle_gap = 4, idle_thickness = 1, idle_opacity = 0.6, idle_outline = true,
	aim_shape = "cross_dot", aim_gap = 4, aim_thickness = 2, aim_opacity = 1, aim_outline = true, aim_outline_thickness = 1,
	aim_shadow = false, aim_shadow_opacity = 0.5, aim_shadow_offset = 2, aim_shadow_blur = 0,
	hitmarker_color = "#ff2d23", hitmarker_kill_color = "#ff2d23", hitmarker_opacity = 0.6, hitmarker_kill_scale = 1.5,
	hitmarker_outline = true,
}

local function setup(options, defaults)
	SET, BITMAPS = {}, {}
	if not defaults then
		for k, v in pairs(LOOK) do if OPTIONS[k] == nil then OPTIONS[k] = v end end
	end
	MOUSE.x, MOUSE.y = 500, 300
	-- A long frame finishes every fade at once; one test below covers the fade.
	rawset(_G, "ENGINE_DT", 1)
	rawset(_G, "Window", { set_cursor = function(p) SET[#SET + 1] = p end })
	-- As in cursor_manager.lua: every method sets the cursor through one shared local function.
	local function set_hardware(path, large) Window.set_cursor(path .. (large and "_large" or "")) end
	rawset(_G, "CursorManager", {
		shown = true, current_cursor = "hud/cursors/game", next_cursor = nil, use_large_cursor = false,
		set_cursor = function(self, path)
			self.current_cursor = path
			set_hardware(path, self.use_large_cursor)
		end,
		set_use_large_cursor = function(self, large)
			self.use_large_cursor = large
			set_hardware(self.current_cursor, large)
		end,
	})
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

test("cursor_manager_sets_the_invisible_cursor_for_covered_game_cursors", function()
	setup()
	frame()
	eq(#SET, 0, "a frame sets no cursor")
	CursorManager:set_cursor("hud/cursors/game")
	CursorManager:set_cursor("hud/cursors/game_transition_02")
	CursorManager:set_use_large_cursor(true)
	CursorManager:set_cursor("hud/cursors/game_inactive")
	CursorManager:set_cursor("hud/cursors/menu")
	CursorManager:set_cursor("hud/cursors/invisible")
	eq(table.concat(SET, " | "), "hud/cursors/invisible | hud/cursors/invisible | hud/cursors/invisible_large | hud/cursors/invisible_large | hud/cursors/menu_large | hud/cursors/invisible_large", "cursors set")
	frame()
	frame()
	local logged = 0
	for _, l in ipairs(LOGS) do
		if l:find("swapped inside CursorManager", 1, true) then logged = logged + 1 end
	end
	eq(logged, 1, "swapped once")
end)

test("a_state_on_game_keeps_that_cursor_in_cursor_manager", function()
	setup({ aim_shape = "game" })
	frame()
	CursorManager:set_cursor("hud/cursors/game")
	CursorManager:set_cursor("hud/cursors/game_inactive")
	eq(table.concat(SET, " | "), "hud/cursors/game | hud/cursors/invisible", "cursors set")
end)

test("a_cursor_manager_it_cannot_read_is_left_alone", function()
	setup()
	CursorManager.set_use_large_cursor = function(self, large) self.use_large_cursor = large end
	frame()
	CursorManager:set_cursor("hud/cursors/game")
	eq(table.concat(SET, " | "), "hud/cursors/game", "game cursor stays")
	eq(LOGS[#LOGS]:find("holds no function", 1, true) ~= nil, true, "logged")
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
	-- The default aiming cross: 3 thick, gap 2, so the right arm starts 4 out from the aim pixel.
	assert(has_rect(862, 104, 99, 8, 3), "default cross")
end)

test("third_person_shows_the_aiming_look_while_firing", function()
	local spot = { x = 960.7, y = 540.2, aiming = false, firing = true }
	IMPORTS[ITP] = { claim_crosshair = function() return true end, crosshair = function() return spot end }
	setup()
	startup()
	CursorManager.shown = false
	frame()
	assert(has_rect(862, 965, 539, 8, 2), "aiming cross while fire is held")
	spot.firing = false
	kit().calls = {}
	frame()
	eq(#rects_at(862), 0, "idle circle once fire is let go")
	-- Integrated Third Person before 0.4.2 sends no firing at all.
	spot.firing = nil
	kit().calls = {}
	frame()
	eq(#rects_at(862), 0, "idle without the field")
end)

test("the_defaults_draw_the_default_look", function()
	setup({}, true)
	frame()
	-- Cross 3 thick, gap 2, 8 long, at 0.95, with a thin outline and a soft shadow behind.
	local arm = has_rect(862, 504, 299, 8, 3)
	assert(arm, "right arm")
	eq(arm.c[4], 242, "0.95 opacity")
	assert(#rects_at(861) == 4, "outline")
	eq(#rects_at(860), 4 * (1 + 24), "the shadow and three rings of eight copies")
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
	setup({ aim_shape = "circle_cross", aim_shadow = true, aim_shadow_blur = 3, aim_shadow_size = 1.2, aim_shadow_spread = 1 })
	local k = kit()
	k.rect, k.poly, k.layer, k.opacity = function() end, function() end, function() end, function() end
	Window.set_cursor = function() end
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

test("blur_copies_draw_behind_the_crosshair_on_the_shadow_layer", function()
	setup({ aim_shape = "cross", aim_outline = false, aim_shadow = true, aim_shadow_offset = 1, aim_shadow_blur = 1 })
	frame()
	-- Right arm 8 x 2 from (505, 299); the shadow one pixel down and to the right, copies a pixel round that.
	local shadow = has_rect(860, 506, 298, 8, 2)
	assert(shadow, "shadow")
	eq(shadow.c[4], 128, "shadow at half strength")
	local copy = has_rect(860, 507, 298, 8, 2)
	assert(copy, "a copy a pixel to the right")
	eq(copy.c[4], math.floor(0.5 / 6 * 255 + 0.5), "a sixth of the shadow")
	eq(#rects_at(860), 4 * 9, "the shadow and eight copies of each arm")
end)

-- Obsidian API ------------------------------------------------------------------------------------

local ME, MATE, BUG, ROCK = "my avatar", "teammate", "bug", "rock"
local RIFLE, GRENADE = "rifle", "grenade"

-- A stand-in for Obsidian API: hit and kill listeners kept for the tests to call, my_unit, and the
-- inventory of this player.
local function fake_api()
	local api = { listeners = { hit = {}, kill = {} } }
	-- As the game's states: tables that live on, not made for each call.
	api.inventory = { primary_weapon = RIFLE, current_weapon = RIFLE }
	api.firearm = { spread = 1, spread_min = 1, spread_max = 5 }
	api.game = {
		my_unit = function() return ME end,
		master = function(unit, component)
			if unit == ME and component == "inventory" then return api.inventory end
			if unit == RIFLE and component == "firearm" then return api.firearm end
			return nil
		end,
	}
	api.combat = { on_hit = function(fn) api.listeners.hit[#api.listeners.hit + 1] = fn return true end }
	api.events = {
		on = function(name, fn)
			if name ~= "on_enemy_killed" then return false, "unexpected" end
			api.listeners.kill[#api.listeners.kill + 1] = fn
			return true
		end,
	}
	function api.hit(victim, hit) for _, fn in ipairs(api.listeners.hit) do fn(victim, hit) end end
	function api.kill(victim, attacker, owner) for _, fn in ipairs(api.listeners.kill) do fn(victim, attacker, owner) end end
	return api
end

local function with_api(options)
	local api = fake_api()
	IMPORTS["obsidian.api"] = api
	rawset(_G, "EntityAux", { has_component = function(unit, name) return name == "enemy" and (unit == BUG) end })
	setup(options)
	return api
end

local function polys_at(z)
	local out = {}
	for _, c in ipairs(kit().calls) do
		if c[1] == "poly" and c.z == z then out[#out + 1] = c end
	end
	return out
end

local function centre_of(pts)
	local x, y = 0, 0
	for i = 1, #pts, 2 do x, y = x + pts[i], y + pts[i + 1] end
	return x / (#pts / 2), y / (#pts / 2)
end

local RIFLE_HIT = { damage = 10, owner_unit = ME, attacker_unit = RIFLE, slot = "primary_weapon" }

test("a_hit_by_this_player_flashes_four_lines_round_the_crosshair", function()
	local api = with_api({ aim_shape = "cross", aim_outline = false })
	frame()
	eq(#polys_at(864), 0, "nothing before a hit")
	api.hit(BUG, RIFLE_HIT)
	kit().calls = {}
	frame()
	local lines = polys_at(864)
	eq(#lines, 4, "four lines in front")
	eq(#polys_at(863), 4, "outlines behind")
	for _, l in ipairs(lines) do
		eq(l.c[1] .. "," .. l.c[2] .. "," .. l.c[3] .. "," .. l.c[4], "255,45,35,255", "red")
		near(l.alpha, 0.6, "hit opacity on the first frame")
		-- The aiming cross is 2 thick: the centre sits on the corner of pixel (500, 300).
		local x, y = centre_of(l[2])
		near(math.sqrt((x - 500) ^ 2 + (y - 300) ^ 2), 6 + 12 / 2, "middle of a line from the centre", 1e-9)
		near(math.abs(x - 500), math.abs(y - 300), "on a diagonal", 1e-9)
	end
	eq(polys_at(863)[1].c[1] .. "," .. polys_at(863)[1].c[4], "0,255", "black outline")
	eq(kit().alpha, 1, "opacity back")
end)

test("the_mark_fades_out_over_the_time_set", function()
	local api = with_api({ hitmarker_time = 0.4, hitmarker_opacity = 1 })
	rawset(_G, "ENGINE_DT", 0.1)
	api.hit(BUG, RIFLE_HIT)
	local strength = {}
	for i = 1, 5 do
		kit().calls = {}
		frame()
		local lines = polys_at(864)
		strength[i] = #lines > 0 and lines[1].alpha or 0
	end
	near(strength[1], 1, "at once")
	near(strength[2], 0.75, "a tenth of a second in")
	near(strength[4], 0.25, "three tenths in")
	near(strength[5], 0, "gone after the time", 1e-9)
	api.hit(BUG, RIFLE_HIT)
	kit().calls = {}
	frame()
	near(polys_at(864)[1].alpha, 1, "a new hit starts again")
end)

test("hits_by_others_on_players_or_off_target_show_nothing", function()
	local api = with_api()
	api.hit(BUG, { damage = 10, owner_unit = MATE, attacker_unit = "their rifle", slot = "primary_weapon" })
	api.hit(MATE, RIFLE_HIT)
	api.hit(ROCK, RIFLE_HIT)
	api.hit(BUG, { damage = 10, owner_unit = ME, attacker_unit = GRENADE })
	frame()
	eq(#polys_at(864), 0, "no mark: a teammate, a teammate hit, not an enemy, a grenade with weapons in hand only")
end)

test("everything_counts_grenades_and_sentries_too", function()
	local api = with_api({ hitmarker_from = "all" })
	api.hit(BUG, { damage = 10, owner_unit = MATE, attacker_unit = GRENADE })
	frame()
	eq(#polys_at(864), 0, "still only this player")
	api.hit(BUG, { damage = 10, owner_unit = ME, attacker_unit = GRENADE })
	frame()
	eq(#polys_at(864), 4, "grenade hit")
end)

test("a_kill_shows_the_kill_color_over_a_hit", function()
	local api = with_api({ hitmarker_kill_color = "#3050ff" })
	api.hit(BUG, RIFLE_HIT)
	api.kill(BUG, RIFLE, ME)
	frame()
	local lines = polys_at(864)
	eq(#lines, 4, "one mark")
	eq(lines[1].c[1] .. "," .. lines[1].c[2] .. "," .. lines[1].c[3], "48,80,255", "kill color")
	near(lines[1].alpha, 1, "a kill shows solid")
	for _, l in ipairs(lines) do
		local x, y = centre_of(l[2])
		near(math.sqrt((x - 500) ^ 2 + (y - 300) ^ 2), (6 + 12 / 2) * 1.5, "half again as far out", 1e-9)
	end
	-- The thickness grows with it: a line is 3 pixels wide.
	local p = lines[1][2]
	near(math.sqrt((p[7] - p[1]) ^ 2 + (p[8] - p[2]) ^ 2), 3, "kill line width", 1e-9)
end)

test("kills_by_others_or_from_other_things_show_nothing", function()
	local api = with_api()
	api.kill(BUG, "their rifle", MATE)
	api.kill(BUG, GRENADE, ME)
	frame()
	eq(#polys_at(864), 0, "a teammate kill, a grenade kill with weapons in hand only")
	fresh_obsidian()
	local all = with_api({ hitmarker_from = "all" })
	all.kill(BUG, GRENADE, ME)
	frame()
	eq(#polys_at(864), 4, "the grenade kill counts with everything")
	eq(polys_at(864)[1].c[2], 45, "TPC red")
end)

test("hits_only_or_kills_only_listen_to_one", function()
	local api = with_api({ hitmarker_kills = false })
	eq(#api.listeners.hit, 1, "hits")
	eq(#api.listeners.kill, 0, "no kills")
	fresh_obsidian()
	api = with_api({ hitmarker_hits = false })
	eq(#api.listeners.hit, 0, "no hits")
	eq(#api.listeners.kill, 1, "kills")
end)

test("hitmarker_off_listens_to_nothing", function()
	for _, options in ipairs({ { hitmarker = false }, { hitmarker_hits = false, hitmarker_kills = false } }) do
		fresh_obsidian()
		local api = with_api(options)
		eq(#api.listeners.hit + #api.listeners.kill, 0, "no listeners")
		frame()
		eq(#polys_at(863) + #polys_at(864), 0, "nothing drawn")
	end
	fresh_obsidian()
	local api = with_api({ hitmarker = false, idle_shape = "game", aim_shape = "game" })
	eq(#FRAMES, 0, "with both states on the game cursor, no frame function either")
	eq(#api.listeners.hit, 0, "no listeners")
end)

test("without_obsidian_api_the_crosshair_still_draws", function()
	setup()
	local said = false
	for _, l in ipairs(LOGS) do said = said or l:find("needs Obsidian API", 1, true) ~= nil end
	eq(said, true, "logged")
	frame()
	assert(has_rect(862, 505, 299, 8, 2), "crosshair at the mouse")
end)

test("both_states_on_game_still_flash_the_mark_at_the_mouse", function()
	local claimed = false
	IMPORTS["alomare.integratedthirdperson"] = { claim_crosshair = function() claimed = true end, crosshair = function() return nil end }
	local api = with_api({ idle_shape = "game", aim_shape = "game" })
	eq(#HOOKS, 0, "game cursors left alone")
	startup()
	eq(claimed, false, "Integrated Third Person keeps the built-in crosshair")
	api.hit(BUG, RIFLE_HIT)
	frame()
	eq(#rects_at(), 0, "no crosshair")
	local lines = polys_at(864)
	eq(#lines, 4, "the mark")
	local x, y = centre_of(lines[1][2])
	eq(x > 500 and y > 300, true, "round the mouse")
end)

test("in_third_person_the_mark_goes_round_the_aim_point", function()
	local spot = { x = 960, y = 540, aiming = true }
	IMPORTS["alomare.integratedthirdperson"] = { claim_crosshair = function() end, crosshair = function() return spot end }
	local api = with_api({ hitmarker_gap = 4, hitmarker_size = 4 })
	startup()
	CursorManager.shown = false
	api.hit(BUG, RIFLE_HIT)
	frame()
	local lines = polys_at(864)
	eq(#lines, 4, "the mark")
	for _, l in ipairs(lines) do
		local x, y = centre_of(l[2])
		near(math.sqrt((x - 960) ^ 2 + (y - 540) ^ 2), 6, "round the aim point", 1e-9)
	end
	CursorManager.shown, CursorManager.current_cursor = true, "hud/cursors/menu"
	kit().calls = {}
	frame()
	eq(#polys_at(864), 0, "hidden under a menu")
end)

test("the_aiming_gap_opens_with_the_spread_of_the_weapon_in_hand", function()
	local shapes = obsidian.module("src/shapes")
	local api = with_api({})
	frame()
	assert(has_rect(862, 505, 299, 8, 2), "no spread: the gap set")
	api.firearm.spread = 5
	kit().calls = {}
	frame()
	assert(has_rect(862, 505 + shapes.SPREAD_GAP, 299, 8, 2), "the most spread: the gap opens all the way")
	api.firearm.spread = 3
	kit().calls = {}
	frame()
	assert(has_rect(862, 505 + shapes.SPREAD_GAP / 2, 299, 8, 2), "half way")
	api.firearm.spread = 1
	with_api({ aim_gap_spread = false })
	api = IMPORTS["obsidian.api"]
	api.firearm.spread = 5
	kit().calls = {}
	frame()
	assert(has_rect(862, 505, 299, 8, 2), "option off: the gap stays")
end)

test("the_mark_sits_on_the_centre_of_an_odd_crosshair", function()
	local api = with_api({ aim_thickness = 1 })
	api.hit(BUG, RIFLE_HIT)
	frame()
	-- Thickness 1: the centre is the middle of pixel (500, 300).
	local x, y = centre_of(polys_at(864)[1][2])
	near(math.abs(x - 500.5), math.abs(y - 300.5), "on a diagonal through the pixel middle", 1e-9)
end)

test("a_frame_with_a_mark_up_makes_no_tables", function()
	local api = with_api({ aim_shadow = true, hitmarker_time = 1.5 })
	rawset(_G, "ENGINE_DT", 0.001)
	local k = kit()
	k.rect, k.poly, k.layer, k.opacity = function() end, function() end, function() end, function() end
	Window.set_cursor = function() end
	api.hit(BUG, RIFLE_HIT)
	api.kill(BUG, RIFLE, ME)
	frame()
	jit.off()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for i = 1, 500 do
		if i % 50 == 0 then api.hit(BUG, RIFLE_HIT) end
		frame()
	end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	jit.on()
	eq(grew < 1, true, "KB allocated over 500 frames: " .. grew)
end)

return T

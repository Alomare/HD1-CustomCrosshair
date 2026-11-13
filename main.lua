-- Custom Crosshair: the aim cursor of the game replaced with a crosshair drawn from shapes, one look
-- between shots (idle) and one while aiming, set in the Options tab of the mod in Obsidian, and a
-- hitmarker that flashes around the crosshair on hits and kills.
--
-- The game shows the aim cursor as a hardware cursor: CursorManager hands a path to
-- Window.set_cursor, "hud/cursors/game" while aiming, "game_inactive" between shots, five
-- "game_transition_0N" frames from one to the other, "menu" in menus, and "invisible" to hide it, each
-- with "_large" after it when the large cursor is on. A hook on Window.set_cursor swaps the game
-- cursor of each state whose shape isn't "game" for the invisible one, and leaves every other cursor
-- alone. Every frame the crosshair is drawn with obsidian.ui.canvas at the mouse, in the look of the
-- state CursorManager asked for. With Integrated Third Person steering the view, it is drawn where that
-- mod says shots go instead.
--
-- With the game option that keeps the crosshair up turned off, the game hides the cursor between
-- shots and draws the cursor image flying back to the Helldiver (InputComponent.update_masters,
-- Gui.bitmap_uv with "cursor_game"). That image is caught while the input code runs, and the aiming
-- crosshair flies back in place of the image, shrinking and fading the same way.
--
-- The hitmarker hears hits from Obsidian API (combat.on_hit, every hit a player of this machine lands
-- that costs health, whichever machine runs the enemy) and kills from the event the game sends to the
-- machine of the killer (on_enemy_killed). Only the main player of this machine counts, never a
-- teammate, a bot or a second controller. With the hitmarker off, nothing listens.
local shapes = obsidian.module("src/shapes")
local hitmarker = obsidian.module("src/hitmarker")

local VERSION = "0.3.1"
local MOD_ID = "alomare.customcrosshair"
local ITP_ID = "alomare.integratedthirdperson"
local API_ID = "obsidian.api"

-- Under the in-game menu of Obsidian (876). The shadow with the blur copies, the outline and the lines
-- take one layer each, then the outline and the lines of the hitmarker.
local LAYER = 860
local ROLE_LAYER = { blur = 0, shadow = 0, outline = 1, fill = 2 }
local MARK_LAYER = { outline = 3, fill = 4 }

local GAME = "hud/cursors/game"
local INACTIVE = "hud/cursors/game_inactive"
local MENU = "hud/cursors/menu"
local HIDDEN = "hud/cursors/invisible"
local TRANSITION = "hud/cursors/game_transition_"
local LARGE = "_large"
local SPRITE = "cursor_game"
local SPRITE_SIZE = 32

local export = { version = VERSION }

local function option(id, default)
	local v = obsidian.settings.get(id)
	if v == nil then return default end
	return v
end

if option("enabled", true) == false then return export end

local ui = obsidian.ui
if not (type(ui) == "table" and type(ui.canvas) == "function") then
	obsidian.log("custom crosshair: this Obsidian has no obsidian.ui canvas, so the game cursor stays")
	return export
end

local settings = {
	idle = shapes.settings("idle", obsidian.settings.get),
	aim = shapes.settings("aim", obsidian.settings.get),
}
-- States whose game cursor goes: every shape but "game".
local hide = { idle = settings.idle.shape ~= "game", aim = settings.aim.shape ~= "game" }
local crosshair = hide.idle or hide.aim

-- The hitmarker settings, or nil while it is off or Obsidian API can't tell hits.
local marker = hitmarker.settings(obsidian.settings.get)
local api = nil
if hitmarker.shown(marker) then
	local ok, mod = pcall(obsidian.import, API_ID)
	if ok and type(mod) == "table" and type(mod.combat) == "table" and type(mod.combat.on_hit) == "function"
		and type(mod.events) == "table" and type(mod.game) == "table" then
		api = mod
	else
		obsidian.log("custom crosshair: the hitmarker needs Obsidian API 1.14.0 or later, so it stays off")
	end
end
if not api then marker = nil end

if not (crosshair or marker) then
	obsidian.log("custom crosshair: both states keep the game cursor")
	return export
end

-- A look: the layers of shapes.layers with a color each, and a point buffer for every polygon, so
-- drawing a frame makes no tables. `centre` is where the centre of the crosshair sits in the aim
-- pixel, for the hitmarker.
local function compile(s, factor)
	local look = shapes.layers(s, factor)
	for _, layer in ipairs(look) do
		layer.color = shapes.color_of(s, layer.role, layer.weight)
		layer.z = LAYER + (ROLE_LAYER[layer.role] or 2)
		for _, item in ipairs(layer.items) do
			if item.kind == "poly" then item.buf = {} end
		end
	end
	-- As shapes.layers works it out.
	look.centre = shapes.centre((s.thickness or 1) * ((s.scale or 1) * (factor or 1)))
	return look
end

-- A state left on "game" compiles to an empty look: the game draws that cursor.
local looks = { idle = compile(settings.idle), aim = compile(settings.aim) }

-- In third person the game shows no cursor, so a state left on "game" takes the default look there.
local third_looks = {
	idle = hide.idle and looks.idle or compile(shapes.DEFAULTS.idle),
	aim = hide.aim and looks.aim or compile(shapes.DEFAULTS.aim),
}

-- The aiming look at a tenth of the size at a time, for the cursor flying back.
local flying = {}
local function flying_look(f)
	local step = math.floor(f * 10 + 0.5)
	if step <= 0 then return nil end
	if step >= 10 then return looks.aim end
	local look = flying[step]
	if not look then
		look = compile(settings.aim, step / 10)
		flying[step] = look
	end
	return look
end

-- Aiming gap scales with spread (option aim_gap_spread): the aiming look with the gap opened by whole
-- pixels as the held weapon's spread grows, each made once.
local spread_on = obsidian.settings.get("aim_gap_spread") ~= false and hide.aim
local game_api = nil
if spread_on then
	local ok, mod = pcall(obsidian.import, API_ID)
	if ok and type(mod) == "table" and type(mod.game) == "table" and type(mod.game.master) == "function" then game_api = mod end
end
local spread_looks = {}

local function spread_now()
	if not game_api then return 0 end
	local ok, player = pcall(game_api.game.my_unit)
	if not ok or player == nil then return 0 end
	local ok_i, inventory = pcall(game_api.game.master, player, "inventory")
	local weapon = ok_i and type(inventory) == "table" and inventory.current_weapon or nil
	if weapon == nil then return 0 end
	local ok_f, firearm = pcall(game_api.game.master, weapon, "firearm")
	if not ok_f then return 0 end
	return shapes.spread_fraction(firearm)
end

-- The aiming look for the spread now: the plain one at none.
local function spread_look(base)
	if not spread_on or base ~= looks.aim then return base end
	local extra = shapes.spread_extra(spread_now())
	if extra <= 0 then return base end
	local look = spread_looks[extra]
	if not look then
		look = compile(shapes.with_gap(settings.aim, extra))
		spread_looks[extra] = look
	end
	return look
end

local kit = ui.canvas("crosshair", { layer = LAYER })

-- Draws a look with the aim point on pixel (x, y), from the bottom left. alpha fades all of it.
local function draw(look, x, y, alpha)
	if not look or #look == 0 then return end
	x, y = math.floor(x), math.floor(y)
	if alpha then kit:opacity(alpha) end
	for li = 1, #look do
		local layer = look[li]
		kit:layer(layer.z)
		local color, items = layer.color, layer.items
		for i = 1, #items do
			local it = items[i]
			if it.kind == "rect" then
				kit:rect(x + it.x, y + it.y, it.w, it.h, color)
			else
				local pts, buf = it.pts, it.buf
				for j = 1, #pts, 2 do
					buf[j], buf[j + 1] = x + pts[j], y + pts[j + 1]
				end
				kit:poly(buf, color)
			end
		end
	end
	if alpha then kit:opacity(1) end
end

-- The cursor to set in place of `path`, or nil to keep it.
local function covered(path)
	if type(path) ~= "string" or path:sub(1, #GAME) ~= GAME then return nil end
	local base, large = path, ""
	if base:sub(-#LARGE) == LARGE then base, large = base:sub(1, -#LARGE - 1), LARGE end
	local swap
	if base == GAME then
		swap = hide.aim
	elseif base == INACTIVE then
		swap = hide.idle
	elseif base:sub(1, #TRANSITION) == TRANSITION then
		swap = true
	end
	if swap then return HIDDEN .. large end
	return nil
end

-- With both states on "game" the cursors stay as they are, and only the hitmarker draws.
if crosshair then
	obsidian.hook("Window", "set_cursor", function(original, path, ...)
		return original(covered(path) or path, ...)
	end)
end

-- In the game the cursor does not pass the hook above (0.3.0 playtest), and setting the cursor from a
-- frame function crashes the engine (0.3.1). Every cursor CursorManager sets goes through one local
-- function of cursor_manager.lua, (path, large), shared as an upvalue by every CursorManager method. That
-- function is swapped once for one that passes the invisible cursor in place of a covered game cursor,
-- so the engine gets only the calls the game makes itself when it hides the cursor.
local patched_method = nil
local function patch_cursor_manager(cm)
	local method = cm.set_use_large_cursor
	if method == patched_method then return end
	patched_method = method
	local getup, setup = debug and debug.getupvalue, debug and debug.setupvalue
	if type(method) ~= "function" or not (getup and setup) then
		obsidian.log("custom crosshair: no CursorManager cursor function to swap")
		return
	end
	local index, set = nil, nil
	for i = 1, 255 do
		local name, v = getup(method, i)
		if name == nil then break end
		if type(v) == "function" then
			if index then
				obsidian.log("custom crosshair: CursorManager.set_use_large_cursor holds more than one function, the game cursor stays")
				return
			end
			index, set = i, v
		end
	end
	if not index then
		obsidian.log("custom crosshair: CursorManager.set_use_large_cursor holds no function, the game cursor stays")
		return
	end
	setup(method, index, function(path, ...)
		return set(covered(path) or path, ...)
	end)
	obsidian.log("custom crosshair: game cursors swapped inside CursorManager")
end

-- "idle" or "aim" while CursorManager shows a game cursor, nil otherwise (a menu, the map, hidden).
-- During a transition the cursor it is heading for counts.
local function cursor_state(cm)
	if type(cm) ~= "table" or not cm.shown then return nil end
	local want = cm.next_cursor or cm.current_cursor
	if want == GAME then return "aim" end
	if want == INACTIVE then return "idle" end
	return nil
end

local function menu_up(cm)
	return type(cm) == "table" and cm.shown and (cm.next_cursor or cm.current_cursor) == MENU
end

local mouse_axis = nil
local function mouse()
	local m = rawget(_G, "Mouse")
	if type(m) ~= "table" then return nil end
	if not mouse_axis then mouse_axis = m.axis_index("cursor") end
	local at = m.axis(mouse_axis)
	if not at then return nil end
	return at.x, at.y
end

-- The cursor image flying back: caught in Gui.bitmap_uv while the input code runs, drawn in the next
-- frame function.
local flight = { on = false, x = 0, y = 0, f = 0 }
local real_bitmap, cursor_gui = nil, nil
local function catch_bitmap(gui, material, uv0, uv1, pos, size, ...)
	if material == SPRITE and gui == cursor_gui and pos and size then
		flight.on, flight.f = true, size.x / SPRITE_SIZE
		flight.x, flight.y = pos.x + size.x / 2, pos.y + size.y / 2
		return
	end
	return real_bitmap(gui, material, uv0, uv1, pos, size, ...)
end

if hide.aim then
	local unpack = unpack or table.unpack
	local function pack(...) return { n = select("#", ...), ... } end
	obsidian.hook("InputComponent", "update_masters", function(original, self, ...)
		local gui = rawget(_G, "Gui")
		if type(gui) ~= "table" or type(self) ~= "table" or self.cursor_gui == nil then return original(self, ...) end
		real_bitmap, cursor_gui = gui.bitmap_uv, self.cursor_gui
		gui.bitmap_uv = catch_bitmap
		local r = pack(pcall(original, self, ...))
		gui.bitmap_uv = real_bitmap
		if not r[1] then error(r[2], 0) end
		return unpack(r, 2, r.n)
	end)
end

-- Integrated Third Person: where shots go while it steers the view. `claimed` while this mod draws the
-- crosshair there; with both states on "game" Integrated Third Person keeps the built-in crosshair, and
-- the hitmarker goes around that one.
local itp, claimed = nil, false
local function third_person()
	if not itp then return nil end
	local ok, spot = pcall(itp.crosshair)
	if ok and type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then return spot end
	return nil
end

local function join_itp()
	if option("third_person", true) == false then return end
	local ok, mod = pcall(obsidian.import, ITP_ID)
	if not (ok and type(mod) == "table" and type(mod.crosshair) == "function") then return end
	itp = mod
	if not crosshair then
		obsidian.log("custom crosshair: hitmarker around the crosshair of Integrated Third Person")
		return
	end
	if type(mod.claim_crosshair) == "function" then
		local done, err = pcall(mod.claim_crosshair, MOD_ID)
		if not done then obsidian.log("custom crosshair: Integrated Third Person refused the crosshair: " .. tostring(err)) end
	end
	claimed = true
	obsidian.log("custom crosshair: drawing the crosshair of Integrated Third Person")
end

if type(obsidian.after_startup) == "function" then
	obsidian.after_startup(join_itp)
else
	join_itp()
end

-- The idle and aiming looks fade into each other over FADE seconds instead of snapping. blend runs from
-- 0 (idle) to 1 (aiming) while a crosshair is up, and is nil while none is.
local FADE = 0.08
local blend = nil
-- The top-down looks: a state left on "game" has an empty one, as the game draws that cursor.
local top_looks = looks

local function frame_time()
	local dt = rawget(_G, "ENGINE_DT")
	if type(dt) ~= "number" or dt <= 0 then return 1 / 60 end
	return math.min(dt, 0.1)
end

-- Moves the blend toward the state shown now, then draws one look, or both while they cross. Answers
-- where the centre sits in the aim pixel, from the look that shows the most.
local function draw_state(pick, aiming, x, y)
	local target = aiming and 1 or 0
	if blend == nil then
		blend = target
	elseif blend ~= target then
		local step = frame_time() / FADE
		blend = target > blend and math.min(target, blend + step) or math.max(target, blend - step)
	end
	local aim = blend > 0 and spread_look(pick.aim) or pick.aim
	if blend >= 1 then
		draw(aim, x, y)
	elseif blend <= 0 then
		draw(pick.idle, x, y)
	else
		draw(pick.idle, x, y, 1 - blend)
		draw(aim, x, y, blend)
	end
	return (blend >= 0.5 and pick.aim or pick.idle).centre
end

-- The hitmarker: a look for each kind of mark and each place the centre can sit in the aim pixel, and
-- the clock (seconds) at the last hit and the last kill. The clock moves only while the hitmarker is on.
local clock, hit_at, kill_at = 0, nil, nil
local marks = nil

local function compile_mark(kind, c)
	local look = hitmarker.layers(marker, kind, c)
	for _, layer in ipairs(look) do
		layer.color = shapes.rgba(layer.hex, 1)
		layer.z = LAYER + MARK_LAYER[layer.role]
		for _, item in ipairs(layer.items) do item.buf = {} end
	end
	return look
end

-- The mark showing now around the aim point (x, y), with the centre at c in the aim pixel. A kill
-- shows over a hit.
local function draw_marker(x, y, c)
	local look, age, kind
	if kill_at and clock - kill_at < marker.time then
		look, age, kind = marks.kill, clock - kill_at, "kill"
	elseif hit_at and clock - hit_at < marker.time then
		look, age, kind = marks.hit, clock - hit_at, "hit"
	else
		return
	end
	draw(look[c] or look[0.5], x, y, hitmarker.fade(age, marker.time) * hitmarker.opacity(marker, kind))
end

-- Whether `owner` is the unit of the main player of this machine.
local function mine(owner)
	if owner == nil then return false end
	local ok, player = pcall(api.game.my_unit)
	return ok and player ~= nil and owner == player
end

local function enemy(unit)
	local aux = rawget(_G, "EntityAux")
	if unit == nil or type(aux) ~= "table" then return false end
	local ok, yes = pcall(aux.has_component, unit, "enemy")
	return ok and yes ~= nil and yes ~= false
end

-- Whether `attacker` is a weapon `owner` holds, as Obsidian API tells the slot of a hit.
local SLOTS = { "primary_weapon", "sidearm_weapon", "support_weapon" }
local function held(owner, attacker)
	if attacker == nil then return false end
	local ok, inventory = pcall(api.game.master, owner, "inventory")
	if not ok or type(inventory) ~= "table" then return false end
	for i = 1, #SLOTS do
		if inventory[SLOTS[i]] == attacker then return true end
	end
	return false
end

if marker then
	marks = {}
	for _, kind in ipairs({ "hit", "kill" }) do
		marks[kind] = { [0] = compile_mark(kind, 0), [0.5] = compile_mark(kind, 0.5) }
	end
	local weapons_only = marker.from ~= "all"
	if marker.hits then
		api.combat.on_hit(function(victim, hit)
			if type(hit) ~= "table" or not mine(hit.owner_unit) then return end
			if weapons_only and hit.slot == nil then return end
			if enemy(victim) then hit_at = clock end
		end)
	end
	if marker.kills then
		local ok, why = api.events.on("on_enemy_killed", function(unit, attacker, owner)
			if not mine(owner) then return end
			if weapons_only and not held(owner, attacker) then return end
			kill_at = clock
		end)
		if ok == false then obsidian.log("custom crosshair: Obsidian API refused the kill event (" .. tostring(why) .. "), so kills show no mark") end
	end
end

local function frame()
	local cm = rawget(_G, "CursorManager")
	if crosshair and type(cm) == "table" then patch_cursor_manager(cm) end
	local spot = third_person()
	-- Where the hitmarker goes: the aim point of the crosshair, while one is up.
	local mx, my, mc = nil, nil, 0.5
	if spot then
		if menu_up(cm) then
			blend = nil
		else
			if claimed then mc = draw_state(third_looks, spot.aiming, spot.x, spot.y) end
			mx, my = spot.x, spot.y
		end
	else
		local state = cursor_state(cm)
		local x, y = nil, nil
		if state then x, y = mouse() end
		if x then
			mc = draw_state(top_looks, state == "aim", x, y)
			mx, my = x, y
		else
			blend = nil
		end
	end
	if flight.on then
		flight.on = false
		if not spot then draw(flying_look(flight.f), flight.x, flight.y, flight.f * flight.f) end
	end
	if marker then
		if mx then draw_marker(mx, my, mc) end
		clock = clock + frame_time()
	end
end

local failed = false
obsidian.on_frame(function()
	local ok, err = pcall(frame)
	if not ok and not failed then
		failed = true
		obsidian.log("custom crosshair: " .. tostring(err))
	end
end)

local function marker_text()
	if not marker then return "hitmarker off" end
	local on = marker.hits and marker.kills and "hits and kills" or marker.hits and "hits" or "kills"
	return "hitmarker on " .. on .. " from " .. (marker.from == "all" and "everything" or "weapons in hand")
end

obsidian.log(string.format("custom crosshair %s: idle %s, aiming %s, %s", VERSION, settings.idle.shape, settings.aim.shape, marker_text()))

return export

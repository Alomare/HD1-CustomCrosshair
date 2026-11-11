-- Custom Crosshair: the aim cursor of the game replaced with a crosshair drawn from shapes, one look
-- between shots (idle) and one while aiming, set in the Options tab of the mod in Obsidian.
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
local shapes = obsidian.module("src/shapes")

local VERSION = "0.1.1"
local MOD_ID = "alomare.customcrosshair"
local ITP_ID = "alomare.integratedthirdperson"

-- Under the in-game menu of Obsidian (876). Shadow, outline and lines take one layer each.
local LAYER = 860
local ROLE_LAYER = { shadow = 0, outline = 1, fill = 2 }

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
if not (hide.idle or hide.aim) then
	obsidian.log("custom crosshair: both states keep the game cursor")
	return export
end

-- A look: the layers of shapes.layers with a color each, and a point buffer for every polygon, so
-- drawing a frame makes no tables.
local function compile(s, factor)
	local look = shapes.layers(s, factor)
	for _, layer in ipairs(look) do
		layer.color = shapes.color_of(s, layer.role)
		layer.z = LAYER + (ROLE_LAYER[layer.role] or 2)
		for _, item in ipairs(layer.items) do
			if item.kind == "poly" then item.buf = {} end
		end
	end
	return look
end

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

obsidian.hook("Window", "set_cursor", function(original, path, ...)
	return original(covered(path) or path, ...)
end)

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

-- Integrated Third Person: where shots go while it steers the view.
local itp = nil
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
	if type(mod.claim_crosshair) == "function" then
		local claimed, err = pcall(mod.claim_crosshair, MOD_ID)
		if not claimed then obsidian.log("custom crosshair: Integrated Third Person refused the crosshair: " .. tostring(err)) end
	end
	itp = mod
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
-- The top-down looks: a state left on "game" has none, as the game draws that cursor.
local top_looks = { idle = hide.idle and looks.idle or nil, aim = hide.aim and looks.aim or nil }

local function frame_time()
	local dt = rawget(_G, "ENGINE_DT")
	if type(dt) ~= "number" or dt <= 0 then return 1 / 60 end
	return math.min(dt, 0.1)
end

-- Moves the blend toward the state shown now, then draws one look, or both while they cross.
local function draw_state(pick, aiming, x, y)
	local target = aiming and 1 or 0
	if blend == nil then
		blend = target
	elseif blend ~= target then
		local step = frame_time() / FADE
		blend = target > blend and math.min(target, blend + step) or math.max(target, blend - step)
	end
	if blend >= 1 then
		draw(pick.aim, x, y)
	elseif blend <= 0 then
		draw(pick.idle, x, y)
	else
		draw(pick.idle, x, y, 1 - blend)
		draw(pick.aim, x, y, blend)
	end
end

local function frame()
	local cm = rawget(_G, "CursorManager")
	local spot = third_person()
	if spot then
		if menu_up(cm) then blend = nil else draw_state(third_looks, spot.aiming, spot.x, spot.y) end
	else
		local state = cursor_state(cm)
		local x, y = nil, nil
		if state then x, y = mouse() end
		if x then draw_state(top_looks, state == "aim", x, y) else blend = nil end
	end
	if flight.on then
		flight.on = false
		if not spot then draw(flying_look(flight.f), flight.x, flight.y, flight.f * flight.f) end
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

obsidian.log(string.format("custom crosshair: idle %s, aiming %s", settings.idle.shape, settings.aim.shape))

return export

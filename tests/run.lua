-- Offline tests for the parts of Custom Crosshair that don't need the game. From the repository root:
--   luajit tests/run.lua
-- Every tests/test_*.lua file returns a list of { name, fn }. Each test starts with a fresh stand-in
-- for the `obsidian` global; a test file builds the engine stand-ins it needs itself.
local passed, failed = 0, 0

-- A canvas that writes down what it was asked to draw.
function fake_kit()
	local kit = { calls = {}, alpha = 1, z = 0 }
	function kit:rect(x, y, w, h, c) self.calls[#self.calls + 1] = { "rect", x, y, w, h, c = c, z = self.z, alpha = self.alpha } end
	function kit:poly(pts, c)
		local copy = {}
		for i, v in ipairs(pts) do copy[i] = v end
		self.calls[#self.calls + 1] = { "poly", copy, c = c, z = self.z, alpha = self.alpha }
	end
	function kit:outline(pts, c, width)
		local copy = {}
		for i, v in ipairs(pts) do copy[i] = v end
		self.calls[#self.calls + 1] = { "outline", copy, c = c, width = width, z = self.z, alpha = self.alpha }
	end
	function kit:layer(n) if n then self.z = n end return self.z end
	function kit:opacity(a) if a then self.alpha = a end return self.alpha end
	return kit
end

function fresh_obsidian()
	local loaded = {}
	LOGS, OPTIONS, HOOKS, FRAMES, STARTUP, IMPORTS, KITS = {}, {}, {}, {}, {}, {}, {}
	obsidian = {
		capabilities = { ui = true, after_startup = true },
		module = function(name)
			if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
			return loaded[name]
		end,
		import = function(id) return IMPORTS[id] end,
		log = function(...) LOGS[#LOGS + 1] = table.concat({ ... }, " ") end,
		caller = function() return "alomare.customcrosshair" end,
		settings = { get = function(id) return OPTIONS[id] end },
		hook = function(target, method, fn) HOOKS[#HOOKS + 1] = { target = target, method = method, fn = fn } end,
		on_frame = function(fn) FRAMES[#FRAMES + 1] = fn end,
		after_startup = function(fn) STARTUP[#STARTUP + 1] = fn end,
		ui = {
			canvas = function(id, opts)
				local kit = fake_kit()
				kit.id, kit.z = id, opts and opts.layer or 700
				KITS[#KITS + 1] = kit
				return kit
			end,
		},
	}
end

function eq(got, want, what)
	if got ~= want then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

function near(got, want, what, tolerance)
	if type(got) ~= "number" or math.abs(got - want) > (tolerance or 1e-6) then
		error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2)
	end
end

local function test(name, fn)
	fresh_obsidian()
	local ok, err = xpcall(fn, debug.traceback)
	if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. "\n" .. err) end
end

local files = {}
local p = io.popen('ls tests 2>nul || dir /b tests')
if p then
	for line in p:lines() do
		local f = line:match("^(test_[%w_]+%.lua)$")
		if f then files[#files + 1] = "tests/" .. f end
	end
	p:close()
end
table.sort(files)

for _, file in ipairs(files) do
	local tests = dofile(file)
	for _, t in ipairs(tests) do test(file .. " " .. t[1], t[2]) end
end
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)

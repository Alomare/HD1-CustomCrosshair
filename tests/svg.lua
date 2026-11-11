-- The preview templates as Obsidian fills them, for the tests: a small XML reader, the expression
-- language of option_previews, and the filling itself ({{expr}} in attributes and text, data-if
-- removing an element). The language is kept to what Obsidian supports: numbers, 'strings', option
-- ids, + - * / %, == != < > <= >=, && || !, a ? b : c, parentheses, min max abs round floor ceil clamp.
-- No unary minus, so a template that leans on one fails here. The limits are the ones of the Launcher
-- (app/src/mods/preview.ts): an expression of more than 400 characters, or nested more than 40 deep,
-- gives nothing there, so it fails here.
local M = {}

M.MAX_EXPR = 400
M.MAX_DEPTH = 40

-- Expressions -------------------------------------------------------------------------------------

local function tokens(src)
	local out, i = {}, 1
	while i <= #src do
		local c = src:sub(i, i)
		if c:find("%s") then
			i = i + 1
		elseif c:find("%d") then
			local num = src:match("^%d+%.?%d*", i)
			out[#out + 1] = { k = "num", v = tonumber(num) }
			i = i + #num
		elseif c == "'" then
			local e = src:find("'", i + 1, true)
			if not e then error("unclosed string in: " .. src, 0) end
			out[#out + 1] = { k = "str", v = src:sub(i + 1, e - 1) }
			i = e + 1
		elseif c:find("[%a_]") then
			local id = src:match("^[%a_][%w_]*", i)
			out[#out + 1] = { k = "id", v = id }
			i = i + #id
		else
			local two = src:sub(i, i + 1)
			if two == "==" or two == "!=" or two == "<=" or two == ">=" or two == "&&" or two == "||" then
				out[#out + 1] = { k = "op", v = two }
				i = i + 2
			elseif ("+-*/%<>!?:(),"):find(c, 1, true) then
				out[#out + 1] = { k = "op", v = c }
				i = i + 1
			else
				error("unknown character " .. c .. " in: " .. src, 0)
			end
		end
	end
	return out
end

local function truthy(v)
	return not (v == nil or v == false or v == 0 or v == "")
end
M.truthy = truthy

local FUNCTIONS = {
	min = math.min,
	max = math.max,
	abs = math.abs,
	round = function(x) return math.floor(x + 0.5) end,
	floor = math.floor,
	ceil = math.ceil,
	clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
}

-- The value of `src` with option values `values`. Depth counts as in the Launcher: one level for each
-- primary (a number, a name, a call, a bracket or a "!") and one for each expression (the whole, each
-- bracket, each argument, each branch of a ? :).
function M.eval(src, values)
	if #src > M.MAX_EXPR then error("expression longer than " .. M.MAX_EXPR .. " characters: " .. src, 0) end
	local t, pos = tokens(src), 1
	local depth = 0
	local function deeper(f)
		depth = depth + 1
		if depth > M.MAX_DEPTH then error("expression nested deeper than " .. M.MAX_DEPTH .. ": " .. src, 0) end
		local v = f()
		depth = depth - 1
		return v
	end
	local function peek() return t[pos] end
	local function take(v)
		local tok = t[pos]
		if not tok or tok.v ~= v then error("expected " .. v .. " in: " .. src, 0) end
		pos = pos + 1
	end
	local function is(v) local tok = t[pos]; return tok and tok.k == "op" and tok.v == v end

	local ternary
	local function primary_at()
		local tok = t[pos]
		if not tok then error("unexpected end of: " .. src, 0) end
		pos = pos + 1
		if tok.k == "num" or tok.k == "str" then return tok.v end
		if tok.k == "id" then
			if is("(") then
				local fn = FUNCTIONS[tok.v]
				if not fn then error("unknown function " .. tok.v .. " in: " .. src, 0) end
				take("(")
				local args = { ternary() }
				while is(",") do
					take(",")
					args[#args + 1] = ternary()
				end
				take(")")
				return fn(unpack(args))
			end
			local v = values[tok.v]
			if v == nil then error("unknown option id " .. tok.v .. " in: " .. src, 0) end
			return v
		end
		if tok.v == "(" then
			local v = ternary()
			take(")")
			return v
		end
		error("unexpected " .. tostring(tok.v) .. " in: " .. src, 0)
	end
	local function primary() return deeper(primary_at) end
	local function unary()
		if is("!") then
			take("!")
			return deeper(function() return not truthy(unary()) end)
		end
		if is("-") then error("unary minus is not in the template language: " .. src, 0) end
		return primary()
	end
	local function binary(next_level, ops)
		return function()
			local v = next_level()
			while peek() and peek().k == "op" and ops[peek().v] do
				local op = peek().v
				pos = pos + 1
				local w = next_level()
				v = ops[op](v, w)
			end
			return v
		end
	end
	local mul = binary(unary, {
		["*"] = function(a, b) return a * b end, ["/"] = function(a, b) return a / b end, ["%"] = function(a, b) return math.fmod(a, b) end,
	})
	local add = binary(mul, { ["+"] = function(a, b) return a + b end, ["-"] = function(a, b) return a - b end })
	local rel = binary(add, {
		["<"] = function(a, b) return a < b end, [">"] = function(a, b) return a > b end,
		["<="] = function(a, b) return a <= b end, [">="] = function(a, b) return a >= b end,
	})
	local eq = binary(rel, { ["=="] = function(a, b) return a == b end, ["!="] = function(a, b) return a ~= b end })
	local function both()
		local v = eq()
		while is("&&") do
			take("&&")
			local w = eq()
			if truthy(v) then v = w end
		end
		return v
	end
	local function either()
		local v = both()
		while is("||") do
			take("||")
			local w = both()
			if not truthy(v) then v = w end
		end
		return v
	end
	ternary = function()
		return deeper(function()
			local c = either()
			if is("?") then
				take("?")
				local a = ternary()
				take(":")
				local b = ternary()
				if truthy(c) then return a end
				return b
			end
			return c
		end)
	end
	local v = ternary()
	if pos <= #t then error("text after the expression: " .. src, 0) end
	return v
end

local function show(v)
	if type(v) == "number" then
		if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
		return string.format("%.12g", v)
	end
	if v == true then return "true" end
	if v == false then return "false" end
	return tostring(v)
end

-- {{expr}} in a string replaced with values.
function M.fill(s, values)
	return (s:gsub("{{(.-)}}", function(expr) return show(M.eval(expr, values)) end))
end

-- XML ---------------------------------------------------------------------------------------------

-- A node: { tag, attrs = { name -> value }, order = { names }, children = { node | string } }.
function M.parse(text)
	local root = { tag = "#root", attrs = {}, order = {}, children = {} }
	local stack, i = { root }, 1
	while i <= #text do
		local lt = text:find("<", i, true)
		local chunk = text:sub(i, (lt or #text + 1) - 1)
		if chunk:find("%S") then table.insert(stack[#stack].children, chunk) end
		if not lt then break end
		if text:sub(lt, lt + 3) == "<!--" then
			i = assert(text:find("-->", lt, true), "unclosed comment") + 3
		elseif text:sub(lt, lt + 1) == "<?" then
			i = assert(text:find("?>", lt, true), "unclosed declaration") + 2
		elseif text:sub(lt, lt + 1) == "</" then
			local name, e = text:match("^</([%w:_-]+)%s*>()", lt)
			assert(name, "bad closing tag at " .. lt)
			local top = table.remove(stack)
			if top.tag ~= name then error("</" .. name .. "> closes <" .. top.tag .. ">", 0) end
			i = e
		else
			local name, j = text:match("^<([%w:_-]+)()", lt)
			assert(name, "bad tag at " .. lt)
			local node = { tag = name, attrs = {}, order = {}, children = {} }
			local close
			while true do
				j = text:match("^%s*()", j)
				if text:sub(j, j + 1) == "/>" then
					close, j = true, j + 2
					break
				elseif text:sub(j, j) == ">" then
					close, j = false, j + 1
					break
				end
				local k, v, e = text:match('^([%w:_-]+)%s*=%s*"([^"]*)"()', j)
				if not k then error("bad attributes on <" .. name .. "> at " .. j .. ": " .. text:sub(j, j + 40), 0) end
				if v:find("[<&]") then error("attribute " .. k .. " of <" .. name .. "> holds < or &, which is not valid XML", 0) end
				if node.attrs[k] then error("attribute " .. k .. " twice on <" .. name .. ">", 0) end
				node.attrs[k] = v
				node.order[#node.order + 1] = k
				j = e
			end
			table.insert(stack[#stack].children, node)
			if not close then stack[#stack + 1] = node end
			i = j
		end
	end
	if #stack ~= 1 then error("<" .. stack[#stack].tag .. "> never closed", 0) end
	return root
end

-- The tree as Obsidian would draw it: data-if decides, {{expr}} filled in.
function M.render(node, values)
	local out = { tag = node.tag, attrs = {}, order = {}, children = {} }
	for _, k in ipairs(node.order) do
		if k ~= "data-if" then
			out.attrs[k] = M.fill(node.attrs[k], values)
			out.order[#out.order + 1] = k
		end
	end
	for _, child in ipairs(node.children) do
		if type(child) == "string" then
			out.children[#out.children + 1] = M.fill(child, values)
		elseif child.attrs["data-if"] == nil or truthy(M.eval(child.attrs["data-if"], values)) then
			out.children[#out.children + 1] = M.render(child, values)
		end
	end
	return out
end

-- Every node under `node` for which match(n) is true, depth first.
function M.find_all(node, match, out)
	out = out or {}
	for _, child in ipairs(node.children) do
		if type(child) == "table" then
			if match(child) then out[#out + 1] = child end
			M.find_all(child, match, out)
		end
	end
	return out
end

function M.text_of(node)
	local parts = {}
	for _, child in ipairs(node.children) do
		if type(child) == "string" then parts[#parts + 1] = child end
	end
	return table.concat(parts)
end

return M

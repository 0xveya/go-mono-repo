local config = require("go_mono_repo.config")
local picker = require("go_mono_repo.picker")
local rootmod = require("go_mono_repo.root")
local scope = require("go_mono_repo.scope")

local M = {}

local methods = {
	Get = "GET",
	Post = "POST",
	Put = "PUT",
	Patch = "PATCH",
	Delete = "DELETE",
	Head = "HEAD",
	Options = "OPTIONS",
	Handle = "HANDLE",
}

local function notify(msg, level)
	if config.options.notify then
		vim.notify(msg, level or vim.log.levels.INFO, { title = "go_mono_repo" })
	end
end

local function rel(root, path)
	return vim.fn.fnamemodify(path, ":p"):gsub("^" .. vim.pesc(vim.fn.fnamemodify(root, ":p")), "")
end

local function normalize_route(path)
	path = path:gsub("//+", "/")
	if path ~= "/" then
		path = path:gsub("/$", "")
	end
	return path
end

local function join_route(base, child)
	if not base or base == "" then
		base = "/"
	end
	if not child or child == "" then
		child = "/"
	end
	if child:sub(1, 1) ~= "/" then
		child = "/" .. child
	end
	if base == "/" then
		return normalize_route(child)
	end
	return normalize_route(base .. child)
end

local function leading_ws(line)
	return #(line:match("^%s*") or "")
end

local function handler_key(expr)
	if not expr then
		return nil
	end
	expr = expr:gsub("%s+", "")
	expr = expr:gsub("%.ServeHTTP$", "")
	return expr:match("([%w_]+)$")
end

local function all_go_files(root)
	local result = vim.system({ "rg", "--files", "-g", "*.go" }, { cwd = root, text = true }):wait()
	if result.code ~= 0 then
		return {}
	end
	local files = {}
	for line in (result.stdout or ""):gmatch("[^\n]+") do
		table.insert(files, vim.fs.normalize(root .. "/" .. line))
	end
	table.sort(files)
	return files
end

local function generated(path)
	if not config.options.exclude_generated then
		return false
	end
	for _, line in ipairs(vim.fn.readfile(path, "", 5)) do
		if line:match(config.options.generated_header_pattern) then
			return true
		end
	end
	return false
end

local function candidate_files(root)
	local current = scope.current()
	if current and current.root == root and current.files then
		return current.files, current.label
	end

	local files = {}
	for _, file in ipairs(all_go_files(root)) do
		if not generated(file) then
			table.insert(files, file)
		end
	end
	return files, "all"
end

local function parse_file(root, file, routes, defs)
	local ok, lines = pcall(vim.fn.readfile, file)
	if not ok then
		return
	end

	local route_stack = { [0] = "/" }
	for lnum, line in ipairs(lines) do
		local indent = leading_ws(line)
		if line:match("%S") and not line:match("^%s*%.") then
			for k in pairs(route_stack) do
				if k >= indent and k ~= 0 then
					route_stack[k] = nil
				end
			end
		end

		local recv, name = line:match("^func%s+%([^)]*%*?([%w_]+)[^)]*%)%s+([%w_]+)%s*%(")
		if name then
			defs[name] = defs[name] or { file = file, line = lnum, receiver = recv }
		else
			name = line:match("^func%s+([%w_]+)%s*%(")
			if name then
				defs[name] = defs[name] or { file = file, line = lnum }
			end
		end

		local route_path = line:match('%.Route%("%s*([^"]-)%s*"')
		if route_path then
			local parent = "/"
			for i = indent - 1, 0, -1 do
				if route_stack[i] then
					parent = route_stack[i]
					break
				end
			end
			route_stack[indent] = join_route(parent, route_path)
			for k in pairs(route_stack) do
				if k > indent then
					route_stack[k] = nil
				end
			end
		end

		local method, path, handler = line:match('%.([A-Z][%w_]*)%("%s*([^"]-)%s*"%s*,%s*([^%)]+)%)')
		if not method then
			method, path, handler = line:match('%.([A-Z][%w_]*)%("%s*([^"]-)%s*"%s*,%s*([^%)]+)$')
		end
		if not method then
			method, path, handler = line:match('^%s*([A-Z][%w_]*)%("%s*([^"]-)%s*"%s*,%s*([^%)]+)%)')
		end
		if not method then
			method, path, handler = line:match('^%s*([A-Z][%w_]*)%("%s*([^"]-)%s*"%s*,%s*([^%)]+)$')
		end
		if method and methods[method] then
			local parent = "/"
			for i = indent, 0, -1 do
				if route_stack[i] then
					parent = route_stack[i]
					break
				end
			end
			local route = join_route(parent, path)
			table.insert(routes, {
				method = methods[method],
				path = route,
				handler = vim.trim(handler:gsub(",%s*$", "")),
				key = handler_key(handler),
				file = file,
				line = lnum,
				source = rel(root, file) .. ":" .. lnum,
			})
		end
	end
end

function M.collect(root)
	local files, scope_label = candidate_files(root)
	local routes = {}
	local defs = {}

	for _, file in ipairs(files) do
		parse_file(root, file, routes, defs)
	end

	local seen_route = {}
	local items = {}
	for _, route in ipairs(routes) do
		local def = route.key and defs[route.key]
		route.handler_file = def and def.file or nil
		route.handler_line = def and def.line or nil
		route.text = ("%s %-42s -> %-36s [%s]"):format(route.method, route.path, route.handler, route.source)
		local key = table.concat({ route.method, route.path, route.handler, route.source }, "\n")
		if not seen_route[key] then
			seen_route[key] = true
			table.insert(items, route)
		end
	end

	if #items == 0 then
		for name, def in pairs(defs) do
			if
				name:match("^Handle")
				or name:match("Handler$")
				or name:match("^List")
				or name:match("^Create")
				or name:match("^Delete")
			then
				table.insert(items, {
					text = ("FUNC %-38s [%s:%d]"):format(name, rel(root, def.file), def.line),
					handler = name,
					handler_file = def.file,
					handler_line = def.line,
					file = def.file,
					line = def.line,
				})
			end
		end
	end

	table.sort(items, function(a, b)
		return a.text < b.text
	end)
	return items, scope_label
end

function M.pick()
	local root, err = rootmod.find()
	if not root then
		notify(err, vim.log.levels.WARN)
		return
	end
	local items, label = M.collect(root)
	if #items == 0 then
		notify("No Go router handlers found for scope " .. label, vim.log.levels.WARN)
		return
	end
	picker.handlers(items)
end

return M

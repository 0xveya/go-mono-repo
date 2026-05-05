local config = require("go_mono_repo.config")
local rootmod = require("go_mono_repo.root")

local M = {}

local uv = vim.uv or vim.loop

local function is_dir(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "directory"
end

local function is_go_file(path)
	return path:sub(-3) == ".go" and vim.fn.filereadable(path) == 1
end

local function has_go_file(path)
	local fd = uv.fs_scandir(path)
	if not fd then
		return false
	end
	while true do
		local name, typ = uv.fs_scandir_next(fd)
		if not name then
			break
		end
		if typ == "file" and name:sub(-3) == ".go" then
			return true
		end
	end
	return false
end

function M.discover_entrypoints(root)
	local dir = root .. "/" .. config.options.entry_dir
	local entries = {}
	if not is_dir(dir) then
		return entries
	end
	local fd = uv.fs_scandir(dir)
	if not fd then
		return entries
	end
	while true do
		local name, typ = uv.fs_scandir_next(fd)
		if not name then
			break
		end
		local full = dir .. "/" .. name
		if typ == "directory" and has_go_file(full) then
			table.insert(entries, {
				label = name,
				entry = "./" .. config.options.entry_dir .. "/" .. name,
				path = full,
			})
		end
	end
	table.sort(entries, function(a, b)
		return a.label < b.label
	end)
	return entries
end

function M.entry_exists(root, entry)
	for _, item in ipairs(M.discover_entrypoints(root)) do
		if item.entry == entry then
			return item
		end
	end
end

local function decode_go_list_json(out)
	local pkgs = {}
	local buf = {}
	local depth = 0
	local in_string = false
	local escape = false

	for i = 1, #out do
		local ch = out:sub(i, i)
		if in_string then
			table.insert(buf, ch)
			if escape then
				escape = false
			elseif ch == "\\" then
				escape = true
			elseif ch == '"' then
				in_string = false
			end
		else
			if ch == '"' then
				in_string = true
				table.insert(buf, ch)
			elseif ch == "{" then
				depth = depth + 1
				table.insert(buf, ch)
			elseif ch == "}" then
				depth = depth - 1
				table.insert(buf, ch)
				if depth == 0 then
					local ok, obj = pcall(vim.json.decode, table.concat(buf))
					if ok then
						table.insert(pkgs, obj)
					end
					buf = {}
				elseif depth < 0 then
					depth = 0
					buf = {}
				end
			elseif depth > 0 then
				table.insert(buf, ch)
			end
		end
	end
	return pkgs
end

local function generated(path)
	local opts = config.options
	if not opts.exclude_generated or not is_go_file(path) then
		return false
	end
	local lines = vim.fn.readfile(path, "", 5)
	for _, line in ipairs(lines) do
		if line:match(opts.generated_header_pattern) then
			return true
		end
	end
	return false
end

local function add_files(scope, pkg, names)
	for _, name in ipairs(names or {}) do
		local path = vim.fs.normalize(pkg.Dir .. "/" .. name)
		if generated(path) then
			scope.generated_files[path] = true
		else
			scope.files[path] = true
		end
	end
end

function M.compute_scope(root, entry)
	local module_path, mod_err = rootmod.module_path(root)
	if not module_path then
		return nil, mod_err
	end

	local cmd = { "go", "list", "-deps", "-json", entry }
	local result = vim.system(cmd, { cwd = root, text = true }):wait()
	if result.code ~= 0 then
		return nil, vim.trim(result.stderr or result.stdout or "go list failed")
	end

	local raw = {
		root = root,
		module = module_path,
		entry = entry,
		import_path = nil,
		label = vim.fs.basename(entry),
		packages = {},
		files = {},
		generated_files = {},
		updated_at = os.time(),
	}

	for _, pkg in ipairs(decode_go_list_json(result.stdout or "")) do
		if pkg.Module and pkg.Module.Path == module_path then
			if pkg.ImportPath == module_path .. "/" .. entry:gsub("^%./", "") then
				raw.import_path = pkg.ImportPath
			end
			table.insert(raw.packages, pkg.ImportPath)
			add_files(raw, pkg, pkg.GoFiles)
			add_files(raw, pkg, pkg.CgoFiles)
			if config.options.include_tests then
				add_files(raw, pkg, pkg.TestGoFiles)
				add_files(raw, pkg, pkg.XTestGoFiles)
			end
		end
	end

	table.sort(raw.packages)
	raw.files = vim.tbl_keys(raw.files)
	raw.generated_files = vim.tbl_keys(raw.generated_files)
	table.sort(raw.files)
	table.sort(raw.generated_files)
	raw.import_path = raw.import_path or (module_path .. "/" .. entry:gsub("^%./", ""))
	return raw
end

return M

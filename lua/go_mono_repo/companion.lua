local config = require("go_mono_repo.config")

local M = {}
local uv = vim.uv or vim.loop

local function excluded(name)
	for _, item in ipairs(config.options.companions.exclude_dirs or {}) do
		if name == item then
			return true
		end
	end
	return false
end

local function walk(path, files, visit)
	local stat = uv.fs_stat(path)
	if not stat then
		return
	end
	if stat.type == "file" then
		files[vim.fs.normalize(path)] = true
		return
	end
	if stat.type ~= "directory" or excluded(vim.fs.basename(path)) then
		return
	end
	if visit then
		visit(path)
	end
	local fd = uv.fs_scandir(path)
	if not fd then
		return
	end
	while true do
		local name = uv.fs_scandir_next(fd)
		if not name then
			break
		end
		walk(path .. "/" .. name, files, visit)
	end
end

local function is_svelte(path)
	if
		vim.fn.filereadable(path .. "/svelte.config.js") == 1
		or vim.fn.filereadable(path .. "/svelte.config.ts") == 1
	then
		return true
	end
	local package = path .. "/package.json"
	if vim.fn.filereadable(package) ~= 1 then
		return false
	end
	local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(package), "\n"))
	if not ok then
		return false
	end
	for _, deps in ipairs({ data.dependencies, data.devDependencies }) do
		if deps and (deps.svelte or deps["@sveltejs/kit"]) then
			return true
		end
	end
	return false
end

local function configured_paths(scope)
	local paths = config.options.companions.paths or {}
	local result = {}
	local label = scope.label == "." and vim.fs.basename(scope.root) or scope.label
	local narrow = scope.companion_key
	local keys = { "*", scope.entry, label }
	if narrow then
		vim.list_extend(keys, { narrow, scope.entry .. "/" .. narrow, label .. "/" .. narrow })
	end
	for _, key in ipairs(keys) do
		for _, path in ipairs(paths[key] or {}) do
			table.insert(result, vim.fs.normalize(scope.root .. "/" .. path))
		end
	end
	return result
end

function M.collect(scope)
	local files = {}
	local roots = {}
	for _, path in ipairs(configured_paths(scope)) do
		roots[path] = true
	end

	if config.options.companions.auto_svelte then
		local relative_entry = scope.entry:gsub("^%./", "")
		local entry_dir = scope.companion_base
			or vim.fs.normalize(scope.root .. "/" .. (relative_entry == "." and "" or relative_entry))
		local ignored = {}
		walk(entry_dir, ignored, function(dir)
			if is_svelte(dir) then
				roots[dir] = true
			end
		end)
	end

	for path in pairs(roots) do
		walk(path, files)
	end
	local result = vim.tbl_keys(files)
	local root_list = vim.tbl_keys(roots)
	table.sort(result)
	table.sort(root_list)
	return result, root_list
end

return M

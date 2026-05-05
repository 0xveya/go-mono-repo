local config = require("go_mono_repo.config")

local M = {}

local uv = vim.uv or vim.loop

local function is_file(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "file"
end

local function is_dir(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "directory"
end

local function parent(path)
	local p = vim.fs.dirname(path)
	if not p or p == path then
		return nil
	end
	return p
end

local function manual_root(start, markers)
	local dir = start
	if is_file(dir) then
		dir = vim.fs.dirname(dir)
	end
	while dir do
		for _, marker in ipairs(markers) do
			if is_file(dir .. "/" .. marker) or is_dir(dir .. "/" .. marker) then
				return dir
			end
		end
		dir = parent(dir)
	end
end

function M.find(start)
	local opts = config.options
	start = start or vim.api.nvim_buf_get_name(0)
	if start == "" then
		start = uv.cwd()
	end

	local root
	if vim.fs and vim.fs.root then
		root = vim.fs.root(start, opts.root_markers)
	end
	root = root or manual_root(start, opts.root_markers)
	if not root then
		return nil, "No project root found"
	end

	local gomod = root .. "/go.mod"
	if not is_file(gomod) then
		return nil, "No go.mod found under " .. root
	end

	return root
end

function M.module_path(root)
	local lines = vim.fn.readfile(root .. "/go.mod", "", 20)
	for _, line in ipairs(lines) do
		local mod = line:match("^module%s+(.+)%s*$")
		if mod then
			return mod
		end
	end
	return nil, "Could not read module path from " .. root .. "/go.mod"
end

return M

local config = require("go_mono_repo.config")
local go = require("go_mono_repo.go")
local handlers = require("go_mono_repo.handlers")
local lsp = require("go_mono_repo.lsp")
local picker = require("go_mono_repo.picker")
local scope = require("go_mono_repo.scope")
local state = require("go_mono_repo.state")
local statusline = require("go_mono_repo.statusline")

local M = {}

local function notify(msg, level)
	if config.options.notify then
		vim.notify(msg, level or vim.log.levels.INFO, { title = "go_mono_repo" })
	end
end

local function map(lhs, rhs, desc)
	if lhs and lhs ~= "" then
		vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
	end
end

local function scoped_or_pick(cb)
	local current, err = scope.ensure()
	if current then
		cb(current)
		return
	end
	notify(err .. "; run :GoMonoPick", vim.log.levels.WARN)
end

local function set_override_maps()
	local override = config.options.override or {}
	map(override.files, function()
		if state.overrides_enabled and M.current() then
			M.files()
		else
			picker.default_files()
		end
	end, "Go mono repo files override")
	map(override.grep, function()
		if state.overrides_enabled and M.current() then
			M.grep()
		else
			picker.default_grep()
		end
	end, "Go mono repo grep override")
	map(override.symbols, function()
		if state.overrides_enabled and M.current() then
			M.symbols()
		else
			picker.default_symbols()
		end
	end, "Go mono repo symbols override")
	map(override.handlers, function()
		M.handlers()
	end, "Go mono repo handlers override")
end

local function setup_commands()
	vim.api.nvim_create_user_command("GoMonoPick", M.pick_entrypoint, { force = true })
	vim.api.nvim_create_user_command("GoMonoClear", M.clear_scope, { force = true })
	vim.api.nvim_create_user_command("GoMonoRefresh", M.refresh_scope, { force = true })
	vim.api.nvim_create_user_command("GoMonoFiles", M.files, { force = true })
	vim.api.nvim_create_user_command("GoMonoGrep", M.grep, { force = true })
	vim.api.nvim_create_user_command("GoMonoSymbols", M.symbols, { force = true })
	vim.api.nvim_create_user_command("GoMonoHandlers", M.handlers, { force = true })
	vim.api.nvim_create_user_command("GoMonoStatus", function()
		local current = M.current()
		if not current then
			notify("Go scope: all")
			return
		end
		notify(
			("Go scope: %s\nroot: %s\npackages: %d\nfiles: %d\ngenerated hidden: %d"):format(
				current.label,
				current.root,
				#(current.packages or {}),
				#(current.files or {}),
				#(current.generated_files or {})
			)
		)
	end, { force = true })
	vim.api.nvim_create_user_command("GoMonoToggleOverrides", function()
		state.overrides_enabled = not state.overrides_enabled
		notify("Go mono repo overrides " .. (state.overrides_enabled and "enabled" or "disabled"))
	end, { force = true })
end

function M.setup(opts)
	config.setup(opts)
	state.setup()
	setup_commands()
	scope.setup_autocmds()

	local km = config.options.keymaps or {}
	map(km.pick_scope, M.pick_entrypoint, "Pick Go scope")
	map(km.pick_entrypoint, M.pick_entrypoint, "Pick Go entrypoint")
	map(km.clear_scope, M.clear_scope, "Clear Go scope")
	map(km.files, M.files, "Go scoped files")
	map(km.grep, M.grep, "Go scoped grep")
	map(km.symbols, M.symbols, "Go scoped symbols")
	map(km.handlers, M.handlers, "Go route handlers")
	set_override_maps()

	local root = scope.current_root()
	if root then
		scope.restore(root)
	end
end

function M.pick_entrypoint()
	local root, err = require("go_mono_repo.root").find()
	if not root then
		notify(err, vim.log.levels.WARN)
		return
	end
	local entries = go.discover_entrypoints(root)
	if #entries == 0 then
		notify("No Go cmd entrypoints found under " .. root .. "/" .. config.options.entry_dir, vim.log.levels.WARN)
		return
	end
	picker.select_entry(entries, function(item)
		if not item then
			return
		end
		local current = scope.compute(root, item.entry, { force = true })
		if current then
			notify(("Go scope: %s, %d packages, %d files"):format(current.label, #current.packages, #current.files))
		end
	end)
end

function M.clear_scope()
	scope.clear()
end

function M.refresh_scope()
	return scope.refresh()
end

function M.files()
	scoped_or_pick(picker.files)
end

function M.grep()
	scoped_or_pick(picker.grep)
end

function M.symbols()
	scoped_or_pick(lsp.symbols)
end

function M.handlers()
	handlers.pick()
end

function M.current()
	return scope.current()
end

function M.status()
	return statusline.status()
end

return M

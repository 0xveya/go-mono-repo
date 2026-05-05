local config = require("go_mono_repo.config")
local go = require("go_mono_repo.go")
local rootmod = require("go_mono_repo.root")
local state = require("go_mono_repo.state")

local M = {}

local function notify(msg, level)
	if config.options.notify then
		vim.notify(msg, level or vim.log.levels.INFO, { title = "go_mono_repo" })
	end
end

local function cache_key(root, entry)
	return root .. "\n" .. entry
end

function M.current_root()
	local root = rootmod.find()
	return root
end

function M.current()
	local root = M.current_root()
	if not root then
		return nil
	end
	return state.selected[root]
end

function M.restore(root)
	if not config.options.persist or state.selected[root] then
		return state.selected[root]
	end
	local saved = state.load()[root]
	if not saved or not saved.entry then
		return nil
	end
	local entry = go.entry_exists(root, saved.entry)
	if not entry then
		state.persist_selection(root, nil)
		return nil
	end
	state.selected[root] = {
		root = root,
		entry = saved.entry,
		label = saved.label or entry.label,
		narrow = saved.narrow,
		updated_at = saved.updated_at,
	}
	return state.selected[root]
end

function M.set(scope)
	state.selected[scope.root] = scope
	state.scopes[cache_key(scope.root, scope.entry)] = scope
	state.persist_selection(scope.root, scope)
end

function M.clear(root)
	root = root or M.current_root()
	if not root then
		return
	end
	state.selected[root] = nil
	state.persist_selection(root, nil)
	notify("Go scope cleared")
end

function M.compute(root, entry, opts)
	opts = opts or {}
	local key = cache_key(root, entry)
	if not opts.force and state.scopes[key] then
		M.set(state.scopes[key])
		return state.scopes[key]
	end

	local previous = state.selected[root]
	local scope, err = go.compute_scope(root, entry)
	if not scope then
		notify("go list failed:\n" .. err, vim.log.levels.ERROR)
		if previous then
			state.selected[root] = previous
		end
		return nil, err
	end
	local discovered = go.entry_exists(root, entry)
	if discovered then
		scope.label = discovered.label
	end
	scope.all_files = vim.deepcopy(scope.files)
	M.set(scope)
	if previous and previous.narrow then
		local narrow = require("go_mono_repo.narrow")
		for _, item in ipairs(narrow.discover(scope)) do
			if item.constructor == previous.narrow.constructor and item.file == previous.narrow.file then
				narrow.apply(scope, item)
				break
			end
		end
	end
	return scope
end

function M.ensure()
	local root, err = rootmod.find()
	if not root then
		notify(err, vim.log.levels.WARN)
		return nil, err
	end

	local current = state.selected[root] or M.restore(root)
	if current and current.files then
		return current
	end
	if current and current.entry then
		return M.compute(root, current.entry)
	end
	return nil, "No Go entrypoint selected"
end

function M.refresh()
	local root, err = rootmod.find()
	if not root then
		notify(err, vim.log.levels.WARN)
		return nil, err
	end
	local current = state.selected[root] or M.restore(root)
	if not current or not current.entry then
		return nil, "No Go entrypoint selected"
	end
	local scope, compute_err = M.compute(root, current.entry, { force = true })
	if scope then
		notify(("Go scope: %s, %d packages, %d files"):format(scope.label, #scope.packages, #scope.files))
	end
	return scope, compute_err
end

function M.setup_autocmds()
	local group = vim.api.nvim_create_augroup("GoMonoRepo", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = { "go.mod", "go.sum" },
		callback = function(args)
			local root = rootmod.find(args.file)
			if not root then
				return
			end
			local current = state.selected[root]
			if current then
				state.scopes[cache_key(root, current.entry)] = nil
				M.compute(root, current.entry, { force = true })
			end
		end,
	})
end

return M

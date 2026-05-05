local config = require("go_mono_repo.config")

local M = {
	scopes = {},
	selected = {},
	overrides_enabled = false,
}

local state_cache

local function read_json(path)
	if vim.fn.filereadable(path) ~= 1 then
		return {}
	end
	local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if ok and type(decoded) == "table" then
		return decoded
	end
	return {}
end

local function write_json(path, data)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(vim.split(vim.json.encode(data), "\n", { plain = true }), path)
end

function M.setup()
	state_cache = nil
	M.overrides_enabled = config.options.override.enabled == true
end

function M.load()
	if not state_cache then
		state_cache = read_json(config.options.state_file)
	end
	return state_cache
end

function M.save()
	if not config.options.persist then
		return
	end
	write_json(config.options.state_file, M.load())
end

function M.persist_selection(root, selection)
	if not config.options.persist then
		return
	end
	local data = M.load()
	if selection then
		data[root] = {
			entry = selection.entry,
			label = selection.label,
			narrow = selection.narrow,
			updated_at = selection.updated_at or os.time(),
		}
	else
		data[root] = nil
	end
	M.save()
end

return M

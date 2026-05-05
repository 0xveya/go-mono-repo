local M = {}
local uv = vim.uv or vim.loop

local function has(mod)
	local ok, value = pcall(require, mod)
	if ok then
		return value
	end
end

local function prefer()
	return require("go_mono_repo.config").options.picker.prefer or {}
end

local function rel(root, path)
	return vim.fn.fnamemodify(path, ":p"):gsub("^" .. vim.pesc(vim.fn.fnamemodify(root, ":p")), "")
end

local function item_text(item)
	return item.text or item.label or item.entry or item.file or tostring(item)
end

function M.select_entry(entries, cb)
	vim.ui.select(entries, {
		prompt = "Go entrypoint",
		format_item = function(item)
			return item.label
		end,
	}, cb)
end

local function snacks_pick(opts)
	local snacks = has("snacks")
	if snacks and snacks.picker and snacks.picker.pick then
		snacks.picker.pick(opts)
		return true
	end
	local picker = has("snacks.picker")
	if picker and picker.pick then
		picker.pick(opts)
		return true
	end
	return false
end

function M.files(scope)
	local items = vim.tbl_map(function(path)
		return { text = rel(scope.root, path), file = path }
	end, scope.files)

	for _, name in ipairs(prefer()) do
		if
			name == "snacks"
			and snacks_pick({
				title = "Go scope files",
				items = items,
				format = function(item)
					return item.text
				end,
				confirm = function(picker, item)
					if picker and picker.close then
						picker:close()
					end
					vim.cmd.edit(vim.fn.fnameescape(item.file))
				end,
			})
		then
			return
		elseif name == "telescope" then
			local ok, pickers = pcall(require, "telescope.pickers")
			if ok then
				local finders = require("telescope.finders")
				local conf = require("telescope.config").values
				pickers
					.new({}, {
						prompt_title = "Go scope files",
						finder = finders.new_table({
							results = items,
							entry_maker = function(item)
								return { value = item, display = item.text, ordinal = item.text, path = item.file }
							end,
						}),
						sorter = conf.file_sorter({}),
						attach_mappings = function(bufnr)
							local actions = require("telescope.actions")
							local action_state = require("telescope.actions.state")
							actions.select_default:replace(function()
								local selected = action_state.get_selected_entry()
								actions.close(bufnr)
								vim.cmd.edit(vim.fn.fnameescape(selected.value.file))
							end)
							return true
						end,
					})
					:find()
				return
			end
		end
	end

	vim.ui.select(items, { prompt = "Go scope files", format_item = item_text }, function(item)
		if item then
			vim.cmd.edit(vim.fn.fnameescape(item.file))
		end
	end)
end

local function scope_set(scope)
	local set = {}
	for _, path in ipairs(scope.files) do
		set[vim.fs.normalize(path)] = true
	end
	return set
end

local function dirs(scope)
	local set = {}
	for _, file in ipairs(scope.files) do
		set[vim.fs.dirname(file)] = true
	end
	return vim.tbl_keys(set)
end

function M.grep(scope)
	for _, name in ipairs(prefer()) do
		if name == "telescope" then
			local ok, builtin = pcall(require, "telescope.builtin")
			if ok then
				builtin.live_grep({ search_dirs = dirs(scope) })
				return
			end
		elseif name == "snacks" then
			local snacks = has("snacks")
			local picker = snacks and snacks.picker or has("snacks.picker")
			if picker and picker.grep then
				picker.grep({ dirs = dirs(scope) })
				return
			end
		end
	end

	vim.ui.input({ prompt = "Go scope grep: " }, function(query)
		if not query or query == "" then
			return
		end
		local args = { "rg", "--vimgrep", "--no-heading", query }
		vim.list_extend(args, scope.files)
		local result = vim.system(args, { cwd = scope.root, text = true }):wait()
		local items = {}
		for line in (result.stdout or ""):gmatch("[^\n]+") do
			local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
			if file then
				table.insert(items, {
					text = rel(scope.root, file) .. ":" .. lnum .. ":" .. col .. ":" .. text,
					file = file,
					lnum = tonumber(lnum),
					col = tonumber(col),
				})
			end
		end
		vim.ui.select(items, { prompt = "Go scope grep", format_item = item_text }, function(item)
			if item then
				vim.cmd.edit(vim.fn.fnameescape(item.file))
				vim.api.nvim_win_set_cursor(0, { item.lnum, math.max(item.col - 1, 0) })
			end
		end)
	end)
end

function M.symbols(scope, symbols)
	local items = {}
	local files = scope_set(scope)
	for _, symbol in ipairs(symbols or {}) do
		local loc = symbol.location or symbol
		local uri = loc.uri or loc.targetUri
		local path = uri and vim.uri_to_fname(uri)
		if path and files[vim.fs.normalize(path)] then
			table.insert(items, { text = symbol.name .. " " .. rel(scope.root, path), symbol = symbol, file = path })
		end
	end

	vim.ui.select(items, { prompt = "Go scope symbols", format_item = item_text }, function(item)
		if item then
			vim.lsp.util.show_document(item.symbol.location or item.symbol, "utf-8", { focus = true })
		end
	end)
end

function M.handlers(items)
	local function open(item)
		local file = item.handler_file or item.file
		local line = item.handler_line or item.line or 1
		vim.cmd.edit(vim.fn.fnameescape(file))
		vim.api.nvim_win_set_cursor(0, { line, 0 })
	end

	for _, name in ipairs(prefer()) do
		if
			name == "snacks"
			and snacks_pick({
				title = "Go route handlers",
				items = items,
				format = function(item)
					return item.text
				end,
				confirm = function(p, item)
					if p and p.close then
						p:close()
					end
					open(item)
				end,
			})
		then
			return
		elseif name == "telescope" then
			local ok, pickers = pcall(require, "telescope.pickers")
			if ok then
				local finders = require("telescope.finders")
				local conf = require("telescope.config").values
				pickers
					.new({}, {
						prompt_title = "Go route handlers",
						finder = finders.new_table({
							results = items,
							entry_maker = function(item)
								return { value = item, display = item.text, ordinal = item.text }
							end,
						}),
						sorter = conf.generic_sorter({}),
						attach_mappings = function(bufnr)
							local actions = require("telescope.actions")
							local action_state = require("telescope.actions.state")
							actions.select_default:replace(function()
								local selected = action_state.get_selected_entry()
								actions.close(bufnr)
								open(selected.value)
							end)
							return true
						end,
					})
					:find()
				return
			end
		end
	end

	vim.ui.select(items, { prompt = "Go route handlers", format_item = item_text }, function(item)
		if item then
			open(item)
		end
	end)
end

function M.default_files()
	local snacks = has("snacks")
	if snacks and snacks.picker and snacks.picker.files then
		return snacks.picker.files()
	end
	local ok, builtin = pcall(require, "telescope.builtin")
	if ok then
		return builtin.find_files()
	end
	vim.cmd.edit(".")
end

function M.default_grep()
	local snacks = has("snacks")
	if snacks and snacks.picker and snacks.picker.grep then
		return snacks.picker.grep()
	end
	local ok, builtin = pcall(require, "telescope.builtin")
	if ok then
		return builtin.live_grep()
	end
	M.grep({ root = uv.cwd(), files = vim.fn.globpath(uv.cwd(), "**/*", false, true) })
end

function M.default_symbols()
	local snacks = has("snacks")
	if snacks and snacks.picker and snacks.picker.lsp_workspace_symbols then
		return snacks.picker.lsp_workspace_symbols()
	end
	local ok, builtin = pcall(require, "telescope.builtin")
	if ok then
		return builtin.lsp_workspace_symbols()
	end
	vim.lsp.buf.workspace_symbol()
end

return M

local state = require("go_mono_repo.state")

local M = {}

local function rel(root, path)
	return vim.fn.fnamemodify(path, ":p"):gsub("^" .. vim.pesc(vim.fn.fnamemodify(root, ":p")), "")
end

local function readfile(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if ok then
		return lines
	end
	return {}
end

local function first_word(use)
	return (use or ""):match("^%s*([^%s]+)")
end

local function parse_imports(lines)
	local imports = {}
	local in_block = false
	for _, line in ipairs(lines) do
		if line:match("^%s*import%s*%(") then
			in_block = true
		elseif in_block and line:match("^%s*%)") then
			in_block = false
		elseif in_block then
			local path = line:match('"([^"]+)"')
			if path then
				table.insert(imports, path)
			end
		else
			local path = line:match('^%s*import%s+"([^"]+)"')
			if path then
				table.insert(imports, path)
			end
		end
	end
	return imports
end

local function file_map(files)
	local map = {}
	local by_dir = {}
	for _, file in ipairs(files or {}) do
		local normalized = vim.fs.normalize(file)
		map[normalized] = true
		local dir = vim.fs.dirname(normalized)
		by_dir[dir] = by_dir[dir] or {}
		table.insert(by_dir[dir], normalized)
	end
	return map, by_dir
end

local function import_dir(scope, import_path)
	if not scope.module or not import_path:find("^" .. vim.pesc(scope.module) .. "/") then
		return nil
	end
	return vim.fs.normalize(scope.root .. "/" .. import_path:sub(#scope.module + 2))
end

local function collect_related_files(scope, start_file)
	local files = scope.all_files or scope.files or {}
	local _, by_dir = file_map(files)
	local included = {}
	local queue = { { file = vim.fs.normalize(start_file) } }
	local seen_dir = {}
	local seen_file = {}

	while #queue > 0 do
		local next_item = table.remove(queue, 1)
		if next_item.file then
			local file = vim.fs.normalize(next_item.file)
			if not seen_file[file] then
				seen_file[file] = true
				included[file] = true
				for _, import_path in ipairs(parse_imports(readfile(file))) do
					local dir_path = import_dir(scope, import_path)
					if dir_path and by_dir[dir_path] and not seen_dir[dir_path] then
						table.insert(queue, { dir = dir_path })
					end
				end
			end
		elseif next_item.dir then
			local dir = vim.fs.normalize(next_item.dir)
			if not seen_dir[dir] then
				seen_dir[dir] = true
				for _, file in ipairs(by_dir[dir] or {}) do
					if not seen_file[file] then
						table.insert(queue, { file = file })
					end
				end
			end
		end
	end

	local ret = vim.tbl_keys(included)
	table.sort(ret)
	return ret
end

local function find_function_blocks(lines)
	local blocks = {}
	for lnum, line in ipairs(lines) do
		local name = line:match("^func%s+([%w_]+)%s*%(")
		if name and name:match("CmdGroup$") then
			local block = {}
			for i = lnum, #lines do
				if i > lnum and lines[i]:match("^func%s+") then
					break
				end
				table.insert(block, lines[i])
			end
			table.insert(blocks, { name = name, line = lnum, text = table.concat(block, "\n") })
		end
	end
	return blocks
end

function M.discover(scope)
	local items = {}
	local seen = {}
	for _, file in ipairs(scope.all_files or scope.files or {}) do
		for _, block in ipairs(find_function_blocks(readfile(file))) do
			if block.text:find("cobra%.Command") then
				local use = block.text:match('Use:%s*"([^"]+)"')
				local label = first_word(use) or block.name:gsub("^New", ""):gsub("CmdGroup$", "")
				local aliases = block.text:match("Aliases:%s*%[%]string%s*(%b{})") or block.text:match("Aliases:%s*(%b{})")
				local alias = aliases and aliases:match('"([^"]+)"')
				local display = alias and (alias .. " -> " .. label) or label
				local key = file .. "\n" .. block.name
				if label and not seen[key] then
					seen[key] = true
					table.insert(items, {
						label = display,
						status = alias or label,
						name = label,
						alias = alias,
						constructor = block.name,
						root = scope.root,
						file = file,
						line = block.line,
						text = ("%s [%s:%d]"):format(display, rel(scope.root, file), block.line),
						files = collect_related_files(scope, file),
					})
				end
			end
		end
	end
	table.sort(items, function(a, b)
		return a.label < b.label
	end)
	return items
end

function M.apply(scope, item)
	if not scope.all_files then
		scope.all_files = vim.deepcopy(scope.files or {})
	end
	scope.narrow = {
		kind = "cobra",
		label = item.label,
		status = item.status or item.name or item.label,
		name = item.name,
		alias = item.alias,
		constructor = item.constructor,
		file = item.file,
		line = item.line,
	}
	scope.files = vim.deepcopy(item.files or {})
	state.persist_selection(scope.root, scope)
end

function M.clear(scope)
	if scope.all_files then
		scope.files = vim.deepcopy(scope.all_files)
	end
	scope.narrow = nil
	state.persist_selection(scope.root, scope)
end

return M

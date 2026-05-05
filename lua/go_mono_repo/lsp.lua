local picker = require("go_mono_repo.picker")

local M = {}

local function flatten(items, out, uri)
	out = out or {}
	for _, item in ipairs(items or {}) do
		if uri and not item.location and not item.uri then
			item.uri = uri
		end
		table.insert(out, item)
		if item.children then
			flatten(item.children, out, uri)
		end
	end
	return out
end

local function get_clients(bufnr)
	return (vim.lsp.get_clients or vim.lsp.get_active_clients)({ bufnr = bufnr })
end

local function supports_method(client, method, bufnr)
	if client.supports_method then
		return client:supports_method(method, bufnr)
	end
	return client.server_capabilities
		and (
			(method == "textDocument/documentSymbol" and client.server_capabilities.documentSymbolProvider)
			or (method == "workspace/symbol" and client.server_capabilities.workspaceSymbolProvider)
		)
end

local function request(client, method, params, callback, bufnr)
	if getmetatable(client) and client.request then
		return client:request(method, params, callback, bufnr)
	end
	return client.request(method, params, callback, bufnr)
end

local function fallback_go_symbols(scope)
	local items = {}
	for _, file in ipairs(scope.files or {}) do
		if file:match("%.go$") then
			local ok, lines = pcall(vim.fn.readfile, file)
			if ok then
				for lnum, line in ipairs(lines) do
					local recv, method = line:match("^func%s+%([^)]*%*?([%w_]+)[^)]*%)%s+([%w_]+)%s*%(")
					local func = line:match("^func%s+([%w_]+)%s*%(")
					local type_name = line:match("^type%s+([%w_]+)%s+")
					local name = method and (recv .. "." .. method) or func or type_name
					local kind = (method or func) and vim.lsp.protocol.SymbolKind.Function or vim.lsp.protocol.SymbolKind.Struct
					if name then
						table.insert(items, {
							name = name,
							kind = kind,
							location = {
								uri = vim.uri_from_fname(file),
								range = {
									start = { line = lnum - 1, character = 0 },
									["end"] = { line = lnum - 1, character = #line },
								},
							},
						})
					end
				end
			end
		end
	end
	return items
end

function M.symbols(scope)
	local clients = get_clients(0)
	if #clients == 0 then
		picker.symbols(scope, fallback_go_symbols(scope))
		return
	end

	local doc_clients = vim.tbl_filter(function(client)
		return supports_method(client, "textDocument/documentSymbol", 0)
	end, clients)
	local all = {}

	if #doc_clients == 0 then
		local workspace_clients = vim.tbl_filter(function(client)
			return supports_method(client, "workspace/symbol", 0)
		end, clients)
		local remaining = #workspace_clients
		if remaining == 0 then
			picker.symbols(scope, fallback_go_symbols(scope))
			return
		end
		for _, client in ipairs(workspace_clients) do
			request(client, "workspace/symbol", { query = "" }, function(err, result)
				remaining = remaining - 1
				if not err and result then
					vim.list_extend(all, flatten(result))
				end
				if remaining == 0 then
					if #all == 0 then
						all = fallback_go_symbols(scope)
					end
					picker.symbols(scope, all)
				end
			end, 0)
		end
		return
	end

	local pending = #doc_clients * #(scope.files or {})
	if pending == 0 then
		picker.symbols(scope, {})
		return
	end

	for _, client in ipairs(doc_clients) do
		for _, file in ipairs(scope.files or {}) do
			local uri = vim.uri_from_fname(file)
			request(client, "textDocument/documentSymbol", { textDocument = { uri = uri } }, function(err, result)
				pending = pending - 1
				if not err and result then
					vim.list_extend(all, flatten(result, nil, uri))
				end
				if pending == 0 then
					if #all == 0 then
						all = fallback_go_symbols(scope)
					end
					picker.symbols(scope, all)
				end
			end, 0)
		end
	end
end

return M

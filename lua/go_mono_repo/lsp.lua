local picker = require("go_mono_repo.picker")

local M = {}

local function flatten(items, out)
	out = out or {}
	for _, item in ipairs(items or {}) do
		table.insert(out, item)
		if item.children then
			flatten(item.children, out)
		end
	end
	return out
end

function M.symbols(scope)
	vim.ui.input({ prompt = "Go scope symbol: " }, function(query)
		if not query or query == "" then
			return
		end
		local params = { query = query }
		local clients = vim.lsp.get_clients({ bufnr = 0 })
		if #clients == 0 then
			vim.notify("No active LSP clients", vim.log.levels.WARN, { title = "go_mono_repo" })
			return
		end
		local remaining = #clients
		local all = {}
		for _, client in ipairs(clients) do
			client.request("workspace/symbol", params, function(err, result)
				remaining = remaining - 1
				if not err and result then
					vim.list_extend(all, flatten(result))
				end
				if remaining == 0 then
					picker.symbols(scope, all)
				end
			end, 0)
		end
	end)
end

return M

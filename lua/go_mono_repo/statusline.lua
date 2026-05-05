local scope = require("go_mono_repo.scope")

local M = {}

function M.status()
	local current = scope.current()
	if not current then
		return "go:all"
	end
	local label = current.label or vim.fs.basename(current.entry)
	if current.narrow and current.narrow.label then
		label = label .. "/" .. (current.narrow.status or current.narrow.label)
	end
	return "go:" .. label
end

return M

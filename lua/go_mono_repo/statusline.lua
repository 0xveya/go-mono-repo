local scope = require("go_mono_repo.scope")

local M = {}

function M.status()
	local current = scope.current()
	if not current then
		return "go:all"
	end
	return "go:" .. (current.label or vim.fs.basename(current.entry))
end

return M

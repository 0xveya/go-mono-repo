local M = {}

M.defaults = {
	root_markers = { "go.work", "go.mod", ".git" },
	entry_dir = "cmd",
	include_tests = true,
	exclude_generated = true,
	generated_header_pattern = "^// Code generated .* DO NOT EDIT%.$",

	state_file = vim.fn.stdpath("state") .. "/go_mono_repo/state.json",
	persist = true,

	picker = {
		prefer = { "snacks", "telescope", "vim_ui" },
	},

	keymaps = {
		pick_scope = nil,
		pick_entrypoint = "<leader>ge",
		narrow = nil,
		clear_narrow = nil,
		clear_scope = "<leader>gE",
		files = "<leader>gf",
		grep = "<leader>gg",
		symbols = "<leader>gs",
		handlers = "<leader>gh",
	},

	override = {
		enabled = false,
		files = nil,
		grep = nil,
		symbols = nil,
		handlers = nil,
	},

	notify = true,
	debug = false,
}

M.options = vim.deepcopy(M.defaults)

local function merge(defaults, opts)
	return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.setup(opts)
	M.options = merge(M.defaults, opts)
	return M.options
end

return M

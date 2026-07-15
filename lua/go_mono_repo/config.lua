local M = {}

M.defaults = {
	root_markers = { "go.work", "go.mod", ".git" },
	entry_dir = "cmd",
	entrypoints = {
		-- Repositories without cmd/* fall back to all local package main targets.
		fallback_main_packages = true,
		-- Enable this to also show tools/* and other main packages beside cmd/*.
		include_main_packages = false,
	},
	include_tests = true,
	exclude_generated = true,
	generated_header_pattern = "^// Code generated .* DO NOT EDIT%.$",
	companions = {
		auto_svelte = true,
		-- Extra files or directories keyed by entry, label, or "*".
		paths = {},
		exclude_dirs = { ".git", ".svelte-kit", "node_modules", "build", "dist", "coverage" },
	},

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

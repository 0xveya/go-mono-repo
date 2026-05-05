# go-mono-repo.nvim

`go-mono-repo.nvim` scopes editor navigation to the Go packages reachable from one selected `cmd/*` entrypoint in a monorepo.

In a repo with multiple Go binaries, selecting `cmd/api` means file search, grep, workspace symbols, and route handlers stay focused on packages imported by the API service. Other entrypoints, such as `cmd/worker` or `cmd/cli`, stay out of the way until you select them.

## Install

Example with `lazy.nvim`:

```lua
{
  "0xveya/go-mono-repo",
  opts = {
    persist = true,
    override = {
      enabled = true,
      files = "<leader>ff",
      grep = "<leader>fg",
      symbols = "<leader>fs",
      handlers = "<leader>fh",
    },
  },
}
```

No picker is required. The plugin tries Snacks first, then Telescope, then built-in `vim.ui` fallbacks.

## API

```lua
local gomono = require("go_mono_repo")

gomono.setup(opts)
gomono.pick_entrypoint()
gomono.narrow_scope()
gomono.clear_narrow()
gomono.clear_scope()
gomono.refresh_scope()
gomono.files()
gomono.grep()
gomono.symbols()
gomono.handlers()
gomono.current()
gomono.status()
```

Statusline integration is plugin-agnostic:

```lua
require("go_mono_repo").status()
```

It returns `go:all` when no entrypoint is selected, or values such as `go:api`, `go:worker`, and `go:cli`.

## Commands

| Command | Behavior |
| --- | --- |
| `:GoMonoPick` | Discover `cmd/*`, pick an entrypoint, compute scope |
| `:GoMonoNarrow` | Narrow the current entrypoint scope to a discovered command group |
| `:GoMonoClearNarrow` | Clear the command-group narrow filter |
| `:GoMonoClear` | Reset current repo to unscoped mode |
| `:GoMonoRefresh` | Recompute the selected entrypoint scope |
| `:GoMonoFiles` | Scoped file picker |
| `:GoMonoGrep` | Scoped live grep |
| `:GoMonoSymbols` | Scoped workspace symbols |
| `:GoMonoHandlers` | Fuzzy pick Go router handlers in the active scope, or whole module when unscoped |
| `:GoMonoStatus` | Show current entrypoint and counts |
| `:GoMonoToggleOverrides` | Toggle configured override keymaps for this session |

Default keymaps:

```lua
{
  pick_entrypoint = "<leader>ge",
  narrow = nil,
  clear_narrow = nil,
  clear_scope = "<leader>gE",
  files = "<leader>gf",
  grep = "<leader>gg",
  symbols = "<leader>gs",
  handlers = "<leader>gh",
}
```

## Configuration

```lua
require("go_mono_repo").setup({
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
    -- Alias for pick_entrypoint; useful if you prefer naming this by the scope action.
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
})
```

For example, set `keymaps.pick_scope = "<leader>ngl"` to open the scope picker with `<leader>ngl`.

Set `keymaps.narrow` to open a second-level picker for narrowing the current entrypoint scope. For example, after selecting a CLI entrypoint, `:GoMonoNarrow` can discover Cobra command groups such as `auth`, `project`, or an alias like `ctl -> cluster-control`. The picker uses the configured Snacks/Telescope preference order, previews the command-group constructor, and falls back to `vim.ui.select` when no picker is available. Scoped files, grep, symbols, and handlers then use the narrowed file set until you run `:GoMonoClearNarrow`.

## Override Keymaps

When `override.enabled = true`, configured override keys call scoped commands while a scope exists:

```lua
override = {
  enabled = true,
  files = "<leader>ff",
  grep = "<leader>fg",
  symbols = "<leader>fs",
  handlers = "<leader>fh",
}
```

If no entrypoint is selected, the keys fall back to normal picker behavior where possible: Snacks, Telescope, then built-in fallback UI. Scoped commands are always available, even when overrides are toggled off with `:GoMonoToggleOverrides`.

## Router Handlers

`:GoMonoHandlers` scans scoped files when an entrypoint is active, or the whole module when unscoped. It recognizes common Chi registrations such as:

```go
r.Route("/api/v1", func(r chi.Router) {
  r.Get("/healthz", commonhandlers.HandleHealthz)
  r.Post("/jobs/{job_name}/run", api.RunJob)
})
```

Picker rows include the HTTP method, joined route path, handler expression, and registration file. When the handler function can be resolved in the scanned file set, selecting the row jumps to the handler implementation; otherwise it jumps to the route registration.

## Scope Computation

Root detection starts from the current buffer, uses `vim.fs.root()` when available, and falls back to walking parents. A `go.mod` file is required, and the module path is read from it.

Entrypoints are immediate directories under `cmd` that contain at least one `.go` file. Selecting `cmd/api` runs:

```sh
go list -deps -json ./cmd/api
```

The plugin keeps only packages where `pkg.Module.Path` equals the current module path. It collects `GoFiles`, `CgoFiles`, and, when enabled, `TestGoFiles` and `XTestGoFiles`. Generated files matching the configured header pattern are hidden from file, grep, and symbol pickers by default, but are retained in `current().generated_files` for diagnostics.

Scopes are cached per `{ root, entry }`. The cache refreshes automatically after `go.mod` or `go.sum` writes, and can be refreshed manually with `:GoMonoRefresh`.

## Persistence

Selections are persisted per repository in:

```text
stdpath("state")/go_mono_repo/state.json
```

No state file is written into your project repo.

## Known Limitations

Dynamic plugin registration, reflection, build tags, and generated code can hide relationships from static `go list`. Manual refresh handles normal Go import changes, but the plugin does not watch every `.go` file in the initial implementation.

## Manual Acceptance

1. Open a Go monorepo that has multiple `cmd/*` entrypoints in Neovim.
2. Run `:GoMonoPick`, select one entrypoint such as `api`.
3. Confirm `require("go_mono_repo").status()` returns the selected scope, such as `go:api`.
4. Run `:GoMonoFiles` and confirm files from unrelated entrypoints are hidden.
5. Run `:GoMonoGrep` and confirm matches are limited to the selected scope.
6. Run `:GoMonoSymbols` and confirm symbols are limited to the selected scope.
7. Run `:GoMonoHandlers` and confirm route rows are limited to the active scope and jump to handler implementations.
8. Run `:GoMonoPick`, select another entrypoint such as `worker`, and confirm scoped pickers update.
9. Restart Neovim in the repo and confirm the last selected entrypoint restores from `stdpath("state")`.

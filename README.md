# dbt-lens.nvim

Neovim plugin for **dbt Core 1.x**: run models, jump to `ref()` / `source()` / macros, browse lineage,
read compiled SQL, preview rows and complete model names. Everything dbt already knows (the graph, the
files, the macros) comes from `target/manifest.json`, not from regexes over your SQL.

## Features

| | |
| --- | --- |
| **Run / test / build** | The current model, `+model`, `model+`, `+model+` or any selector. Output streams into a split, failures land in the quickfix list, a summary pops up. |
| **Go to definition** | `ref('a')`, `ref('pkg', 'a')`, `ref('a', v=2)`, `source('s', 't')` and macro calls (`money(...)`, `pkg.money(...)`), multi-line calls included. Sources open their YAML at the table, macros at `{% macro %}`. |
| **Lineage** | Upstream and downstream of a model as a tree in a sidebar: open, re-root, change depth, refresh. |
| **Compiled SQL / show** | Open the compiled SQL of a model (compiled on demand) read-only; preview a model's rows, or a visual selection as inline SQL, in a float. |
| **Completion** | A [blink.cmp](https://github.com/Saghen/blink.cmp) source for `ref('`, `ref('pkg', '`, `source('`, `source('s', '` and macro names. |
| **Pickers** | `vim.ui.select` by default; snacks.nvim and telescope.nvim pickers (with file previews) when installed. |
| **Health** | `:checkhealth dbt_lens`: dbt, project, profile, manifest, optional dependencies. |

## Requirements

- Neovim **0.11+**
- dbt Core **1.9+** (manifest schema v12). Tested with dbt-core 1.10 and dbt-duckdb; dbt-core 1.9 and 1.11 are
  covered in CI. Any adapter should work, since only dbt-core's artifacts and flags are used. dbt Fusion /
  dbt Core 2 is out of scope.
- A working dbt project and profile (`dbt parse` needs a valid profile).

## Install

With the built-in `vim.pack`:

```lua
vim.pack.add { 'https://github.com/drumandbytes/dbt-lens.nvim' }
```

There is no `setup()` to call. Configure through `vim.g.dbt_lens` (a table, or a function returning one) before
the plugin is used:

```lua
vim.g.dbt_lens = {
  cmd = nil,        -- dbt executable: string or list. Default: <root>/.venv/bin/dbt, then `uv run dbt`
                    -- when a uv.lock exists, then `dbt` on $PATH
  picker = 'auto',  -- 'auto' (snacks, then telescope, then vim.ui.select) | 'ui' | 'snacks' | 'telescope'
  keymaps = false,  -- true for the defaults below, or a table to override single keys (false disables one)
  log = { height = 15 },
  show = { limit = 20 },
  lineage = { up = 2, down = 2, width = 48, follow = false },
  manifest = { warn_mb = 100 },
}
```

## Usage

One command with completion:

```
:DbtLens status                 project, dbt command, manifest age and counts
:DbtLens refresh                dbt parse, then reload the manifest
:DbtLens run [selector]         default: the current model
:DbtLens test [selector]
:DbtLens build [selector]
:DbtLens cancel                 stop the running dbt job
:DbtLens goto [split|vsplit|tab]    definition of the ref / source / macro under the cursor
:DbtLens references             models that depend on the current model (quickfix)
:DbtLens yaml                   the model's entry in its schema YAML
:DbtLens lineage [model]
:DbtLens compiled[!]            compiled SQL; ! recompiles even if the file looks fresh
:DbtLens show [model]           dbt show; with a visual range, runs the selected SQL inline
:DbtLens models                 pick a model and open it
```

Selectors are dbt's: `name`, `+name`, `name+`, `+name+`, `1+name`, `tag:nightly`. `%` stands for the current
model (`:DbtLens build +%` builds it and everything upstream). Models are selected by their full name
(`demo.staging.stg_orders`, `demo.versioned.v2`), so versions and name clashes across packages are safe.

When the current buffer is not a model file, `run`, `compiled`, `show` and `lineage` ask which model you mean.

A `<Plug>(dbt-lens-<command>)` mapping exists for each of `run`, `test`, `build`, `models`, `refresh`,
`status`, `cancel`, `goto`, `references`, `yaml`, `lineage`, `compiled` and `show`.

### Keymaps

Off by default. With `keymaps = true` (or a table), these are set buffer-locally in SQL and Jinja files that
are inside a dbt project:

| Key | Command |
| --- | --- |
| `gd` | `goto`; when the cursor is not on a dbt reference it falls back to `vim.lsp.buf.definition()` |
| `<leader>dr` / `dt` / `db` | `run` / `test` / `build` |
| `<leader>dl` | `lineage` |
| `<leader>dc` | `compiled` |
| `<leader>ds` | `show` |
| `<leader>dm` | `models` |

Override one: `keymaps = { run = '<leader>xr', build = false }`.

### Lineage view

| Key | Action |
| --- | --- |
| `<CR>` | open the file of the node under the cursor (sources open their YAML) |
| `r` | re-root on that node |
| `+` / `-` | one level deeper / shallower (up and down) |
| `R` | `dbt parse`, then reload |
| `y` | yank `+model+` as a selector |
| `q` | close |

A node reachable by several paths is listed once and marked `↺` afterwards; `…` marks nodes with more beyond the
depth limit. With `lineage.follow = true` the view re-roots whenever you enter another model file.

### blink.cmp source

```lua
sources = {
  per_filetype = { sql = { 'lsp', 'dbt_lens', 'snippets', 'buffer' } },
  providers = { dbt_lens = { name = 'dbt', module = 'dbt_lens.blink' } },
}
```

It only answers inside a dbt project, and only where it is useful: inside `ref(`, `source(`, or an open
`{{ }}` / `{% %}` block (macros).

### Telescope

`:Telescope dbt_lens models` after `require('telescope').load_extension 'dbt_lens'`.

## How it works

dbt-lens reads `target/manifest.json` (cached by modification time; if dbt is rewriting it, the last good
copy is kept) and builds an index of models, sources, macros and the parent/child graph. Nothing re-parses
silently: `:DbtLens refresh` (or any `run` / `build` / `compile`, which rewrite the manifest) updates it, and
the lineage winbar shows the manifest's age.

Commands that talk to dbt run it with `vim.system` in the project root, as an argument list (no shell). The
project root is found per buffer from `dbt_project.yml`; buffers with a URI scheme (`oil://`, `fugitive://`)
start from the working directory.

## Troubleshooting

- **"no manifest"**: run `:DbtLens refresh`. It needs a valid profile; `:checkhealth dbt_lens` shows which
  `profiles.yml` dbt will use.
- **dbt not found**: it must be on `$PATH`, in `<root>/.venv/bin`, run through `uv run` (with a `uv.lock`), or
  set via `vim.g.dbt_lens.cmd = { 'uvx', '--from', 'dbt-core==1.10.*', ... , 'dbt' }`.
- **`dbt parse` fails on a `ref()` inside a SQL comment**: dbt evaluates Jinja in `-- comments` too. Use
  `{# #}` for commented-out refs.
- **A macro "is not on disk"**: it lives in a package that is not installed (`dbt deps`).
- **dbt-core below 1.9** is not supported.

## Development

```sh
make test               # unit tests (mini.test, headless)
make test-integration   # real dbt-core 1.10 + dbt-duckdb through uvx
scripts/gen-fixture.sh  # regenerate tests/fixtures/manifest.json
```

## Prior art

[dbtpal](https://github.com/PedramNavid/dbtpal), [dbt-forge.nvim](https://github.com/gbakes/dbt-forge),
[dbt.nvim](https://github.com/EloiSanchez/dbt.nvim), [cmp-dbt](https://github.com/MattiasMTS/cmp-dbt).

## License

MIT

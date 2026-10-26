# CLAUDE.md

Neovim plugin for **dbt Core 1.x** (`drumandbytes/dbt-lens.nvim`, private): run dbt, go to ref/source/macro,
lineage tree, compiled SQL / `dbt show`, blink.cmp source. Lua, Neovim 0.11+, dbt-core 1.9+.
User docs: `README.md`, `doc/dbt-lens.txt`. This file is for whoever (human or Claude) changes the code next.

## Status: what is and is not verified

Verified: 79 unit tests and an integration test (`make test-integration`) against dbt-core 1.10 +
dbt-duckdb; CI green (stylua, luacheck, unit tests on Neovim 0.11.7 and stable, integration); the Telescope
picker live.

**Not verified yet** (check these first when it is used on a real project):
dbt-starrocks / any adapter other than duckdb; dbt-core 1.9 and 1.11 (CI does not pin them yet, only the
`dbt show` output was compared on 1.9 and 1.10); the snacks picker and blink.cmp against the real plugins
(only a fake `Snacks` and blink's documented source API are tested); big real manifests (decode was benchmarked on
synthetic 70 and 278 MB files: ~80 ms and ~330 ms); projects using `packages-install-path`, `model-paths` other
than `models`, or seeds/snapshots.

## Commands

```sh
make test                 # unit tests, headless mini.test (clones mini.nvim into .deps/ on first run)
make test-integration     # real dbt via uvx (needs uv); ~10 s
scripts/gen-fixture.sh    # regenerate tests/fixtures/manifest.json after changing the fixture project
nvim --headless -l scripts/bench-decode.lua 500   # manifest decode benchmark
```

Format with StyLua (`.stylua.toml`); CI runs `stylua --check` and luacheck (`.luacheckrc`). Locally:
`mise exec aqua:JohnnyMorganz/StyLua -- stylua .`. luacheck is not installable through mise, so CI is where it runs.
`:checkhealth dbt_lens` (underscore, not dash).

## Layout and the one layering rule

```
plugin/dbt-lens.lua          :DbtLens command + <Plug> maps. Tiny, no requires at load.
ftplugin/{sql,jinja}.lua     buffer-local keymaps, only when vim.g.dbt_lens is set
lua/dbt_lens/
  init.lua      :DbtLens subcommand table + completion, goto_definition()
  config.lua    vim.g.dbt_lens merged over defaults, validated; unknown keys reported by health
  project.lua   root per buffer, dbt_project.yml scan, dbt command resolution, abs_path / rel_path
  manifest.lua  build_index (pure), resolve_ref (pure), node_for_path (pure), load (mtime cache)
  graph.lua     PURE: depth-limited tree walk, selector strings
  lineage.lua   build() rows (pure) + the sidebar window
  nav.lua       PURE text scanning for ref/source/macro + resolve() through the index
  complete.lua  PURE completion context + items; blink.lua is the thin adapter
  runner.lua    vim.system wrapper, selector expansion, run_results -> summary/quickfix
  compiled.lua  compile on demand, dbt show; float.lua, log.lua, pick.lua (backends), keymaps.lua, health.lua
lua/telescope/_extensions/dbt_lens.lua
tests/          mini.test specs; fixtures/ = a dbt-duckdb project + local package + a trimmed real manifest
```

Rule: modules marked PURE take plain tables/strings and never touch buffers or windows, so they are tested with
fixtures and no editor state. Put new logic there and keep the UI modules thin.

## Decisions that are not obvious from the code

- **Manifest-first.** Graph, files and macros come from `manifest.json`; the only text scanning is locating a
  ref in the buffer and a macro/source definition line in a file (the manifest has **no line positions**).
- **Selectors use the fqn** (`demo.staging.stg_orders`, `demo.versioned.v2`), not the bare name: unambiguous for
  versioned models and name clashes across packages. `%` in a user selector expands to it.
- **`by_file` is keyed `<package>:<original_file_path>`**: package files have package-relative paths, so
  `models/shared.sql` exists in two packages in the fixture.
- **Test, analysis and disabled nodes are dropped from the graph at both ends** (otherwise models get phantom
  test children); failing tests are still resolvable for the quickfix through `idx.tests`.
- **Versioned models:** unique id `model.<pkg>.<name>.v<N>`; `ref('m')` without `v=` means the latest version.
- **`dbt show` prints a markdown table by default** (`--quiet`), identical on 1.9 and 1.10, so it is shown as is;
  no JSON rendering (`--output json` is `{node, show:[...]}` if ever needed).
- **Compiled path** is `<target>/compiled/<package>/<original_file_path>`. Stale when missing or older than the
  source (`:DbtLens compiled!` forces).
- **Manifest decode stays on the main thread** (benchmarked, fast enough); the last good index is kept when the
  file is unreadable mid-write. Any run/build/compile invalidates the cache (dbt rewrites the manifest).
- **No mandatory `setup()`**; `gd` is never mapped globally, only opt-in buffer-locally with an LSP fallback.
- **sqruff/dbt templater:** the dbt templater cannot run inside an LSP (no stdin); that is the user's dotfiles
  concern, not this plugin's.
- dbt Fusion / dbt Core 2 is out of scope (dbt-starrocks has no plan for it).

## dbt gotchas met while building

- `dbt parse` needs a valid profile; a bad `ref()` (even inside a `--` SQL comment, dbt evaluates Jinja there) aborts
  it and writes no manifest.
- `target-path` in `dbt_project.yml` is deprecated in dbt 1.10 (still honoured; `DBT_TARGET_PATH` wins here too).
- Two models with the same relation name across packages fail the parse: give one an `alias` (fixture does).
- `uvx --from dbt-duckdb` pulls the **latest** dbt-core (1.12 at the time); pin `dbt-core==1.10.*` for anything
  reproducible. macOS tmp paths: use `/private/tmp`, not `/tmp`, wherever dbt matches files by path.

## Testing gotchas

- Tests run with `--noplugin`; `tests/minimal_init.lua` sources `plugin/dbt-lens.lua` itself.
- Do not `cd` inside tests (later tests use repo-relative paths); copy the fixture project to a temp dir and use
  absolute paths (`fs_realpath` it: macOS `/var` is a symlink).
- `ipairs` stops at the first nil in a table literal, so filter lists such as `{ vim.env.X, ... }` first.
- StyLua rewrites files, run it before committing or `--check` fails in CI. luacheck: `Snacks` is a declared
  read-only global; `212/self` is ignored because blink sources are method tables.

## Workflow

- `main` is protected by an org ruleset (pull request + "Required checks passed"); admins can push through but
  should not. Branch, PR, wait for CI, merge only when the owner says so.
- Never add `Co-Authored-By` or other attribution to commits.
- The design document and milestone plan (M0-M7, all done) live outside the repo (`~/dev/dbt-lens-DESIGN.md` on the
  author's machine) and are not part of it; keep this file and the README current instead.
- User-visible change: update `README.md` and `doc/dbt-lens.txt` (a test checks the vimdoc builds tags) and
  `CHANGELOG.md`.

## Ideas not built

Rail/lane graph renderer for lineage (dbt-forge style, behind the same `graph.tree` data); column completion
from `catalog.json` or YAML; `--defer --favor-state` toggle; dbt-codegen helpers; `run_results.json` history
picker; unit-test shortcuts; treesitter YAML lookup instead of the line scan for sources; CI matrix over
dbt-core 1.9 / 1.11; luarocks / release-please once public.

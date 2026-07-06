# worktree-switcher.nvim — Design

## Purpose

A small Neovim plugin that lists the git worktrees of the current repository in a
picker and, on selection, switches the editor's workspace to that worktree:
change the global working directory and fire a user-supplied callback so config
can update state such as `vim.g.project_root`.

Prefers the [snacks.nvim](https://github.com/folke/snacks.nvim) picker when
available and falls back to `vim.ui.select` so it works in a bare Neovim.

## Scope

In scope:
- List worktrees of the repo anchored at the current file's directory (fallback cwd).
- Pick one via Snacks picker, or `vim.ui.select` fallback.
- On selection: global `:cd` to the worktree, then invoke `on_switch(wt)`.

Out of scope (YAGNI, may add later):
- Creating / removing / pruning worktrees.
- Tab-local (`:tcd`) or window-local (`:lcd`) directory changes.
- Setting `vim.g.project_root` inside the plugin — that is the user's callback's job.

## Module structure

Three small modules, each with one purpose and a narrow interface.

### `lua/worktree-switcher/git.lua` — worktree discovery
- `list(anchor_dir, cb)`:
  - Runs `git worktree list --porcelain` via `vim.system` (async) with `cwd = anchor_dir`.
  - On success, parses porcelain output into a list of worktree items and calls
    `cb(nil, items)`.
  - On failure (not a repo, git missing, non-zero exit), calls `cb(err_string, nil)`.
- Worktree item shape:
  ```lua
  {
    path     = "/abs/path/to/worktree", -- from `worktree` line
    head     = "abc123def...",          -- from `HEAD` line (nil if bare)
    branch   = "feature/x",             -- short branch name from `branch refs/heads/...` (nil if detached/bare)
    bare     = false,                   -- true if `bare` line present
    detached = false,                   -- true if `detached` line present
  }
  ```
- Porcelain parsing: records are separated by blank lines; each record is a set
  of `key value` lines (`worktree`, `HEAD`, `branch`, plus bare flags `bare` /
  `detached`). `branch refs/heads/foo` is shortened to `foo`.

### `lua/worktree-switcher/picker.lua` — UI with fallback
- `open(items, current_path, on_choice)`:
  - If `Snacks` global and `Snacks.picker` exist → open a Snacks picker whose items
    are the worktrees. Each row shows the branch (or `(detached)`/`(bare)`) and the
    path; the item matching `current_path` is marked (e.g. a `*` prefix / distinct
    highlight). Confirm calls `on_choice(wt)`.
  - Else → build display strings and call `vim.ui.select(items, { prompt, format_item }, on_choice)`.
  - The picker module knows nothing about git or `cd`; it only renders items and
    reports the chosen `wt` via `on_choice`.

### `lua/worktree-switcher/init.lua` — public API + config
- `setup(opts)` — stores config. Options:
  - `on_switch = function(wt) end` — called after a successful `cd`. Optional.
- `pick()` — entry point to bind to a key:
  1. Resolve the anchor dir: directory of the current buffer's file if it names a
     real file on disk, else `vim.fn.getcwd()`.
  2. `git.list(anchor, cb)`.
     - On error → `vim.notify(err, WARN)` and stop.
     - On empty → `vim.notify("no worktrees", INFO)` and stop (shouldn't normally happen).
  3. Determine `current_path` = current global cwd (normalised) for marking.
  4. `picker.open(items, current_path, function(wt) M.switch(wt) end)`.
- `switch(wt)`:
  1. `local ok, err = pcall(vim.cmd.cd, wt.path)` (global `:cd`).
  2. On failure → `vim.notify("cd failed: " .. err, ERROR)`, do NOT call `on_switch`.
  3. On success → if `config.on_switch` then `pcall(config.on_switch, wt)` (guarded
     so a broken callback doesn't throw a raw error at the user); notify the switch.

## Data flow

```
pick()
  -> resolve anchor dir
  -> git.list(anchor, cb)          [async vim.system]
  -> picker.open(items, current, on_choice)
  -> on_choice(wt) == switch(wt)
  -> vim.cmd.cd(wt.path)           [global]
  -> config.on_switch(wt)          [user updates vim.g.project_root etc.]
```

## Error handling

| Condition            | Behaviour                                             |
|----------------------|-------------------------------------------------------|
| Not in a git repo    | `notify(WARN)`, no picker.                             |
| git not on PATH      | `notify(WARN)` with the error, no picker.             |
| Zero/one worktree    | Still open picker if ≥1; notify INFO only if empty.   |
| `cd` fails           | `notify(ERROR)`; `on_switch` NOT called.              |
| `on_switch` throws   | `pcall`-guarded; `notify(ERROR)` with the message.    |

## Testing

- `git.lua` parser: unit-test `parse(porcelain_string)` against sample
  `git worktree list --porcelain` outputs — normal branch, detached HEAD, bare
  main, multiple worktrees. Pure function, no git needed.
- Manual/integration: in a repo with `git worktree add`, run `pick()`, confirm the
  picker lists all worktrees, selecting one changes `getcwd()` and fires `on_switch`.

## User config example (README)

```lua
require("worktree-switcher").setup({
  on_switch = function(wt)
    vim.g.project_root = wt.path
    vim.g.project_path = wt.path
  end,
})
vim.keymap.set("n", "<leader>gw", require("worktree-switcher").pick, { desc = "Switch worktree" })
```

## Local development wiring (lazy.nvim)

The plugin source lives at `~/personal/worktree-switcher.nvim` and is published to
`github.com/jackielii/worktree-switcher.nvim`. For local testing it is loaded into
the user's config via a lazy.nvim spec that points at the local checkout with
`dir=`, so edits in `~/personal/...` take effect on restart without going through
GitHub.

File: `~/.config/nvim/lua/plugins/worktree-switcher.lua`

```lua
return {
  dir = vim.fn.expand("~/personal/worktree-switcher.nvim"),
  -- url when published: "jackielii/worktree-switcher.nvim",
  keys = {
    { "<leader>gw", function() require("worktree-switcher").pick() end, desc = "Switch worktree" },
  },
  opts = {
    on_switch = function(wt)
      vim.g.project_root = wt.path
      vim.g.project_path = wt.path
    end,
  },
}
```

`init.lua`'s `setup(opts)` is what lazy.nvim calls with `opts` (lazy calls
`require("worktree-switcher").setup(opts)` because the module name is derived from
the spec; the `main`/module resolution is standard lazy behaviour for a plugin
whose lua module matches its directory name).

## Repo layout

```
worktree-switcher.nvim/
├── README.md
├── lua/worktree-switcher/
│   ├── init.lua
│   ├── git.lua
│   └── picker.lua
└── docs/superpowers/specs/2026-07-06-worktree-switcher-design.md
```

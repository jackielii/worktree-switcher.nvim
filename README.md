# worktree-switcher.nvim

List the git worktrees of the current repository in a picker and switch your
workspace to the selected one: it runs a global `:cd` to the worktree and fires
an `on_switch(wt)` callback so you can update your own state.

Uses [snacks.nvim](https://github.com/folke/snacks.nvim)'s picker when available,
falling back to `vim.ui.select`.

## Install (lazy.nvim)

```lua
{
  "jackielii/worktree-switcher.nvim",
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

## API

- `require("worktree-switcher").setup(opts)` — `opts.on_switch = function(wt) end`.
- `require("worktree-switcher").pick()` — list worktrees and switch on selection.

Each `wt` passed to `on_switch` is:

```lua
{ path = string, head = string|nil, branch = string|nil, bare = boolean, detached = boolean }
```

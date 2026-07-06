# worktree-switcher.nvim

List the git worktrees of the current repository in a picker and switch your
workspace to the selected one: it runs a global `:cd` to the worktree and fires
an `on_switch(wt)` callback so you can update your own state.

If the current buffer's file lives inside the worktree you're leaving, it opens
the file at the same relative path in the new worktree (when that file exists
there) so you stay on the same file across the switch.

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

- `require("worktree-switcher").setup(opts)` — options:
  - `on_switch = function(wt) end` — called after a successful switch.
  - `follow_current_file = true` — open the equivalent file in the new worktree
    (see above). Set to `false` to always keep the current buffer.
- `require("worktree-switcher").pick()` — list worktrees and switch on selection.

Each `wt` passed to `on_switch` is:

```lua
{ path = string, head = string|nil, branch = string|nil, bare = boolean, detached = boolean }
```

### Example: re-root the snacks explorer on switch

`on_switch` is where you sync app state. For example, to point the snacks file
explorer at the new worktree:

```lua
on_switch = function(wt)
  vim.g.project_root = wt.path
  local explorer = Snacks.picker.get({ source = "explorer" })[1]
  if explorer and not explorer.closed then
    explorer:set_cwd(wt.path)
  end
end,
```

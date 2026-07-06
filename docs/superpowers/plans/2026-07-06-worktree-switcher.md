# worktree-switcher.nvim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Neovim plugin that lists the current repo's git worktrees in a picker (snacks.nvim, with `vim.ui.select` fallback) and, on selection, `:cd`s to the worktree and fires an `on_switch(wt)` callback.

**Architecture:** Three focused Lua modules under `lua/worktree-switcher/`: `git.lua` (async discovery + pure porcelain parser), `picker.lua` (Snacks or `vim.ui.select` UI), `init.lua` (config + `pick`/`switch` orchestration). The parser is a pure function so it is unit-testable without git or a live editor.

**Tech Stack:** Lua, Neovim `vim.system`/`vim.ui.select`, optional `Snacks.picker`. Tests run via `nvim -l` (Neovim's Lua interpreter mode).

## Global Constraints

- Plugin root: `~/personal/worktree-switcher.nvim`; lua module namespace: `worktree-switcher`.
- Published as `github.com/jackielii/worktree-switcher.nvim`.
- `git.parse(text)` MUST be pure — no `vim.*` calls — so it runs under `nvim -l` without a UI.
- Directory changes use global `:cd` (`vim.cmd.cd`), never `:tcd`/`:lcd`.
- The plugin MUST NOT set `vim.g.project_root` itself; that is the user's `on_switch` callback's job.
- Worktree item shape (used across all modules):
  ```lua
  { path = string, head = string|nil, branch = string|nil, bare = boolean, detached = boolean }
  ```

---

### Task 1: git module — porcelain parser + async list

**Files:**
- Create: `~/personal/worktree-switcher.nvim/lua/worktree-switcher/git.lua`
- Test: `~/personal/worktree-switcher.nvim/tests/git_spec.lua`

**Interfaces:**
- Produces:
  - `M.parse(text: string) -> item[]` — pure; parses `git worktree list --porcelain` output.
  - `M.list(anchor_dir: string, cb: fun(err: string|nil, items: item[]|nil))` — async via `vim.system`.
  - `item = { path=string, head=string|nil, branch=string|nil, bare=boolean, detached=boolean }`.

- [ ] **Step 1: Write the failing test**

Create `tests/git_spec.lua`:

```lua
-- Run with: nvim -l tests/git_spec.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local git = require("worktree-switcher.git")

local failures = 0
local function check(name, cond)
  if cond then
    print("ok - " .. name)
  else
    failures = failures + 1
    print("NOT OK - " .. name)
  end
end

-- Sample porcelain output: main worktree on a branch, one detached, one bare.
local sample = table.concat({
  "worktree /home/u/proj",
  "HEAD 1111111111111111111111111111111111111111",
  "branch refs/heads/main",
  "",
  "worktree /home/u/proj-feat",
  "HEAD 2222222222222222222222222222222222222222",
  "branch refs/heads/feature/x",
  "",
  "worktree /home/u/proj-detached",
  "HEAD 3333333333333333333333333333333333333333",
  "detached",
  "",
  "worktree /home/u/proj-bare",
  "bare",
  "",
}, "\n")

local items = git.parse(sample)
check("parses 4 worktrees", #items == 4)
check("first path", items[1].path == "/home/u/proj")
check("first head", items[1].head == "1111111111111111111111111111111111111111")
check("first branch shortened", items[1].branch == "main")
check("first not detached", items[1].detached == false)
check("first not bare", items[1].bare == false)
check("second branch keeps slashes", items[2].branch == "feature/x")
check("detached flagged", items[3].detached == true)
check("detached has no branch", items[3].branch == nil)
check("bare flagged", items[4].bare == true)
check("bare has no head", items[4].head == nil)
check("bare has no branch", items[4].branch == nil)

-- Trailing-whitespace / no final blank line still parses the last record.
local no_trailing = "worktree /a\nHEAD 4444444444444444444444444444444444444444\nbranch refs/heads/dev"
local items2 = git.parse(no_trailing)
check("parses record without trailing blank", #items2 == 1 and items2[1].branch == "dev")

if failures > 0 then
  os.exit(1)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/personal/worktree-switcher.nvim && nvim -l tests/git_spec.lua`
Expected: FAIL — `module 'worktree-switcher.git' not found`.

- [ ] **Step 3: Write minimal implementation**

Create `lua/worktree-switcher/git.lua`:

```lua
local M = {}

--- Parse `git worktree list --porcelain` output into worktree items.
--- Pure function: no vim.* calls, unit-testable under `nvim -l`.
--- @param text string
--- @return table[] items
function M.parse(text)
  local items = {}
  local cur = nil

  local function flush()
    if cur then
      cur.bare = cur.bare or false
      cur.detached = cur.detached or false
      items[#items + 1] = cur
      cur = nil
    end
  end

  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line == "" then
      flush()
    else
      local key, rest = line:match("^(%S+)%s*(.*)$")
      if key == "worktree" then
        flush()
        cur = { path = rest }
      elseif key == "HEAD" then
        if cur then cur.head = rest end
      elseif key == "branch" then
        if cur then cur.branch = (rest:gsub("^refs/heads/", "")) end
      elseif key == "bare" then
        if cur then cur.bare = true end
      elseif key == "detached" then
        if cur then cur.detached = true end
      end
    end
  end
  flush()
  return items
end

--- List worktrees of the repo containing `anchor_dir`, asynchronously.
--- @param anchor_dir string
--- @param cb fun(err: string|nil, items: table[]|nil)
function M.list(anchor_dir, cb)
  vim.system(
    { "git", "worktree", "list", "--porcelain" },
    { cwd = anchor_dir, text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          local msg = (res.stderr and res.stderr ~= "" and res.stderr)
            or ("git worktree list failed (exit " .. tostring(res.code) .. ")")
          cb(vim.trim(msg), nil)
          return
        end
        cb(nil, M.parse(res.stdout or ""))
      end)
    end
  )
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/personal/worktree-switcher.nvim && nvim -l tests/git_spec.lua`
Expected: all `ok - ...` lines, exit code 0.

- [ ] **Step 5: Commit**

```bash
cd ~/personal/worktree-switcher.nvim
git add lua/worktree-switcher/git.lua tests/git_spec.lua
git commit -m "feat: git worktree porcelain parser and async list"
```

---

### Task 2: picker module — Snacks with vim.ui.select fallback

**Files:**
- Create: `~/personal/worktree-switcher.nvim/lua/worktree-switcher/picker.lua`

**Interfaces:**
- Consumes: `item` shape from Task 1.
- Produces:
  - `M.open(items: item[], current_path: string, on_choice: fun(item))` — renders the
    picker and calls `on_choice(item)` with the chosen worktree (never called if cancelled).
  - `M.label(item: item) -> string` — display string for one worktree (pure helper, reused by both backends).

- [ ] **Step 1: Write the failing test**

Append to `tests/git_spec.lua` a second block covering the pure label helper (the
interactive `open` is verified manually in Task 4):

```lua
-- picker.label formatting (pure)
local picker = require("worktree-switcher.picker")
check("label shows branch", picker.label({ path = "/a", branch = "main" }):find("main", 1, true) ~= nil)
check("label shows path", picker.label({ path = "/a/b", branch = "main" }):find("/a/b", 1, true) ~= nil)
check("label detached", picker.label({ path = "/a", detached = true }):find("detached", 1, true) ~= nil)
check("label bare", picker.label({ path = "/a", bare = true }):find("bare", 1, true) ~= nil)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/personal/worktree-switcher.nvim && nvim -l tests/git_spec.lua`
Expected: FAIL — `module 'worktree-switcher.picker' not found`.

- [ ] **Step 3: Write minimal implementation**

Create `lua/worktree-switcher/picker.lua`:

```lua
local M = {}

--- Human-readable label for a worktree item. Pure.
--- @param item table
--- @return string
function M.label(item)
  local ref
  if item.bare then
    ref = "(bare)"
  elseif item.detached then
    ref = "(detached)"
  elseif item.branch then
    ref = item.branch
  else
    ref = (item.head and item.head:sub(1, 7)) or "(unknown)"
  end
  return string.format("%-30s %s", ref, item.path)
end

local function open_snacks(items, current_path, on_choice)
  local finder_items = {}
  for i, wt in ipairs(items) do
    finder_items[#finder_items + 1] = {
      idx = i,
      text = M.label(wt),
      wt = wt,
      current = wt.path == current_path,
    }
  end
  Snacks.picker({
    title = "Git Worktrees",
    items = finder_items,
    format = function(pick_item)
      local prefix = pick_item.current and "* " or "  "
      return { { prefix, "SnacksPickerSpecial" }, { pick_item.text, "SnacksPickerFile" } }
    end,
    confirm = function(pick, pick_item)
      pick:close()
      if pick_item then
        on_choice(pick_item.wt)
      end
    end,
  })
end

local function open_ui_select(items, current_path, on_choice)
  vim.ui.select(items, {
    prompt = "Git Worktrees",
    format_item = function(wt)
      local marker = wt.path == current_path and "* " or "  "
      return marker .. M.label(wt)
    end,
  }, function(choice)
    if choice then
      on_choice(choice)
    end
  end)
end

--- Open a picker over worktrees; call on_choice(item) with the selection.
--- @param items table[]
--- @param current_path string
--- @param on_choice fun(item: table)
function M.open(items, current_path, on_choice)
  if _G.Snacks and Snacks.picker then
    open_snacks(items, current_path, on_choice)
  else
    open_ui_select(items, current_path, on_choice)
  end
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/personal/worktree-switcher.nvim && nvim -l tests/git_spec.lua`
Expected: all `ok - ...` lines including the new label checks, exit code 0.

- [ ] **Step 5: Commit**

```bash
cd ~/personal/worktree-switcher.nvim
git add lua/worktree-switcher/picker.lua tests/git_spec.lua
git commit -m "feat: worktree picker with Snacks and vim.ui.select fallback"
```

---

### Task 3: init module — setup, pick, switch

**Files:**
- Create: `~/personal/worktree-switcher.nvim/lua/worktree-switcher/init.lua`

**Interfaces:**
- Consumes: `git.list` (Task 1), `picker.open` (Task 2).
- Produces:
  - `M.setup(opts: { on_switch?: fun(item) })`
  - `M.pick()` — entry point to bind to a key.
  - `M.switch(item)` — `:cd` then `on_switch`.

- [ ] **Step 1: Write the implementation**

There is no pure unit surface here (all paths touch the editor/git); this task is
verified via the manual integration check in Task 4. Create `lua/worktree-switcher/init.lua`:

```lua
local git = require("worktree-switcher.git")
local picker = require("worktree-switcher.picker")

local M = {}

M.config = { on_switch = nil }

--- @param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
end

--- Directory to anchor `git worktree list` on: the current file's dir, else cwd.
--- @return string
local function anchor_dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.uv.fs_stat(name) then
    return vim.fs.dirname(name)
  end
  return vim.fn.getcwd()
end

--- Change the global cwd to the worktree and fire on_switch.
--- @param wt table
function M.switch(wt)
  local ok, err = pcall(function()
    vim.cmd.cd(vim.fn.fnameescape(wt.path))
  end)
  if not ok then
    vim.notify("worktree-switcher: cd failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  vim.notify("worktree-switcher: " .. wt.path, vim.log.levels.INFO)
  if M.config.on_switch then
    local cb_ok, cb_err = pcall(M.config.on_switch, wt)
    if not cb_ok then
      vim.notify("worktree-switcher: on_switch error: " .. tostring(cb_err), vim.log.levels.ERROR)
    end
  end
end

--- List worktrees and open the picker; selection switches the workspace.
function M.pick()
  git.list(anchor_dir(), function(err, items)
    if err then
      vim.notify("worktree-switcher: " .. err, vim.log.levels.WARN)
      return
    end
    if not items or #items == 0 then
      vim.notify("worktree-switcher: no worktrees found", vim.log.levels.INFO)
      return
    end
    local current = vim.fn.getcwd()
    picker.open(items, current, function(wt)
      M.switch(wt)
    end)
  end)
end

return M
```

- [ ] **Step 2: Smoke-check the module loads**

Run: `cd ~/personal/worktree-switcher.nvim && nvim -l -c 'lua require("worktree-switcher")' -c 'qa' 2>&1; echo "exit: $status"`

Alternative (portable) smoke check:

Run: `cd ~/personal/worktree-switcher.nvim && nvim --headless -c 'lua require("worktree-switcher").setup({})' -c 'qa' 2>&1; echo done`
Expected: no Lua error, prints `done`.

- [ ] **Step 3: Commit**

```bash
cd ~/personal/worktree-switcher.nvim
git add lua/worktree-switcher/init.lua
git commit -m "feat: setup/pick/switch orchestration"
```

---

### Task 4: README, lazy.nvim wiring, and manual integration verification

**Files:**
- Create: `~/personal/worktree-switcher.nvim/README.md`
- Create: `~/.config/nvim/lua/plugins/worktree-switcher.lua`

**Interfaces:**
- Consumes: `M.setup`, `M.pick` (Task 3).

- [ ] **Step 1: Write the README**

Create `~/personal/worktree-switcher.nvim/README.md`:

```markdown
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
```

- [ ] **Step 2: Wire it into the nvim config for local dev**

Create `~/.config/nvim/lua/plugins/worktree-switcher.lua`:

```lua
return {
  dir = vim.fn.expand("~/personal/worktree-switcher.nvim"),
  -- switch to `"jackielii/worktree-switcher.nvim"` once published
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

- [ ] **Step 3: Manual integration test**

Set up worktrees and drive the plugin:

```bash
cd ~/personal/worktree-switcher.nvim
git worktree add ../wts-test-feat -b wts-test-feat 2>/dev/null || true
```

In Neovim (restart so lazy picks up the new spec), from inside the repo:
1. Press `<leader>gw`.
2. Confirm the picker lists both `worktree-switcher.nvim` and `wts-test-feat`,
   with the current one marked `*`.
3. Select `wts-test-feat`.
4. Run `:pwd` — confirm it changed to the `wts-test-feat` worktree path.
5. Run `:lua print(vim.g.project_root)` — confirm it equals that path.

Cleanup:

```bash
cd ~/personal/worktree-switcher.nvim && git worktree remove ../wts-test-feat --force 2>/dev/null || true
```

- [ ] **Step 4: Commit**

```bash
cd ~/personal/worktree-switcher.nvim
git add README.md
git commit -m "docs: README with install and API"
```

(The `~/.config/nvim/lua/plugins/worktree-switcher.lua` file lives in the separate
nvim-config repo; commit it there if that repo is tracked.)

---

### Task 5: Publish to GitHub

**Files:** none (repo operations only).

- [ ] **Step 1: Create the remote and push**

```bash
cd ~/personal/worktree-switcher.nvim
gh repo create jackielii/worktree-switcher.nvim --public --source=. --remote=origin --description "List git worktrees in a picker and switch your Neovim workspace"
git push -u origin HEAD
```

Expected: repo created, `main` pushed. (Confirm with the user before running — this is outward-facing.)

- [ ] **Step 2: Verify**

Run: `gh repo view jackielii/worktree-switcher.nvim --web` (optional) or `git remote -v`.
Expected: `origin` points at `github.com/jackielii/worktree-switcher.nvim`.

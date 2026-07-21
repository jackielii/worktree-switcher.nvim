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

--- Build the Snacks finder item for a worktree. Pure.
--- Wired for Snacks' `git_log` previewer (the one its `git_branches` source
--- uses): `cwd` scopes `git log` to this worktree and `commit` anchors it at the
--- checked-out tip, so the preview shows the worktree's branch history rather
--- than a directory file listing. Bare worktrees have no head, so `commit` is
--- nil and git falls back to the repo's default branch.
--- @param wt table
--- @param idx integer
--- @param current_path string
--- @return table
function M.finder_item(wt, idx, current_path)
  return {
    idx = idx,
    text = M.label(wt),
    wt = wt,
    current = wt.path == current_path,
    cwd = wt.path,
    commit = wt.head,
  }
end

local function open_snacks(items, current_path, on_choice)
  local finder_items = {}
  for i, wt in ipairs(items) do
    finder_items[#finder_items + 1] = M.finder_item(wt, i, current_path)
  end
  Snacks.picker({
    title = "Git Worktrees",
    items = finder_items,
    preview = "git_log",
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

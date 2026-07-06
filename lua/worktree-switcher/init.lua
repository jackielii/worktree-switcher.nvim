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

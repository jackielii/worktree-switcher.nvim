local git = require("worktree-switcher.git")
local picker = require("worktree-switcher.picker")

local M = {}

M.config = {
  on_switch = nil,
  --- When switching, if the current buffer's file lives inside the worktree
  --- being left, open the file at the same relative path in the new worktree
  --- (only if it exists there). Set to false to disable.
  follow_current_file = true,
}

--- @param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
end

--- The worktree item from `items` whose path is the longest prefix of `path`,
--- or nil if `path` is not inside any of them. Pure.
--- @param items table[]
--- @param path string
--- @return table|nil
function M._containing_worktree(items, path)
  local best
  for _, wt in ipairs(items) do
    local root = vim.fs.normalize(wt.path)
    if path == root or path:sub(1, #root + 1) == root .. "/" then
      if not best or #root > #vim.fs.normalize(best.path) then
        best = wt
      end
    end
  end
  return best
end

--- The path `curfile` would map to inside worktree `dest`: same path relative
--- to the source worktree that currently contains `curfile`. Returns nil when
--- `curfile` is outside every worktree or already inside `dest`. Pure — does
--- NOT check whether the resulting file exists.
--- @param items table[]
--- @param curfile string  normalized absolute path
--- @param dest table  destination worktree item
--- @return string|nil
function M._mapped_path(items, curfile, dest)
  local src = M._containing_worktree(items, curfile)
  if not src or vim.fs.normalize(src.path) == vim.fs.normalize(dest.path) then
    return nil
  end
  local rel = curfile:sub(#vim.fs.normalize(src.path) + 2) -- strip "<src>/"
  return vim.fs.normalize(dest.path) .. "/" .. rel
end

--- Change the global cwd to the worktree and fire on_switch.
--- @param wt table
--- @return boolean ok  true if the cd succeeded
function M.switch(wt)
  local ok, err = pcall(function()
    vim.cmd.cd(vim.fn.fnameescape(wt.path))
  end)
  if not ok then
    vim.notify("worktree-switcher: cd failed: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  vim.notify("worktree-switcher: " .. wt.path, vim.log.levels.INFO)
  if M.config.on_switch then
    local cb_ok, cb_err = pcall(M.config.on_switch, wt)
    if not cb_ok then
      vim.notify("worktree-switcher: on_switch error: " .. tostring(cb_err), vim.log.levels.ERROR)
    end
  end
  return true
end

--- List worktrees and open the picker; selection switches the workspace.
function M.pick()
  local cwd = vim.fn.getcwd()
  git.list(cwd, function(err, items)
    if err then
      vim.notify("worktree-switcher: " .. err, vim.log.levels.WARN)
      return
    end
    if not items or #items == 0 then
      vim.notify("worktree-switcher: no worktrees found", vim.log.levels.INFO)
      return
    end
    local curname = vim.api.nvim_buf_get_name(0)
    local curfile = curname ~= "" and vim.fs.normalize(curname) or nil
    picker.open(items, cwd, function(wt)
      local target
      if M.config.follow_current_file and curfile then
        local mapped = M._mapped_path(items, curfile, wt)
        if mapped and vim.uv.fs_stat(mapped) then
          target = mapped
        end
      end
      if M.switch(wt) and target then
        pcall(vim.cmd.edit, vim.fn.fnameescape(target))
      end
    end)
  end)
end

return M

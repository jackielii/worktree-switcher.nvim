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
  -- vim.system can throw synchronously when the spawn fails immediately (e.g. a
  -- non-existent cwd raises ENOENT). Wrap in pcall and route that failure through
  -- vim.schedule so the callback timing/contract is uniform with the async path.
  local ok, err = pcall(vim.system,
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
  if not ok then
    vim.schedule(function() cb(vim.trim(tostring(err)), nil) end)
  end
end

return M

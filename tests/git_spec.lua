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

-- M.list must honor its async contract even when the spawn fails synchronously
-- (a non-existent cwd makes vim.system raise ENOENT). It must not throw, and must
-- call back with (err_string, nil).
local done, got_err, got_items = false, nil, nil
local ok_call = pcall(function()
  git.list("/definitely/does/not/exist/xyz", function(e, items)
    got_err, got_items, done = e, items, true
  end)
end)
vim.wait(2000, function() return done end)
check("list does not throw on bad anchor", ok_call == true)
check("list called back", done == true)
check("list reports error string", type(got_err) == "string" and got_err ~= "")
check("list items nil on error", got_items == nil)

if failures > 0 then
  os.exit(1)
end

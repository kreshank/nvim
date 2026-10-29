-- nvim --headless -u NONE -l tests/remote-ssh.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local ssh = require("features.remote.ssh")
assert(ssh.destination("student@server.example") == "student@server.example")
for _, invalid in ipairs({ "-oProxyCommand=evil", "-o@host", "host\nHost bad", "", "user@host/path" }) do
  assert(not ssh.destination(invalid), "unsafe destination accepted")
end
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local config = root .. "/config"
vim.fn.writefile({ "User baseline", "Port 2201", "Host existing", "  HostName old.example" }, config)
local expand = vim.fn.expand
vim.fn.expand = function(value, ...)
  if value == "~/.ssh/config" then return config end
  return expand(value, ...)
end
local input, select = vim.ui.input, vim.ui.select
local answers = { "campus-test", "server.example", "student", "2202", "" }
local at = 0
vim.ui.input = function(_, callback) at = at + 1; callback(answers[at]) end
ssh.add_host()
assert(vim.bo.modified, "wizard should leave a reviewable unsaved entry")
assert(vim.fn.readfile(config)[1] == "User baseline", "wizard wrote config without :write")
vim.cmd.write()
local function resolved(host)
  local result = vim.system({ "ssh", "-G", "-F", config, host }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
assert(resolved("campus-test"):find("user student", 1, true))
assert(resolved("campus-test"):find("port 2202", 1, true))
assert(resolved("existing"):find("user baseline", 1, true), "original default context changed")
assert(resolved("existing"):find("hostname old.example", 1, true))
local entry = ssh.scan({ config }).entries["campus-test"]
assert(entry and entry.path == config and entry.line == 1)
ssh.edit_config("existing")
assert(vim.api.nvim_win_get_cursor(0)[1] > 1, "alias editor did not jump to stanza")
-- Empty host configurations still offer a direct connection.
local hosts = ssh.hosts
ssh.hosts = function() return {} end
vim.ui.select = function(options, _, callback) callback(options[1], 1) end
vim.ui.input = function(_, callback) callback("student@direct.example") end
local chosen
ssh.pick_host(function(host) chosen = host end)
assert(chosen == "student@direct.example")
ssh.hosts = hosts
vim.ui.input, vim.ui.select = input, select
vim.fn.expand = expand

package.loaded["sshfs.config"] = { get_control_master_options = function()
  return { "ControlMaster=auto", "ControlPath=" .. root .. "/%C", "ControlPersist=4h" }
end }
local remote = require("features.remote")
assert(vim.tbl_contains(remote.ssh_client_options({ batch = false }), "BatchMode=no"))
assert(vim.tbl_contains(remote.ssh_client_options({ batch = true }), "BatchMode=yes"))
local start_job, tmux = vim.fn.jobstart, vim.env.TMUX
local direct
vim.env.TMUX = nil
vim.fn.jobstart = function(cmd, opts) direct = { cmd = cmd, opts = opts }; return 1 end
remote.open_ssh("student@direct.example")
assert(direct and direct.opts.term and vim.tbl_contains(direct.cmd, "BatchMode=no"))
assert(direct.cmd[#direct.cmd] == "student@direct.example", "direct terminal destination is wrong")
vim.fn.jobstart, vim.env.TMUX = start_job, tmux
vim.cmd.stopinsert()
local run, terminal = remote.ssh_run, ssh.auth_terminal
local probes, prompted, authenticated = 0, false, false
remote.ssh_run = function(_, _, _, callback) probes = probes + 1; callback(probes > 1) end
ssh.auth_terminal = function(cmd, _, callback)
  assert(vim.tbl_contains(cmd, "BatchMode=no"))
  assert(vim.tbl_contains(cmd, "PasswordAuthentication=yes"))
  assert(vim.tbl_contains(cmd, "KbdInteractiveAuthentication=yes"))
  assert(vim.tbl_contains(cmd, "ControlMaster=yes"))
  prompted = true
  callback(true)
end
remote.authenticate("student@direct.example", function(ok) authenticated = ok end)
assert(prompted and authenticated and probes == 2, "password fallback did not authenticate then recheck")
ssh.auth_terminal = function(_, _, callback) callback(false) end
probes = 0
remote.authenticate("student@direct.example", function(ok) assert(not ok) end)
remote.ssh_run, ssh.auth_terminal = run, terminal
-- Exercise a real terminal's no-echo password prompt, without contacting a host.
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/sshfs.nvim")
local finished
ssh.auth_terminal({ vim.fn.exepath("python3"), "-c",
  "import getpass; assert getpass.getpass('Password: ') == 'fixture-value'",
}, "authentication-fixture", function(ok) finished = ok end)
local term = vim.api.nvim_get_current_buf()
assert(vim.wait(3000, function()
  return table.concat(vim.api.nvim_buf_get_lines(term, 0, -1, false), "\n"):find("Password:", 1, true)
end, 20), "interactive password prompt was not visible")
vim.fn.chansend(vim.b[term].terminal_job_id, "fixture-value\n")
assert(vim.wait(3000, function() return finished ~= nil end, 20) and finished,
  "real terminal password entry did not complete")
vim.cmd("silent! %bwipeout!")
vim.fn.delete(root, "rf")
print("SSH destinations, config wizard, OpenSSH resolution, and password fallback passed")

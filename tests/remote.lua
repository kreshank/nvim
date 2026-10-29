-- Run: nvim --headless -u NONE -l tests/remote.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local a = { host = "one", remote_root = "/srv/a b", mount_path = "/tmp/mount-a" }
local b = { host = "two", remote_root = "/srv/b", mount_path = "/tmp/mount-b" }
local probes, starts, prompts = {}, {}, 0
local remote = {
  project_for_path = function(path)
    if path:find(a.mount_path, 1, true) == 1 then return a end
    if path:find(b.mount_path, 1, true) == 1 then return b end
  end,
  ssh_argv = function(host, extra) return { "ssh", host, unpack(extra) } end,
  ssh_run = function(host, argv, _, cb)
    probes[#probes + 1] = { host, argv[1] }
    if argv[1]:find("fake%-ls") then cb(true, "/opt/bin/fake-ls") else cb(true, "") end
  end,
}
package.loaded["features.remote"] = remote
local mod = { servers = { "fake", "missing" }, lsp = {
  fake = { cmd = { "fake-ls", "--stdio" } },
  missing = { cmd = { "missing-ls" } },
} }
package.loaded.lang = { for_filetype = function() return mod end }
package.loaded["features.lsp"] = { mason_exe = function() return "/bin/true" end }
vim.lsp.start = function(cfg, opts) starts[#starts + 1] = { cfg, opts } end
vim.ui.select = function(_, _, cb) prompts = prompts + 1; cb("local", 1) end
local function buffer(path)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, path)
  vim.bo[buf].filetype = "test"
  return buf
end
buffer(a.mount_path .. "/one.test")
buffer(b.mount_path .. "/two.test")
local lsp = require("features.remote.lsp")
lsp.ensure(a)
lsp.ensure(b)
assert(#probes == 4 and prompts == 2, "probe each server once per project")
assert(a._servers.fake.mode == "remote" and b._servers.missing.mode == "local")
assert(starts[1][1].cmd[#starts[1][1].cmd]:find("cd '/srv/a b'", 1, true))
local stopped = {}
local original_get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function() return {
  { config = { root_dir = a.mount_path }, stop = function() stopped.a = true end },
  { config = { root_dir = b.mount_path }, stop = function() stopped.b = true end },
} end
lsp.stop_for_project(a)
assert(stopped.a and not stopped.b, "stop must be isolated to one project")
vim.lsp.get_clients = original_get_clients
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
vim.fn.writefile({ "Host included alias # comment", "Host * !excluded", "Include " .. temp .. "/config" }, temp .. "/extra")
vim.fn.writefile({ "host primary", "Include \"" .. temp .. "/extra\"" }, temp .. "/config")
assert(vim.deep_equal(require("features.remote.ssh").hosts({ temp .. "/config" }), { "alias", "included", "primary" }))
vim.fn.delete(temp, "rf")
print("Remote discovery, fallback, isolation, quoting and SSH Include tests passed")

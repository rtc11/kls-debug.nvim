local uv = vim.uv or vim.loop

local kls = require("kls-debug.kls")

local M = {}

local function sanitize_path(path)
	if type(path) ~= "string" or path == "" then
		return path
	end
	return vim.fn.fnamemodify(path, ":~")
end

local function tcp_reachable(port, timeout_ms)
	local tcp = uv.new_tcp()
	if not tcp then
		return false
	end

	local done = false
	local ok = false

	local function close_tcp()
		pcall(function()
			tcp:close()
		end)
	end

	pcall(function()
		tcp:connect("127.0.0.1", port, function(err)
			ok = not err
			done = true
			close_tcp()
		end)
	end)

	vim.wait(timeout_ms or 600, function()
		return done
	end, 10)

	if not done then
		close_tcp()
	end

	return ok
end

function M.check()
	vim.health.start("kls-debug")

	if vim.fn.executable("opencode") == 1 then
		vim.health.ok("opencode found at " .. sanitize_path(vim.fn.exepath("opencode")))
	else
		vim.health.error("opencode CLI not found in PATH", { "install from https://opencode.ai" })
	end

	if vim.fn.has("nvim-0.9") == 1 then
		vim.health.ok("Neovim " .. tostring(vim.version()))
	else
		vim.health.error("Neovim 0.9+ required", {})
	end

	local root = kls.find_workspace_root(0)
	if root then
		vim.health.ok("workspace root resolved")
		local port_file = root .. "/.kls-debug-port"
		if vim.uv.fs_stat(port_file) then
			vim.health.ok("port file present")
			local port = kls.read_port(root)
			if port then
				if tcp_reachable(port, 600) then
					vim.health.ok("KLS debug server reachable on port " .. port)
				else
					vim.health.warn("KLS not listening on port " .. port)
				end
			else
				vim.health.warn("KLS debug port file unreadable")
			end
		else
			vim.health.warn(
				"KLS debug port file missing — KLS may not be running with debug server enabled"
			)
		end
	else
		vim.health.warn("no KLS LSP attached or .kls-debug-port found in tree")
	end

	if pcall(require, "plenary") then
		vim.health.info("plenary available for tests")
	else
		vim.health.info("plenary not installed (only needed to run tests)")
	end
end

return M

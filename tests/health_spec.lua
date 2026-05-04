local health = require("kls-debug.health")
local kls = require("kls-debug.kls")
local uv = vim.uv or vim.loop

local function start_mock_server(handler)
	local server = uv.new_tcp()
	assert(server:bind("127.0.0.1", 0))
	local port = server:getsockname().port

	server:listen(16, function(listen_err)
		assert(not listen_err, listen_err)
		local client = uv.new_tcp()
		server:accept(client)
		local buf = ""
		client:read_start(function(read_err, chunk)
			if read_err or chunk == nil then
				pcall(function()
					client:close()
				end)
				return
			end
			buf = buf .. chunk
			local s, e = buf:find("\r\n\r\n", 1, true)
			if not s then
				return
			end
			local len = tonumber(buf:sub(1, s - 1):match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
			if not len or #buf < e + len then
				return
			end
			local body = buf:sub(e + 1, e + len)
			local req = vim.json.decode(body)
			local response = handler(req, client)
			if response ~= nil then
				local out = vim.json.encode(response)
				client:write(string.format("Content-Length: %d\r\n\r\n%s", #out, out), function()
					pcall(function()
						client:shutdown()
					end)
					pcall(function()
						client:close()
					end)
				end)
			end
		end)
	end)

	return server, port
end

local function stop_server(server)
	pcall(function()
		server:close()
	end)
end

local function make_workspace(port)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	if port then
		local f = assert(io.open(dir .. "/.kls-debug-port", "w"))
		f:write(tostring(port))
		f:close()
	end
	return dir
end

local function capture_health()
	local calls = {}
	local saved = {
		start = vim.health.start,
		ok = vim.health.ok,
		warn = vim.health.warn,
		error = vim.health.error,
		info = vim.health.info,
	}

	vim.health.start = function(name)
		table.insert(calls, { kind = "start", msg = name })
	end
	vim.health.ok = function(msg)
		table.insert(calls, { kind = "ok", msg = msg })
	end
	vim.health.warn = function(msg, advice)
		table.insert(calls, { kind = "warn", msg = msg, advice = advice })
	end
	vim.health.error = function(msg, advice)
		table.insert(calls, { kind = "error", msg = msg, advice = advice })
	end
	vim.health.info = function(msg)
		table.insert(calls, { kind = "info", msg = msg })
	end

	return calls,
		function()
			vim.health.start = saved.start
			vim.health.ok = saved.ok
			vim.health.warn = saved.warn
			vim.health.error = saved.error
			vim.health.info = saved.info
		end
end

describe("kls-debug health", function()
	it("reports all ok checks", function()
		local server, port = start_mock_server(function(req)
			return { jsonrpc = "2.0", id = req.id, result = "ok" }
		end)
		local root = make_workspace(port)
		local calls, restore = capture_health()
		local saved = {
			executable = vim.fn.executable,
			exepath = vim.fn.exepath,
			root = kls.find_workspace_root,
		}

		vim.fn.executable = function(bin)
			if bin == "opencode" then
				return 1
			end
			return saved.executable(bin)
		end
		vim.fn.exepath = function(bin)
			if bin == "opencode" then
				return vim.loop.os_homedir() .. "/bin/opencode"
			end
			return saved.exepath(bin)
		end
		kls.find_workspace_root = function()
			return root
		end

		health.check()

		vim.fn.executable = saved.executable
		vim.fn.exepath = saved.exepath
		kls.find_workspace_root = saved.root
		restore()
		stop_server(server)

		assert.are.same("start", calls[1].kind)
		assert.are.same("kls-debug", calls[1].msg)
		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind .. ":" .. item.msg
			end, calls),
			"ok:opencode found at ~/bin/opencode"
		))
		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind
			end, calls),
			"ok"
		))
		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind .. ":" .. item.msg
			end, calls),
			"ok:workspace root resolved"
		))
		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind .. ":" .. item.msg
			end, calls),
			"ok:port file present"
		))
		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind .. ":" .. item.msg
			end, calls),
			"ok:KLS debug server reachable on port " .. port
		))
		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind .. ":" .. item.msg
			end, calls),
			"info:plenary available for tests"
		) or vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind .. ":" .. item.msg
			end, calls),
			"info:plenary not installed (only needed to run tests)"
		))
	end)

	it("errors when opencode missing", function()
		local calls, restore = capture_health()
		local saved = vim.fn.executable
		vim.fn.executable = function(bin)
			if bin == "opencode" then
				return 0
			end
			return saved(bin)
		end

		health.check()

		vim.fn.executable = saved
		restore()

		assert.are.same("error", calls[2].kind)
		assert.is_true(calls[2].msg:find("opencode CLI not found") ~= nil)
	end)

	it("warns when workspace root missing", function()
		local calls, restore = capture_health()
		local saved = {
			executable = vim.fn.executable,
			root = kls.find_workspace_root,
		}
		vim.fn.executable = function(bin)
			if bin == "opencode" then
				return 1
			end
			return saved.executable(bin)
		end
		kls.find_workspace_root = function()
			return nil
		end

		health.check()

		vim.fn.executable = saved.executable
		kls.find_workspace_root = saved.root
		restore()

		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.kind .. ":" .. item.msg
			end, calls),
			"warn:no KLS LSP attached or .kls-debug-port found in tree"
		))
	end)
end)

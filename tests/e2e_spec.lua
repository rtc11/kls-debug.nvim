--- End-to-end smoke test.
---
--- Wires the full :KlsDebugAsk flow against:
---   * a real in-process mock KLS TCP server (libuv) returning canned fixtures
---   * a stub for `vim.fn.jobstart` that captures the opencode argv + cwd and
---     replays canned JSONL chunks into on_stdout / on_exit.
---
--- The test asserts:
---   * jobstart received an arg-LIST (no shell injection)
---   * cmd[1] == "opencode" with required `run --format json` flags
---   * cwd == workspace root
---   * the prompt includes file/diagnostics/cursor section markers + the user
---     question text
---   * an output buffer is created with kls-debug name + filetype + canned text

local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()
vim.opt.runtimepath:prepend(ROOT)

local uv = vim.uv or vim.loop

local function script_dir()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h")
end

local function read_fixture_result(name)
	local path = script_dir() .. "/fixtures/kls/" .. name
	local f = assert(io.open(path, "r"))
	local data = f:read("*a")
	f:close()
	local decoded = vim.json.decode(data)
	return decoded.result
end

local function read_jsonl_lines(name)
	local path = script_dir() .. "/fixtures/opencode/" .. name
	local f = assert(io.open(path, "r"))
	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()
	return lines
end

local function frame_body(body)
	return string.format("Content-Length: %d\r\n\r\n%s", #body, body)
end

--- Start a tiny KLS-shaped TCP server. Returns (server, port).
--- The handler maps `params.command` to a canned fixture result.
local function start_mock_kls()
	local server = assert(uv.new_tcp())
	assert(server:bind("127.0.0.1", 0))
	local port = server:getsockname().port

	local fixtures = {
		["kotlin.queryIndex"] = read_fixture_result("queryIndex.json"),
		["kotlin.lastCursor"] = read_fixture_result("lastCursor.json"),
		["kotlin.diagnosticsForUri"] = read_fixture_result("diagnosticsForUri.json"),
		["kotlin.astAt"] = read_fixture_result("astAt.json"),
		["kotlin.typeAt"] = read_fixture_result("typeAt.json"),
		["kotlin.hoverAt"] = read_fixture_result("hoverAt.json"),
	}

	local clients = {}

	server:listen(16, function(listen_err)
		if listen_err then
			return
		end
		local client = assert(uv.new_tcp())
		server:accept(client)
		table.insert(clients, client)
		local buf = ""
		client:read_start(function(read_err, chunk)
			if read_err or chunk == nil then
				pcall(function()
					client:close()
				end)
				return
			end
			buf = buf .. chunk
			while true do
				local s, e = buf:find("\r\n\r\n", 1, true)
				if not s then
					return
				end
				local len = tonumber(buf:sub(1, s - 1):match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
				if not len or #buf < e + len then
					return
				end
				local body = buf:sub(e + 1, e + len)
				buf = buf:sub(e + len + 1)
				local ok, req = pcall(vim.json.decode, body)
				if ok and type(req) == "table" then
					local cmd = req.params and req.params.command
					local result = fixtures[cmd] or vim.empty_dict()
					local resp_body = vim.json.encode({
						jsonrpc = "2.0",
						id = req.id,
						result = result,
					})
					client:write(frame_body(resp_body))
				end
			end
		end)
	end)

	local function stop()
		for _, c in ipairs(clients) do
			pcall(function()
				c:close()
			end)
		end
		pcall(function()
			server:close()
		end)
	end

	return port, stop
end

local function make_workspace_with_port(port)
	local dir = vim.fn.resolve(vim.fn.tempname())
	vim.fn.mkdir(dir, "p")
	local f = assert(io.open(dir .. "/.kls-debug-port", "w"))
	f:write(tostring(port))
	f:close()
	return dir
end

local function load_command_from_plugin()
	-- Source the plugin file once so :KlsDebugAsk is registered. The plugin
	-- guards itself with vim.g.loaded_kls_debug, so re-sourcing in subsequent
	-- runs is a no-op (which is fine: the user_command stays registered).
	if vim.fn.exists(":KlsDebugAsk") ~= 2 then
		vim.cmd("runtime! plugin/kls-debug.lua")
	end
end

describe("kls-debug end-to-end", function()
	local saved_jobstart
	local saved_chansend
	local saved_chanclose
	local saved_jobwait

	local kls_port
	local stop_kls
	local workspace_root
	local kt_path
	local bufnr

	local captured

	before_each(function()
		captured = {
			cmd = nil,
			cwd = nil,
			prompt = nil,
			env = nil,
			on_stdout = nil,
			on_exit = nil,
		}

		kls_port, stop_kls = start_mock_kls()
		workspace_root = make_workspace_with_port(kls_port)

		kt_path = workspace_root .. "/Sample.kt"
		local f = assert(io.open(kt_path, "w"))
		f:write("package sample\n\nfun main() {\n    val x: String = 42\n}\n")
		f:close()

		vim.cmd("edit " .. kt_path)
		bufnr = vim.api.nvim_get_current_buf()
		vim.bo[bufnr].filetype = "kotlin"
		vim.api.nvim_win_set_cursor(0, { 4, 4 })

		local jsonl_lines = read_jsonl_lines("simple_response.jsonl")

		saved_jobstart = vim.fn.jobstart
		saved_chansend = vim.fn.chansend
		saved_chanclose = vim.fn.chanclose
		saved_jobwait = vim.fn.jobwait

		vim.fn.jobstart = function(cmd, opts)
			captured.cmd = cmd
			captured.cwd = opts and opts.cwd or nil
			captured.env = opts and opts.env or nil
			captured.on_stdout = opts and opts.on_stdout or nil
			captured.on_exit = opts and opts.on_exit or nil
			-- Schedule canned stdout chunks + exit asynchronously to mirror
			-- real jobstart behaviour. Each line is delivered as a separate
			-- `data` table in the shape neovim uses (last entry partial = "").
			vim.schedule(function()
				if captured.on_stdout then
					for _, line in ipairs(jsonl_lines) do
						pcall(captured.on_stdout, 99999, { line, "" }, "stdout")
					end
				end
				if captured.on_exit then
					pcall(captured.on_exit, 99999, 0, "exit")
				end
			end)
			return 99999
		end

		-- Capture stdin payload (the full prompt) without actually writing.
		vim.fn.chansend = function(_, data)
			captured.prompt = (captured.prompt or "") .. tostring(data)
			return #tostring(data)
		end

		vim.fn.chanclose = function()
			return 1
		end

		-- Avoid the deferred timeout watchdog calling into a real job id.
		vim.fn.jobwait = function()
			return { 0 }
		end

		-- Reset orchestrator single-flight + setup with split output.
		package.loaded["kls-debug.orchestrator"] = nil
		package.loaded["kls-debug"] = nil
		require("kls-debug").setup({ output = "split" })
		load_command_from_plugin()
	end)

	after_each(function()
		vim.fn.jobstart = saved_jobstart
		vim.fn.chansend = saved_chansend
		vim.fn.chanclose = saved_chanclose
		vim.fn.jobwait = saved_jobwait

		pcall(stop_kls)

		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end

		-- Close any kls-debug-output windows/buffers created by the run.
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(b)
			if name:find("kls-debug", 1, true) then
				pcall(vim.api.nvim_buf_delete, b, { force = true })
			end
		end

		pcall(os.remove, workspace_root .. "/.kls-debug-port")
		pcall(os.remove, kt_path)
		pcall(vim.fn.delete, workspace_root, "rf")
	end)

	it("runs the full pipeline with mocked opencode and KLS", function()
		vim.cmd("KlsDebugAsk why does this fail")

		-- Wait for jobstart to be called (after async context fan-out).
		assert.is_true(vim.wait(3000, function()
			return captured.cmd ~= nil
		end, 10))

		-- Wait for output buffer to be populated.
		local function output_ready()
			for _, b in ipairs(vim.api.nvim_list_bufs()) do
				local name = vim.api.nvim_buf_get_name(b)
				if name:find("kls-debug", 1, true) then
					local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
					if #lines > 0 and table.concat(lines, "\n") ~= "" then
						return true
					end
				end
			end
			return false
		end
		assert.is_true(vim.wait(3000, output_ready, 10))

		-- Core security guarantee: cmd is a list, not a shell string.
		assert.are.equal("table", type(captured.cmd))
		assert.are.equal("opencode", captured.cmd[1])

		local has_run, has_format, has_json = false, false, false
		for i, arg in ipairs(captured.cmd) do
			if arg == "run" then
				has_run = true
			end
			if arg == "--format" and captured.cmd[i + 1] == "json" then
				has_format = true
				has_json = true
			end
		end
		assert.is_true(has_run, "cmd must include 'run'")
		assert.is_true(has_format and has_json, "cmd must include '--format json'")

		-- cwd must be the workspace root that contains .kls-debug-port.
		assert.is_string(captured.cwd)
		assert.are.equal(vim.fn.resolve(workspace_root), vim.fn.resolve(captured.cwd))

		-- Prompt must contain the user question + bundle section headers.
		assert.is_string(captured.prompt)
		assert.is_truthy(captured.prompt:find("why does this fail", 1, true))
		assert.is_truthy(captured.prompt:find("## File:", 1, true))
		-- KLS context succeeded → expect at least one KLS section header.
		assert.is_truthy(captured.prompt:find("## KLS", 1, true))

		-- Output buffer must exist with kls-debug name + markdown filetype.
		local found_output = false
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(b)
			if name:find("kls-debug", 1, true) then
				found_output = true
				assert.are.equal("markdown", vim.bo[b].filetype)
				local text = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
				-- "Hi there friend" is the text payload of simple_response.jsonl.
				assert.is_truthy(text:find("Hi there friend", 1, true))
				break
			end
		end
		assert.is_true(found_output, "no kls-debug-output buffer was created")
	end)
end)

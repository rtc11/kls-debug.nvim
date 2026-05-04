local kls = require("kls-debug.kls")
local uv = vim.uv or vim.loop

local function read_fixture(name)
	local source = debug.getinfo(1, "S").source:sub(2)
	local script_dir = vim.fn.fnamemodify(source, ":p:h")
	local path = script_dir .. "/fixtures/kls/" .. name
	local f = assert(io.open(path, "r"))
	local data = f:read("*a")
	f:close()
	return vim.json.decode(data)
end

local function fixture_result(name)
	return read_fixture(name).result
end

local function frame(body)
	return string.format("Content-Length: %d\r\n\r\n%s", #body, body)
end

local function start_mock_server(handler)
	local server = uv.new_tcp()
	assert(server:bind("127.0.0.1", 0))
	local addr = server:getsockname()
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
				client:write(frame(out), function()
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
	return server, addr.port
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

local function wait_for(predicate, timeout_ms)
	local ok = vim.wait(timeout_ms or 2000, predicate, 10)
	return ok
end

describe("kls-debug.kls", function()
	describe("read_port", function()
		it("returns nil when port file missing", function()
			local dir = make_workspace(nil)
			assert.is_nil(kls.read_port(dir))
		end)

		it("parses valid port", function()
			local dir = make_workspace(54321)
			assert.are.equal(54321, kls.read_port(dir))
		end)

		it("trims whitespace", function()
			local dir = make_workspace(nil)
			local f = assert(io.open(dir .. "/.kls-debug-port", "w"))
			f:write("  42\n\n")
			f:close()
			assert.are.equal(42, kls.read_port(dir))
		end)

		it("rejects garbage", function()
			local dir = make_workspace(nil)
			local f = assert(io.open(dir .. "/.kls-debug-port", "w"))
			f:write("notanumber")
			f:close()
			assert.is_nil(kls.read_port(dir))
		end)

		it("rejects zero/negative", function()
			local dir = make_workspace(nil)
			local f = assert(io.open(dir .. "/.kls-debug-port", "w"))
			f:write("0")
			f:close()
			assert.is_nil(kls.read_port(dir))
		end)

		it("returns nil for nil workspace", function()
			assert.is_nil(kls.read_port(nil))
			assert.is_nil(kls.read_port(""))
		end)
	end)

	describe("find_workspace_root", function()
		it("walks up to .kls-debug-port", function()
			local root = vim.fn.resolve(make_workspace(1234))
			local nested = root .. "/a/b/c"
			vim.fn.mkdir(nested, "p")
			local file = nested .. "/Foo.kt"
			local f = assert(io.open(file, "w"))
			f:write("class Foo")
			f:close()
			vim.cmd("edit " .. file)
			local bufnr = vim.api.nvim_get_current_buf()
			local found = kls.find_workspace_root(bufnr)
			assert.are.equal(root, vim.fn.resolve(found))
			vim.cmd("bdelete!")
		end)

		it("returns nil when no marker found", function()
			local lonely = vim.fn.tempname()
			vim.fn.mkdir(lonely, "p")
			local file = lonely .. "/Foo.kt"
			local f = assert(io.open(file, "w"))
			f:write("class Foo")
			f:close()
			vim.cmd("edit " .. file)
			local found = kls.find_workspace_root(vim.api.nvim_get_current_buf())
			assert.is_nil(found)
			vim.cmd("bdelete!")
		end)
	end)

	describe("request", function()
		it("round-trips a single message with framing", function()
			local server, port = start_mock_server(function(req)
				return { jsonrpc = "2.0", id = req.id, result = { echo = req.params } }
			end)
			local ws = make_workspace(port)

			local err_seen, res_seen
			kls.request(ws, "ping", { hello = "world" }, function(err, res)
				err_seen = err or false
				res_seen = res
			end, { timeout_ms = 2000 })

			assert.is_true(wait_for(function()
				return err_seen ~= nil
			end, 3000))
			assert.are.equal(false, err_seen)
			assert.are.equal("2.0", res_seen.jsonrpc)
			assert.are.same({ hello = "world" }, res_seen.result.echo)
			stop_server(server)
		end)

		it("handles response delivered in two chunks", function()
			local server = uv.new_tcp()
			assert(server:bind("127.0.0.1", 0))
			local port = server:getsockname().port
			server:listen(8, function()
				local client = uv.new_tcp()
				server:accept(client)
				local buf = ""
				client:read_start(function(_, chunk)
					if not chunk then
						return
					end
					buf = buf .. chunk
					local s, e = buf:find("\r\n\r\n", 1, true)
					if not s then
						return
					end
					local len = tonumber(buf:sub(1, s - 1):match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
					if #buf < e + len then
						return
					end
					local req = vim.json.decode(buf:sub(e + 1, e + len))
					local body = vim.json.encode({ jsonrpc = "2.0", id = req.id, result = "ok" })
					local out = string.format("Content-Length: %d\r\n\r\n%s", #body, body)
					local mid = math.floor(#out / 2)
					client:write(out:sub(1, mid), function()
						local timer = uv.new_timer()
						timer:start(
							20,
							0,
							vim.schedule_wrap(function()
								timer:stop()
								timer:close()
								client:write(out:sub(mid + 1), function()
									pcall(function()
										client:close()
									end)
								end)
							end)
						)
					end)
				end)
			end)
			local ws = make_workspace(port)
			local err_seen, res_seen
			kls.request(ws, "split", {}, function(err, res)
				err_seen = err or false
				res_seen = res
			end, { timeout_ms = 2000 })
			assert.is_true(wait_for(function()
				return err_seen ~= nil
			end, 3000))
			assert.are.equal(false, err_seen)
			assert.are.equal("ok", res_seen.result)
			stop_server(server)
		end)

		it("times out when server never responds", function()
			local server = uv.new_tcp()
			assert(server:bind("127.0.0.1", 0))
			local port = server:getsockname().port
			server:listen(4, function()
				local client = uv.new_tcp()
				server:accept(client)
			end)
			local ws = make_workspace(port)

			local err_seen, res_seen
			local t0 = uv.hrtime()
			kls.request(ws, "noop", {}, function(err, res)
				err_seen = err
				res_seen = res
			end, { timeout_ms = 200 })

			assert.is_true(wait_for(function()
				return err_seen ~= nil
			end, 2000))
			local elapsed_ms = (uv.hrtime() - t0) / 1e6
			assert.is_nil(res_seen)
			assert.is_string(err_seen)
			assert.is_true(err_seen:lower():find("timed out") ~= nil)
			assert.is_true(elapsed_ms < 1500)
			stop_server(server)
		end)

		it("returns error when port file missing", function()
			local dir = vim.fn.tempname()
			vim.fn.mkdir(dir, "p")
			local err_seen
			kls.request(dir, "x", {}, function(err)
				err_seen = err or false
			end)
			assert.is_true(wait_for(function()
				return err_seen ~= nil
			end, 1000))
			assert.is_string(err_seen)
			assert.is_true(err_seen:find("Cannot read") ~= nil)
		end)

		it("returns error on connection refused", function()
			local probe = uv.new_tcp()
			assert(probe:bind("127.0.0.1", 0))
			local port = probe:getsockname().port
			probe:close()
			local ws = make_workspace(port)
			local err_seen
			kls.request(ws, "x", {}, function(err)
				err_seen = err or false
			end, { timeout_ms = 1000 })
			assert.is_true(wait_for(function()
				return err_seen ~= nil
			end, 2000))
			assert.is_string(err_seen)
			assert.is_true(
				err_seen:find("connect") ~= nil or err_seen:lower():find("refused") ~= nil
			)
		end)
	end)

	describe("execute_command", function()
		local function run_cmd_test(command, args, fixture)
			local canned = fixture_result(fixture)
			local seen_command, seen_args
			local server, port = start_mock_server(function(req)
				seen_command = req.params.command
				seen_args = req.params.arguments
				return { jsonrpc = "2.0", id = req.id, result = canned }
			end)
			local ws = make_workspace(port)
			local err_seen, res_seen
			kls.execute_command(ws, command, args, function(err, res)
				err_seen = err or false
				res_seen = res
			end, { timeout_ms = 2000 })
			assert.is_true(wait_for(function()
				return err_seen ~= nil
			end, 3000))
			stop_server(server)
			assert.are.equal(false, err_seen)
			assert.are.equal(command, seen_command)
			assert.are.same(args or {}, seen_args)
			assert.are.same(canned, res_seen)
		end

		it("dispatches kotlin.queryIndex", function()
			run_cmd_test("kotlin.queryIndex", {}, "queryIndex.json")
		end)

		it("dispatches kotlin.listOpenDocuments", function()
			run_cmd_test("kotlin.listOpenDocuments", {}, "listOpenDocuments.json")
		end)

		it("dispatches kotlin.lastEditedUri", function()
			run_cmd_test("kotlin.lastEditedUri", {}, "lastEditedUri.json")
		end)

		it("dispatches kotlin.lastCursor", function()
			run_cmd_test("kotlin.lastCursor", {}, "lastCursor.json")
		end)

		it("dispatches kotlin.diagnosticsForUri", function()
			run_cmd_test(
				"kotlin.diagnosticsForUri",
				{ "file:///tmp/A.kt" },
				"diagnosticsForUri.json"
			)
		end)

		it("dispatches kotlin.hoverAt", function()
			run_cmd_test("kotlin.hoverAt", { "file:///tmp/A.kt", 0, 0 }, "hoverAt.json")
		end)

		it("dispatches kotlin.definitionAt", function()
			run_cmd_test("kotlin.definitionAt", { "file:///tmp/A.kt", 0, 0 }, "definitionAt.json")
		end)

		it("dispatches kotlin.referencesAt", function()
			run_cmd_test("kotlin.referencesAt", { "file:///tmp/A.kt", 0, 0 }, "referencesAt.json")
		end)

		it("dispatches kotlin.astAt", function()
			run_cmd_test("kotlin.astAt", { "file:///tmp/A.kt", 0, 0 }, "astAt.json")
		end)

		it("dispatches kotlin.typeAt", function()
			run_cmd_test("kotlin.typeAt", { "file:///tmp/A.kt", 0, 0 }, "typeAt.json")
		end)

		it("surfaces JSON-RPC error field", function()
			local server, port = start_mock_server(function(req)
				return {
					jsonrpc = "2.0",
					id = req.id,
					error = { code = -32601, message = "Method not found" },
				}
			end)
			local ws = make_workspace(port)
			local err_seen, res_seen
			kls.execute_command(ws, "kotlin.bogus", {}, function(err, res)
				err_seen = err or false
				res_seen = res
			end, { timeout_ms = 2000 })
			assert.is_true(wait_for(function()
				return err_seen ~= nil
			end, 3000))
			stop_server(server)
			assert.is_nil(res_seen)
			assert.is_string(err_seen)
			assert.is_true(err_seen:find("KLS error") ~= nil)
		end)
	end)
end)

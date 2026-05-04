local context_kls = require("kls-debug.context.kls")
local uv = vim.uv or vim.loop

local function read_fixture_result(name)
	local source = debug.getinfo(1, "S").source:sub(2)
	local script_dir = vim.fn.fnamemodify(source, ":p:h")
	local path = script_dir .. "/fixtures/kls/" .. name
	local f = assert(io.open(path, "r"))
	local data = f:read("*a")
	f:close()
	return vim.json.decode(data).result
end

local function frame(body)
	return string.format("Content-Length: %d\r\n\r\n%s", #body, body)
end

local function start_server(handler)
	local server = uv.new_tcp()
	assert(server:bind("127.0.0.1", 0))
	local port = server:getsockname().port
	server:listen(32, function(listen_err)
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
			local response = handler(req)
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

local function make_kotlin_buffer(name)
	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(
		bufnr,
		name or ("/tmp/ContextKlsSpec_" .. tostring(uv.hrtime()) .. ".kt")
	)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "package sample", "", "fun main() {}" })
	return bufnr
end

local function wait_for(predicate, timeout_ms)
	return vim.wait(timeout_ms or 3000, predicate, 10)
end

local FIXTURE_BY_COMMAND = {
	["kotlin.queryIndex"] = "queryIndex.json",
	["kotlin.lastCursor"] = "lastCursor.json",
	["kotlin.diagnosticsForUri"] = "diagnosticsForUri.json",
	["kotlin.astAt"] = "astAt.json",
	["kotlin.typeAt"] = "typeAt.json",
	["kotlin.hoverAt"] = "hoverAt.json",
}

describe("kls-debug.context.kls", function()
	it("fans out all 6 queries and aggregates results", function()
		local seen = {}
		local server, port = start_server(function(req)
			local cmd = req.params.command
			seen[cmd] = (seen[cmd] or 0) + 1
			local fixture = FIXTURE_BY_COMMAND[cmd]
			assert(fixture, "unexpected command: " .. tostring(cmd))
			return {
				jsonrpc = "2.0",
				id = req.id,
				result = read_fixture_result(fixture),
			}
		end)

		local ws = make_workspace(port)
		local bufnr = make_kotlin_buffer()

		local result_seen, meta_seen
		local fired = false
		context_kls.collect(ws, bufnr, 2, 4, function(result, meta)
			result_seen = result
			meta_seen = meta
			fired = true
		end)

		assert.is_true(wait_for(function()
			return fired
		end))
		stop_server(server)
		vim.cmd("bdelete!")

		assert.is_nil(meta_seen)
		assert.is_table(result_seen)
		assert.is_table(result_seen.summary)
		assert.is_table(result_seen.last_cursor)
		assert.is_table(result_seen.diagnostics)
		assert.is_table(result_seen.ast_chain)
		assert.is_table(result_seen.type_info)
		assert.is_table(result_seen.hover)
		assert.are.same({}, result_seen.errors)

		for cmd in pairs(FIXTURE_BY_COMMAND) do
			assert.are.equal(1, seen[cmd], "expected exactly one call to " .. cmd)
		end
	end)

	it("forwards buffer URI and cursor to cursor-dependent ops", function()
		local captured = {}
		local server, port = start_server(function(req)
			local cmd = req.params.command
			captured[cmd] = req.params.arguments
			local fixture = FIXTURE_BY_COMMAND[cmd]
			return {
				jsonrpc = "2.0",
				id = req.id,
				result = read_fixture_result(fixture),
			}
		end)

		local ws = make_workspace(port)
		local path = "/tmp/ContextKlsArgs_" .. tostring(uv.hrtime()) .. ".kt"
		local bufnr = make_kotlin_buffer(path)
		local expected_uri = vim.uri_from_bufnr(bufnr)

		local fired = false
		context_kls.collect(ws, bufnr, 7, 3, function()
			fired = true
		end)

		assert.is_true(wait_for(function()
			return fired
		end))
		stop_server(server)
		vim.cmd("bdelete!")

		assert.are.same({ expected_uri }, captured["kotlin.diagnosticsForUri"])
		assert.are.same({ expected_uri, 7, 3 }, captured["kotlin.hoverAt"])
		assert.are.same({ expected_uri, 7, 3 }, captured["kotlin.astAt"])
		assert.are.same({ expected_uri, 7, 3 }, captured["kotlin.typeAt"])
		assert.are.same({}, captured["kotlin.queryIndex"])
		assert.are.same({}, captured["kotlin.lastCursor"])
	end)

	it("records partial failures without aborting", function()
		local server, port = start_server(function(req)
			local cmd = req.params.command
			if cmd == "kotlin.astAt" or cmd == "kotlin.typeAt" then
				return {
					jsonrpc = "2.0",
					id = req.id,
					error = { code = -32603, message = "boom for " .. cmd },
				}
			end
			local fixture = FIXTURE_BY_COMMAND[cmd]
			return {
				jsonrpc = "2.0",
				id = req.id,
				result = read_fixture_result(fixture),
			}
		end)

		local ws = make_workspace(port)
		local bufnr = make_kotlin_buffer()

		local result_seen, meta_seen
		local fired = false
		context_kls.collect(ws, bufnr, 0, 0, function(result, meta)
			result_seen = result
			meta_seen = meta
			fired = true
		end)

		assert.is_true(wait_for(function()
			return fired
		end))
		stop_server(server)
		vim.cmd("bdelete!")

		assert.is_nil(meta_seen)
		assert.is_table(result_seen)
		assert.is_table(result_seen.summary)
		assert.is_table(result_seen.last_cursor)
		assert.is_table(result_seen.diagnostics)
		assert.is_table(result_seen.hover)
		assert.is_nil(result_seen.ast_chain)
		assert.is_nil(result_seen.type_info)
		assert.are.equal(2, #result_seen.errors)

		local failed = {}
		for _, e in ipairs(result_seen.errors) do
			failed[e.command] = e.error
		end
		assert.is_string(failed["kotlin.astAt"])
		assert.is_string(failed["kotlin.typeAt"])
	end)

	it("soft-degrades when workspace_root is nil", function()
		local result_seen, meta_seen
		local fired = false
		context_kls.collect(nil, 0, 0, 0, function(result, meta)
			result_seen = result
			meta_seen = meta
			fired = true
		end)
		assert.is_true(wait_for(function()
			return fired
		end))
		assert.is_nil(result_seen)
		assert.is_table(meta_seen)
		assert.is_false(meta_seen.available)
		assert.is_string(meta_seen.reason)
	end)

	it("soft-degrades when port file is missing", function()
		local ws = vim.fn.tempname()
		vim.fn.mkdir(ws, "p")
		local result_seen, meta_seen
		local fired = false
		context_kls.collect(ws, 0, 0, 0, function(result, meta)
			result_seen = result
			meta_seen = meta
			fired = true
		end)
		assert.is_true(wait_for(function()
			return fired
		end))
		assert.is_nil(result_seen)
		assert.is_table(meta_seen)
		assert.is_false(meta_seen.available)
		assert.is_string(meta_seen.reason)
		assert.is_true(meta_seen.reason:lower():find("port") ~= nil)
	end)

	it("skips cursor-dependent ops when bufnr has no name", function()
		local seen = {}
		local server, port = start_server(function(req)
			local cmd = req.params.command
			seen[cmd] = (seen[cmd] or 0) + 1
			local fixture = FIXTURE_BY_COMMAND[cmd]
			return {
				jsonrpc = "2.0",
				id = req.id,
				result = read_fixture_result(fixture),
			}
		end)

		local ws = make_workspace(port)
		vim.cmd("enew")
		local bufnr = vim.api.nvim_get_current_buf()

		local result_seen
		local fired = false
		context_kls.collect(ws, bufnr, 0, 0, function(result)
			result_seen = result
			fired = true
		end)

		assert.is_true(wait_for(function()
			return fired
		end))
		stop_server(server)
		vim.cmd("bdelete!")

		assert.is_table(result_seen)
		assert.are.equal(1, seen["kotlin.queryIndex"] or 0)
		assert.are.equal(1, seen["kotlin.lastCursor"] or 0)
		assert.is_nil(seen["kotlin.diagnosticsForUri"])
		assert.is_nil(seen["kotlin.hoverAt"])
		assert.is_nil(seen["kotlin.astAt"])
		assert.is_nil(seen["kotlin.typeAt"])
		assert.are.same({}, result_seen.errors)
	end)
end)

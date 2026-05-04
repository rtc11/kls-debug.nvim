--- KLS TCP client — JSON-RPC 2.0 over Content-Length framing via vim.uv.
---
--- Public API (all async, callback-style for nvim 0.9 compat):
---   M.find_workspace_root(bufnr) -> string|nil
---   M.read_port(workspace_root)  -> integer|nil
---   M.request(workspace_root, method, params, callback, opts?)
---   M.execute_command(workspace_root, command, args, callback, opts?)
---
--- Wire format (matches .opencode/tools/kls-query.ts):
---   "Content-Length: <bytes>\r\n\r\n<json-body>"
---
--- Timeouts (default 500ms) hard-cancel the connect/read; socket + timer always
--- closed via pcall in every error path so leaks are impossible.

local uv = vim.uv or vim.loop

local M = {}

local DEFAULT_CONNECT_TIMEOUT_MS = 500
local PORT_FILE_NAME = ".kls-debug-port"

local next_id = 1

local function gen_id()
	local id = next_id
	next_id = next_id + 1
	return id
end

local function safe_close(handle)
	if handle and not handle:is_closing() then
		pcall(function()
			handle:close()
		end)
	end
end

local function safe_timer_stop(timer)
	if timer then
		pcall(function()
			timer:stop()
		end)
		safe_close(timer)
	end
end

--- Walk up from `start_path` looking for a directory containing `marker`.
--- Returns the directory path or nil.
local function find_up(start_path, marker)
	if not start_path or start_path == "" then
		return nil
	end
	local dir = start_path
	if vim.fn.isdirectory(dir) ~= 1 then
		dir = vim.fn.fnamemodify(dir, ":h")
	end
	while dir and dir ~= "" and dir ~= "/" do
		local candidate = dir .. "/" .. marker
		if vim.fn.filereadable(candidate) == 1 then
			return dir
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end
	return nil
end

--- Find workspace root for a buffer.
--- 1. Try LSP client `kls`'s `config.root_dir`.
--- 2. Fallback: walk up looking for `.kls-debug-port`.
--- 3. Fallback: walk up looking for `project.json`.
---@param bufnr integer
---@return string|nil
function M.find_workspace_root(bufnr)
	bufnr = bufnr or 0
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	local ok, clients = pcall(get_clients, { bufnr = bufnr, name = "kls" })
	if ok and clients and #clients > 0 then
		local root = clients[1].config and clients[1].config.root_dir
		if type(root) == "string" and root ~= "" then
			return root
		end
	end

	local fname = vim.api.nvim_buf_get_name(bufnr)
	if fname == "" then
		return nil
	end
	local root = find_up(fname, PORT_FILE_NAME)
	if root then
		return root
	end
	return find_up(fname, "project.json")
end

--- Read the TCP port from `<workspace_root>/.kls-debug-port`.
--- Returns nil on missing file or invalid (non-positive integer) contents.
---@param workspace_root string
---@return integer|nil
function M.read_port(workspace_root)
	if type(workspace_root) ~= "string" or workspace_root == "" then
		return nil
	end
	local port_file = workspace_root .. "/" .. PORT_FILE_NAME
	if vim.fn.filereadable(port_file) ~= 1 then
		return nil
	end
	local lines = vim.fn.readfile(port_file)
	local data = lines[1]
	if type(data) ~= "string" then
		return nil
	end
	local trimmed = data:match("^%s*(.-)%s*$")
	local port = tonumber(trimmed)
	if not port or port ~= math.floor(port) or port <= 0 or port > 65535 then
		return nil
	end
	return math.floor(port)
end

--- Build a fresh framing-parser state for one TCP connection.
local function new_parser()
	return {
		buf = "",
		expected = nil,
		header_end = nil,
	}
end

--- Try to extract one complete message from the parser buffer.
--- Returns: body string on success, nil if more data needed,
--- or (nil, err_string) on malformed header.
local function parser_pop(p)
	if not p.expected then
		local s, e = p.buf:find("\r\n\r\n", 1, true)
		if not s then
			return nil
		end
		local header = p.buf:sub(1, s - 1)
		local len_str = header:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")
		if not len_str then
			return nil, "missing Content-Length header"
		end
		p.expected = tonumber(len_str)
		p.header_end = e + 1
	end
	local available = #p.buf - (p.header_end - 1)
	if available < p.expected then
		return nil
	end
	local body = p.buf:sub(p.header_end, p.header_end + p.expected - 1)
	p.buf = p.buf:sub(p.header_end + p.expected)
	p.expected = nil
	p.header_end = nil
	return body
end

--- Send a JSON-RPC request over TCP and invoke `callback(err, response)`.
--- `callback` is always invoked exactly once via `vim.schedule`.
--- On success: `err == nil`, `response` is the decoded JSON-RPC envelope.
--- On failure: `err` is a descriptive string, `response` is nil.
---@param workspace_root string
---@param method string
---@param params table|nil
---@param callback fun(err: string|nil, response: table|nil)
---@param opts table|nil { timeout_ms = integer }
function M.request(workspace_root, method, params, callback, opts)
	opts = opts or {}
	local timeout_ms = opts.timeout_ms or DEFAULT_CONNECT_TIMEOUT_MS

	local function done(err, response)
		vim.schedule(function()
			callback(err, response)
		end)
	end

	local port = M.read_port(workspace_root)
	if not port then
		done(
			string.format(
				"Cannot read %s/%s. Is KLS running with debug server enabled?",
				workspace_root or "<nil>",
				PORT_FILE_NAME
			),
			nil
		)
		return
	end

	local request_obj = {
		jsonrpc = "2.0",
		id = gen_id(),
		method = method,
		params = params or vim.empty_dict(),
	}
	local ok_enc, json_body = pcall(vim.json.encode, request_obj)
	if not ok_enc then
		done("failed to encode JSON-RPC request: " .. tostring(json_body), nil)
		return
	end
	local frame = string.format("Content-Length: %d\r\n\r\n%s", #json_body, json_body)

	local sock = uv.new_tcp()
	if not sock then
		done("failed to allocate TCP handle", nil)
		return
	end

	local timer = uv.new_timer()
	local finished = false
	local parser = new_parser()

	local function finish(err, response)
		if finished then
			return
		end
		finished = true
		safe_timer_stop(timer)
		safe_close(sock)
		done(err, response)
	end

	if timer then
		timer:start(
			timeout_ms,
			0,
			vim.schedule_wrap(function()
				finish(
					string.format("KLS request timed out after %dms (port %d)", timeout_ms, port),
					nil
				)
			end)
		)
	end

	sock:connect("127.0.0.1", port, function(connect_err)
		if connect_err then
			finish(
				string.format(
					"Cannot connect to KLS debug server on 127.0.0.1:%d: %s",
					port,
					connect_err
				),
				nil
			)
			return
		end

		sock:write(frame, function(write_err)
			if write_err then
				finish(string.format("Failed writing to KLS socket: %s", write_err), nil)
				return
			end
		end)

		sock:read_start(function(read_err, chunk)
			if read_err then
				finish(string.format("Failed reading from KLS socket: %s", read_err), nil)
				return
			end
			if chunk == nil then
				if not finished then
					finish("KLS closed connection before sending complete response", nil)
				end
				return
			end
			parser.buf = parser.buf .. chunk
			local body, perr = parser_pop(parser)
			if perr then
				finish("Malformed KLS response: " .. perr, nil)
				return
			end
			if not body then
				return
			end
			local ok_dec, decoded = pcall(vim.json.decode, body)
			if not ok_dec then
				finish(
					"Failed to decode KLS response JSON: "
						.. tostring(decoded)
						.. " (body="
						.. body:sub(1, 200)
						.. ")",
					nil
				)
				return
			end
			finish(nil, decoded)
		end)
	end)
end

--- Convenience wrapper around workspace/executeCommand. Returns the
--- `result` field on success, surfaces JSON-RPC `error` as a string.
---@param workspace_root string
---@param command string
---@param args table|nil
---@param callback fun(err: string|nil, result: any)
---@param opts table|nil
function M.execute_command(workspace_root, command, args, callback, opts)
	M.request(workspace_root, "workspace/executeCommand", {
		command = command,
		arguments = args or {},
	}, function(err, response)
		if err then
			callback(err, nil)
			return
		end
		if type(response) ~= "table" then
			callback("KLS returned non-object response", nil)
			return
		end
		if response.error then
			callback(string.format("KLS error: %s", vim.json.encode(response.error)), nil)
			return
		end
		callback(nil, response.result)
	end, opts)
end

return M

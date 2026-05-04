--- KLS debug context collector.
---
--- Fans out 6 parallel KLS debug queries via the TCP client (T3) and aggregates
--- the results into a single bundle. Per-query failures are recorded in the
--- `errors` list and never abort the whole collection.
---
--- Public API:
---   M.collect(workspace_root, bufnr, line, character, callback)
---     callback(result, meta)
---       result:
---         table with keys {summary, last_cursor, diagnostics, ast_chain,
---         type_info, hover, errors} when KLS is reachable.
---         nil when soft-degraded (no workspace_root or port file missing).
---       meta:
---         nil when result is populated.
---         { available = false, reason = "..." } on soft-degrade.
---
--- Soft-degrade triggers (no callback error, no throw):
---   * workspace_root == nil or empty
---   * port file (`<workspace_root>/.kls-debug-port`) missing
---
--- All TCP work goes through `kls-debug.kls` (T3); this module never opens
--- sockets directly.

local kls = require("kls-debug.kls")
local config = require("kls-debug.config")

local M = {}

--- Build the list of (key, command, args) tuples to dispatch.
--- Cursor-dependent ops are skipped when `uri`/`line`/`character` are missing.
local function build_queries(uri, line, character)
	local has_cursor = type(uri) == "string"
		and uri ~= ""
		and type(line) == "number"
		and type(character) == "number"

	local queries = {
		{ key = "summary", command = "kotlin.queryIndex", args = {} },
		{ key = "last_cursor", command = "kotlin.lastCursor", args = {} },
	}

	if has_cursor then
		table.insert(queries, {
			key = "diagnostics",
			command = "kotlin.diagnosticsForUri",
			args = { uri },
		})
		table.insert(queries, {
			key = "ast_chain",
			command = "kotlin.astAt",
			args = { uri, line, character },
		})
		table.insert(queries, {
			key = "type_info",
			command = "kotlin.typeAt",
			args = { uri, line, character },
		})
		table.insert(queries, {
			key = "hover",
			command = "kotlin.hoverAt",
			args = { uri, line, character },
		})
	end

	return queries
end

--- Best-effort URI for a buffer. Returns nil if the buffer has no name.
local function uri_for_bufnr(bufnr)
	if type(bufnr) ~= "number" then
		return nil
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local ok, uri = pcall(vim.uri_from_bufnr, bufnr)
	if not ok or type(uri) ~= "string" or uri == "" or uri == "file://" then
		return nil
	end
	return uri
end

--- Async fan-out collector. See module header for semantics.
---@param workspace_root string|nil
---@param bufnr integer|nil
---@param line integer|nil   0-based LSP line
---@param character integer|nil  0-based LSP character
---@param callback fun(result: table|nil, meta: table|nil)
function M.collect(workspace_root, bufnr, line, character, callback)
	assert(type(callback) == "function", "callback must be a function")

	if type(workspace_root) ~= "string" or workspace_root == "" then
		callback(nil, { available = false, reason = "no workspace_root" })
		return
	end

	if not kls.read_port(workspace_root) then
		callback(nil, {
			available = false,
			reason = "port file missing (is KLS running with debug server enabled?)",
		})
		return
	end

	local uri = uri_for_bufnr(bufnr)
	local queries = build_queries(uri, line, character)
	local total = #queries

	local result = {
		summary = nil,
		last_cursor = nil,
		diagnostics = nil,
		ast_chain = nil,
		type_info = nil,
		hover = nil,
		errors = {},
	}

	local pending = total
	local fired = false
	local function maybe_finish()
		if pending > 0 or fired then
			return
		end
		fired = true
		callback(result, nil)
	end

	if total == 0 then
		maybe_finish()
		return
	end

	local cfg_ok, cfg = pcall(config.get)
	local timeout_ms = (cfg_ok and type(cfg) == "table" and cfg.kls_connect_timeout_ms) or 500
	local opts = { timeout_ms = timeout_ms }

	for _, q in ipairs(queries) do
		kls.execute_command(workspace_root, q.command, q.args, function(err, res)
			if err then
				table.insert(result.errors, { command = q.command, error = err })
			else
				result[q.key] = res
			end
			pending = pending - 1
			maybe_finish()
		end, opts)
	end
end

return M

local M = {}

local function detect_log_path(opts)
	if type(opts) ~= "table" then
		return nil
	end

	if type(opts.kls_log_path) == "string" and opts.kls_log_path ~= "" then
		return opts.kls_log_path
	end

	local workspace_root = opts.workspace_root
	if type(workspace_root) ~= "string" or workspace_root == "" then
		workspace_root = vim.fn.getcwd()
	end

	local candidates = {
		workspace_root .. "/kls.log",
		"/tmp/kls.log",
	}

	for _, path in ipairs(candidates) do
		if vim.fn.filereadable(path) == 1 then
			return path
		end
	end

	return nil
end

local function read_tail(path, max_lines)
	if vim.fn.filereadable(path) ~= 1 then
		return nil, "not found"
	end

	local lines = vim.fn.readfile(path, "", -max_lines)
	return table.concat(lines, "\n"), nil
end

function M.collect(opts, callback)
	local result = { kind = "kls_log", ok = false }
	local cb = type(callback) == "function" and callback or function() end
	local ok, err = pcall(function()
		local path = detect_log_path(opts)
		if type(path) ~= "string" or path == "" then
			result.reason = "no log file found"
			cb(result)
			return
		end

		local lines = tonumber(type(opts) == "table" and opts.log_tail_lines or nil) or 200
		local data, reason = read_tail(path, lines)
		if data == nil then
			result.reason = reason or "not found"
			cb(result)
			return
		end

		result.ok = true
		result.data = data
		cb(result)
	end)

	if not ok then
		cb({ kind = "kls_log", ok = false, reason = tostring(err) })
	end
end

return M

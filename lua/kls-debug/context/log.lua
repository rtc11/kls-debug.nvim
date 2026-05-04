local M = {}

local uv = vim.uv or vim.loop

local MAX_BYTES = 100 * 1024
local CHUNK_SIZE = 8192
local READ_ALL_CUTOFF = 1024 * 1024

local function split_lines(text)
	local lines = {}
	if type(text) ~= "string" or text == "" then
		return lines
	end
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, line)
	end
	return lines
end

local function tail_lines_from_text(text, max_lines)
	local lines = split_lines(text)
	if #lines <= max_lines then
		return text
	end
	local start = #lines - max_lines + 1
	local out = {}
	for i = start, #lines do
		table.insert(out, lines[i])
	end
	return table.concat(out, "\n")
end

local function read_tail(path, max_lines)
	local fd = uv.fs_open(path, "r", 438)
	if not fd then
		return nil, "not found"
	end

	local stat = uv.fs_fstat(fd)
	if not stat then
		uv.fs_close(fd)
		return nil, "not found"
	end

	local size = stat.size or 0
	local cap = math.min(MAX_BYTES, size)
	if size <= READ_ALL_CUTOFF then
		local data = uv.fs_read(fd, cap, 0) or ""
		uv.fs_close(fd)
		return tail_lines_from_text(data, max_lines), nil
	end

	local chunks = {}
	local remaining = cap
	local offset = size
	local total = 0
	while remaining > 0 and offset > 0 do
		local read_len = math.min(CHUNK_SIZE, remaining, offset)
		offset = offset - read_len
		local chunk = uv.fs_read(fd, read_len, offset) or ""
		table.insert(chunks, 1, chunk)
		total = total + #chunk
		remaining = remaining - #chunk
		if total >= cap then
			break
		end
	end

	uv.fs_close(fd)
	local text = table.concat(chunks, "")
	return tail_lines_from_text(text, max_lines), nil
end

function M.collect(opts, callback)
	local result = { kind = "log", ok = false }
	local cb = type(callback) == "function" and callback or function() end
	local ok, err = pcall(function()
		local path = type(opts) == "table" and opts.kls_log_path or nil
		if type(path) ~= "string" or path == "" then
			result.reason = "not configured"
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
		cb({ kind = "log", ok = false, reason = tostring(err) })
	end
end

return M

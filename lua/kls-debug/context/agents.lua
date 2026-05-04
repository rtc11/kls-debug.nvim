local M = {}

local uv = vim.uv or vim.loop

local MAX_BYTES = 50 * 1024

local function read_head(path, cap)
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
	local to_read = math.min(size, cap)
	local data = uv.fs_read(fd, to_read, 0) or ""
	uv.fs_close(fd)
	return data, nil
end

function M.collect(_opts, workspace_root)
	if type(workspace_root) ~= "string" or workspace_root == "" then
		return { kind = "agents", ok = false, reason = "not found" }
	end

	local path = workspace_root .. "/AGENTS.md"
	local ok, data_or_reason = pcall(read_head, path, MAX_BYTES)
	if not ok then
		return { kind = "agents", ok = false, reason = tostring(data_or_reason) }
	end

	if data_or_reason == nil then
		return { kind = "agents", ok = false, reason = "not found" }
	end

	return { kind = "agents", ok = true, data = data_or_reason }
end

return M

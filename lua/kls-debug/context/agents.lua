local M = {}

local MAX_BYTES = 50 * 1024

local function read_head(path, cap)
	if vim.fn.filereadable(path) ~= 1 then
		return nil, "not found"
	end

	local lines = vim.fn.readfile(path)
	local data = table.concat(lines, "\n")
	if #data > cap then
		data = data:sub(1, cap)
	end
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

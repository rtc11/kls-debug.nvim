local M = {}

local severity_order = {
	[vim.diagnostic.severity.ERROR] = 1,
	[vim.diagnostic.severity.WARN] = 2,
	[vim.diagnostic.severity.INFO] = 3,
	[vim.diagnostic.severity.HINT] = 4,
}

local function normalize_args(a, b, c)
	if type(a) == "table" then
		return a, b or 0, c
	end

	return b or {}, a or 0, c
end

local function get_namespace_name(ns)
	local ok, info = pcall(vim.diagnostic.get_namespace, ns)
	if not ok or type(info) ~= "table" then
		return nil
	end

	return info.name
end

function M.collect(a, b, c)
	local opts, bufnr, line_range = normalize_args(a, b, c)
	opts = opts or {}
	bufnr = bufnr or 0

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { kind = "diagnostics", ok = false, data = nil, error = "invalid buffer" }
	end

	local diagnostics = vim.diagnostic.get(bufnr, line_range)
	local namespace_name = opts.namespace_name
	if namespace_name == nil and opts.namespace ~= nil then
		namespace_name = get_namespace_name(opts.namespace)
	end

	local items = {}
	for _, diag in ipairs(diagnostics) do
		if
			namespace_name == nil
			or diag.source == namespace_name
			or diag.namespace_name == namespace_name
		then
			table.insert(items, {
				line = diag.lnum or 0,
				col = diag.col or 0,
				severity = severity_order[diag.severity] or 99,
				message = diag.message or "",
				source = diag.source or "",
			})
		end
	end

	table.sort(items, function(a_item, b_item)
		if a_item.severity ~= b_item.severity then
			return a_item.severity < b_item.severity
		end
		if a_item.line ~= b_item.line then
			return a_item.line < b_item.line
		end
		if a_item.col ~= b_item.col then
			return a_item.col < b_item.col
		end
		return a_item.message < b_item.message
	end)

	local cap = opts.diagnostic_cap or 50
	if #items > cap then
		while #items > cap do
			table.remove(items)
		end
	end

	return {
		kind = "diagnostics",
		ok = true,
		data = items,
	}
end

return M

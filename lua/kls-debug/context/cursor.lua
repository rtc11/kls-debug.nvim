local M = {}

local function normalize_args(a, b, c, d)
	if type(a) == "table" then
		return a, b or 0, c, d
	end

	return b or {}, a or 0, c, d
end

local function word_at(line, col)
	if not line or line == "" then
		return ""
	end
	local idx = math.max(1, math.min(#line, (col or 0) + 1))
	local left = idx
	while left > 1 and line:sub(left - 1, left - 1):match("[%w_]") do
		left = left - 1
	end
	local right = idx
	while right <= #line and line:sub(right, right):match("[%w_]") do
		right = right + 1
	end
	return line:sub(left, right - 1)
end

function M.collect(a, b, c, d)
	local opts, bufnr, row, col = normalize_args(a, b, c, d)
	opts = opts or {}
	bufnr = bufnr or 0

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { kind = "cursor", ok = false, data = nil, error = "invalid buffer" }
	end

	row = row or vim.api.nvim_win_get_cursor(0)[1]
	col = col or vim.api.nvim_win_get_cursor(0)[2]
	local line_text = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
	local surrounding = opts.surrounding_lines or 10
	local before =
		vim.api.nvim_buf_get_lines(bufnr, math.max(0, row - surrounding - 1), row - 1, false)
	local after = vim.api.nvim_buf_get_lines(bufnr, row, row + surrounding, false)

	return {
		kind = "cursor",
		ok = true,
		data = {
			line = row,
			col = col,
			symbol = word_at(line_text, col),
			line_text = line_text,
			surrounding_before = table.concat(before, "\n"),
			surrounding_after = table.concat(after, "\n"),
		},
	}
end

return M

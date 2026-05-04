local M = {}

local function normalize_args(a, b)
	if type(a) == "table" then
		return a, b or 0
	end

	return b or {}, a or 0
end

local function get_range(bufnr)
	local srow, scol = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
	local erow, ecol = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
	if srow == 0 or erow == 0 then
		return nil
	end
	if erow < srow or (erow == srow and ecol < scol) then
		srow, erow = erow, srow
		scol, ecol = ecol, scol
	end
	return srow, scol, erow, ecol
end

local function lines_between(bufnr, start_line, end_line)
	return vim.api.nvim_buf_get_lines(bufnr, math.max(0, start_line - 1), end_line, false)
end

function M.collect(a, b)
	local opts, bufnr = normalize_args(a, b)
	opts = opts or {}
	bufnr = bufnr or 0

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { kind = "selection", ok = false, data = nil, error = "invalid buffer" }
	end

	local srow, scol, erow, ecol = get_range(bufnr)
	if not srow then
		return { kind = "selection", ok = false, data = nil }
	end

	local before_start = math.max(1, srow - (opts.surrounding_lines or 10))
	local after_end = erow + (opts.surrounding_lines or 10)
	local selection_lines = lines_between(bufnr, srow, erow)
	local before_lines = lines_between(bufnr, before_start, srow - 1)
	local after_lines = lines_between(bufnr, erow + 1, after_end)

	return {
		kind = "selection",
		ok = true,
		data = {
			start_line = srow,
			start_col = scol,
			end_line = erow,
			end_col = ecol,
			content = table.concat(selection_lines, "\n"),
			surrounding_before = table.concat(before_lines, "\n"),
			surrounding_after = table.concat(after_lines, "\n"),
		},
	}
end

return M

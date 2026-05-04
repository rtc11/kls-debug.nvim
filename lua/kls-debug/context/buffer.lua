local M = {}

local trunc_marker = "\n[... TRUNCATED ...]\n"

local function normalize_args(a, b, c)
	if type(a) == "table" then
		return a, b or 0, c
	end

	return b or {}, a or 0, c
end

local function join_lines(lines)
	return table.concat(lines, "\n")
end

local function slice_bytes(text, start_byte, end_byte)
	if start_byte < 1 then
		start_byte = 1
	end
	if end_byte < start_byte then
		return ""
	end
	return text:sub(start_byte, end_byte)
end

local function line_start_offsets(lines)
	local starts = {}
	local offset = 1
	for i, line in ipairs(lines) do
		starts[i] = offset
		offset = offset + #line + 1
	end
	return starts, offset - 1
end

function M.collect(a, b, c)
	local opts, bufnr, cursor_row = normalize_args(a, b, c)
	opts = opts or {}
	bufnr = bufnr or 0

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { kind = "buffer", ok = false, data = nil, error = "invalid buffer" }
	end
	if vim.bo[bufnr].binary == true then
		return { kind = "buffer", ok = false, data = nil, error = "binary buffer" }
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = join_lines(lines)
	local byte_count = #content
	local cap = opts.buffer_byte_cap or 102400
	local around = opts.buffer_around_cursor or 20480

	if byte_count <= cap then
		return {
			kind = "buffer",
			ok = true,
			data = {
				filename = vim.api.nvim_buf_get_name(bufnr),
				filetype = vim.bo[bufnr].filetype,
				content = content,
				truncated = false,
				byte_count = byte_count,
			},
		}
	end

	local starts, total_bytes = line_start_offsets(lines)
	local cursor_line = cursor_row or math.max(1, math.floor(#lines / 2) + 1)
	if cursor_line < 1 then
		cursor_line = 1
	elseif cursor_line > #lines then
		cursor_line = #lines
	end

	local line_text = lines[cursor_line] or ""
	local line_start = starts[cursor_line] or 1
	local line_end = math.min(total_bytes, line_start + #line_text - 1)
	local half = math.floor(around / 2)
	local window_start = math.max(1, line_start - half)
	local window_end = math.min(total_bytes, line_end + (around - half))

	local head_budget = math.max(0, cap - around)
	local head = slice_bytes(content, 1, math.min(head_budget, window_start - 1))
	local middle = slice_bytes(content, window_start, window_end)
	local tail_start = math.max(
		window_end + 1,
		total_bytes - math.max(0, cap - #head - #middle - #trunc_marker * 2) + 1
	)
	local tail = slice_bytes(content, tail_start, total_bytes)

	local truncated = true
	local out = head .. trunc_marker .. middle .. trunc_marker .. tail

	return {
		kind = "buffer",
		ok = true,
		data = {
			filename = vim.api.nvim_buf_get_name(bufnr),
			filetype = vim.bo[bufnr].filetype,
			content = out,
			truncated = truncated,
			byte_count = #out,
		},
	}
end

return M

local M = {}

local output_prefix = "[kls-debug-output]"
local notify_prefix = "[kls-debug]"

local function is_valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(bufnr)
	return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

local function normalize_lines(lines)
	if lines == nil then
		return {}
	end

	if type(lines) == "string" then
		return vim.split(lines, "\n", { plain = true, trimempty = false })
	end

	return lines
end

local function buffer_name()
	local name = output_prefix
	local suffix = 1

	while vim.fn.bufexists(name) == 1 do
		suffix = suffix + 1
		name = string.format("%s-%d", output_prefix, suffix)
	end

	return name
end

local function configure_buffer(bufnr)
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = "markdown"
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].readonly = false
	vim.bo[bufnr].buflisted = false
	vim.api.nvim_buf_set_name(bufnr, buffer_name())
end

local function map_close(bufnr, close)
	vim.keymap.set("n", "q", close, {
		buffer = bufnr,
		silent = true,
		nowait = true,
	})
	vim.keymap.set("n", "<Esc>", close, {
		buffer = bufnr,
		silent = true,
		nowait = true,
	})
end

local function set_buffer_text(bufnr, lines)
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, normalize_lines(lines))
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].readonly = true
	vim.api.nvim_buf_set_option(bufnr, "modified", false)
end

local function append_buffer_text(bufnr, lines)
	local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for _, line in ipairs(normalize_lines(lines)) do
		table.insert(current, line)
	end
	set_buffer_text(bufnr, current)
end

local function close_window(win)
	if is_valid_win(win) then
		vim.api.nvim_win_close(win, true)
	end
end

local function open_split(bufnr)
	vim.cmd("rightbelow split")
	local win = vim.api.nvim_get_current_win()
	local height = math.max(5, math.floor(vim.o.lines * 0.4))
	vim.api.nvim_win_set_height(win, height)
	vim.api.nvim_win_set_buf(win, bufnr)
	return win
end

local function open_float(bufnr)
	local cols = vim.o.columns
	local lines = vim.o.lines
	local width = math.max(20, math.floor(cols * 0.8))
	local height = math.max(5, math.floor(lines * 0.8))
	local row = math.floor((lines - height) / 2 - 1)
	local col = math.floor((cols - width) / 2)
	return vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		row = row,
		col = col,
		width = width,
		height = height,
	})
end

local function open_tab(bufnr)
	vim.cmd("tabnew")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, bufnr)
	return win
end

local function open_window(bufnr, output)
	if output == "float" then
		return open_float(bufnr)
	end

	if output == "tab" then
		return open_tab(bufnr)
	end

	return open_split(bufnr)
end

function M.create_output(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_create_buf(false, true)
	configure_buffer(bufnr)

	local win = open_window(bufnr, opts.output or "split")

	local function close()
		close_window(win)
	end

	map_close(bufnr, close)

	return {
		buf = bufnr,
		win = win,
		name = vim.api.nvim_buf_get_name(bufnr),
		set_text = function(lines)
			if is_valid_buf(bufnr) then
				set_buffer_text(bufnr, lines)
			end
		end,
		append = function(lines)
			if is_valid_buf(bufnr) then
				append_buffer_text(bufnr, lines)
			end
		end,
		close = close,
	}
end

function M.show_output(text, opts)
	local view = M.create_output(opts)
	view.set_text(text)
	vim.api.nvim_win_set_cursor(view.win, { 1, 0 })
	return view.buf, view.win
end

function M.show_split(text)
	return M.show_output(text, { output = "split" })
end

function M.show_float(text)
	return M.show_output(text, { output = "float" })
end

function M.show_tab(text)
	return M.show_output(text, { output = "tab" })
end

function M.notify(msg, level)
	vim.notify(string.format("%s %s", notify_prefix, msg), level)
end

return M

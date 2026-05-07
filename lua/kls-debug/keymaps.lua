local M = {}

local function escape_backticks(value)
	return (value:gsub("`", "\\`"))
end

function M._normal_diag_handler()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local ok, diagnostics = pcall(vim.diagnostic.get, 0, { lnum = line - 1 })
	if not ok or type(diagnostics) ~= "table" or #diagnostics == 0 then
		vim.notify("kls-debug: no diagnostic at cursor", vim.log.levels.WARN)
		return
	end

	local msg = diagnostics[1].message or ""
	local q = "Why this error and how to fix? `" .. escape_backticks(msg) .. "`"
	vim.cmd("KlsDebugAsk " .. q)
end

function M.setup(cfg)
	if cfg == nil or cfg.keymaps == nil or cfg.keymaps.enabled ~= true then
		return
	end

	local visual_lhs = cfg.keymaps.visual
	local normal_lhs = cfg.keymaps.normal_diag

	vim.keymap.set("v", visual_lhs, function()
		local cursor_line = vim.fn.line(".")
		local anchor_line = vim.fn.line("v")
		local line1 = math.min(cursor_line, anchor_line)
		local line2 = math.max(cursor_line, anchor_line)

		vim.cmd("normal! \27")

		vim.ui.input({ prompt = "KlsDebugAsk: " }, function(input)
			if input == nil then
				return
			end

			vim.api.nvim_cmd({
				cmd = "KlsDebugAsk",
				range = { line1, line2 },
				args = { input },
			}, {})
		end)
	end, { desc = "KlsDebugAsk selection", silent = true })

	vim.keymap.set(
		"n",
		normal_lhs,
		M._normal_diag_handler,
		{ desc = "KlsDebugAsk diagnostic", silent = true }
	)
end

return M

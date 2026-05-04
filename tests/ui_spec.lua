local ui = require("kls-debug.ui")

local function close_all_windows()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		pcall(vim.api.nvim_win_close, win, true)
	end
end

local function check(cond, msg)
	assert(cond, msg)
end

local function eq(a, b, msg)
	check(a == b, msg or string.format("expected %s, got %s", vim.inspect(b), vim.inspect(a)))
end

describe("kls-debug.ui", function()
	after_each(function()
		close_all_windows()
	end)

	for _, mode in ipairs({ "split", "float", "tab" }) do
		it("creates " .. mode .. " output", function()
			local view = ui.create_output({ output = mode })

			check(vim.api.nvim_buf_is_valid(view.buf), "buffer invalid")
			check(vim.api.nvim_win_is_valid(view.win), "window invalid")
			check(string.find(view.name, "kls-debug-output", 1, true) ~= nil, "name missing")
			eq(vim.bo[view.buf].filetype, "markdown")
			eq(vim.bo[view.buf].buftype, "nofile")
			eq(vim.bo[view.buf].modifiable, true)
			eq(vim.bo[view.buf].readonly, false)

			view.close()
		end)
	end

	it("writes lines with set_text", function()
		local view = ui.create_output({ output = "split" })
		view.set_text({ "# hello", "", "world" })

		local lines = vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)
		eq(#lines, 3)
		eq(lines[1], "# hello")
		eq(lines[2], "")
		eq(lines[3], "world")
		eq(vim.bo[view.buf].modifiable, false)
		view.close()
	end)

	it("closes window from q keymap", function()
		local view = ui.create_output({ output = "float" })
		vim.schedule(function()
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("q", true, false, true),
				"mx",
				false
			)
		end)
		vim.wait(1000, function()
			return not vim.api.nvim_win_is_valid(view.win)
		end)

		check(not vim.api.nvim_win_is_valid(view.win), "window still valid")
	end)
end)

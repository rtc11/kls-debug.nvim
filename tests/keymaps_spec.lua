local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()

vim.opt.runtimepath:prepend(ROOT)

local function del_map(mode, lhs)
	pcall(vim.keymap.del, mode, lhs)
end

describe("kls-debug keymaps", function()
	local original_cmd
	local original_notify
	local original_input
	local cmd_calls
	local notify_calls

	before_each(function()
		cmd_calls = {}
		notify_calls = {}
		original_cmd = vim.cmd
		original_notify = vim.notify
		original_input = vim.ui.input

		vim.cmd = function(cmd)
			table.insert(cmd_calls, cmd)
		end

		vim.notify = function(msg, level)
			table.insert(notify_calls, { msg = msg, level = level })
		end

		del_map("v", "<leader>kdv")
		del_map("n", "<leader>kdn")
		del_map("v", "<leader>kd")
		del_map("n", "<leader>kd")
	end)

	after_each(function()
		vim.cmd = original_cmd
		vim.notify = original_notify
		vim.ui.input = original_input
		del_map("v", "<leader>kdv")
		del_map("n", "<leader>kdn")
		del_map("v", "<leader>kd")
		del_map("n", "<leader>kd")
	end)

	it("registers both maps when enabled", function()
		require("kls-debug.keymaps").setup({
			keymaps = {
				enabled = true,
				visual = "<leader>kdv",
				normal_diag = "<leader>kdn",
			},
		})

		assert.is_not.equal("", vim.fn.maparg("<leader>kdv", "v"))
		assert.is_not.equal("", vim.fn.maparg("<leader>kdn", "n"))
	end)

	it("registers nothing when disabled", function()
		require("kls-debug.keymaps").setup({
			keymaps = {
				enabled = false,
				visual = "<leader>kdv",
				normal_diag = "<leader>kdn",
			},
		})

		assert.are.same("", vim.fn.maparg("<leader>kdv", "v"))
		assert.are.same("", vim.fn.maparg("<leader>kdn", "n"))
	end)

	it("normal handler warns when no diagnostics", function()
		local original_get = vim.diagnostic.get
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.diagnostic.get = function()
			return {}
		end

		require("kls-debug.keymaps")._normal_diag_handler()

		assert.are.same({
			{ msg = "kls-debug: no diagnostic at cursor", level = vim.log.levels.WARN },
		}, notify_calls)
		assert.are.same({}, cmd_calls)
		vim.diagnostic.get = original_get
	end)

	it("normal handler asks about diagnostic", function()
		local original_get = vim.diagnostic.get
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.diagnostic.get = function()
			return { { message = "bad `thing`" } }
		end

		require("kls-debug.keymaps")._normal_diag_handler()

		assert.are.same(
			{ "KlsDebugAsk Why this error and how to fix? `bad \\`thing\\``" },
			cmd_calls
		)
		assert.are.same({}, notify_calls)
		vim.diagnostic.get = original_get
	end)
end)

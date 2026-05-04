local selection = require("kls-debug.context.selection")

describe("kls-debug.context.selection", function()
	local bufnr

	before_each(function()
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
			"one",
			"two",
			"three",
			"four",
			"five",
		})
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	it("reads visual marks and surrounding lines", function()
		vim.api.nvim_buf_set_mark(bufnr, "<", 2, 0, {})
		vim.api.nvim_buf_set_mark(bufnr, ">", 4, 0, {})

		local result = selection.collect({ surrounding_lines = 1 }, bufnr)
		assert.is_true(result.ok)
		assert.are.equal(2, result.data.start_line)
		assert.are.equal(4, result.data.end_line)
		assert.are.equal("two\nthree\nfour", result.data.content)
		assert.are.equal("one", result.data.surrounding_before)
		assert.are.equal("five", result.data.surrounding_after)
	end)

	it("returns ok false when marks missing", function()
		local result = selection.collect({}, bufnr)
		assert.is_false(result.ok)
		assert.is_nil(result.data)
	end)
end)

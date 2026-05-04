local cursor = require("kls-debug.context.cursor")

describe("kls-debug.context.cursor", function()
	local bufnr

	before_each(function()
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
			"alpha beta",
			"gamma delta",
			"epsilon zeta",
			"eta theta",
		})
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	it("returns cursor symbol and context lines", function()
		local result = cursor.collect({ surrounding_lines = 1 }, bufnr, 2, 8)
		assert.is_true(result.ok)
		assert.are.equal(2, result.data.line)
		assert.are.equal(8, result.data.col)
		assert.are.equal("delta", result.data.symbol)
		assert.are.equal("gamma delta", result.data.line_text)
		assert.are.equal("alpha beta", result.data.surrounding_before)
		assert.are.equal("epsilon zeta", result.data.surrounding_after)
	end)
end)

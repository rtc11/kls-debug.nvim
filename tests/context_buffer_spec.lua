local buffer = require("kls-debug.context.buffer")

describe("kls-debug.context.buffer", function()
	local bufnr

	before_each(function()
		bufnr = vim.api.nvim_create_buf(false, true)
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	it("returns full content under cap", function()
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello", "world" })
		local result =
			buffer.collect({ buffer_byte_cap = 100, buffer_around_cursor = 20 }, bufnr, 1)
		assert.is_true(result.ok)
		assert.is_false(result.data.truncated)
		assert.are.equal("hello\nworld", result.data.content)
	end)

	it("truncates over cap and includes marker", function()
		local lines = {}
		for i = 1, 5000 do
			lines[i] = string.rep("x", 20)
		end
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		local result =
			buffer.collect({ buffer_byte_cap = 1024, buffer_around_cursor = 256 }, bufnr, 2000)
		assert.is_true(result.ok)
		assert.is_true(result.data.truncated)
		assert.is_true(result.data.byte_count > 0)
		assert.is_true(result.data.content:find("%[%... TRUNCATED %...%]") ~= nil)
	end)

	it("refuses binary buffer", function()
		vim.bo[bufnr].binary = true
		local result = buffer.collect({}, bufnr, 1)
		assert.is_false(result.ok)
		assert.is_nil(result.data)
	end)
end)

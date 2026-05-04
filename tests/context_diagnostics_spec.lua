local diagnostics = require("kls-debug.context.diagnostics")

describe("kls-debug.context.diagnostics", function()
	local bufnr
	local ns

	before_each(function()
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
		ns = vim.api.nvim_create_namespace("kls-debug-test-diag")
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	it("sorts by severity and caps result", function()
		local items = {}
		for i = 1, 60 do
			items[i] = {
				lnum = i % 3,
				col = 0,
				severity = (i % 4) + 1,
				message = string.format("d%d", i),
				source = "kls",
			}
		end
		vim.diagnostic.set(ns, bufnr, items, {})

		local result = diagnostics.collect({ diagnostic_cap = 50 }, bufnr)
		assert.is_true(result.ok)
		assert.are.equal("diagnostics", result.kind)
		assert.are.equal(50, #result.data)
		assert.are.equal(1, result.data[1].severity)
		assert.is_true(result.data[1].message ~= "")
	end)

	it("supports line range", function()
		vim.diagnostic.set(ns, bufnr, {
			{
				lnum = 0,
				col = 0,
				severity = vim.diagnostic.severity.ERROR,
				message = "a",
				source = "kls",
			},
			{
				lnum = 1,
				col = 0,
				severity = vim.diagnostic.severity.WARN,
				message = "b",
				source = "kls",
			},
		}, {})

		local result = diagnostics.collect({ diagnostic_cap = 10 }, bufnr, { lnum = 1 })
		assert.are.equal(1, #result.data)
		assert.are.equal("b", result.data[1].message)
	end)
end)

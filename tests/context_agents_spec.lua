local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()
vim.opt.runtimepath:prepend(ROOT)

local agents = require("kls-debug.context.agents")

describe("kls-debug.context.agents", function()
	it("reads AGENTS.md head", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		local body = { "# AGENTS", "line 1", "line 2" }
		vim.fn.writefile(body, dir .. "/AGENTS.md")

		local got = agents.collect({}, dir)
		assert.are.equal("agents", got.kind)
		assert.is_true(got.ok)
		assert.is_string(got.data)
		assert.is_truthy(got.data:find("# AGENTS", 1, true))
	end)

	it("soft skips missing AGENTS.md", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		local got = agents.collect({}, dir)
		assert.are.equal("agents", got.kind)
		assert.is_false(got.ok)
		assert.are.equal("not found", got.reason)
	end)
end)

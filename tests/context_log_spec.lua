local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()
vim.opt.runtimepath:prepend(ROOT)

local log = require("kls-debug.context.log")

local function wait_for(done, timeout_ms)
	return vim.wait(timeout_ms or 5000, function()
		return done.value
	end, 20)
end

describe("kls-debug.context.log", function()
	it("returns tail lines", function()
		local path = vim.fn.tempname()
		local lines = {}
		for i = 1, 260 do
			table.insert(lines, string.format("line %03d", i))
		end
		vim.fn.writefile(lines, path)

		local done = { value = false }
		local got
		log.collect({ kls_log_path = path, log_tail_lines = 200 }, function(result)
			got = result
			done.value = true
		end)

		assert.is_true(wait_for(done))
		assert.are.equal("log", got.kind)
		assert.is_true(got.ok)
		assert.is_string(got.data)
		assert.is_nil(got.data:find("line 001", 1, true))
		assert.is_truthy(got.data:find("line 260", 1, true))
	end)

	it("soft skips when not configured", function()
		local done = { value = false }
		local got
		log.collect({}, function(result)
			got = result
			done.value = true
		end)

		assert.is_true(wait_for(done))
		assert.are.equal("log", got.kind)
		assert.is_false(got.ok)
		assert.are.equal("not configured", got.reason)
	end)
end)

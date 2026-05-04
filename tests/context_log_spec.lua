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
		assert.are.equal("kls_log", got.kind)
		assert.is_true(got.ok)
		assert.is_string(got.data)
		assert.is_nil(got.data:find("line 001", 1, true))
		assert.is_truthy(got.data:find("line 260", 1, true))
	end)

	it("auto-detects workspace kls.log", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		local path = dir .. "/kls.log"
		vim.fn.writefile({ "workspace log" }, path)

		local done = { value = false }
		local got
		log.collect({ workspace_root = dir }, function(result)
			got = result
			done.value = true
		end)

		assert.is_true(wait_for(done))
		assert.are.equal("kls_log", got.kind)
		assert.is_true(got.ok)
		assert.are.equal("workspace log", got.data)
	end)

	it("auto-detects /tmp/kls.log fallback", function()
		local path = "/tmp/kls.log"
		local had_existing = vim.fn.filereadable(path) == 1
		local original = had_existing and vim.fn.readfile(path) or nil
		vim.fn.writefile({ "tmp fallback log" }, path)

		local done = { value = false }
		local got
		log.collect({ workspace_root = vim.fn.tempname() }, function(result)
			got = result
			done.value = true
		end)

		assert.is_true(wait_for(done))
		assert.are.equal("kls_log", got.kind)
		assert.is_true(got.ok)
		assert.are.equal("tmp fallback log", got.data)

		if had_existing then
			vim.fn.writefile(original, path)
		else
			vim.fn.delete(path)
		end
	end)

	it("soft skips when no log file found", function()
		local path = "/tmp/kls.log"
		local had_existing = vim.fn.filereadable(path) == 1
		local original = had_existing and vim.fn.readfile(path) or nil
		if had_existing then
			vim.fn.delete(path)
		end

		local done = { value = false }
		local got
		log.collect({ workspace_root = vim.fn.tempname() }, function(result)
			got = result
			done.value = true
		end)

		assert.is_true(wait_for(done))
		assert.are.equal("kls_log", got.kind)
		assert.is_false(got.ok)
		assert.are.equal("no log file found", got.reason)

		if had_existing then
			vim.fn.writefile(original, path)
		end
	end)
end)

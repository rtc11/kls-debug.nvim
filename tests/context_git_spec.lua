local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()
vim.opt.runtimepath:prepend(ROOT)

local git = require("kls-debug.context.git")

local function wait_for(done, timeout_ms)
	return vim.wait(timeout_ms or 5000, function()
		return done.value
	end, 20)
end

local function run(cmd)
	local out = vim.fn.system(cmd)
	assert.are.equal(0, vim.v.shell_error)
	return out
end

describe("kls-debug.context.git", function()
	it("collects branch, commit, status, diff", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		run({ "git", "-C", dir, "init" })
		run({ "git", "-C", dir, "config", "user.name", "Test" })
		run({ "git", "-C", dir, "config", "user.email", "test@example.com" })

		local file = dir .. "/main.kt"
		vim.fn.writefile({ "first" }, file)
		run({ "git", "-C", dir, "add", "main.kt" })
		run({ "git", "-C", dir, "commit", "-m", "init" })

		vim.fn.writefile({ "first", "second" }, file)
		run({ "git", "-C", dir, "add", "main.kt" })
		vim.fn.writefile({ "first", "second", "third" }, file)

		local done = { value = false }
		local got
		git.collect({ file_path = file }, dir, function(result)
			got = result
			done.value = true
		end)

		assert.is_true(wait_for(done))
		assert.is_table(got)
		assert.are.equal("git", got.kind)
		assert.is_true(got.ok)
		assert.is_table(got.data)
		assert.is_string(got.data.branch)
		assert.is_string(got.data.commit)
		assert.is_string(got.data.status)
		assert.is_string(got.data.diff)
		assert.is_truthy(got.data.diff:find("--- staged", 1, true))
		assert.is_truthy(got.data.diff:find("--- unstaged", 1, true))
	end)

	it("soft skips non-repo", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		local done = { value = false }
		local got
		git.collect({}, dir, function(result)
			got = result
			done.value = true
		end)

		assert.is_true(wait_for(done))
		assert.are.equal("git", got.kind)
		assert.is_false(got.ok)
		assert.are.equal("not found", got.reason)
	end)
end)

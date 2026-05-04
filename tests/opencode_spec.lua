local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()
local FIX = ROOT .. "/tests/fixtures"

vim.opt.runtimepath:prepend(ROOT)

local opencode = require("kls-debug.opencode")

local function wait_for(predicate, timeout_ms)
	local ok = vim.wait(timeout_ms or 5000, predicate, 20)
	return ok
end

describe("opencode.build_env", function()
	it("includes PATH and HOME", function()
		vim.env.PATH = vim.env.PATH or "/usr/bin"
		vim.env.HOME = vim.env.HOME or "/tmp"
		local env = opencode._build_env()
		assert.is_truthy(env.PATH)
		assert.is_truthy(env.HOME)
	end)

	it("includes XDG_* keys", function()
		vim.env.XDG_TEST_KEY = "xyz"
		local env = opencode._build_env()
		assert.equals("xyz", env.XDG_TEST_KEY)
		vim.env.XDG_TEST_KEY = nil
	end)

	it("includes OPENCODE_* keys", function()
		vim.env.OPENCODE_FOO = "bar"
		local env = opencode._build_env()
		assert.equals("bar", env.OPENCODE_FOO)
		vim.env.OPENCODE_FOO = nil
	end)

	it("excludes secrets and unrelated vars", function()
		vim.env.SECRET_KEY_TEST = "supersecret"
		vim.env.AWS_ACCESS_KEY_ID = "leaky"
		local env = opencode._build_env()
		assert.is_nil(env.SECRET_KEY_TEST)
		assert.is_nil(env.AWS_ACCESS_KEY_ID)
		vim.env.SECRET_KEY_TEST = nil
		vim.env.AWS_ACCESS_KEY_ID = nil
	end)
end)

describe("opencode JSONL decoder", function()
	it("collects complete lines and ignores partial trailing", function()
		local decoder = opencode._make_jsonl_decoder()
		local seen = {}
		decoder({ '{"type":"step_start"}', '{"type":"text","par' }, function(ev)
			table.insert(seen, ev.type)
		end)
		assert.equals(1, #seen)
		assert.equals("step_start", seen[1])
		decoder({ 't":{"text":"hi"}}', '{"type":"step_finish"}' }, function(ev)
			table.insert(seen, ev.type)
		end)
		assert.equals(2, #seen)
		assert.equals("text", seen[2])
	end)

	it("ignores malformed JSON without raising", function()
		local decoder = opencode._make_jsonl_decoder()
		local seen = {}
		decoder({ "not json", "" }, function(ev)
			table.insert(seen, ev)
		end)
		assert.equals(0, #seen)
	end)
end)

describe("opencode.run_headless", function()
	it("accumulates text events from canned JSONL", function()
		local done = false
		local got_code, got_text
		opencode.run_headless("ignored prompt", {
			cmd = FIX .. "/fake-opencode.sh",
			timeout_ms = 5000,
		}, function(code, text)
			got_code = code
			got_text = text
			done = true
		end)
		assert.is_true(wait_for(function()
			return done
		end, 5000))
		assert.equals(0, got_code)
		assert.equals("hello world", got_text)
	end)

	it("hard-timeout fires and reports non-zero exit", function()
		local done = false
		local got_code
		local start = vim.uv.now()
		opencode.run_headless("", {
			cmd = FIX .. "/sleep-opencode.sh",
			timeout_ms = 300,
		}, function(code)
			got_code = code
			done = true
		end)
		assert.is_true(wait_for(function()
			return done
		end, 5000))
		local elapsed = vim.uv.now() - start
		assert.is_true(elapsed < 4000, "elapsed=" .. tostring(elapsed))
		assert.is_truthy(got_code ~= 0)
	end)

	it("prompt cannot trigger shell interpretation", function()
		local sentinel = vim.fn.tempname()
		vim.fn.writefile({ "alive" }, sentinel)
		assert.equals(1, vim.fn.filereadable(sentinel))
		local done = false
		local prompt = "; rm " .. sentinel .. "; echo PWNED"
		opencode.run_headless(prompt, {
			cmd = FIX .. "/cat-opencode.sh",
			timeout_ms = 5000,
		}, function()
			done = true
		end)
		assert.is_true(wait_for(function()
			return done
		end, 5000))
		assert.equals(1, vim.fn.filereadable(sentinel))
		vim.fn.delete(sentinel)
	end)

	it("env allowlist is enforced at subprocess boundary", function()
		vim.env.SECRET_KEY_TEST = "supersecret-do-not-leak"
		vim.env.OPENCODE_TESTVAR = "should-pass"
		local done = false
		local raw_env_dump
		local stdout_lines = {}
		local jid = vim.fn.jobstart({ FIX .. "/env-opencode.sh" }, {
			clear_env = true,
			env = opencode._build_env(),
			stdout_buffered = true,
			on_stdout = function(_, data)
				if data then
					for _, l in ipairs(data) do
						table.insert(stdout_lines, l)
					end
				end
			end,
			on_exit = function()
				raw_env_dump = table.concat(stdout_lines, "\n")
				done = true
			end,
		})
		assert.is_true(jid > 0)
		assert.is_true(wait_for(function()
			return done
		end, 5000))
		assert.is_truthy(raw_env_dump)
		assert.is_nil(string.find(raw_env_dump, "SECRET_KEY_TEST", 1, true))
		assert.is_nil(string.find(raw_env_dump, "supersecret-do-not-leak", 1, true))
		assert.is_truthy(string.find(raw_env_dump, "OPENCODE_TESTVAR=should%-pass"))
		vim.env.SECRET_KEY_TEST = nil
		vim.env.OPENCODE_TESTVAR = nil
	end)

	it("returns negative jid on missing executable", function()
		local jid = opencode.run_headless("p", {
			cmd = "/nonexistent/path/to/no-such-bin",
			timeout_ms = 1000,
		}, function() end)
		assert.is_true(jid <= 0)
	end)
end)

describe("opencode.cancel", function()
	it("stops a running job", function()
		local done = false
		local jid = opencode.run_headless("", {
			cmd = FIX .. "/sleep-opencode.sh",
			timeout_ms = 30000,
		}, function()
			done = true
		end)
		assert.is_true(jid > 0)
		assert.is_true(opencode.cancel(jid))
		assert.is_true(wait_for(function()
			return done
		end, 5000))
	end)
end)

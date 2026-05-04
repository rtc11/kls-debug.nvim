local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()

vim.opt.runtimepath:prepend(ROOT)

local saved_modules = {}

local function remember_module(name)
	if saved_modules[name] == nil then
		saved_modules[name] = package.loaded[name]
	end
end

local function set_module(name, value)
	remember_module(name)
	package.loaded[name] = value
end

local function reset_modules()
	for name, value in pairs(saved_modules) do
		package.loaded[name] = value
	end
	saved_modules = {}
	package.loaded["kls-debug.orchestrator"] = nil
end

local function load_orchestrator(mocks)
	mocks = mocks or {}
	for name, value in pairs(mocks) do
		set_module(name, value)
	end
	package.loaded["kls-debug.orchestrator"] = nil
	return require("kls-debug.orchestrator")
end

local function wait_for(predicate, timeout_ms)
	return vim.wait(timeout_ms or 1000, predicate, 10)
end

local function make_buffer(path, lines)
	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(bufnr, path)
	vim.bo[bufnr].filetype = "kotlin"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "fun main() {}" })
	return bufnr
end

describe("kls-debug.orchestrator", function()
	local cfg
	local notifications
	local shown
	local created_buffers

	before_each(function()
		cfg = require("kls-debug.config").merge({
			model = "gpt-test",
			agent = "test-agent",
			output = "split",
			timeout_ms = 3210,
			kls_log_path = nil,
		})
		notifications = {}
		shown = {}
		created_buffers = {}
	end)

	after_each(function()
		for _, bufnr in ipairs(created_buffers) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
		reset_modules()
	end)

	it("rejects concurrent invocations with single-flight warning", function()
		local bufnr = make_buffer("/tmp/orchestrator_single_flight.kt")
		table.insert(created_buffers, bufnr)

		local headless_calls = 0
		local orchestrator = load_orchestrator({
			["kls-debug.ui"] = {
				notify = function(msg, level)
					table.insert(notifications, { msg = msg, level = level })
				end,
				show_output = function(text, opts)
					table.insert(shown, { text = text, opts = opts })
				end,
			},
			["kls-debug.kls"] = {
				find_workspace_root = function()
					return "/tmp/ws"
				end,
			},
			["kls-debug.opencode"] = {
				run_headless = function()
					headless_calls = headless_calls + 1
					return 77
				end,
				run_terminal = function()
					return 0
				end,
				cancel = function() end,
			},
			["kls-debug.context.kls"] = {
				collect = function(_, _, _, _, callback)
					vim.schedule(function()
						callback(nil, { available = false, reason = "no debug port" })
					end)
				end,
			},
			["kls-debug.context.git"] = {
				collect = function(_, _, callback)
					vim.schedule(function()
						callback({ kind = "git", ok = false, reason = "not found" })
					end)
				end,
			},
			["kls-debug.context.log"] = {
				collect = function(_, callback)
					vim.schedule(function()
						callback({ kind = "kls_log", ok = false, reason = "no log file found" })
					end)
				end,
			},
		})

		orchestrator.ask("first", "headless", { bufnr = bufnr, cursor_line = 1, cursor_col = 0 })
		assert.is_true(wait_for(function()
			return headless_calls == 1
		end))

		orchestrator.ask("second", "headless", { bufnr = bufnr, cursor_line = 1, cursor_col = 0 })

		assert.are.equal(1, headless_calls)
		assert.is_truthy(#notifications >= 1)
		assert.is_truthy(notifications[#notifications].msg:find("already running", 1, true))
		assert.are.equal(vim.log.levels.WARN, notifications[#notifications].level)
	end)

	it("cancels in-flight headless job", function()
		local bufnr = make_buffer("/tmp/orchestrator_cancel.kt")
		table.insert(created_buffers, bufnr)

		local canceled_jid
		local started = false
		local orchestrator = load_orchestrator({
			["kls-debug.ui"] = {
				notify = function(msg, level)
					table.insert(notifications, { msg = msg, level = level })
				end,
				show_output = function(text, opts)
					table.insert(shown, { text = text, opts = opts })
				end,
			},
			["kls-debug.kls"] = {
				find_workspace_root = function()
					return "/tmp/ws"
				end,
			},
			["kls-debug.opencode"] = {
				run_headless = function()
					started = true
					return 91
				end,
				run_terminal = function()
					return 0
				end,
				cancel = function(jid)
					canceled_jid = jid
					return true
				end,
			},
			["kls-debug.context.kls"] = {
				collect = function(_, _, _, _, callback)
					vim.schedule(function()
						callback(nil, { available = false, reason = "missing" })
					end)
				end,
			},
			["kls-debug.context.git"] = {
				collect = function(_, _, callback)
					vim.schedule(function()
						callback({ kind = "git", ok = false, reason = "not found" })
					end)
				end,
			},
			["kls-debug.context.log"] = {
				collect = function(_, callback)
					vim.schedule(function()
						callback({ kind = "kls_log", ok = false, reason = "no log file found" })
					end)
				end,
			},
		})

		orchestrator.ask(
			"cancel me",
			"headless",
			{ bufnr = bufnr, cursor_line = 1, cursor_col = 0 }
		)
		assert.is_true(wait_for(function()
			return started
		end))

		orchestrator.cancel()

		assert.are.equal(91, canceled_jid)
		assert.is_truthy(notifications[#notifications].msg:find("cancelled", 1, true))
		assert.are.equal(vim.log.levels.INFO, notifications[#notifications].level)

		orchestrator.cancel()
		assert.is_truthy(notifications[#notifications].msg:find("no job to cancel", 1, true))
	end)

	it("soft-degrades when workspace root missing and omits KLS sections", function()
		local bufnr = make_buffer("/tmp/orchestrator_soft_degrade.kt", {
			"package sample",
			"",
			"fun main() = Unit",
		})
		table.insert(created_buffers, bufnr)

		local prompt_seen
		local opts_seen
		local orchestrator = load_orchestrator({
			["kls-debug.ui"] = {
				notify = function(msg, level)
					table.insert(notifications, { msg = msg, level = level })
				end,
				show_output = function(text, opts)
					table.insert(shown, { text = text, opts = opts })
				end,
			},
			["kls-debug.kls"] = {
				find_workspace_root = function()
					return nil
				end,
			},
			["kls-debug.opencode"] = {
				run_headless = function(prompt, opts, on_done)
					prompt_seen = prompt
					opts_seen = opts
					if on_done then
						vim.schedule(function()
							on_done(0, "ok", "")
						end)
					end
					return 12
				end,
				run_terminal = function()
					return 0
				end,
				cancel = function() end,
			},
			["kls-debug.context.kls"] = {
				collect = function(_, _, _, _, callback)
					vim.schedule(function()
						callback(nil, { available = false, reason = "no workspace_root" })
					end)
				end,
			},
			["kls-debug.context.git"] = {
				collect = function(_, _, callback)
					vim.schedule(function()
						callback({ kind = "git", ok = false, reason = "not found" })
					end)
				end,
			},
			["kls-debug.context.log"] = {
				collect = function(_, callback)
					vim.schedule(function()
						callback({ kind = "kls_log", ok = false, reason = "no log file found" })
					end)
				end,
			},
		})

		orchestrator.ask("why nil?", "headless", { bufnr = bufnr, cursor_line = 3, cursor_col = 4 })

		assert.is_true(wait_for(function()
			return prompt_seen ~= nil and #shown > 0
		end))
		assert.is_truthy(prompt_seen:find("why nil?", 1, true))
		assert.is_truthy(prompt_seen:find("## File:", 1, true))
		assert.is_nil(prompt_seen:find("## KLS", 1, true))
		assert.is_nil(opts_seen.cwd)
		assert.is_truthy(notifications[1].msg:find("KLS context unavailable", 1, true))
		assert.are.equal(vim.log.levels.WARN, notifications[1].level)
	end)

	it("assembles prompt with enabled sections", function()
		local bufnr = make_buffer("/tmp/orchestrator_prompt.kt", {
			"package sample",
			"fun answer() = 42",
		})
		table.insert(created_buffers, bufnr)

		local ns = vim.api.nvim_create_namespace("orchestrator-prompt-spec")
		vim.diagnostic.set(ns, bufnr, {
			{
				lnum = 1,
				col = 0,
				severity = vim.diagnostic.severity.ERROR,
				message = "boom",
				source = "kls",
			},
		}, {})

		local prompt_seen
		local orchestrator = load_orchestrator({
			["kls-debug.ui"] = {
				notify = function(msg, level)
					table.insert(notifications, { msg = msg, level = level })
				end,
				show_output = function(text, opts)
					table.insert(shown, { text = text, opts = opts })
				end,
			},
			["kls-debug.kls"] = {
				find_workspace_root = function()
					return "/tmp/ws"
				end,
			},
			["kls-debug.opencode"] = {
				run_headless = function(prompt, _, on_done)
					prompt_seen = prompt
					if on_done then
						vim.schedule(function()
							on_done(0, "done", "")
						end)
					end
					return 13
				end,
				run_terminal = function()
					return 0
				end,
				cancel = function() end,
			},
			["kls-debug.context.kls"] = {
				collect = function(_, _, _, _, callback)
					vim.schedule(function()
						callback({
							summary = { file_count = 3, symbol_count = 9 },
							ast_chain = {
								{ kind = "FUN_DECL", name = "answer", start = 2, ["end"] = 2 },
							},
							type_info = { type = "Int", nullable = false },
							hover = { value = "fun answer(): Int" },
							errors = {},
						}, nil)
					end)
				end,
			},
			["kls-debug.context.git"] = {
				collect = function(_, _, callback)
					vim.schedule(function()
						callback({
							kind = "git",
							ok = true,
							data = {
								branch = "main",
								commit = "abc feat",
								status = "M file",
								diff = "diff",
							},
						})
					end)
				end,
			},
			["kls-debug.context.log"] = {
				collect = function(_, callback)
					vim.schedule(function()
						callback({ kind = "log", ok = true, data = "log line" })
					end)
				end,
			},
			["kls-debug.context.agents"] = {
				collect = function()
					return { kind = "agents", ok = true, data = "# AGENTS\n- keep tests" }
				end,
			},
		})

		orchestrator.ask(
			"debug answer",
			"headless",
			{ bufnr = bufnr, cursor_line = 2, cursor_col = 4 }
		)

		assert.is_true(wait_for(function()
			return prompt_seen ~= nil and #shown > 0
		end))
		assert.is_truthy(prompt_seen:find("debug answer", 1, true))
		assert.is_truthy(prompt_seen:find("## File:", 1, true))
		assert.is_truthy(prompt_seen:find("## Diagnostics", 1, true))
		assert.is_truthy(prompt_seen:find("## Cursor:", 1, true))
		assert.is_truthy(prompt_seen:find("## KLS Workspace Summary", 1, true))
		assert.is_truthy(prompt_seen:find("## Git", 1, true))
		assert.is_truthy(prompt_seen:find("## AGENTS.md", 1, true))
	end)

	it("dispatches headless and terminal by mode", function()
		local bufnr = make_buffer("/tmp/orchestrator_modes.kt")
		table.insert(created_buffers, bufnr)

		local headless_calls = 0
		local terminal_calls = 0
		local headless_opts
		local terminal_opts
		local orchestrator = load_orchestrator({
			["kls-debug.ui"] = {
				notify = function(msg, level)
					table.insert(notifications, { msg = msg, level = level })
				end,
				show_output = function(text, opts)
					table.insert(shown, { text = text, opts = opts })
				end,
			},
			["kls-debug.kls"] = {
				find_workspace_root = function()
					return "/tmp/mode-ws"
				end,
			},
			["kls-debug.opencode"] = {
				run_headless = function(_, opts, on_done)
					headless_calls = headless_calls + 1
					headless_opts = opts
					if on_done then
						vim.schedule(function()
							on_done(0, "headless", "")
						end)
					end
					return 31
				end,
				run_terminal = function(_, opts)
					terminal_calls = terminal_calls + 1
					terminal_opts = opts
					return 32
				end,
				cancel = function() end,
			},
			["kls-debug.context.kls"] = {
				collect = function(_, _, _, _, callback)
					vim.schedule(function()
						callback(nil, { available = false, reason = "no port" })
					end)
				end,
			},
			["kls-debug.context.git"] = {
				collect = function(_, _, callback)
					vim.schedule(function()
						callback({ kind = "git", ok = false, reason = "not found" })
					end)
				end,
			},
			["kls-debug.context.log"] = {
				collect = function(_, callback)
					vim.schedule(function()
						callback({ kind = "kls_log", ok = false, reason = "no log file found" })
					end)
				end,
			},
		})

		orchestrator.ask(
			"headless q",
			"headless",
			{ bufnr = bufnr, cursor_line = 1, cursor_col = 0 }
		)
		assert.is_true(wait_for(function()
			return headless_calls == 1 and #shown > 0
		end))

		orchestrator.ask(
			"terminal q",
			"terminal",
			{ bufnr = bufnr, cursor_line = 1, cursor_col = 0 }
		)
		assert.is_true(wait_for(function()
			return terminal_calls == 1
		end))

		assert.are.equal(1, headless_calls)
		assert.are.equal(1, terminal_calls)
		assert.are.same({
			cwd = "/tmp/mode-ws",
			model = cfg.model,
			agent = cfg.agent,
			timeout_ms = cfg.timeout_ms,
		}, headless_opts)
		assert.are.same({
			cwd = "/tmp/mode-ws",
			model = cfg.model,
			agent = cfg.agent,
			output = cfg.output,
		}, terminal_opts)
	end)
end)

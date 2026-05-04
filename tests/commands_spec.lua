local function repo_root()
	local src = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(src, ":p:h:h")
end

local ROOT = repo_root()

vim.opt.runtimepath:prepend(ROOT)

local saved_modules = {}
local created_commands = {}
local captured = {}
local original_create_user_command

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
	vim.g.loaded_kls_debug = nil
	package.loaded["kls-debug"] = nil
	package.loaded["kls-debug.orchestrator"] = nil
	package.loaded["kls-debug.config"] = nil
end

local function load_plugin()
	package.loaded["kls-debug"] = nil
	vim.g.loaded_kls_debug = nil
	vim.cmd("runtime plugin/kls-debug.lua")
end

describe("kls-debug commands", function()
	before_each(function()
		created_commands = {}
		captured = {}
		original_create_user_command = vim.api.nvim_create_user_command
		set_module("kls-debug.orchestrator", {
			ask = function(...)
				captured.ask = { ... }
			end,
			cancel = function(...)
				captured.cancel = { ... }
			end,
		})

		set_module("kls-debug.config", {
			merge = function(opts)
				captured.setup = opts
				return opts
			end,
		})

		set_module("kls-debug", nil)

		vim.api.nvim_create_user_command = function(name, callback, opts)
			created_commands[name] = { callback = callback, opts = opts }
		end
	end)

	after_each(function()
		vim.api.nvim_create_user_command = original_create_user_command
		reset_modules()
	end)

	it("registers commands and setup merges config", function()
		load_plugin()
		require("kls-debug").setup({ foo = "bar" })

		assert.is_truthy(created_commands["KlsDebugAsk"])
		assert.is_truthy(created_commands["KlsDebugChat"])
		assert.is_truthy(created_commands["KlsDebugCancel"])
		assert.are.same({ foo = "bar" }, captured.setup)
	end)

	it("wires cancel command", function()
		load_plugin()
		created_commands["KlsDebugCancel"].callback({})

		assert.are.same({}, captured.cancel)
	end)

	it("builds visual trigger ctx from ranged command", function()
		load_plugin()
		created_commands["KlsDebugAsk"].callback({
			range = 2,
			line1 = 5,
			line2 = 10,
			fargs = { "why" },
		})

		assert.are.same(
			{
				"why",
				"headless",
				{
					bufnr = 0,
					line1 = 5,
					line2 = 10,
					visual = true,
					visual_range = { 5, 10 },
				},
			},
			captured.ask
		)
	end)

	it("concats nargs star question words", function()
		load_plugin()
		created_commands["KlsDebugChat"].callback({
			range = 0,
			line1 = 1,
			line2 = 1,
			fargs = { "one", "two", "three" },
		})

		assert.are.same(
			{
				"one two three",
				"terminal",
				{
					bufnr = 0,
					line1 = 1,
					line2 = 1,
					visual = false,
					visual_range = nil,
				},
			},
			captured.ask
		)
	end)
end)

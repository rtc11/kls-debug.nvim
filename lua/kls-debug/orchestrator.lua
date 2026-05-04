local config = require("kls-debug.config")
local kls = require("kls-debug.kls")
local opencode = require("kls-debug.opencode")
local ui = require("kls-debug.ui")

local buffer_ctx = require("kls-debug.context.buffer")
local selection_ctx = require("kls-debug.context.selection")
local diagnostics_ctx = require("kls-debug.context.diagnostics")
local cursor_ctx = require("kls-debug.context.cursor")
local kls_ctx = require("kls-debug.context.kls")
local git_ctx = require("kls-debug.context.git")
local agents_ctx = require("kls-debug.context.agents")
local log_ctx = require("kls-debug.context.log")
local bundler = require("kls-debug.context.bundler")

local M = {}

local state = {
	in_flight_job = nil,
}

local active_request = 0

local valid_modes = {
	headless = true,
	terminal = true,
}

local function trim_question(question)
	if type(question) ~= "string" then
		return nil
	end

	local trimmed = vim.trim(question)
	if trimmed == "" then
		return nil
	end

	return trimmed
end

local function resolve_cursor(trigger_ctx)
	trigger_ctx = trigger_ctx or {}
	local row = trigger_ctx.cursor_line
	local col = trigger_ctx.cursor_col

	if type(row) == "number" and type(col) == "number" then
		return row, col
	end

	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
	if ok and type(cursor) == "table" then
		return row or cursor[1] or 1, col or cursor[2] or 0
	end

	return row or 1, col or 0
end

local function apply_visual_range(bufnr, trigger_ctx)
	if type(trigger_ctx) ~= "table" or trigger_ctx.visual ~= true then
		return
	end

	local visual_range = trigger_ctx.visual_range
	if type(visual_range) ~= "table" then
		return
	end

	local start_line = tonumber(visual_range[1])
	local end_line = tonumber(visual_range[2])
	if not start_line or not end_line or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	if end_line < start_line then
		start_line, end_line = end_line, start_line
	end

	local end_text = vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1] or ""
	pcall(vim.api.nvim_buf_set_mark, bufnr, "<", start_line, 0, {})
	pcall(vim.api.nvim_buf_set_mark, bufnr, ">", end_line, math.max(0, #end_text - 1), {})
end

local function dispatch(prompt, mode, cfg, workspace_root)
	if mode == "terminal" then
		local jid = opencode.run_terminal(prompt, {
			cwd = workspace_root,
			model = cfg.model,
			agent = cfg.agent,
			output = cfg.output,
		})
		if type(jid) ~= "number" or jid <= 0 then
			ui.notify("kls-debug: failed to start terminal opencode job", vim.log.levels.ERROR)
		end
		state.in_flight_job = nil
		return
	end

	local jid = opencode.run_headless(prompt, {
		cwd = workspace_root,
		model = cfg.model,
		agent = cfg.agent,
		timeout_ms = cfg.timeout_ms,
	}, function(_, text, stderr)
		state.in_flight_job = nil
		vim.schedule(function()
			ui.show_output(text or stderr or "", { output = cfg.output })
		end)
	end)

	if type(jid) ~= "number" or jid <= 0 then
		state.in_flight_job = nil
		ui.notify("kls-debug: failed to start headless opencode job", vim.log.levels.ERROR)
		return
	end

	state.in_flight_job = jid
end

function M.ask(question, mode, trigger_ctx)
	local clean_question = trim_question(question)
	if clean_question == nil then
		ui.notify("kls-debug: question required", vim.log.levels.ERROR)
		return
	end

	if not valid_modes[mode] then
		ui.notify("kls-debug: mode must be 'headless' or 'terminal'", vim.log.levels.ERROR)
		return
	end

	local cfg = config.get()
	trigger_ctx = type(trigger_ctx) == "table" and trigger_ctx or {}
	local bufnr = trigger_ctx.bufnr or 0

	if state.in_flight_job ~= nil then
		ui.notify("kls-debug: already running, use :KlsDebugCancel", vim.log.levels.WARN)
		return
	end

	active_request = active_request + 1
	local request_id = active_request
	state.in_flight_job = 0

	local filetype = vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype or ""
	if trigger_ctx.auto_diag == true and filetype ~= "kotlin" then
		state.in_flight_job = nil
		ui.notify("kls-debug: auto diagnostics only work for Kotlin buffers", vim.log.levels.WARN)
		return
	end

	apply_visual_range(bufnr, trigger_ctx)

	local cursor_line, cursor_col = resolve_cursor(trigger_ctx)
	local workspace_root = kls.find_workspace_root(bufnr)
	local diagnostic_range = nil
	if trigger_ctx.auto_diag == true then
		diagnostic_range = { lnum = math.max(0, cursor_line - 1) }
	end

	local bundle = {
		buffer = buffer_ctx.collect(cfg, bufnr, cursor_line),
		selection = selection_ctx.collect(cfg, bufnr),
		diagnostics = diagnostics_ctx.collect(cfg, bufnr, diagnostic_range),
		cursor = cursor_ctx.collect(cfg, bufnr, cursor_line, cursor_col),
		agents = agents_ctx.collect(cfg, workspace_root),
		kls = nil,
		git = nil,
		log = nil,
	}

	local pending = 3
	local finished = false
	local function on_async_done()
		if request_id ~= active_request or state.in_flight_job == nil then
			return
		end
		pending = pending - 1
		if pending > 0 or finished then
			return
		end
		finished = true
		local prompt = bundler.format(bundle, clean_question, cfg)
		dispatch(prompt, mode, cfg, workspace_root)
	end

	kls_ctx.collect(workspace_root, bufnr, cursor_line - 1, cursor_col, function(result, meta)
		bundle.kls = result
		if type(meta) == "table" and meta.available == false then
			ui.notify(
				"kls-debug: KLS context unavailable: " .. tostring(meta.reason or "unknown reason"),
				vim.log.levels.WARN
			)
		end
		on_async_done()
	end)

	git_ctx.collect(
		vim.tbl_extend("force", cfg, { bufnr = bufnr }),
		workspace_root,
		function(result)
			bundle.git = result
			on_async_done()
		end
	)

	log_ctx.collect(cfg, function(result)
		bundle.log = result
		on_async_done()
	end)
end

function M.cancel()
	if state.in_flight_job == nil then
		ui.notify("kls-debug: no job to cancel", vim.log.levels.INFO)
		return
	end

	if state.in_flight_job > 0 then
		opencode.cancel(state.in_flight_job)
	end
	state.in_flight_job = nil
	ui.notify("kls-debug: cancelled", vim.log.levels.INFO)
end

return M

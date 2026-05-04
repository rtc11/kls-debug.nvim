if vim.g.loaded_kls_debug then
	return
end
vim.g.loaded_kls_debug = true

local function trigger_ctx_from_command(opts)
	local trigger_ctx = {
		bufnr = 0,
		line1 = opts.line1,
		line2 = opts.line2,
		visual = opts.range > 0,
		visual_range = nil,
	}

	if opts.range > 0 then
		trigger_ctx.visual_range = { opts.line1, opts.line2 }
	end

	return trigger_ctx
end

local function question_from_command(opts)
	return table.concat(opts.fargs or {}, " ")
end

vim.api.nvim_create_user_command("KlsDebugAsk", function(opts)
	require("kls-debug").ask(
		question_from_command(opts),
		"headless",
		trigger_ctx_from_command(opts)
	)
end, {
	nargs = "*",
	range = true,
})

vim.api.nvim_create_user_command("KlsDebugChat", function(opts)
	require("kls-debug").ask(
		question_from_command(opts),
		"terminal",
		trigger_ctx_from_command(opts)
	)
end, {
	nargs = "*",
	range = true,
})

vim.api.nvim_create_user_command("KlsDebugCancel", function()
	require("kls-debug").cancel()
end, {
	nargs = 0,
})

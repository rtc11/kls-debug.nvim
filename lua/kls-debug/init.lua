local M = {}

local config = require("kls-debug.config")
local orchestrator = require("kls-debug.orchestrator")
local keymaps = require("kls-debug.keymaps")

function M.setup(opts)
	local cfg = config.merge(opts)
	if cfg.keymaps and cfg.keymaps.enabled == true then
		keymaps.setup(cfg)
	end

	return cfg
end

function M.ask(question, mode, trigger_ctx)
	return orchestrator.ask(question, mode, trigger_ctx)
end

function M.cancel()
	return orchestrator.cancel()
end

return M

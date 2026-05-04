local M = {}

local config = require("kls-debug.config")
local orchestrator = require("kls-debug.orchestrator")

function M.setup(opts)
	return config.merge(opts)
end

function M.ask(question, mode, trigger_ctx)
	return orchestrator.ask(question, mode, trigger_ctx)
end

function M.cancel()
	return orchestrator.cancel()
end

return M

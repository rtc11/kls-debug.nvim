local M = {}

M.defaults = {
	model = nil,
	agent = nil,
	output = "split",
	timeout_ms = 60000,
	kls_connect_timeout_ms = 500,
	buffer_byte_cap = 102400,
	buffer_around_cursor = 20480,
	diagnostic_cap = 50,
	log_tail_lines = 200,
	surrounding_lines = 10,
	context = {
		diagnostics = true,
		buffer = true,
		selection = true,
		kls = true,
		cursor_symbol = true,
		kls_log = true,
		git = true,
		agents_md = true,
	},
	kls_log_path = nil,
	keymaps = {
		visual = "<leader>kd",
		normal_diag = "<leader>kd",
		enabled = true,
	},
}

local valid_outputs = {
	split = true,
	float = true,
	tab = true,
}

local current = vim.deepcopy(M.defaults)

local function is_positive_integer(value)
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function assert_type(value, expected, name)
	if type(value) ~= expected then
		error(string.format("%s must be %s", name, expected), 2)
	end
end

local function validate_context(context)
	assert_type(context, "table", "context")

	local expected = {
		diagnostics = "boolean",
		buffer = "boolean",
		selection = "boolean",
		kls = "boolean",
		cursor_symbol = "boolean",
		kls_log = "boolean",
		git = "boolean",
		agents_md = "boolean",
	}

	for key, kind in pairs(expected) do
		assert_type(context[key], kind, "context." .. key)
	end

	return context
end

local function validate_keymaps(keymaps)
	assert_type(keymaps, "table", "keymaps")
	assert_type(keymaps.visual, "string", "keymaps.visual")
	assert_type(keymaps.normal_diag, "string", "keymaps.normal_diag")
	assert_type(keymaps.enabled, "boolean", "keymaps.enabled")

	return keymaps
end

function M.validate(opts)
	opts = opts or {}
	assert_type(opts, "table", "opts")

	local cfg = vim.deepcopy(M.defaults)
	cfg = vim.tbl_deep_extend("force", cfg, opts)

	if cfg.model ~= nil then
		assert_type(cfg.model, "string", "model")
	end

	if cfg.agent ~= nil then
		assert_type(cfg.agent, "string", "agent")
	end

	assert_type(cfg.output, "string", "output")
	if not valid_outputs[cfg.output] then
		error("output must be one of split, float, tab", 2)
	end

	if not is_positive_integer(cfg.timeout_ms) then
		error("timeout_ms must be a positive integer", 2)
	end

	if not is_positive_integer(cfg.kls_connect_timeout_ms) then
		error("kls_connect_timeout_ms must be a positive integer", 2)
	end

	if not is_positive_integer(cfg.buffer_byte_cap) then
		error("buffer_byte_cap must be a positive integer", 2)
	end

	if not is_positive_integer(cfg.buffer_around_cursor) then
		error("buffer_around_cursor must be a positive integer", 2)
	end

	if not is_positive_integer(cfg.diagnostic_cap) then
		error("diagnostic_cap must be a positive integer", 2)
	end

	if not is_positive_integer(cfg.log_tail_lines) then
		error("log_tail_lines must be a positive integer", 2)
	end

	if not is_positive_integer(cfg.surrounding_lines) then
		error("surrounding_lines must be a positive integer", 2)
	end

	validate_context(cfg.context)
	if cfg.kls_log_path ~= nil then
		assert_type(cfg.kls_log_path, "string", "kls_log_path")
	end
	validate_keymaps(cfg.keymaps)

	return cfg
end

function M.merge(user_opts)
	current = M.validate(vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {}))
	return current
end

function M.get()
	return current
end

return M
